// Workouts: summaries, per-second samples, pace splits and GPS tracks synced from the watch and kept on this Mac.
import Foundation
import AppKit

struct TrackPoint: Codable, Equatable {
    var t: Date
    var lat: Double
    var lon: Double
    var alt: Double?
    var pause: Bool
}

struct WorkoutSample: Codable, Identifiable {
    var id: Date { t }
    var t: Date
    var hr: Int?
    var speed: Double?          // m/s
    var cadence: Int?           // steps per minute
}

struct PaceSplit: Codable, Identifiable {
    var id: Int { index }
    var index: Int
    var distance: Int           // kilometres (or miles when unit == 1) covered at the end of the split
    var unit: Int
    var pace: Int               // seconds per kilometre / mile
}

struct Workout: Codable, Identifiable {
    var id: String { "\(Int(start.timeIntervalSince1970))" }
    var number: Int
    var type: Int
    var start: Date
    var end: Date
    var duration: Int           // seconds of activity
    var calories: Int?
    var distance: Int?          // metres
    var steps: Int?
    var ascent: Int?
    var descent: Int?
    var hrMin: Int?
    var hrMax: Int?
    var samples: [WorkoutSample] = []
    var splits: [PaceSplit] = []
    var track: [TrackPoint] = []

    var name: String { workoutTypeNames[type] ?? "Workout" }
    var symbol: String { workoutSymbols[type] ?? "figure.mixed.cardio" }
    var avgHR: Int? {
        let v = samples.compactMap(\.hr)
        return v.isEmpty ? nil : v.reduce(0, +) / v.count
    }
    /// Seconds per kilometre, from distance and duration.
    var avgPace: Int? {
        guard let d = distance, d > 50, duration > 0 else { return nil }
        return Int(Double(duration) / (Double(d) / 1000))
    }
    /// Distance along the GPS track, used when the watch reports none.
    var trackDistance: Double {
        var total = 0.0
        for (a, b) in zip(track, track.dropFirst()) where !b.pause { total += haversine(a, b) }
        return total
    }
}

func haversine(_ a: TrackPoint, _ b: TrackPoint) -> Double {
    let r = 6_371_000.0, rad = Double.pi / 180
    let dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad
    let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * rad) * cos(b.lat * rad) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * asin(min(1, h.squareRoot()))
}

