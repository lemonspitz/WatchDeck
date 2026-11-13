// One connection to a watch: pairing handshake, request/response plumbing and feature commands.
import Foundation
import CryptoKit
import IOBluetooth
import AppKit

struct DeviceIdentity: Codable {
    var name = ""
    var kind = TransportKind.classic
    var androidId = Data.random(16).hex            // stable fake phone id
    var fakeMac = "FF:FF:FF:" + Data.random(3).map { String(format: "%02X", $0) }.joined(separator: ":")
    var authKey: String?                            // session/bonding key, hex
    var watchMac = ""                               // real watch address (typed by the user for LE models)
    var pakeSeed: String?                           // our Ed25519 identity for HiChain PAKE watches
    var pakePeerId: String?                         // the watch's identity, learned at the first PAKE pairing
    var pakePeerPk: String?
}

struct StepSample: Identifiable, Codable {
    var id: Date { time }
    var time: Date
    var steps = 0, calories = 0, distance = 0
    var heartRate: Int?
    var spo2: Int?
}

struct WatchFace: Identifiable, Equatable {
    var id: String { fileName }
    var fileName: String
    var version: String
    var type: Int
    var title: String?
    var isCurrent: Bool { type & 1 == 1 }
    var isFactory: Bool { (type >> 1) & 1 == 1 }
}

struct WatchAlarm: Identifiable, Equatable {
    var id: Int { index }
    var index: Int
    var enabled = true
    var hour = 7, minute = 0
    var repeatMask = 0          // bit 0 = Monday … bit 6 = Sunday
    var name = "Alarm"
}

@MainActor
final class WatchSession: ObservableObject {
    enum Status: Equatable { case disconnected, connecting, pairing, ready, failed(String) }

    @Published var status = Status.disconnected
    @Published var statusDetail = ""
    @Published var deviceName = ""
    @Published var model = ""
    @Published var firmware = ""
    @Published var serial = ""
    @Published var battery: Int?
    @Published var services: Set<Int> = []
    @Published var totalSteps: Int?
    @Published var totalCalories: Int?
    @Published var totalDistance: Int?
    @Published var samples: [StepSample] = []
    @Published var sleep: [SleepSegment] = []
    @Published var dayTotals: [String: DayTotal] = [:]
    @Published var lastSync: Date?
    @Published var gpsAssistStatus = "Not sent yet"
    @Published var faceMeta: [String: FaceMeta] = Storage.loadFaceMeta()
    @Published var library: [LibraryFace] = []
    @Published var workouts: [Workout] = []
    @Published var workoutSyncing = false
    @Published var workoutStatus = ""
    /// Receives file-download data (GPS tracks) while a download is running.
    var fileBlockSink: ((Data) -> Void)?
    var fileBlockKind = 0
    /// Size of faces shown in the library ("280 × 456", or "All"). Follows the connected watch unless the user picks another.
    @Published var librarySize = UserDefaults.standard.string(forKey: "librarySize") ?? "280 × 456"
    @Published var librarySizes: [String] = []
    @Published var syncing = false
    @Published var faces: [WatchFace] = []
    @Published var faceSize = ""
    @Published var uploadProgress: Double?
    @Published var alarms: [WatchAlarm] = []
    @Published var log: [String] = []
    @Published var lastError: String?
    @Published var findingPhone = false

