// Bluetooth transports: Bluetooth LE (older bands, original Watch Fit) and classic RFCOMM (Watch Fit 2 and newer).
import Foundation
import CoreBluetooth
import IOBluetooth

enum TransportKind: String, Codable { case le, classic }

struct FoundDevice: Identifiable, Equatable {
    var id: String            // CoreBluetooth UUID string, or classic MAC address
    var name: String
    var kind: TransportKind
    var rssi: Int?
    var paired = false
}

protocol Transport: AnyObject {
    var onData: ((Data) -> Void)? { get set }
    var onOpen: (() -> Void)? { get set }
    var onClose: ((String?) -> Void)? { get set }
    /// MAC address of the watch if the system exposes it (classic only).
    var macAddress: String? { get }
    func open()
    func close()
    func send(_ frames: [Data])
}

func looksLikeHuawei(_ name: String) -> Bool {
    let n = name.lowercased()
    return n.hasPrefix("huawei") || n.hasPrefix("honor") || n.hasPrefix("watch gt") || n.hasPrefix("watch ultimate")
}

// MARK: - Scanner

final class DeviceScanner: NSObject, ObservableObject, CBCentralManagerDelegate, IOBluetoothDeviceInquiryDelegate {
    @Published var devices: [FoundDevice] = []
    @Published var scanning = false
    @Published var bluetoothProblem: String?

    private(set) var central: CBCentralManager!
    private(set) var peripherals: [String: CBPeripheral] = [:]
    private var inquiry: IOBluetoothDeviceInquiry?
    private var wantScan = false

    static let serviceUUID = CBUUID(string: "FE86")
    /// Newer Honor bands (Band 7, 9, 10) use their own GATT service.
    static let honorServiceUUID = CBUUID(string: "C5F0AD48-CC27-48FD-9F67-8DC8E8F4A9CB")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        wantScan = true
        scanning = true
        devices.removeAll { !$0.paired }
        addPairedClassic()
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            for p in central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID, Self.honorServiceUUID]) { add(peripheral: p, rssi: nil) }
        }
        if inquiry == nil, let inq = IOBluetoothDeviceInquiry(delegate: self) {
            inq.inquiryLength = 12
            inq.updateNewDeviceNames = true
            inquiry = inq
            inq.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.stop() }
    }

    func stop() {
        wantScan = false
        scanning = false
        if central.state == .poweredOn { central.stopScan() }
        inquiry?.stop()
        inquiry = nil
    }

    private func addPairedClassic() {
        for case let d as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] {
            guard let name = d.name, looksLikeHuawei(name), let addr = d.addressString else { continue }
            upsert(FoundDevice(id: addr.uppercased().replacingOccurrences(of: "-", with: ":"), name: name, kind: .classic, rssi: nil, paired: true))
        }
    }

    private func upsert(_ d: FoundDevice) {
        if let i = devices.firstIndex(where: { $0.id == d.id }) { devices[i] = d } else { devices.append(d) }
    }

    private func add(peripheral p: CBPeripheral, rssi: Int?, advName: String? = nil) {
        guard let name = advName ?? p.name, looksLikeHuawei(name) else { return }
        peripherals[p.identifier.uuidString] = p
        upsert(FoundDevice(id: p.identifier.uuidString, name: name, kind: .le, rssi: rssi))
    }

    func peripheral(for id: String) -> CBPeripheral? {
        if let p = peripherals[id] { return p }
        guard let uuid = UUID(uuidString: id) else { return nil }
        let p = central.retrievePeripherals(withIdentifiers: [uuid]).first
        if let p { peripherals[id] = p }
        return p
    }

    // CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetoothProblem = nil; if wantScan { start() }
        case .unauthorized: bluetoothProblem = "Bluetooth access is not allowed. Enable WatchDeck in System Settings › Privacy & Security › Bluetooth."
        case .poweredOff: bluetoothProblem = "Bluetooth is off."
        case .unsupported: bluetoothProblem = "This Mac does not support Bluetooth LE."
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        add(peripheral: peripheral, rssi: RSSI.intValue, advName: advertisementData[CBAdvertisementDataLocalNameKey] as? String)
    }

    // Forwarded to the active LE transport.
    weak var leTransport: LETransport?
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { leTransport?.didConnect() }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        leTransport?.didDisconnect(error?.localizedDescription ?? "could not connect")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        leTransport?.didDisconnect(error?.localizedDescription)
    }

    // IOBluetoothDeviceInquiryDelegate
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) { addClassic(device) }
    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) { addClassic(device) }
    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) { inquiry = nil }

    private func addClassic(_ d: IOBluetoothDevice?) {
        guard let d, let name = d.name, looksLikeHuawei(name), let addr = d.addressString else { return }
        upsert(FoundDevice(id: addr.uppercased().replacingOccurrences(of: "-", with: ":"), name: name, kind: .classic,
                           rssi: nil, paired: d.isPaired()))
    }
}

// MARK: - Bluetooth LE

final class LETransport: NSObject, Transport, CBPeripheralDelegate {
    var onData: ((Data) -> Void)?
    var onOpen: (() -> Void)?
    var onClose: ((String?) -> Void)?
    var macAddress: String? { nil }