func paceText(_ s: Int) -> String { String(format: "%d'%02d\"", s / 60, s % 60) }
func durationText(_ s: Int) -> String {
    s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

/// Workout type codes used by Huawei watches.
let workoutTypeNames: [Int: String] = [
    1: "Outdoor Run", 2: "Outdoor Walk", 3: "Outdoor Cycle", 4: "Mountain Hike", 5: "Indoor Run", 6: "Pool Swim",
    7: "Indoor Cycle", 8: "Open Water Swim", 11: "Trail Run", 13: "Indoor Walk", 14: "Hiking", 21: "Jump Rope",
    22: "Free Diving", 25: "Scuba Diving", 128: "Table Tennis", 129: "Badminton", 130: "Tennis", 131: "Football",
    132: "Basketball", 133: "Volleyball", 134: "Elliptical", 135: "Rowing Machine", 136: "Stepper", 137: "Yoga",
    138: "Pilates", 139: "Aerobics", 140: "Strength Training", 141: "Spinning", 142: "Air Walker", 143: "HIIT",
    145: "CrossFit", 146: "Functional Training", 147: "Physical Training", 148: "Taekwondo", 149: "Boxing",
    150: "Free Sparring", 151: "Karate", 152: "Fencing", 153: "Belly Dance", 154: "Jazz Dance", 155: "Latin Dance",
    156: "Ballet", 157: "Core Training", 158: "Body Combat", 159: "Kendo", 160: "Horizontal Bar", 161: "Parallel Bars",
    162: "Street Dance", 163: "Roller Skating", 164: "Martial Arts", 165: "Square Dance", 166: "Tai Chi", 167: "Dance",
    168: "Hula Hoop", 169: "Frisbee", 170: "Darts", 171: "Archery", 172: "Horse Riding", 173: "Laser Tag",
    174: "Kite Flying", 175: "Tug of War", 176: "Swing", 177: "Stair Climbing", 178: "Obstacle Race", 179: "Billiards",
    180: "Bowling", 181: "Shuttlecock", 182: "Handball", 183: "Baseball", 184: "Softball", 185: "Cricket", 186: "Rugby",
    187: "Beach Football", 188: "Beach Volleyball", 189: "Gateball", 190: "Hockey", 191: "Squash", 192: "Sepak Takraw",
]

let workoutSymbols: [Int: String] = [
    1: "figure.run", 2: "figure.walk", 3: "figure.outdoor.cycle", 4: "figure.hiking", 5: "figure.run", 6: "figure.pool.swim",
    7: "figure.indoor.cycle", 8: "figure.open.water.swim", 11: "figure.run", 13: "figure.walk", 14: "figure.hiking",
    21: "figure.jumprope", 130: "figure.tennis", 131: "figure.soccer", 132: "figure.basketball", 133: "figure.volleyball",
    134: "figure.elliptical", 135: "figure.rower", 136: "figure.stair.stepper", 137: "figure.yoga", 138: "figure.pilates",
    140: "figure.strengthtraining.traditional", 141: "figure.indoor.cycle", 143: "figure.highintensity.intervaltraining",
    149: "figure.boxing", 166: "figure.taichi", 167: "figure.dance", 177: "figure.stairs",
]

/// Decodes a Huawei workout GPS file: a start position followed by per-second deltas (in metres) and pause flags.
func parseHuaweiGPS(_ data: Data) -> [TrackPoint] {
    let b = [UInt8](data)
    guard b.count > 70 else { return [] }
    var pos = 0x20
    func u8() -> UInt8 { defer { pos += 1 }; return b[pos] }
    func i16() -> Int16 { defer { pos += 2 }; return Int16(bitPattern: UInt16(b[pos]) | UInt16(b[pos + 1]) << 8) }
    func i32() -> Int32 { defer { pos += 4 }; return Int32(bitPattern: UInt32(b[pos]) | UInt32(b[pos + 1]) << 8 | UInt32(b[pos + 2]) << 16 | UInt32(b[pos + 3]) << 24) }
    func f32() -> Float { Float(bitPattern: UInt32(bitPattern: i32())) }
    func f64() -> Double {
        var v: UInt64 = 0
        for k in 0 ..< 8 { v |= UInt64(b[pos + k]) << (8 * UInt64(k)) }
        pos += 8
        return Double(bitPattern: v)
    }
    let fileType = u8()
    let hasAlt = fileType & 0x03 == 0x03
    var time = Int(i32())
    let lon0 = f64() * 0.017453292519943, lat0 = f64() * 0.017453292519943
    var alt = hasAlt ? f64() : 0
    pos = hasAlt ? 70 : 62
    var lat = lat0, lon = lon0
    let size = hasAlt ? 19 : 15
    var out: [TrackPoint] = []
    while b.count - pos > size {
        time += Int(i16())
        _ = i16()
        let dLon = Double(f32()), dLat = Double(f32())
        _ = u8(); _ = u8()
        let pause = u8() == 1
        lat += dLat; lon += dLon
        if hasAlt { alt = Double(i16()); _ = i16() }
        let la = (lat / 6378245.0 + lat0) / 0.017453292519943
        let lo = (lon / 6378245.0 / cos(lat0) + lon0) / 0.017453292519943
        if abs(la) <= 90, abs(lo) <= 180 {
            out.append(TrackPoint(t: Date(timeIntervalSince1970: TimeInterval(time)), lat: la, lon: lo, alt: hasAlt ? alt : nil, pause: pause))
        }
    }
    return out
}

/// Parses one WorkoutData reply into samples (fields per Gadgetbridge's documentation of the format).
func parseWorkoutSamples(_ c: TLV) -> [WorkoutSample] {
    guard let header = c.bytes(0x04), header.count == 14, let raw = c.bytes(0x05) else { return [] }
    let h = [UInt8](header)
    let ts = Int(h[4]) << 24 | Int(h[5]) << 16 | Int(h[6]) << 8 | Int(h[7])
    let interval = Int(h[8]), count = Int(h[9]) << 8 | Int(h[10]), length = Int(h[11]), bitmap = Int(h[12]) << 8 | Int(h[13])
    let innerLen = c.int(0x08) ?? 0
    let fieldLen = [1, 2, 1, 2, 2, 4, innerLen, 2, 2, 2]
    let d = [UInt8](raw)
    var out: [WorkoutSample] = []
    for i in 0 ..< count where (i + 1) * length <= d.count {
        var p = i * length
        var s = WorkoutSample(t: Date(timeIntervalSince1970: TimeInterval(ts + interval * i)))
        for f in 0 ..< fieldLen.count where bitmap & (1 << f) != 0 {
            let n = fieldLen[f]
            guard p + n <= d.count else { break }
            switch f {
            case 0: let v = Int(d[p]); if v > 0, v < 250 { s.hr = v }
            case 1: let v = Int(Int16(bitPattern: UInt16(d[p]) << 8 | UInt16(d[p + 1]))); if v >= 0 { s.speed = Double(v) / 10 }
            case 2: let v = Int(d[p]); if v > 0, v < 255 { s.cadence = v }
            default: break
            }
            p += n
        }
        out.append(s)
    }
    return out
}

extension Storage {
    static func workoutsURL(_ deviceId: String) -> URL {
        root.appendingPathComponent("workouts-" + deviceId.replacingOccurrences(of: ":", with: "") + ".json")
    }
    static func loadWorkouts(_ deviceId: String) -> [Workout] {
        guard let d = try? Data(contentsOf: workoutsURL(deviceId)) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode([Workout].self, from: d)) ?? []
    }
    static func saveWorkouts(_ w: [Workout], deviceId: String) {
        guard !deviceId.isEmpty else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(w) { try? d.write(to: workoutsURL(deviceId), options: .atomic) }
    }
}

