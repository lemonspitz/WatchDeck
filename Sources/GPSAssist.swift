// GPS assist: gives the watch this Mac's position and the exact time so its GPS chip can start its
// satellite search from the right place instead of from scratch.
import Foundation
import CoreLocation

final class LocationHelper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []
    private(set) var last: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var denied: Bool { manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted }

    /// A recent fix if we have one, otherwise asks the system (waits up to 20 seconds).
    func current() async -> CLLocation? {
        if let l = last, l.timestamp.timeIntervalSinceNow > -600 { return l }
        if denied { return nil }
        return await withCheckedContinuation { cont in
            waiting.append(cont)
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
            manager.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.finish(self?.last) }
        }
    }

    private func finish(_ l: CLLocation?) {
        let w = waiting
        waiting.removeAll()
        w.forEach { $0.resume(returning: l) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let l = locations.last { last = l; finish(l) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(last) }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if !waiting.isEmpty, !denied, manager.authorizationStatus != .notDetermined { manager.requestLocation() }
        if denied { finish(nil) }
    }
}

extension WatchSession {
    static let locator = LocationHelper()

    /// Sends exact time, time zone and approximate position to the watch.
    func sendGPSAssist() async {
        guard isReady else { return }
        gpsAssistStatus = "Finding this Mac's location…"
        try? await syncTime()
        guard let loc = await Self.locator.current() else {
            gpsAssistStatus = Self.locator.denied
                ? "Location access is off. Allow WatchDeck in System Settings › Privacy & Security › Location Services."
                : "This Mac could not determine its location (Wi-Fi must be on)."
            note("GPS assist: no location available")
            return
        }
        var lat = Data(), lon = Data()
        withUnsafeBytes(of: loc.coordinate.latitude.bitPattern.littleEndian) { lat = Data($0) }
        withUnsafeBytes(of: loc.coordinate.longitude.bitPattern.littleEndian) { lon = Data($0) }
        let tlv = TLV().with(1, int: Int(loc.timestamp.timeIntervalSince1970)).with(2, lat).with(3, lon)
        do {
            let r = try await request(0x18, 0x07, tlv, timeout: 6)
            let ok = r.tlv.int(0x7F).map { $0 == 0x186A0 } ?? true
            let when = Date().formatted(date: .omitted, time: .shortened)
            gpsAssistStatus = ok
                ? "Sent at \(when): position within about \(Int(loc.horizontalAccuracy)) m, plus exact time."
                : "The watch refused the position hint (code \(r.tlv.int(0x7F) ?? -1))."
            note("GPS assist sent (accuracy \(Int(loc.horizontalAccuracy)) m), watch replied: \(r.tlv.description)")
        } catch {
            gpsAssistStatus = "The watch did not answer the position hint; only the time was synced."
            note("GPS assist: no reply to position hint")
        }
    }

    func startGPSAssistLoop() {
        Task {
            while isReady {
                if UserDefaults.standard.object(forKey: "set.gpsAssist") as? Bool ?? true { await sendGPSAssist() }
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
        }
    }
}