    private let scanner: DeviceScanner
    private let peripheral: CBPeripheral
    private var writeChar: CBCharacteristic?
    private var closed = false

    static let writeUUID = CBUUID(string: "FE01")
    static let readUUID = CBUUID(string: "FE02")
    static let honorWriteUUID = CBUUID(string: "2A5FC8BD-3DE4-43CB-9449-354BCDECCC70")
    static let honorReadUUID = CBUUID(string: "A563D757-B216-48BC-8A0F-E8DDE1F916AA")
    private var activeRead = LETransport.readUUID

    init(scanner: DeviceScanner, peripheral: CBPeripheral) {
        self.scanner = scanner
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    func open() {
        scanner.leTransport = self
        scanner.central.connect(peripheral, options: nil)
    }

    func close() {
        closed = true
        scanner.central.cancelPeripheralConnection(peripheral)
    }

    func send(_ frames: [Data]) {
        guard let c = writeChar else { return }
        let mtu = max(20, peripheral.maximumWriteValueLength(for: .withoutResponse))
        for f in frames {
            var pos = 0
            while pos < f.count {
                let n = min(mtu, f.count - pos)
                peripheral.writeValue(f.subdata(in: pos ..< pos + n), for: c, type: .withoutResponse)
                pos += n
            }
        }
    }

    func didConnect() { peripheral.discoverServices([DeviceScanner.serviceUUID, DeviceScanner.honorServiceUUID]) }

    func didDisconnect(_ reason: String?) {
        writeChar = nil
        onClose?(closed ? nil : (reason ?? "connection lost"))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let s = peripheral.services?.first(where: { $0.uuid == DeviceScanner.serviceUUID }) {
            activeRead = Self.readUUID
            peripheral.discoverCharacteristics([Self.writeUUID, Self.readUUID], for: s)
        } else if let s = peripheral.services?.first(where: { $0.uuid == DeviceScanner.honorServiceUUID }) {
            activeRead = Self.honorReadUUID
            peripheral.discoverCharacteristics([Self.honorWriteUUID, Self.honorReadUUID], for: s)
        } else {
            onClose?("this device does not expose the Huawei or Honor data service over Bluetooth LE")
            close()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == Self.writeUUID || c.uuid == Self.honorWriteUUID { writeChar = c }
            if c.uuid == activeRead { peripheral.setNotifyValue(true, for: c) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == activeRead, characteristic.isNotifying, writeChar != nil { onOpen?() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let v = characteristic.value { onData?(v) }
    }
}

// MARK: - Classic Bluetooth (RFCOMM)

final class ClassicTransport: NSObject, Transport, IOBluetoothRFCOMMChannelDelegate {
    var onData: ((Data) -> Void)?
    var onOpen: (() -> Void)?
    var onClose: ((String?) -> Void)?
    var macAddress: String? { address }

    private let address: String
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var closed = false

    static let sdpUUIDs = ["82FF3820-8411-400C-B85A-55BDB32CF060", "C9770A18-4C3D-453A-8AAF-D7EC7BBD2785"]

    init(address: String) {
        self.address = address
        super.init()
    }

    private func fail(_ msg: String) { onClose?(msg) }

    func open() {
        guard let d = IOBluetoothDevice(addressString: address.replacingOccurrences(of: ":", with: "-")) else {
            return fail("unknown Bluetooth address")
        }
        device = d
        let uuids = Self.sdpUUIDs.compactMap { Self.sdpUUID($0) }
        if d.performSDPQuery(self, uuids: uuids) != kIOReturnSuccess {
            fail("could not query the watch. Make sure it is nearby and paired in System Settings › Bluetooth.")
        }
    }

    private static func sdpUUID(_ s: String) -> IOBluetoothSDPUUID? {
        let d = Data(hex: s)
        return d.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: d.count) }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard status == kIOReturnSuccess else {
            return fail("the watch did not answer the service query. Pair it in System Settings › Bluetooth first.")
        }
        var channelID: BluetoothRFCOMMChannelID = 0
        var found = false
        for u in Self.sdpUUIDs {
            if let uuid = Self.sdpUUID(u), let rec = device.getServiceRecord(for: uuid),
               rec.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
                found = true
                break
            }
        }
        guard found else { return fail("this device does not offer the Huawei data service over classic Bluetooth") }
        var ch: IOBluetoothRFCOMMChannel?
        let r = device.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
        guard r == kIOReturnSuccess else { return fail("could not open a data channel to the watch (\(r))") }
        channel = ch
    }

    func close() {
        closed = true
        channel?.close()
        channel = nil
        device?.closeConnection()
    }

    func send(_ frames: [Data]) {
        guard let ch = channel else { return }
        let mtu = max(64, Int(ch.getMTU()))
        for f in frames {
            var pos = 0
            while pos < f.count {
                let n = min(mtu, f.count - pos)
                var chunk = [UInt8](f.subdata(in: pos ..< pos + n))
                _ = ch.writeSync(&chunk, length: UInt16(n))
                pos += n
            }
        }
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess { onOpen?() } else { fail("the data channel could not be opened (\(error))") }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        onData?(Data(bytes: dataPointer, count: dataLength))
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        channel = nil
        onClose?(closed ? nil : "connection lost")
    }
}