// MARK: - Sync

extension WatchSession {
    func loadStoredWorkouts(for id: String) { workouts = Storage.loadWorkouts(id).sorted { $0.start > $1.start } }

    func syncWorkoutsNow() {
        run("Workout sync") { [self] in try await syncWorkouts() }
    }

    func syncWorkouts() async throws {
        guard isReady, !workoutSyncing else { return }
        workoutSyncing = true
        defer { workoutSyncing = false; workoutStatus = "" }
        workoutStatus = "Checking for workouts…"
        var newSteps = false
        if let c = try? await request(0x17, 0x15, TLV().with(1), timeout: 4) { newSteps = (c.tlv.int(1) ?? 0) & 2 == 2 }
        var gpsNewSync = false
        if let r = try? await request(0x01, 0x31, TLV().with(1).with(2).with(3).with(4).with(5).with(6), timeout: 4) {
            gpsNewSync = (r.tlv.int(2) ?? 0) & 8 != 0
        }
        let end = Int(Date().timeIntervalSince1970)
        let start = workouts.map { Int($0.end.timeIntervalSince1970) + 1 }.max() ?? end - 60 * 86400
        let r = try await request(0x17, 0x07, TLV().with(0x81, TLV().with(3, int: start).with(4, int: end)), timeout: 10)
        if let e = r.tlv.int(0x7F), e != 0x186A0 { note("Workout count error \(e)"); return }
        // The watch sends an empty placeholder entry when there are none, so trust the count.
        let count = r.tlv.object(0x81)?.int(0x02) ?? 0
        let entries = count == 0 ? [] : Array((r.tlv.object(0x81)?.objects(0x85) ?? []).prefix(count))
        note("Workouts on the watch since last sync: \(entries.count)")
        for (k, e) in entries.enumerated() {
            guard let number = e.int(0x06) else { continue }
            let dataCount = e.int(0x07) ?? 0, paceCount = e.int(0x08) ?? 0
            workoutStatus = "Downloading workout \(k + 1) of \(entries.count)…"
            let t = try await request(0x17, 0x08, TLV().with(0x81, TLV().with(2, short: number)), timeout: 10)
            guard let c = t.tlv.object(0x81), let st = c.int(0x04), let en = c.int(0x05) else { continue }
            var w = Workout(number: number, type: c.int(0x14) ?? 0, start: Date(timeIntervalSince1970: TimeInterval(st)),
                            end: Date(timeIntervalSince1970: TimeInterval(en)), duration: max(0, c.int(0x12) ?? (en - st)))
            if w.duration > 200_000 { w.duration /= 1000 }
            w.calories = c.int(0x06).map { $0 > 100_000 ? $0 / 1000 : $0 }
            w.distance = c.int(0x07); w.steps = c.int(0x08)
            w.ascent = c.int(0x0B); w.descent = c.int(0x1B)
            if let hr = c.bytes(0x0C), hr.count >= 2 { w.hrMin = Int(hr[hr.startIndex]); w.hrMax = Int(hr[hr.startIndex + 1]) }
            for i in 0 ..< dataCount {
                var req = TLV().with(2, short: number).with(3, short: i)
                if newSteps { req.put(6, byte: 1) }
                req.put(7)
                if let d = try? await request(0x17, 0x0A, TLV().with(0x81, req), timeout: 10), let dc = d.tlv.object(0x81) {
                    w.samples += parseWorkoutSamples(dc)
                }
            }
            for i in 0 ..< paceCount {
                if let p = try? await request(0x17, 0x0C, TLV().with(0x81, TLV().with(2, short: number).with(8, short: i)), timeout: 10) {
                    for b in p.tlv.object(0x81)?.objects(0x83) ?? [] {
                        if let dist = b.int(0x04), let pace = b.int(0x06) {
                            w.splits.append(PaceSplit(index: w.splits.count, distance: dist, unit: b.int(0x05) ?? 0, pace: pace))
                        }
                    }
                }
            }
            workoutStatus = "Downloading route of workout \(k + 1)…"
            do {
                if let gps = try await downloadGPS(workout: number, newSync: gpsNewSync) { w.track = parseHuaweiGPS(gps) }
            } catch { note("GPS download failed: \(error.localizedDescription)") }
            note("Workout \(number): \(w.name), \(w.samples.count) samples, \(w.splits.count) splits, \(w.track.count) GPS points")
            workouts.removeAll { $0.id == w.id }
            workouts.append(w)
            workouts.sort { $0.start > $1.start }
            Storage.saveWorkouts(workouts, deviceId: deviceId)
        }
    }

