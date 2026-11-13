// Minimal read-only zip reader (stored and deflate entries), enough for .hwt watch-face packages.
import Foundation
import Compression

struct ZipArchive {
    struct Entry { var name: String; var method: Int; var compressedSize: Int; var size: Int; var localOffset: Int }
    let data: Data
    private(set) var entries: [Entry] = []

    init?(data: Data) {
        self.data = data
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard b.count >= 22 else { return nil }
        // End of central directory record: search backwards (it may be followed by a comment).
        var eocd = -1
        var i = b.count - 22
        while i >= max(0, b.count - 22 - 65_535) {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x05, b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0 ..< count {
            guard p + 46 <= b.count, u32(p) == 0x0201_4B50 else { return nil }
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            guard p + 46 + nameLen <= b.count else { return nil }
            let name = String(decoding: b[(p + 46) ..< (p + 46 + nameLen)], as: UTF8.self)
            entries.append(Entry(name: name, method: u16(p + 10), compressedSize: u32(p + 20), size: u32(p + 24), localOffset: u32(p + 42)))
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    init?(contentsOf url: URL) {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.init(data: d)
    }

    var names: [String] { entries.map(\.name) }

    func read(_ name: String) -> Data? {
        guard let e = entries.first(where: { $0.name == name }) else { return nil }
        let b = data
        let lo = data.startIndex + e.localOffset
        guard lo + 30 <= data.endIndex else { return nil }
        let nameLen = Int(b[lo + 26]) | Int(b[lo + 27]) << 8
        let extraLen = Int(b[lo + 28]) | Int(b[lo + 29]) << 8
        let start = lo + 30 + nameLen + extraLen
        guard start + e.compressedSize <= data.endIndex else { return nil }
        let raw = data.subdata(in: start ..< start + e.compressedSize)
        switch e.method {
        case 0: return raw
        case 8:
            if e.size == 0 { return Data() }
            var out = Data(count: e.size)
            let n = out.withUnsafeMutableBytes { dst in
                raw.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, e.size,
                                              src.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
                }
            }
            return n == e.size ? out : nil
        default: return nil
        }
    }
}