    let scanner = DeviceScanner()
    private var transport: Transport?
    private let params = LinkParams()
    private let assembler = PacketAssembler()
    private var identity = DeviceIdentity()
    /// The connected model, looked up from its Bluetooth name (nil for names the catalogue does not know).
    @Published private(set) var watchModel: ModelInfo?
    private(set) var deviceId = ""
    private var onUploadNamed: ((String) -> Void)?
    /// Keeps macOS from napping the app, which would pause scanning, timeouts and the GPS-assist timer.
    private let keepAwake = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                                  reason: "Keeping the watch connection running")

    init() {
        if let last = UserDefaults.standard.string(forKey: "lastDevice") {
            deviceId = last
            loadStoredHealth(for: last)
            loadStoredWorkouts(for: last)
        }
        reloadLibrary()
    }
    private var waiters: [(id: UUID, key: String, cont: CheckedContinuation<Packet, Error>)] = []
    private var notificationCounter = 0
    private var upload: (data: Data, name: String, fileId: Int, unit: Int, encrypt: Bool)?
    private var findPhoneSound: NSSound?

    var isReady: Bool { status == .ready }

    // MARK: Identity storage

    private func loadIdentity(_ id: String) -> DeviceIdentity {
        if let d = UserDefaults.standard.data(forKey: "device." + id), let i = try? JSONDecoder().decode(DeviceIdentity.self, from: d) { return i }
        return DeviceIdentity()
    }

    private func saveIdentity() {
        if let d = try? JSONEncoder().encode(identity) { UserDefaults.standard.set(d, forKey: "device." + deviceId) }
    }

    func forgetPairing(_ id: String) {
        UserDefaults.standard.removeObject(forKey: "device." + id)
        if UserDefaults.standard.string(forKey: "lastDevice") == id { UserDefaults.standard.removeObject(forKey: "lastDevice") }
    }

    func storedMac(for id: String) -> String { loadIdentity(id).watchMac }

    // MARK: Logging

    func note(_ s: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        let line = f.string(from: Date()) + "  " + s
        log.append(line)
        Self.appendToLogFile(line)
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
    }

    static let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/WatchDeck.log")

    private static func appendToLogFile(_ line: String) {
        guard let d = (line + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(d); try? h.close()
        } else {
            try? d.write(to: logURL)
        }
    }

    /// macOS hides Bluetooth LE addresses from apps, but lists them in the system report while the device is connected.
    nonisolated static func lookupMac(name: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                p.arguments = ["SPBluetoothDataType"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                guard (try? p.run()) != nil else { return cont.resume(returning: nil) }
                let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let lines = out.components(separatedBy: "\n")
                var result: String?
                for (i, l) in lines.enumerated() where l.trimmingCharacters(in: .whitespaces) == name + ":" {
                    for next in lines[(i + 1)...].prefix(4) {
                        let t = next.trimmingCharacters(in: .whitespaces)
                        if t.hasPrefix("Address:") { result = t.dropFirst(8).trimmingCharacters(in: .whitespaces).uppercased(); break }
                    }
                    if result != nil { break }
                }
                cont.resume(returning: result)
            }
        }
    }

    /// `--connect <part of name>`: scan and connect to the first matching device (used for unattended testing).
    func autoConnect(matching part: String) {
        note("Auto-connect: looking for a device whose name contains \"\(part)\"")
        scanner.start()
        var tries = 0
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self, t.isValid else { t.invalidate(); return }
                tries += 1
                if tries % 5 == 0 { self.note("Seen so far: " + self.scanner.devices.map { "\($0.name) [\($0.kind.rawValue)]" }.joined(separator: ", ")) }
                if let d = self.scanner.devices.first(where: { $0.name.lowercased().contains(part.lowercased()) }) {
                    t.invalidate()
                    self.connect(d, watchMac: self.storedMac(for: d.id))
                } else if tries >= 40 {
                    t.invalidate()
                    self.note("Auto-connect: no matching device found")
                } else if !self.scanner.scanning {
                    self.scanner.start()
                }
            }
        }
    }

    // MARK: Connect / disconnect

    func connect(_ device: FoundDevice, watchMac: String = "") {
        disconnect()
        scanner.stop()
        deviceId = device.id
        identity = loadIdentity(device.id)
        loadStoredHealth(for: device.id)
        loadStoredWorkouts(for: device.id)
        identity.name = device.name
        identity.kind = device.kind
        if !watchMac.isEmpty { identity.watchMac = watchMac.uppercased() }
        saveIdentity()
        deviceName = device.name
        status = .connecting
        statusDetail = "Opening Bluetooth connection…"
        lastError = nil
        resetLink()

        watchModel = ModelInfo.match(device.name)
        params.crypted = watchModel?.encrypted ?? true
        if let m = watchModel { note("Model: \(m.displayName) (\(m.link == .br ? "classic Bluetooth" : "Bluetooth LE")\(m.pake ? ", PAKE pairing" : "")\(m.encrypted ? "" : ", unencrypted"))") }
        else { note("Model not in the catalogue; using the connection type it was found with") }

        let t: Transport
        let wantLE = watchModel.map { $0.usesLE } ?? (device.kind == .le)
        if wantLE {
            let leId = device.kind == .le ? device.id : scanner.devices.first { $0.kind == .le && $0.name == device.name }?.id
            guard let leId, let p = scanner.peripheral(for: leId) else {
                return fail("\(device.name) talks over Bluetooth LE but is not in range right now. Wake the watch and scan again.")
            }
            t = LETransport(scanner: scanner, peripheral: p)
        } else {
            guard let address = device.kind == .classic ? device.id : Self.pairedClassicAddress(name: device.name) else {
                return fail("\(device.name) uses classic Bluetooth. Pair it once in System Settings › Bluetooth (keep the watch on its pairing screen), then connect here.")
            }
            identity.watchMac = address
            t = ClassicTransport(address: address)
        }
        transport = t
        t.onData = { [weak self] d in Task { @MainActor in self?.received(d) } }
        t.onOpen = { [weak self] in Task { @MainActor in self?.opened() } }
        t.onClose = { [weak self] r in Task { @MainActor in self?.closed(r) } }
        note("Connecting to \(device.name) (\(wantLE ? "Bluetooth LE" : "classic Bluetooth"))")
        t.open()
        let token = deviceId
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self, self.status == .connecting, self.deviceId == token else { return }
            self.fail("Could not reach the watch. Keep it close, awake, and disconnected from other phones.")
        }
    }

    private func resetLink() {
        assembler.reset()
        params.secretKey = nil; params.firstKey = nil; params.pinCode = nil
        params.authMode = 0; params.encryptionCounter = 0
    }

    func disconnect() {
        transport?.close()
        transport = nil
        failWaiters(WatchError.notConnected)
        if case .failed = status {} else { status = .disconnected }
        statusDetail = ""
        upload = nil; uploadProgress = nil
        stopFindPhoneSound()
    }

    private func fail(_ message: String) {
        note("FAILED: " + message)
        transport?.close()
        transport = nil
        failWaiters(WatchError.notConnected)
        status = .failed(message)
    }

    private func closed(_ reason: String?) {
        guard transport != nil else { return }
        transport = nil
        failWaiters(WatchError.notConnected)
        if let reason { status = .failed("Disconnected: " + reason); note("Disconnected: " + reason) }
        else { status = .disconnected }
    }

    private func opened() {
        note("Bluetooth channel open")
        status = .pairing
        Task {
            do {
                try await handshake()
                try await configure()
                status = .ready
                statusDetail = ""
                UserDefaults.standard.set(deviceId, forKey: "lastDevice")
                await refreshAll()
                startGPSAssistLoop()
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    // MARK: Packet plumbing

    private func received(_ data: Data) {
        for p in assembler.feed(data, params: params) {
            note("← \(p.id)  " + (p.tlv.items.isEmpty ? p.raw.hex : p.tlv.description))
            if let i = waiters.firstIndex(where: { $0.key == p.id }) {
                let w = waiters.remove(at: i)
                w.cont.resume(returning: p)
            } else {
                handleAsync(p)
            }
        }
    }

    private func failWaiters(_ e: Error) {
        let ws = waiters
        waiters.removeAll()
        ws.forEach { $0.cont.resume(throwing: e) }
    }

    private func frames(_ service: Int, _ command: Int, _ tlv: TLV, encrypt: Bool, sliced: Bool) throws -> [Data] {
        var body = tlv.data
        if encrypt, params.crypted, params.secretKey != nil { body = try params.encrypt(body).data }
        let s = UInt8(service), c = UInt8(command)
        return sliced ? Packet.frameSliced(service: s, command: c, body: body, sliceSize: params.sliceSize)
            : Packet.frameUnsliced(service: s, command: c, body: body)
    }

    func send(_ service: Int, _ command: Int, _ tlv: TLV, encrypt: Bool = true, sliced: Bool = true) throws {
        guard let transport else { throw WatchError.notConnected }
        note(String(format: "→ %02X/%02X  ", service, command) + tlv.description)
        transport.send(try frames(service, command, tlv, encrypt: encrypt, sliced: sliced))
    }

    @discardableResult
    func request(_ service: Int, _ command: Int, _ tlv: TLV, encrypt: Bool = true, sliced: Bool = true,
                 timeout: Double = 6) async throws -> Packet {
        let key = String(format: "%02X/%02X", service, command)
        let id = UUID()
        return try await withCheckedThrowingContinuation { cont in
            waiters.append((id, key, cont))
            do { try send(service, command, tlv, encrypt: encrypt, sliced: sliced) } catch {
                waiters.removeAll { $0.id == id }
                cont.resume(throwing: error)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, let i = self.waiters.firstIndex(where: { $0.id == id }) else { return }
                let w = self.waiters.remove(at: i)
                w.cont.resume(throwing: WatchError.timeout(key))
            }
        }
    }

    // MARK: Handshake

    private var androidId: Data { Data(identity.androidId.utf8) }
    private var clientSerial: Data { Data(identity.fakeMac.replacingOccurrences(of: ":", with: "").suffix(6).utf8) }

    private func handshake() async throws {
        statusDetail = "Negotiating link…"
        var linkReq = TLV().with(1).with(2).with(3).with(4)
        if watchModel?.link == .aw { linkReq.put(6) }
        let link = try await request(0x01, 0x01, linkReq, encrypt: false, sliced: false, timeout: 10)
        let t = link.tlv
        if let v = t.int(0x02) { params.sliceSize = v }
        if let v = t.int(0x03) { params.mtu = v }
        guard let nonce = t.bytes(0x05), nonce.count >= 18 else { throw WatchError.auth("unexpected link parameters") }
        let nb = [UInt8](nonce)
        params.authVersion = Int(nb[1])
        params.serverNonce = Data(nb[2 ..< 18])
        params.deviceSupportType = t.int(0x07) ?? 0
        params.authAlgo = t.int(0x08) ?? 0
        params.encryptMethod = t.int(0x0C) ?? 0
        note("Link: authVersion \(params.authVersion), supportType \(params.deviceSupportType), authAlgo \(params.authAlgo), encryptMethod \(params.encryptMethod), slice \(params.sliceSize)")

        if watchModel?.link == .br || (watchModel == nil && identity.kind == .classic) {
            if let st = try? await request(0x01, 0x16, TLV().with(1), encrypt: false, timeout: 4) {
                note("Device status: \(st.tlv.int(1).map(String.init) ?? "none")")
            }
        }

        let type = params.deviceSupportType
        if [1, 2, 3, 4].contains(type), watchModel?.pake == true {
            params.authMode = type == 4 ? 4 : 2
            try await pake()
        } else if [1, 2, 3, 4].contains(type) {
            params.authMode = type == 4 ? 4 : 2
            var neg = TLV().with(1, byte: params.authMode).with(2, byte: 1).with(5, androidId).with(3, byte: 1).with(4, byte: 0)
            if params.authMode == 4 { neg.put(6); neg.put(7, "Mac") }
            if params.encryptMethod == 1 { neg.put(0x0D, byte: 1) }
            let r = try await request(0x01, 0x33, neg, encrypt: false, timeout: 10)
            var authType = -1
            var pw = -1
            if let a = r.tlv.int(1) { if a == 1 { authType = 0x186A0 }; if a == 4 { pw = 4 } }
            if let b = r.tlv.int(2) { authType = b; if pw != -1 { authType ^= pw } }
            if let e = r.tlv.bytes(0x7F)?.first { authType = Int(e) }
            note("Security negotiation: authType \(authType)")
            if authType == 0x186A0 || (authType ^ 1) == 4 || (authType ^ 2) == 4 {
                try await hiChain()
            } else if authType == 1 || authType == 2 {
                try await liteOrNormal(lite: true)
            } else {
                throw WatchError.auth("the watch refused this pairing mode (code \(authType)). Factory-reset the watch and try again.")
            }
        } else {
            try await liteOrNormal(lite: false)
        }
    }

    private func ensureAuthKey() {
        if identity.authKey == nil { identity.authKey = Data.random(16).hex; saveIdentity() }
        params.secretKey = Data(hex: identity.authKey!)
    }

    private func fetchPinCode() async throws {
        statusDetail = "Requesting pairing code…"
        let r = try await request(0x01, 0x2C, TLV().with(1), encrypt: false, timeout: 15)
        guard let msg = r.tlv.bytes(1), let iv = r.tlv.bytes(2) else { throw WatchError.auth("no pairing code received") }
        params.pinCode = try HWCrypto.crypt(msg, key: params.digestSecret, iv: iv, gcm: params.encryptMethod == 1, encrypt: false)
    }

    private func liteOrNormal(lite: Bool) async throws {
        ensureAuthKey()
        if lite, params.pinCode == nil, params.authVersion != 2 { try await fetchPinCode() }

        statusDetail = "Authenticating… confirm on the watch if it asks"
        let clientNonce = Data.random(16)
        let doubleNonce = params.serverNonce + clientNonce
        var key: Data?
        if params.authMode == 2 { key = params.authVersion == 2 ? params.secretKey : params.pinCode }
        let digest = try params.digestChallenge(key: key, nonce: doubleNonce)
        params.firstKey = digest.subdata(in: 32 ..< 48)
        var auth = TLV().with(1, digest.prefix(32)).with(2, Data.be16(params.authVersion) + clientNonce)
        if params.authMode == 2 { auth.put(3, byte: params.authAlgo) }
        let r = try await request(0x01, 0x13, auth, encrypt: false, timeout: 30)
        let expected = try params.digestResponse(key: key, nonce: doubleNonce).prefix(32)
        guard r.tlv.bytes(1) == Data(expected) else {
            throw WatchError.auth("the watch's answer did not match. If it was paired with a phone before, factory-reset it and try again.")
        }

        guard lite || (watchModel.map { $0.usesLE } ?? (identity.kind == .le)) else { return }
        statusDetail = "Bonding…"
        let bp = try await request(0x01, 0x0F, TLV().with(1).with(3, clientSerial).with(4, byte: 2).with(5)
            .with(7, Data(identity.fakeMac.utf8)).with(9), encrypt: false, timeout: 10)
        params.encryptionCounter = UInt32(truncatingIfNeeded: bp.tlv.int(9) ?? 0)
        if params.authMode != 2, bp.tlv.int(1) == 1 { note("Already bonded"); return }

        let iv = params.nextIV()
        let wrapKey: Data
        if params.authMode == 2 {
            wrapKey = params.firstKey!
        } else {
            var mac = transport?.macAddress ?? identity.watchMac
            if mac.replacingOccurrences(of: ":", with: "").count != 12, let found = await Self.lookupMac(name: identity.name) {
                note("Watch address from system Bluetooth records: \(found)")
                mac = found
                identity.watchMac = found
                saveIdentity()
            }
            guard mac.replacingOccurrences(of: ":", with: "").count == 12 else {
                throw WatchError.auth("this model needs the watch's Bluetooth address to pair. Enter it (watch Settings › About) and connect again.")
            }
            wrapKey = params.bondingWrapKey(mac: mac)
        }
        let wrapped = try HWCrypto.crypt(params.secretKey!, key: wrapKey, iv: iv, gcm: params.encryptMethod == 1, encrypt: true)
        _ = try await request(0x01, 0x0E, TLV().with(1).with(3, byte: 0).with(5, clientSerial).with(6, wrapped).with(7, iv),
                              encrypt: false, timeout: 10)
    }

    // HiChain (ISO-style PSK exchange carried as JSON).
    private func hiChain() async throws {
        if identity.authKey == nil {
            try await fetchPinCode()
            statusDetail = "Pairing… confirm on the watch"
            try await hiChainRun(operation: 1)
        }
        statusDetail = "Authenticating…"
        try await hiChainRun(operation: 2)
    }

    private func hiChainRun(operation op: Int) async throws {
        let groupId = "7B0BC0CBCE474F6C238D9661C63400B797B166EA7849B3A370FC73A9A236E989"
        let requestId = Int64(Date().timeIntervalSince1970 * 1000)
        let authIdSelf = androidId
        let timeout: Double = op == 1 ? 30 : 8

        func exchange(step: Int, payload extra: [String: Any], deviceLevel: Bool = false) async throws -> [String: Any]? {
            var payload: [String: Any] = ["version": ["minVersion": "1.0.0", "currentVersion": "2.0.16"]]
            extra.forEach { payload[$0] = $1 }
            var value: [String: Any] = ["authForm": 0, "payload": payload, "groupAndModuleVersion": "2.0.1",
                                        "message": op == 2 ? step | 0x10 : step]
            if op == 1 {
                value["requestId"] = String(requestId); value["groupId"] = groupId; value["groupName"] = "health_group_name"
                value["groupOp"] = 2; value["groupType"] = 256; value["peerDeviceId"] = identity.androidId
                value["connDeviceId"] = identity.androidId; value["appId"] = "com.huawei.health"; value["ownerName"] = ""
            }
            if deviceLevel { value["isDeviceLevel"] = false }
            let json = try JSONSerialization.data(withJSONObject: value)
            let r = try await request(0x01, 0x28, TLV().with(1, json).with(2, byte: op).with(3, Data.be64(requestId)),
                                      encrypt: false, timeout: timeout)
            guard r.tlv.has(4) else { throw WatchError.auth("unexpected pairing reply") }
            if r.tlv.int(4) != 0 { return nil }      // final acknowledgement
            guard let js = r.tlv.bytes(1), let obj = try JSONSerialization.jsonObject(with: js) as? [String: Any],
                  let pl = obj["payload"] as? [String: Any] else { throw WatchError.auth("unreadable pairing reply") }
            if let code = pl["errorCode"] as? Int, code != 0 {
                throw WatchError.auth("the watch rejected pairing (error \(code)). Factory-reset the watch, then pair again.")
            }
            return pl
        }
        func hexField(_ d: [String: Any]?, _ k: String) throws -> Data {
            guard let s = d?[k] as? String else { throw WatchError.auth("pairing reply is missing \(k)") }
            return Data(hex: s)
        }

        // Step 1
        let seed = Data.random(32), randSelf = Data.random(16)
        var p1: [String: Any] = ["isoSalt": randSelf.hex, "peerAuthId": authIdSelf.hex, "operationCode": op,
                                 "seed": seed.hex, "peerUserType": 0]
        if op == 2 { p1["pkgName"] = "com.huawei.devicegroupmanage"; p1["serviceType"] = groupId; p1["keyLength"] = 32 }
        let r1 = try await exchange(step: 1, payload: p1, deviceLevel: op == 2)
        let randPeer = try hexField(r1, "isoSalt"), authIdPeer = try hexField(r1, "peerAuthId"), peerToken = try hexField(r1, "token")
        let baseKey: Data
        if op == 1 {
            guard let pin = params.pinCode else { throw WatchError.auth("no pairing code") }
            baseKey = HWCrypto.sha256(Data(pin.hex.utf8))
        } else {
            guard let k = identity.authKey else { throw WatchError.auth("no stored key") }
            baseKey = Data(hex: k)
        }
        let psk = HWCrypto.hmac(key: baseKey, seed)
        guard HWCrypto.hmac(key: psk, randPeer + randSelf + authIdSelf + authIdPeer) == peerToken else {
            if op == 2 { identity.authKey = nil; saveIdentity() }
            throw WatchError.auth(op == 2 ? "the saved pairing is no longer valid. Factory-reset the watch and connect again to pair from scratch."
                                          : "the pairing code did not verify.")
        }

        // Step 2
        let selfToken = HWCrypto.hmac(key: psk, randSelf + randPeer + authIdPeer + authIdSelf)
        let r2 = try await exchange(step: 2, payload: ["peerAuthId": authIdSelf.hex, "token": selfToken.hex], deviceLevel: op == 2)
        guard try hexField(r2, "returnCodeMac") == HWCrypto.hmac(key: psk, Data(count: 4)) else {
            throw WatchError.auth("pairing confirmation mismatch")
        }

        // Step 3 (bind only) and 4
        let salt = randSelf + randPeer
        let sessionKey = HWCrypto.hkdf(key: psk, salt: salt, info: Data("hichain_iso_session_key".utf8), length: 32)
        if op == 1 {
            let nonce = Data.random(12), challenge = Data.random(16)
            let enc = try HWCrypto.gcmEncrypt(challenge, key: sessionKey, iv: nonce, aad: Data("hichain_iso_exchange".utf8))
            let r3 = try await exchange(step: 3, payload: ["nonce": nonce.hex, "encData": enc.hex])
            let token = try HWCrypto.gcmDecrypt(try hexField(r3, "encAuthToken"), key: sessionKey, iv: try hexField(r3, "nonce"), aad: challenge)
            identity.authKey = token.hex
            saveIdentity()
            note("Pairing key stored")
        }
        let nonce = Data.random(12)
        let encResult = try HWCrypto.gcmEncrypt(Data(count: 4), key: sessionKey, iv: nonce, aad: Data("hichain_iso_result".utf8))
        _ = try await exchange(step: 4, payload: ["nonce": nonce.hex, "encResult": encResult.hex, "operationCode": op])
        if op == 2 {
            params.secretKey = HWCrypto.hkdf(key: sessionKey, salt: salt, info: Data("hichain_return_key".utf8), length: 32)
        }
    }

    func linkDecrypt(_ t: TLV) throws -> Data { try params.decrypt(t) }

    // MARK: HiChain PAKE (Honor Watch 5 / 5 Pro / 6)

    private func pakeSeed() -> Data {
        if identity.pakeSeed == nil { identity.pakeSeed = Data.random(32).hex; saveIdentity() }
        return Data(hex: identity.pakeSeed!)
    }

    /// Sends one PAKE JSON message and returns the payload of the watch's reply (nil when it reports completion).
    private func pakeMessage(_ id: Int, _ payload: [(String, Any)], first: Bool, op: Int, authForm: Bool = false) async throws -> [String: Any]? {
        var body = payload
        if first {
            body.append(("version", [("minVersion", "1.0.0"), ("currentVersion", "2.0.15")] as [(String, Any)]))
            body.append(("operationCode", op))
        }
        var value: [(String, Any)] = []
        if authForm { value.append(("authForm", 0)) }
        value += [("message", id), ("payload", body)]
        let r = try await request(0x01, 0x28, TLV().with(1, byte: 2).with(2, orderedJSON(value)), encrypt: false, timeout: 30)
        if r.tlv.int(1) == 3 { return nil }
        guard r.tlv.int(1) == 2, let js = r.tlv.bytes(2), let obj = try JSONSerialization.jsonObject(with: js) as? [String: Any],
              let pl = obj["payload"] as? [String: Any] else { throw WatchError.auth("unexpected pairing reply") }
        if let code = pl["errorCode"] as? Int, code != 0 {
            throw WatchError.auth("the watch rejected pairing (error \(code)). Factory-reset the watch, then pair again.")
        }
        return pl
    }

    private func hexField(_ d: [String: Any]?, _ k: String) throws -> Data {
        guard let s = d?[k] as? String else { throw WatchError.auth("pairing reply is missing \(k)") }
        return Data(hex: s)
    }

    private func pake() async throws {
        let known = identity.pakePeerPk != nil
        let r = try await request(0x01, 0x33, TLV().with(1, byte: params.authMode).with(2, byte: known ? 2 : 1).with(3, androidId),
                                  encrypt: false, timeout: 10)
        let pairType = r.tlv.int(2) ?? -1
        note("PAKE negotiation: pair type \(pairType)")
        if pairType == 2, known {
            do { try await pakeReconnect() } catch {
                identity.pakePeerId = nil; identity.pakePeerPk = nil; saveIdentity()
                throw WatchError.auth("the saved pairing was not accepted (\(error.localizedDescription)). Connect again to pair from scratch.")
            }
        } else {
            try await pakeBind()
        }
        ensureAuthKey()
    }

    private func pakeBind() async throws {
        statusDetail = "Pairing… confirm on the watch"
        // 1. X25519 exchange: both sides derive the same pairing PIN.
        let devPriv = Data.random(32)
        let r0 = try await request(0x01, 0x28, TLV().with(1, byte: 1).with(2, try Pake.x25519Base(devPriv)), encrypt: false, timeout: 30)
        guard r0.tlv.int(1) == 1, let peerPub = r0.tlv.bytes(2) else { throw WatchError.auth("unexpected key-exchange reply") }
        let pin = Pake.derivePin(try Pake.x25519(devPriv, peerPub))
        // 2. SPEKE.
        let p1 = try await pakeMessage(1, [("support256mod", true), ("serviceType", "WEAR_MBB")], first: true, op: 1)
        let speke = try Pake.Speke(pinHex: pin, peerChallenge: try hexField(p1, "challenge"), salt: try hexField(p1, "salt"),
                                   peerEpk: try hexField(p1, "epk"))
        let p2 = try await pakeMessage(2, [("challenge", speke.selfChallenge.hex), ("epk", speke.selfPublic.hex), ("kcfData", speke.proof.hex)],
                                       first: false, op: 1)
        guard speke.verifyServer(try hexField(p2, "kcfData")) else { throw WatchError.auth("the watch's pairing proof did not verify") }
        // 3. Exchange signed identities.
        let me = try Curve25519.Signing.PrivateKey(rawRepresentation: pakeSeed())
        let info = Data(orderedJSON([("authId", androidId.hex), ("authPk", me.publicKey.rawRepresentation.hex)]).utf8)
        let sig = try me.signature(for: Data(SHA256.hash(data: speke.selfChallenge + speke.peerChallenge + info)))
        let ex = try Pake.seal(info + sig, key: speke.sessionKey, aad: Pake.exchangeRequestAAD)
        let p3 = try await pakeMessage(3, [("exAuthInfo", ex.hex)], first: false, op: 1)
        let plain = try Pake.open(try hexField(p3, "exAuthInfo"), key: speke.sessionKey, aad: Pake.exchangeResponseAAD)
        guard plain.count > 64 else { throw WatchError.auth("bad identity reply") }
        let peerInfo = plain.prefix(plain.count - 64), peerSig = plain.suffix(64)
        guard let pj = try JSONSerialization.jsonObject(with: peerInfo) as? [String: Any],
              let pid = pj["authId"] as? String, let ppk = pj["authPk"] as? String else { throw WatchError.auth("bad identity reply") }
        let peerKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(hex: ppk))
        guard peerKey.isValidSignature(peerSig, for: Data(SHA256.hash(data: speke.peerChallenge + speke.selfChallenge + peerInfo))) else {
            throw WatchError.auth("the watch's identity signature did not verify")
        }
        identity.pakePeerId = pid; identity.pakePeerPk = ppk; saveIdentity()
        note("PAKE pairing complete; watch identity stored")
    }

    private func pakeReconnect() async throws {
        statusDetail = "Authenticating…"
        let ephemeral = try Pake.x25519Base(Data.random(32))
        let p1 = try await pakeMessage(17, [("challenge", Data.random(16).hex), ("epk", ephemeral.hex), ("serviceType", "WEAR_MBB"),
                                            ("peerAuthId", androidId.hex), ("keyLength", 32), ("keyInfoSize", 0)],
                                       first: true, op: 2, authForm: true)
        guard let peerPk = identity.pakePeerPk else { throw WatchError.auth("no stored watch identity") }
        let psk = try Pake.x25519(Pake.ed25519PrivateToX25519(pakeSeed()), Pake.ed25519PublicToX25519(Data(hex: peerPk)))
        let pin = Pake.lowerHex(HWCrypto.hkdf(key: psk, salt: try hexField(p1, "nonce"), info: Pake.tmpAuthKeyInfo, length: 32))
        let speke = try Pake.Speke(pinHex: pin, peerChallenge: try hexField(p1, "challenge"), salt: try hexField(p1, "salt"),
                                   peerEpk: try hexField(p1, "epk"))
        let p2 = try await pakeMessage(18, [("challenge", speke.selfChallenge.hex), ("epk", speke.selfPublic.hex), ("kcfData", speke.proof.hex)],
                                       first: false, op: 2, authForm: true)
        guard speke.verifyServer(try hexField(p2, "kcfData")) else { throw WatchError.auth("reconnect proof did not verify") }
    }

    /// Address of a classic-Bluetooth watch already paired with this Mac, found by name.
    nonisolated static func pairedClassicAddress(name: String) -> String? {
        for case let d as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] where d.name == name {
            return d.addressString?.uppercased().replacingOccurrences(of: "-", with: ":")
        }
        return nil
    }

    // MARK: Post-auth setup

    private func configure() async throws {
        statusDetail = "Reading device information…"
        var req = TLV()
        let infoTags = watchModel?.link == .aw ? [0x01, 0x02, 0x03, 0x07, 0x09, 0x0A, 0x0C, 0x11]
            : [0x01, 0x02, 0x07, 0x09, 0x0A, 0x11, 0x12, 0x16, 0x1A, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23]
        for t in infoTags { req.put(t) }
        let info = try await request(0x01, 0x07, req, timeout: 10)
        firmware = info.tlv.string(0x07) ?? ""
        serial = info.tlv.string(0x09) ?? ""
        model = (info.tlv.string(0x0A) ?? "").trimmingCharacters(in: .whitespaces)
        if let n = info.tlv.string(0x11), !n.isEmpty { deviceName = n }

        try? await syncTime()
        try? await refreshBattery()

        let known: [UInt8] = [0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13,
                              0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1D, 0x20, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2A, 0x2B,
                              0x2D, 0x2E, 0x30, 0x32, 0x33, 0x34, 0x35]
        if let r = try? await request(0x01, 0x02, TLV().with(1, Data(known))), let flags = r.tlv.bytes(2) {
            services = Set(zip(known, flags).filter { $0.1 == 1 }.map { Int($0.0) })
            note("Supported services: " + services.sorted().map { String(format: "%02X", $0) }.joined(separator: " "))
        }
        // Re-apply the wrist settings on every connection, as the phone app does; the watch does not always keep them.
        let ud = UserDefaults.standard
        let raise = ud.object(forKey: "set.raise") as? Bool ?? true
        let right = ud.bool(forKey: "set.right")
        _ = try? await request(0x01, 0x1A, TLV().with(1, byte: right ? 0 : 1), timeout: 4)
        _ = try? await request(0x01, 0x09, TLV().with(1, raise), timeout: 4)
        if let r = try? await request(0x01, 0x1D, TLV().with(1), timeout: 4) { note("Raise-to-wake during do-not-disturb mode: \(r.tlv.description)") }
        // Turn on notification delivery.
        try? send(0x02, 0x04, TLV().with(0x81, TLV().with(2, true).with(3, true)))
    }

    func refreshAll() async {
        try? await refreshTotals()
        try? await refreshFaces()
        try? await refreshAlarms()
    }

    func run(_ what: String, _ body: @escaping () async throws -> Void) {
        Task {
            do { try await body(); lastError = nil } catch {
                lastError = "\(what): \(error.localizedDescription)"
                note("ERROR " + lastError!)
            }
        }
    }

    // MARK: Status & find

    func refreshBattery() async throws {
        let r = try await request(0x01, 0x08, TLV().with(1))
        battery = r.tlv.int(1)
    }

    func syncTime() async throws {
        let now = Date()
        let offset = TimeZone.current.secondsFromGMT(for: now)
        let hours = offset < 0 ? (-offset / 3600 + 128) : offset / 3600
        let zone = Data([UInt8(truncatingIfNeeded: hours), UInt8(truncatingIfNeeded: abs(offset) / 60 % 60)])
        try await request(0x01, 0x05, TLV().with(1, int: Int(now.timeIntervalSince1970)).with(2, zone))
    }

    func findWatch(start: Bool) {
        run("Find watch") { [self] in
            let item = TLV().with(5, int: 900_100_002).with(6, byte: start ? 2 : 1)
            do {
                try await request(0x37, 0x01, TLV().with(1, "hw.unitedevice.finddevice").with(2, "findDevice")
                    .with(0x83, TLV().with(0x84, item)), timeout: 4)
            } catch WatchError.timeout {
                // Older models have no "find" service: buzz the watch with a notification instead.
                if start { try sendNotificationNow(title: "Find my watch", sender: "WatchDeck", body: "Here I am!") }
            }
        }
    }

    private func stopFindPhoneSound() {
        findPhoneSound?.stop(); findPhoneSound = nil; findingPhone = false
    }

    func stopFindPhone() {
        stopFindPhoneSound()
        try? send(0x0B, 0x02, TLV().with(1, byte: 2))
    }

    // MARK: Notifications

    private func sendNotificationNow(title: String, sender: String, body: String, type: Int = 0x7F) throws {
        notificationCounter = (notificationCounter + 1) & 0x7FFF
        var elements = TLV()
        for (kind, text) in [(3, title), (2, sender), (1, body)] {
            var el = TLV().with(0x0E, byte: kind).with(0x0F, byte: 2)
            if !text.isEmpty { el.put(0x10, String(text.prefix(240))) }
            elements.put(0x8D, el)
        }
        let tlv = TLV().with(1, short: notificationCounter).with(2, byte: type).with(3, true)
            .with(0x84, TLV().with(0x8C, elements)).with(0x11, "com.lemonspitz.watchdeck")
        try send(0x02, 0x01, tlv)
    }

    func sendNotification(title: String, sender: String, body: String, type: Int = 0x7F) {
        run("Send notification") { [self] in try sendNotificationNow(title: title, sender: sender, body: body, type: type) }
    }

    // MARK: Health

    func refreshTotals() async throws {
        let r = try await request(0x07, 0x03, TLV().with(1))
        var steps = 0, cal = 0, dist = 0
        for t in r.tlv.object(0x81)?.objects(0x83) ?? [] {
            steps += t.int(5) ?? 0; cal += t.int(6) ?? 0; dist += t.int(7) ?? 0
        }
        totalSteps = steps; totalCalories = cal; totalDistance = dist
        dayTotals[Storage.dayKey(Date())] = DayTotal(steps: steps, calories: cal, distance: dist)
    }

    func syncHealth(days: Int) {
        guard !syncing else { return }
        syncing = true
        run("Health sync") { [self] in
            defer { syncing = false }
            try await refreshTotals()
            let end = Int(Date().timeIntervalSince1970)
            let start = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970) - (days - 1) * 86400
            let c = try await request(0x07, 0x0A, TLV().with(0x81).with(3, int: start).with(4, int: end), timeout: 15)
            let count = c.tlv.object(0x81)?.int(2) ?? 0
            note("Step data frames: \(count)")
            var out: [Date: StepSample] = [:]
            var i = 0
            while i < count {
                let r = try await request(0x07, 0x0B, TLV().with(0x81, TLV().with(2, short: i)), timeout: 15)
                guard let c81 = r.tlv.object(0x81) else { break }
                let base = c81.int(3) ?? 0
                for sub in c81.objects(0x84) {
                    guard let off = sub.int(5), let d = sub.bytes(6) else { continue }
                    let time = Date(timeIntervalSince1970: TimeInterval(base + 60 * off))
                    if let s = Self.parseStepData(d, time: time) { out[time] = s }
                }
                i += 1
            }
            var merged = Dictionary(samples.map { ($0.time, $0) }, uniquingKeysWith: { $1 })
            out.forEach { merged[$0] = $1 }
            samples = merged.values.sorted { $0.time < $1.time }
            lastSync = Date()
            storeHealth()

            // Sleep: segments of light (6) and deep (7) sleep.
            do {
                let sc = try await request(0x07, 0x0C, TLV().with(0x81).with(3, int: start - 86400).with(4, int: end), timeout: 15)
                let n = sc.tlv.object(0x81)?.int(2) ?? 0
                note("Sleep data frames: \(n)")
                var segs = Dictionary(sleep.map { ($0.start, $0) }, uniquingKeysWith: { $1 })
                var j = 0
                while j < n {
                    let r = try await request(0x07, 0x0D, TLV().with(0x81, TLV().with(2, short: j)), timeout: 15)
                    for sub in r.tlv.object(0x81)?.objects(0x83) ?? [] {
                        guard let type = sub.int(4), let ts = sub.bytes(5), ts.count >= 6 else { continue }
                        let b = [UInt8](ts)
                        let begin = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
                        let minutes = Int(b[4]) << 8 | Int(b[5])
                        guard begin > 0, minutes > 0 else { continue }
                        guard type == 6 || type == 7 else { note("Ignoring non-sleep marker type \(type)"); continue }
                        let st = Date(timeIntervalSince1970: TimeInterval(begin))
                        segs[st] = SleepSegment(start: st, end: st.addingTimeInterval(TimeInterval(minutes * 60)), type: type)
                    }
                    j += 1
                }
                sleep = segs.values.sorted { $0.start < $1.start }
            } catch WatchError.timeout {
                note("The watch did not answer the sleep request")
            }
            storeHealth()
            try? await syncWorkouts()
        }
    }

    nonisolated static func parseStepData(_ data: Data, time: Date) -> StepSample? {
        let d = [UInt8](data)
        guard !d.isEmpty else { return nil }
        var i = 0
        let bm1 = d[i]; i += 1
        var bm2: UInt8 = 0
        if bm1 & 0x80 != 0 { guard i < d.count else { return nil }; bm2 = d[i]; i += 1 }
        var s = StepSample(time: time)
        var bit: UInt8 = 1
        while bit < 0x80 {
            if bm1 & bit != 0 {
                var value = 0
                if bit == 0x20 || bit == 0x40 {
                    guard i < d.count else { return nil }
                    value = Int(d[i]); i += 1
                } else {
                    guard i + 1 < d.count else { return nil }
                    value = Int(d[i]) << 8 | Int(d[i + 1]); i += 2
                }
                switch bit {
                case 0x02: s.steps = value
                case 0x04: s.calories = value
                case 0x08: s.distance = value
                case 0x40: if value > 0 { s.heartRate = value }
                default: break
                }
            }
            bit <<= 1
        }
        var bit2 = 1
        while bit2 < 0x100 {
            if Int(bm2) & bit2 != 0 {
                guard i < d.count else { return nil }
                let v = Int(d[i]); i += 1
                if bit2 == 1, v > 0 { s.spo2 = v }
            }
            bit2 <<= 1
        }
        return s
    }

    // MARK: Settings

    func setting(_ name: String, _ service: Int, _ command: Int, _ tlv: TLV) {
        run(name) { [self] in try await request(service, command, tlv) }
    }

    func setRaiseToWake(_ on: Bool) { setting("Raise to wake", 0x01, 0x09, TLV().with(1, on)) }
    func setRotateToSwitch(_ on: Bool) { setting("Rotate to switch", 0x01, 0x1B, TLV().with(1, on)) }
    func setWearRight(_ right: Bool) { setting("Wearing wrist", 0x01, 0x1A, TLV().with(1, byte: right ? 0 : 1)) }   // the watch uses 1 = left, 0 = right
    func setAutoHeartRate(_ on: Bool) { setting("Continuous heart rate", 0x07, 0x17, TLV().with(1, on)) }
    func setAutoSpO2(_ on: Bool) { setting("Automatic SpO₂", 0x07, 0x24, TLV().with(1, on)) }
    func setTimeFormat(is24h: Bool, dateFormat: Int) {
        setting("Time format", 0x01, 0x04, TLV().with(0x81, TLV().with(2, byte: dateFormat).with(3, byte: is24h ? 2 : 1)))
    }
    func setLanguage(_ locale: String, imperial: Bool) {
        setting("Language", 0x0C, 0x01, TLV().with(1, locale).with(2, byte: imperial ? 1 : 0))
    }
    func setStepGoal(_ steps: Int) {
        setting("Step goal", 0x07, 0x01, TLV().with(0x81, TLV().with(0x82, TLV().with(3, byte: 1).with(4, byte: 0).with(5, int: steps))))
    }
    func setDoNotDisturb(enabled: Bool, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        run("Do not disturb") { [self] in
            if enabled {
                let dnd = TLV().with(2, byte: 1).with(3, true).with(4, byte: 0)
                    .with(5, Data([UInt8(startHour), UInt8(startMinute)])).with(6, Data([UInt8(endHour), UInt8(endMinute)])).with(7, byte: 0x7F)
                try await request(0x01, 0x0C, TLV().with(0x81, dnd))
            } else {
                try await request(0x01, 0x0B, TLV().with(0x81, TLV().with(2, byte: 1)))
            }
        }
    }
    func syncTimeNow() { run("Time sync") { [self] in try await syncTime() } }
    func refreshBatteryNow() { run("Battery") { [self] in try await refreshBattery() } }
    func factoryReset() { run("Factory reset") { [self] in try send(0x01, 0x0D, TLV().with(1, byte: 1)) } }

    // MARK: Alarms

    func refreshAlarms() async throws {
        let r = try await request(0x08, 0x03, TLV().with(1))
        alarms = (r.tlv.object(0x81)?.objects(0x82) ?? []).compactMap { t in
            guard let idx = t.int(3), let hm = t.int(5) else { return nil }
            return WatchAlarm(index: idx, enabled: t.int(4) == 1, hour: (hm >> 8) & 0xFF, minute: hm & 0xFF,
                              repeatMask: t.int(6) ?? 0, name: t.string(7) ?? "Alarm")
        }
    }

    func saveAlarms(_ list: [WatchAlarm]) {
        run("Alarms") { [self] in
            var all = TLV()
            for (i, a) in list.prefix(5).enumerated() {
                all.put(0x82, TLV().with(3, byte: i + 1).with(4, a.enabled).with(5, short: a.hour << 8 | a.minute)
                    .with(6, byte: a.repeatMask).with(7, a.name))
            }
            if list.isEmpty { all.put(0x82, TLV().with(3, byte: 1)) }
            try await request(0x08, 0x01, TLV().with(0x81, all))
            alarms = list.prefix(5).enumerated().map { var a = $1; a.index = $0 + 1; return a }
        }
    }

    // MARK: Watch faces

    func refreshFaces() async throws {
        if let p = try? await request(0x27, 0x01, TLV().with(1).with(2).with(3).with(4).with(5).with(0x0E).with(0x0F)),
           let w = p.tlv.int(2), let h = p.tlv.int(3) {
            faceSize = "\(w) × \(h)"
            if librarySize != faceSize { librarySize = faceSize; reloadLibrary() }
        }
        let r = try await request(0x27, 0x02, TLV().with(1).with(6, byte: 3), timeout: 10)
        var list: [WatchFace] = (r.tlv.object(0x81)?.objects(0x82) ?? []).compactMap { t in
            guard let name = t.string(3) else { return nil }
            return WatchFace(fileName: name, version: t.string(4) ?? "", type: t.int(5) ?? 0)
        }
        if !list.isEmpty {
            var names = TLV()
            for f in list { names.put(0x83, TLV().with(4, f.fileName)) }
            if let n = try? await request(0x27, 0x06, TLV().with(1, byte: 1).with(0x82, names), timeout: 10) {
                for t in n.tlv.object(0x82)?.objects(0x83) ?? [] {
                    if let file = t.string(4), let i = list.firstIndex(where: { $0.fileName == file }) { list[i].title = t.string(5) }
                }
            }
        }
        faces = list
    }

    func refreshFacesNow() { run("Watch faces") { [self] in try await refreshFaces() } }

    func faceOperation(_ face: WatchFace, delete: Bool) {
        run(delete ? "Delete watch face" : "Set watch face") { [self] in
            try await request(0x27, 0x03, TLV().with(1, face.fileName).with(2, face.version).with(3, byte: delete ? 2 : 1), timeout: 10)
            try await refreshFaces()
        }
    }

    func installFace(from url: URL, named: ((String) -> Void)? = nil) {
        run("Install watch face") { [self] in
            guard upload == nil else { throw WatchError.unsupported("another upload is still running") }
            let data = try HWT.payload(url)
            let name = String(format: "%09d_1.0.0", Int.random(in: 0 ..< 1_000_000_000))
            upload = (data, name, 0, 0, true)
            onUploadNamed = named
            uploadProgress = 0
            let parts = name.split(separator: "_").map(String.init)
            do {
                let r = try await request(0x28, 0x02, TLV().with(1, name).with(2, int: data.count).with(3, byte: 1)
                    .with(5, parts[0]).with(6, parts[1]), timeout: 15)
                if let code = r.tlv.int(0x7F), code != 0x186A0 { throw WatchError.unsupported("the watch refused the file (code \(code))") }
            } catch {
                upload = nil; uploadProgress = nil
                throw error
            }
        }
    }

    // MARK: Messages initiated by the watch

    private func handleAsync(_ p: Packet) {
        let t = p.tlv
        switch (p.service, p.command) {
        case (0x01, 0x27), (0x01, 0x08):
            if let b = t.int(1) { battery = b }
        case (0x0A, 0x05), (0x2C, 0x05):
            if let d = fileBlockPayload(p) { fileBlockSink?(d) }
        case (0x01, 0x38):
            // The watch asks whether the phone may do something (e.g. reply to SMS); answer "no".
            try? send(0x01, 0x38, TLV().with(1, short: t.int(1) ?? 0).with(2, short: 0))
        case (0x01, 0x10):
            // The watch asks about the "phone"; answer with neutral values so it stops asking.
            if t.items.count == 1, t.has(0x7F) { return }
            var reply = TLV()
            for (tag, _) in t.items {
                switch tag {
                case 0x00, 0x0F: break
                case 0x02, 0x04, 0x15: reply.put(Int(tag))
                case 0x08: reply.put(Int(tag), "14")
                case 0x11: reply.put(Int(tag), int: 1_600_103_320)
                default: reply.put(Int(tag), byte: 0)
                }
            }
            try? send(0x01, 0x10, reply)
        case (0x0B, 0x01):
            if t.int(1) == 1 {
                findingPhone = true
                let s = NSSound(named: "Submarine"); s?.loops = true; s?.play(); findPhoneSound = s
            } else { stopFindPhoneSound() }
        case (0x28, 0x03):
            guard var u = upload, let fid = t.int(1) else { return }
            u.fileId = fid; upload = u
            try? send(0x28, 0x03, TLV().with(1, byte: fid).with(3, HWCrypto.sha256(u.data)))
        case (0x28, 0x04):
            guard var u = upload else { return }
            u.unit = t.int(5) ?? 0
            let noEncrypt = t.int(9) ?? 0
            u.encrypt = noEncrypt == 0
            upload = u
            var ack = TLV().with(0x7F, int: 0x186A0).with(1, byte: u.fileId)
            if noEncrypt == 1 { ack.put(9, byte: 1) }
            try? send(0x28, 0x04, ack)
        case (0x28, 0x05):
            guard let u = upload, let offset = t.int(2), let size = t.int(3), u.unit > 0, let transport else { return }
            uploadProgress = Double(offset) / Double(max(1, u.data.count))
            let end = min(u.data.count, offset + size)
            guard offset < end else { return }
            var pos = offset, index = 0
            var frames: [Data] = []
            while pos < end {
                let n = min(u.unit, end - pos)
                var payload = Data([UInt8(u.fileId), UInt8(truncatingIfNeeded: index)]) + Data.be32(pos) + u.data.subdata(in: pos ..< pos + n)
                if u.encrypt, params.secretKey != nil, let enc = try? params.encrypt(payload) { payload = enc.data }
                frames += Packet.frameSliced(service: 0x28, command: 0x06, body: payload, sliceSize: params.sliceSize)
                pos += n; index += 1
            }
            transport.send(frames)
        case (0x28, 0x07):
            guard let u = upload else { return }
            try? send(0x28, 0x07, TLV().with(0x7F, int: 0x186A0).with(1, byte: u.fileId))
            upload = nil; uploadProgress = nil
            note("Upload finished")
            onUploadNamed?(String(u.name.split(separator: "_").first ?? ""))
            onUploadNamed = nil
            Task { try? await Task.sleep(nanoseconds: 2_000_000_000); try? await refreshFaces() }
        case (0x28, 0x08):
            if let code = t.int(0x7F), code != 0x186A0, upload != nil {
                upload = nil; uploadProgress = nil
                lastError = "Install watch face: the watch reported error \(code)"
            }
        case (0x27, 0x05):
            guard let name = t.string(1) else { return }
            let version = t.string(2) ?? ""
            try? send(0x27, 0x05, TLV().with(1, name).with(2, version).with(0x7F, int: 0x186A0))
            if t.int(3) == 2 { try? send(0x27, 0x03, TLV().with(1, name).with(2, version).with(3, byte: 1)) }
        default:
            break
        }
    }
}
