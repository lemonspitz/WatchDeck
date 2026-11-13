// On-disk storage: synced health history, and the watch-face library with preview images.
import Foundation
import AppKit

struct SleepSegment: Codable, Identifiable, Equatable {
    var id: Date { start }
    var start: Date
    var end: Date
    var type: Int               // 6 = light, 7 = deep
    var isDeep: Bool { type == 7 }
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

struct DayTotal: Codable, Equatable {
    var steps = 0, calories = 0, distance = 0
}

struct HealthFile: Codable {
    var samples: [StepSample] = []
    var sleep: [SleepSegment] = []
    var days: [String: DayTotal] = [:]
    var lastSync: Date?
}

struct Night: Identifiable {
    var id: Date { day }
    var day: Date               // the morning the sleep ended on
    var segments: [SleepSegment]
    var deep: Int { segments.filter { $0.isDeep }.reduce(0) { $0 + $1.minutes } }
    var light: Int { segments.filter { !$0.isDeep }.reduce(0) { $0 + $1.minutes } }
    var total: Int { deep + light }
    var bedtime: Date { segments.map(\.start).min() ?? day }
    var wake: Date { segments.map(\.end).max() ?? day }
}

struct FaceMeta: Codable, Equatable {
    var title: String?
    var preview: String?        // file name inside the Previews folder
}

struct LibraryFace: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var title: String
    var screen: String
    var preview: URL?
    var category = "Digital"
}

enum Storage {
    static let root: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WatchDeck")
        for sub in ["", "Faces", "Previews"] {
            try? FileManager.default.createDirectory(at: u.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        return u
    }()
    static var faces: URL { root.appendingPathComponent("Faces") }
    static var previews: URL { root.appendingPathComponent("Previews") }
    static var faceMeta: URL { root.appendingPathComponent("faces.json") }

    static func healthURL(_ deviceId: String) -> URL {
        root.appendingPathComponent("health-" + deviceId.replacingOccurrences(of: ":", with: "") + ".json")
    }

    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    static func loadHealth(_ deviceId: String) -> HealthFile {
        guard let d = try? Data(contentsOf: healthURL(deviceId)), let h = try? JSONDecoder().decode(HealthFile.self, from: d) else { return HealthFile() }
        return h
    }

    static func saveHealth(_ h: HealthFile, deviceId: String) {
        guard !deviceId.isEmpty, let d = try? JSONEncoder().encode(h) else { return }
        try? d.write(to: healthURL(deviceId), options: .atomic)
    }

    static func loadFaceMeta() -> [String: FaceMeta] {
        guard let d = try? Data(contentsOf: faceMeta), let m = try? JSONDecoder().decode([String: FaceMeta].self, from: d) else { return [:] }
        return m
    }

    static func saveFaceMeta(_ m: [String: FaceMeta]) {
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: faceMeta, options: .atomic) }
    }

    static func nights(from segments: [SleepSegment]) -> [Night] {
        let cal = Calendar.current
        // A night belongs to the day it ends on: anything starting after 18:00 counts toward the next morning.
        let groups = Dictionary(grouping: segments) { cal.startOfDay(for: $0.start.addingTimeInterval(6 * 3600)) }
        return groups.map { Night(day: $0.key, segments: $0.value.sorted { $0.start < $1.start }) }.sorted { $0.day < $1.day }
    }
}

// MARK: - Reading .hwt watch-face packages (zip archives)

enum HWT {
    static func entries(_ url: URL) -> [String] { ZipArchive(contentsOf: url)?.names ?? [] }

    static func read(_ url: URL, entry: String) -> Data? { ZipArchive(contentsOf: url)?.read(entry) }