    /// Waits for `expected` bytes of file data, arriving as unsolicited block packets after `trigger` runs.
    private func receiveFile(expected: Int, timeout: Double, trigger: () throws -> Void) async throws -> Data {
        final class Box {
            var data = Data(), result: Result<Data, Error>?, cont: CheckedContinuation<Data, Error>?
            let expected: Int
            init(_ e: Int) { expected = e }
            func finish(_ r: Result<Data, Error>) {
                guard result == nil else { return }
                result = r
                if let c = cont { cont = nil; c.resume(with: r) }
            }
            func add(_ chunk: Data) { data.append(chunk); if data.count >= expected { finish(.success(data)) } }
        }
        let box = Box(expected)
        fileBlockSink = { box.add($0) }
        defer { fileBlockSink = nil }
        try trigger()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            box.finish(box.data.isEmpty ? .failure(WatchError.timeout("file data")) : .success(box.data))
        }
        return try await withCheckedThrowingContinuation { cont in
            if let r = box.result { cont.resume(with: r) } else { box.cont = cont }
        }
    }

    /// Downloads a workout's GPS file through whichever file service the watch uses. Nil when the workout has no route.
    func downloadGPS(workout number: Int, newSync: Bool) async throws -> Data? {
        if newSync {
            let r = try await request(0x2C, 0x01, TLV().with(1, "\(number)_gps.bin").with(2, byte: 0x11).with(5, int: 0).with(6, int: 0), timeout: 10)
            guard let fid = r.tlv.int(3), let size = r.tlv.int(4), size > 0 else { return nil }
            let info = try await request(0x2C, 0x03, TLV().with(1, byte: fid).with(2).with(3).with(4).with(5), timeout: 10)
            let block = max(256, info.tlv.int(4) ?? 4096), noEncrypt = info.tlv.int(5) == 1
            fileBlockKind = 0x2C
            var data = Data()
            while data.count < size {
                let len = min(block, size - data.count)
                let offset = data.count
                data += try await receiveFile(expected: len, timeout: 20) {
                    try send(0x2C, 0x04, TLV().with(1, byte: fid).with(2, int: offset).with(3, int: len), encrypt: !noEncrypt)
                }
            }
            try? send(0x2C, 0x06, TLV().with(1, byte: fid).with(2, byte: 1))
            return data.prefix(size)
        }
        let r = try await request(0x0A, 0x01, TLV().with(2, byte: 2).with(0x86, TLV().with(7, byte: 1).with(0x88, TLV().with(9, short: number))), timeout: 10)
        let names = (r.tlv.string(0x01) ?? r.tlv.object(0x8B)?.object(0x8C)?.string(0x0D) ?? "")
            .split(separator: ";").map(String.init).filter { $0.contains("_gps.bin") }
        guard let name = names.first else { return nil }
        let p = try await request(0x0A, 0x02, TLV().with(6, byte: 2).with(7, byte: 3), timeout: 10)
        let block = max(256, p.tlv.int(4) ?? 4096)
        let info = try await request(0x0A, 0x03, TLV().with(1, name), timeout: 10)
        let size = info.tlv.int(2) ?? 0
        guard size > 0 else { return nil }
        fileBlockKind = 0x0A
        var data = Data()
        while data.count < size {
            let len = min(block, size - data.count)
            let offset = data.count
            data += try await receiveFile(expected: len, timeout: 20) {
                try send(0x0A, 0x04, TLV().with(1, name).with(2, int: offset).with(3, int: len))
            }
        }
        try? send(0x0A, 0x06, TLV().with(6, true))
        return data.prefix(size)
    }

    /// Unpacks one file-data packet (0A/05 or 2C/05), decrypting it when needed.
    func fileBlockPayload(_ p: Packet) -> Data? {
        var raw = p.raw
        if let t = try? TLV(raw), t.has(0x7C), let plain = try? linkDecrypt(t) { raw = plain }
        let b = [UInt8](raw)
        if p.service == 0x2C { return b.count > 6 ? Data(b[6...]) : nil }   // fileId, offset (4), flag, data
        return b.count > 1 ? Data(b[1...]) : nil                             // packet number, data
    }

    func deleteWorkout(_ w: Workout) {
        workouts.removeAll { $0.id == w.id }
        Storage.saveWorkouts(workouts, deviceId: deviceId)
    }
}