    /// The bytes the watch actually wants: the compiled face inside the package, not the package itself.
    static func payload(_ url: URL) throws -> Data {
        guard let zip = ZipArchive(contentsOf: url) else { return try Data(contentsOf: url) }   // already a bare compiled file
        guard let name = zip.names.first(where: { $0 == "com.huawei.watchface" || $0 == "com.honor.watchface" }),
              let inner = zip.read(name), !inner.isEmpty else {
            throw WatchError.unsupported("this file has no compiled watch face inside (com.huawei.watchface)")
        }
        guard inner.starts(with: [0x50, 0x4B]) else { return inner }
        if let bin = ZipArchive(data: inner)?.read("watchface.bin"), !bin.isEmpty { return bin }
        throw WatchError.unsupported("this watch face is built for newer watches (no watchface.bin inside), not for this model")
    }

    private static func tag(_ name: String, in xml: String) -> String? {
        guard let a = xml.range(of: "<\(name)>"), let b = xml.range(of: "</\(name)>", range: a.upperBound ..< xml.endIndex) else { return nil }
        let s = xml[a.upperBound ..< b.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Title, screen size and preview image of a package. The preview is cached in the Previews folder.
    private static let cacheLock = NSLock()
    private static var cache: [String: LibraryFace] = [:]

    /// Reads a package once per file version; later calls are served from memory.
    static func describe(_ url: URL) -> LibraryFace {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let stamp = Int((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        let key = url.path + "#\(stamp)"
        cacheLock.lock()
        if let hit = cache[key] { cacheLock.unlock(); return hit }
        cacheLock.unlock()
        let item = describeUncached(url, stamp: stamp)
        cacheLock.lock(); cache[key] = item; cacheLock.unlock()
        return item
    }

    private static func describeUncached(_ url: URL, stamp: Int) -> LibraryFace {
        let zip = ZipArchive(contentsOf: url)
        let list = zip?.names ?? []
        var category = "Digital"
        var title = url.deletingPathExtension().lastPathComponent
        var screen = ""
        if let e = list.first(where: { $0.lowercased().hasSuffix("description.xml") }), let d = zip?.read(e) {
            let xml = String(decoding: d, as: UTF8.self)
            if let t = tag("title", in: xml) { title = t }
            let raw = tag("screen", in: xml) ?? ""
            screen = screenSpecs.first { $0.code == raw }?.label ?? raw.replacingOccurrences(of: "*", with: " × ")
            if let c = tag("category", in: xml) { category = c }
        }
        let images = list.filter { let l = $0.lowercased(); return l.hasSuffix(".jpg") || l.hasSuffix(".jpeg") || l.hasSuffix(".png") }
        let pick = images.first { $0.lowercased().contains("cover") }
            ?? images.first { $0.lowercased().hasPrefix("preview/") }
            ?? images.first
        var preview: URL?
        let cache = Storage.previews.appendingPathComponent("lib-" + url.deletingPathExtension().lastPathComponent + "-\(stamp).img")
        if FileManager.default.fileExists(atPath: cache.path) {
            preview = cache
        } else if let pick, let d = zip?.read(pick), NSImage(data: d) != nil {
            try? d.write(to: cache)
            preview = cache
        }
        return LibraryFace(url: url, title: title, screen: screen, preview: preview, category: category)
    }
}

// MARK: - Session additions

extension WatchSession {
    func loadStoredHealth(for id: String) {
        let h = Storage.loadHealth(id)
        samples = h.samples
        sleep = h.sleep.filter { $0.type == 6 || $0.type == 7 }
        dayTotals = h.days
        lastSync = h.lastSync
    }

    func storeHealth() {
        Storage.saveHealth(HealthFile(samples: samples, sleep: sleep, days: dayTotals, lastSync: lastSync), deviceId: deviceId)
    }

    var nights: [Night] { Storage.nights(from: sleep) }

    /// Folders searched for watch faces: the app's own folder, the generated face sets next to the app, and folders the user added.
    var faceFolders: [URL] {
        var out = [Storage.faces]
        let generated = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Faces")
        if FileManager.default.fileExists(atPath: generated.path) { out.append(generated) }
        for p in UserDefaults.standard.stringArray(forKey: "faceFolders") ?? [] { out.append(URL(fileURLWithPath: p)) }
        return out
    }

    func addFaceFolder(_ url: URL) {
        var list = UserDefaults.standard.stringArray(forKey: "faceFolders") ?? []
        if !list.contains(url.path) { list.append(url.path) }
        UserDefaults.standard.set(list, forKey: "faceFolders")
        reloadLibrary()
    }

    /// Generated sets live in folders named like "HWHD06-280x456"; returns the size label for such a folder.
    nonisolated static func sizeOfFolder(_ name: String) -> String? {
        guard let dash = name.firstIndex(of: "-") else { return nil }
        let dims = name[name.index(after: dash)...].split(separator: "x")
        guard dims.count == 2, let w = Int(dims[0]), let h = Int(dims[1]) else { return nil }
        return "\(w) × \(h)"
    }

    /// Loads the faces for `librarySize` ("All" for every size). Faces inside size folders are only opened when that size is shown.
    func reloadLibrary() {
        let fm = FileManager.default
        var sizes = Set<String>()
        var candidates: [(URL, String?)] = []
        for root in faceFolders {
            for item in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
                if item.pathExtension.lowercased() == "hwt" { candidates.append((item, nil)); continue }
                guard (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let size = Self.sizeOfFolder(item.lastPathComponent)
                if let size { sizes.insert(size) }
                if size == nil || librarySize == "All" || size == librarySize {
                    for f in (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension.lowercased() == "hwt" {
                        candidates.append((f, size))
                    }
                }
            }
        }
        let wanted = librarySize
        Task.detached {
            let items = candidates.sorted { $0.0.lastPathComponent < $1.0.lastPathComponent }.map { HWT.describe($0.0) }
                .filter { wanted == "All" || $0.screen == wanted }
            await MainActor.run {
                self.library = items
                self.librarySizes = sizes.union(items.map(\.screen)).filter { !$0.isEmpty }.sorted { a, b in
                    let pa = a.split(separator: " ").compactMap { Int($0) }, pb = b.split(separator: " ").compactMap { Int($0) }
                    return (pa.first ?? 0, pa.last ?? 0) < (pb.first ?? 0, pb.last ?? 0)
                }
            }
        }
    }

    func addToLibrary(_ urls: [URL]) {
        for u in urls {
            let dest = Storage.faces.appendingPathComponent(u.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.copyItem(at: u, to: dest) }
        }
        reloadLibrary()
    }

    func removeFromLibrary(_ face: LibraryFace) {
        try? FileManager.default.removeItem(at: face.url)
        reloadLibrary()
    }

    func previewImage(for face: WatchFace) -> NSImage? {
        guard let name = faceMeta[face.fileName]?.preview else { return nil }
        return NSImage(contentsOf: Storage.previews.appendingPathComponent(name))
    }

    func displayTitle(for face: WatchFace) -> String {
        if let t = faceMeta[face.fileName]?.title, !t.isEmpty { return t }
        if let t = face.title, !t.isEmpty { return t }
        return "Face " + face.fileName
    }

    /// Attach a picture (e.g. a photo of the watch) to a face that is already on the watch.
    func setPicture(_ url: URL, for face: WatchFace) {
        guard let d = try? Data(contentsOf: url), NSImage(data: d) != nil else { return }
        let name = "face-" + face.fileName + ".img"
        try? d.write(to: Storage.previews.appendingPathComponent(name))
        var m = faceMeta[face.fileName] ?? FaceMeta()
        m.preview = name
        faceMeta[face.fileName] = m
        Storage.saveFaceMeta(faceMeta)
    }

    func rename(_ face: WatchFace, to title: String) {
        var m = faceMeta[face.fileName] ?? FaceMeta()
        m.title = title
        faceMeta[face.fileName] = m
        Storage.saveFaceMeta(faceMeta)
    }

    func install(_ item: LibraryFace) {
        installFace(from: item.url) { [weak self] id in
            guard let self else { return }
            var meta = FaceMeta(title: item.title)
            if let p = item.preview {
                let name = "face-" + id + ".img"
                try? FileManager.default.copyItem(at: p, to: Storage.previews.appendingPathComponent(name))
                meta.preview = name
            }
            self.faceMeta[id] = meta
            Storage.saveFaceMeta(self.faceMeta)
        }
    }
}