// MARK: - GPX export

func gpx(for w: Workout) -> String {
    let iso = ISO8601DateFormatter()
    var hrAt: [Int: Int] = [:]
    for s in w.samples { if let h = s.hr { hrAt[Int(s.t.timeIntervalSince1970)] = h } }
    func hr(_ t: Date) -> Int? {
        let k = Int(t.timeIntervalSince1970)
        for d in 0 ... 5 { if let v = hrAt[k - d] ?? hrAt[k + d] { return v } }
        return nil
    }
    var out = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="WatchDeck" xmlns="http://www.topografix.com/GPX/1/1"
         xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
      <metadata><time>\(iso.string(from: w.start))</time></metadata>
      <trk><name>\(w.name)</name><trkseg>

    """
    for p in w.track {
        out += "      <trkpt lat=\"\(String(format: "%.7f", p.lat))\" lon=\"\(String(format: "%.7f", p.lon))\">"
        if let a = p.alt { out += "<ele>\(String(format: "%.1f", a))</ele>" }
        out += "<time>\(iso.string(from: p.t))</time>"
        if let h = hr(p.t) { out += "<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>\(h)</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>" }
        out += "</trkpt>\n"
        if p.pause { out += "    </trkseg><trkseg>\n" }
    }
    out += "  </trkseg></trk>\n</gpx>\n"
    return out
}
