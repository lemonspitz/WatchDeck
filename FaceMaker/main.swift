// FaceMaker: draws watch-face designs and compiles them into .hwt packages for the
// Huawei Watch Fit (HWHD06, 280 x 456).
//
// Binary layout (as documented by the MIT-licensed stia-hwt-packer project):
//   16-byte header | protobuf layout | image index | image blob (run-length encoded BGRA)
//
// Usage: facemaker <output folder> [only-index]
import AppKit
import CoreText

let W = 280, H = 456

// MARK: - Small utilities

struct RNG {
    var s: UInt64
    init(_ seed: Int) { s = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> Double {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return Double(s % 1_000_000) / 1_000_000
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    mutating func int(_ a: Int, _ b: Int) -> Int { a + Int(next() * Double(b - a + 1)) }
}

struct RGB {
    var r, g, b: CGFloat
    init(_ hex: Int) { r = CGFloat((hex >> 16) & 255) / 255; g = CGFloat((hex >> 8) & 255) / 255; b = CGFloat(hex & 255) / 255 }
    init(r: CGFloat, g: CGFloat, b: CGFloat) { self.r = r; self.g = g; self.b = b }
    func cg(_ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func mix(_ o: RGB, _ t: CGFloat) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
    var isDark: Bool { 0.299 * r + 0.587 * g + 0.114 * b < 0.5 }
    var outline: CGColor { isDark ? CGColor(gray: 1, alpha: 0.55) : CGColor(gray: 0, alpha: 0.5) }
    var bytes: [Int] { [Int(r * 255), Int(g * 255), Int(b * 255), 255] }
}

/// An RGBA canvas with a top-left origin.
final class Canvas {
    let w: Int, h: Int
    let ctx: CGContext
    init(_ w: Int, _ h: Int) {
        self.w = w; self.h = h
        ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(true)
    }

    /// A canvas measured in design units: `w` x `h` units drawn at `scale` pixels per unit.
    convenience init(design w: CGFloat, _ h: CGFloat, scale: CGFloat) {
        self.init(max(1, Int((w * scale).rounded(.up))), max(1, Int((h * scale).rounded(.up))))
        ctx.scaleBy(x: scale, y: scale)
    }

    /// Straight-alpha RGBA bytes, colours snapped to a coarse grid so flat areas compress well.
    func rgba() -> [UInt8] {
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0 ..< w * h {
            let a = Int(p[i * 4 + 3])
            if a == 0 { continue }
            for c in 0 ..< 3 {
                var v = Int(p[i * 4 + c])
                if a < 255 { v = min(255, v * 255 / a) }
                out[i * 4 + c] = UInt8(min(255, (v + 2) / 4 * 4))
            }
            out[i * 4 + 3] = UInt8(a)
        }
        return out
    }

    var image: CGImage { ctx.makeImage()! }

    func fill(_ c: CGColor, _ r: CGRect) { ctx.setFillColor(c); ctx.fill(r) }

    func gradient(_ colors: [RGB], in r: CGRect) {
        // Drawn row by row so every row is one flat colour (compresses to almost nothing).
        let n = Int(r.height)
        for i in 0 ..< n {
            let t = CGFloat(i) / CGFloat(max(1, n - 1)) * CGFloat(colors.count - 1)
            let k = min(colors.count - 2, Int(t))
            fill(colors[k].mix(colors[k + 1], t - CGFloat(k)).cg(), CGRect(x: r.minX, y: r.minY + CGFloat(i), width: r.width, height: 2))
        }
    }

    func draw(_ img: CGImage, at p: CGPoint) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y + CGFloat(img.height)); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.restoreGState()
    }

    /// Draws text centred (or left/right aligned) inside a box, shrinking the font until it fits.
    func text(_ s: String, font name: String, size: CGFloat, color: CGColor, in box: CGRect, align: Int = 1,
              stroke: CGColor? = nil, strokeWidth: CGFloat = 0, fixedSize: Bool = false) {
        var size = size
        var line: CTLine
        var b: CGRect
        while true {
            let attrs: [NSAttributedString.Key: Any] = [.font: makeFont(name, size), .foregroundColor: color]
            line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
            b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            if fixedSize || (b.width <= box.width && b.height <= box.height) || size < 6 { break }
            size -= 1
        }
        let x = align == 0 ? box.minX - b.minX : align == 2 ? box.maxX - b.maxX : box.midX - b.midX
        ctx.saveGState()
        ctx.translateBy(x: x, y: box.midY + b.midY); ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        if let stroke {
            ctx.setTextDrawingMode(.stroke); ctx.setLineWidth(strokeWidth); ctx.setStrokeColor(stroke); ctx.setLineJoin(.round)
            CTLineDraw(line, ctx)
            ctx.textPosition = .zero
        }
        ctx.setTextDrawingMode(.fill)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

}

func makeFont(_ name: String, _ size: CGFloat) -> NSFont {
    switch name {
    case "rounded":
        let d = NSFont.systemFont(ofSize: size, weight: .heavy).fontDescriptor.withDesign(.rounded)!
        return NSFont(descriptor: d, size: size)!
    case "system": return NSFont.systemFont(ofSize: size, weight: .bold)
    case "thin": return NSFont.systemFont(ofSize: size, weight: .light)
    case "mono": return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
    case "serif":
        let d = NSFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withDesign(.serif)!
        return NSFont(descriptor: d, size: size)!
    default: return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }
}

// MARK: - Binary encoding

func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255)] }
func le32(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8((v >> 24) & 255)] }

func rle(_ w: Int, _ h: Int, _ rgba: [UInt8]) -> [UInt8] {
    var out: [UInt8] = [69, 35, 136, 136] + le16(w) + le16(h)
    out.reserveCapacity(w * h)
    var i = 0
    let n = w * h
    func px(_ k: Int) -> [UInt8] {
        var p = [rgba[k * 4 + 2], rgba[k * 4 + 1], rgba[k * 4], rgba[k * 4 + 3]]
        if p == [137, 103, 69, 35] { p[3] = 36 }       // never emit the run marker as a pixel
        return p
    }
    while i < n {
        let c = px(i)
        var run = 1
        while i + run < n, px(i + run) == c { run += 1 }
        if run > 3 { out += [137, 103, 69, 35] + c + le32(run) } else { for _ in 0 ..< run { out += c } }
        i += run
    }
    return out
}

enum PB {
    static func varint(_ v: Int) -> [UInt8] {
        var v = UInt64(v), out: [UInt8] = []
        repeat { var b = UInt8(v & 0x7F); v >>= 7; if v != 0 { b |= 0x80 }; out.append(b) } while v != 0
        return out
    }
    static func v(_ field: Int, _ value: Int) -> [UInt8] { varint(field << 3) + varint(value) }
    static func b(_ field: Int, _ bytes: [UInt8]) -> [UInt8] { varint(field << 3 | 2) + varint(bytes.count) + bytes }
    static func s(_ field: Int, _ str: String) -> [UInt8] { b(field, Array(str.utf8)) }
    static func point(_ x: Int, _ y: Int) -> [UInt8] { v(1, x) + v(2, y) }
    static func rect(_ r: [Int]) -> [UInt8] { v(1, r[0]) + v(2, r[1]) + v(3, r[2]) + v(4, r[3]) }
}

// MARK: - Face model

struct Layer {
    enum Kind {
        case single(String, Int, Int)
        case selected([String], Int, Int, Int)             // images, x, y, value type
        case text([Int], [Int], Int)                        // rect, rgba, value type
        case hand(String, [Int], Int, Int, Int)             // image, rotate rect (centre = pivot on screen), pivot x/y in image, value type
        case arc(String, [Int], Int, Int, Int, Int, Int, Int)   // image, rect, centre x/y in image, radius, line width, start, end (+ value below)
    }
    var arcValue = 0
    var kind: Kind
}

struct Container { var rect: [Int]; var dataType: Int; var layers: [Layer] }

final class Face {
    var title: String
    var images: [(name: String, w: Int, h: Int, rgba: [UInt8])] = []
    var background: [Layer] = [], time: [Layer] = [], date: [Layer] = []
    var containers: [Container] = []
    /// Element drawing order. Analog faces put the time element last so the hands pass over everything.
    var order = [0, 1, 2, 3]
    init(_ title: String) { self.title = title }

    @discardableResult func add(_ name: String, _ c: Canvas) -> String {
        images.append((name, c.w, c.h, c.rgba())); return name
    }

    private func id(_ name: String) -> String {
        String(format: "%03d", images.firstIndex { $0.name == name }! + 1)   // image table is one-based
    }

    private func encode(_ l: Layer, _ index: Int) -> [UInt8] {
        switch l.kind {
        case .single(let n, let x, let y):
            return PB.v(1, index) + PB.v(2, 1) + PB.b(4, PB.s(1, id(n)) + PB.b(2, PB.point(x, y)))
        case .selected(let ns, let x, let y, let value):
            return PB.v(1, index) + PB.v(2, 2) + PB.b(5, ns.flatMap { PB.s(1, id($0)) } + PB.b(2, PB.point(x, y)) + PB.v(3, value))
        case .text(let r, let c, let value):
            return PB.v(1, index) + PB.v(2, 0) + PB.b(3, PB.b(1, PB.rect(r)) + PB.b(2, PB.rect(c)) + PB.v(3, 127) + PB.v(4, 1) + PB.v(5, value))
        case .hand(let n, let r, let px, let py, let value):
            return PB.v(1, index) + PB.v(2, 5) + PB.b(8, PB.s(1, id(n)) + PB.b(2, PB.rect(r)) + PB.b(3, PB.point(px, py))
                + PB.v(4, 0) + PB.v(5, 360) + PB.v(6, value))
        case .arc(let n, let r, let cx, let cy, let radius, let lw, let start, let end):
            return PB.v(1, index) + PB.v(2, 7) + PB.b(10, PB.s(1, id(n)) + PB.b(2, PB.rect(r)) + PB.b(3, PB.point(cx, cy))
                + PB.v(4, radius) + PB.v(5, lw) + PB.v(6, start) + PB.v(7, end) + PB.v(8, l.arcValue))
        }
    }

    private func element(_ label: Int, _ layers: [Layer], _ conts: [Container] = []) -> [UInt8] {
        var e = PB.v(1, label) + PB.v(2, 0)
        for (i, l) in layers.enumerated() { e += PB.b(5, encode(l, i)) }
        for (i, c) in conts.enumerated() {
            var cb = PB.v(1, i) + PB.v(2, 0) + PB.b(5, PB.rect(c.rect))
            for (j, l) in c.layers.enumerated() { cb += PB.b(6, encode(l, j)) }
            cb += PB.v(8, c.dataType)
            e += PB.b(8, cb)
        }
        return e
    }

    func binary() -> [UInt8] {
        var proto: [UInt8] = []
        for label in order {
            switch label {
            case 0: proto += PB.b(1, element(0, background))
            case 1: proto += PB.b(1, element(1, time))
            case 2: proto += PB.b(1, element(2, date))
            default: proto += PB.b(1, element(3, [], containers))
            }
        }
        proto += PB.s(2, title) + PB.s(3, title)
        precondition(proto.count < 65536, "layout too large")
        var blob: [UInt8] = [85, 85, 85, 85, 1, 0, 0, 1]
        var index: [UInt8] = []
        for im in images {
            let enc = rle(im.w, im.h, im.rgba)
            index += le32(blob.count) + le32(enc.count)
            blob += enc
        }
        let head: [UInt8] = [2, 0] + le16(proto.count) + le16(index.count) + [0, 0] + le32(blob.count) + le32(0)
        return head + proto + index + blob
    }
}

// MARK: - Design description

enum Layout { case stack, inline, left, bottom, split }

struct Design {
    var title: String
    var bg: Int                      // background style
    var colors: [Int]                // background colours (2-4)
    var fg: Int                      // minutes / text colour
    var accent: Int                  // hours / highlight colour
    var font: String
    var layout: Layout
    var seed: Int
}

func drawBackground(_ c: Canvas, _ d: Design, panel showPanel: Bool = true) {
    let cols = d.colors.map { RGB($0) }
    let acc = RGB(d.accent)
    var rng = RNG(d.seed)
    let full = CGRect(x: 0, y: 0, width: W, height: H)
    let ctx = c.ctx
    c.gradient(cols.count > 1 ? Array(cols.prefix(2)) : [cols[0], cols[0]], in: full)
    let third = cols.count > 2 ? cols[2] : acc
    let fourth = cols.count > 3 ? cols[3] : third
    switch d.bg {
    case 1:     // sunset: sun with horizon bands
        let cy: CGFloat = d.layout == .bottom ? 150 : 228
        ctx.setFillColor(third.cg()); ctx.fillEllipse(in: CGRect(x: 140 - 86, y: cy - 86, width: 172, height: 172))
        for i in 0 ..< 7 {
            let y = cy + 6 + CGFloat(i) * 12
            c.fill(cols[1].mix(cols[0], 0.1).cg(), CGRect(x: 0, y: y, width: CGFloat(W), height: 2 + CGFloat(i)))
        }
    case 2:     // layered mountains
        for layer in 0 ..< 4 {
            let base = 250 + CGFloat(layer) * 52
            let col = third.mix(fourth, CGFloat(layer) / 3).mix(RGB(0), CGFloat(layer) * 0.12)
            ctx.beginPath(); ctx.move(to: CGPoint(x: 0, y: CGFloat(H)))
            var x: CGFloat = 0
            ctx.addLine(to: CGPoint(x: 0, y: base))
            while x < CGFloat(W) {
                x += CGFloat(rng.range(24, 60))
                ctx.addLine(to: CGPoint(x: x, y: base - CGFloat(rng.range(-10, 70 - Double(layer) * 12))))
            }
            ctx.addLine(to: CGPoint(x: CGFloat(W), y: CGFloat(H))); ctx.closePath()
            ctx.setFillColor(col.cg()); ctx.fillPath()
        }
    case 3:     // waves
        for layer in 0 ..< 5 {
            let base = 240 + CGFloat(layer) * 46
            let ph = rng.range(0, 6.28), amp = rng.range(8, 20), freq = rng.range(0.02, 0.045)
            ctx.beginPath(); ctx.move(to: CGPoint(x: 0, y: CGFloat(H)))
            for x in stride(from: 0, through: W, by: 4) {
                ctx.addLine(to: CGPoint(x: CGFloat(x), y: base + CGFloat(sin(Double(x) * freq + ph) * amp)))
            }
            ctx.addLine(to: CGPoint(x: CGFloat(W), y: CGFloat(H))); ctx.closePath()
            ctx.setFillColor(third.mix(fourth, CGFloat(layer) / 4).cg()); ctx.fillPath()
        }
    case 4:     // starfield
        for _ in 0 ..< 90 {
            let r = CGFloat(rng.range(0.6, 2.2))
            ctx.setFillColor(RGB(0xFFFFFF).mix(third, CGFloat(rng.next())).cg(CGFloat(rng.range(0.4, 1))))
            ctx.fillEllipse(in: CGRect(x: CGFloat(rng.range(0, 280)), y: CGFloat(rng.range(0, 456)), width: r * 2, height: r * 2))
        }
        ctx.setFillColor(third.cg()); ctx.fillEllipse(in: CGRect(x: 196, y: 30, width: 46, height: 46))
        ctx.setFillColor(cols[0].cg()); ctx.fillEllipse(in: CGRect(x: 186, y: 24, width: 44, height: 44))
    case 5:     // diagonal stripes
        ctx.saveGState(); ctx.translateBy(x: 140, y: 228); ctx.rotate(by: -.pi / 5)
        for i in -12 ..< 12 where i % 2 == 0 {
            c.fill(third.cg(i % 4 == 0 ? 0.9 : 0.45), CGRect(x: -400, y: CGFloat(i) * 34, width: 800, height: 34))
        }
        ctx.restoreGState()
    case 6:     // perspective grid
        ctx.setStrokeColor(third.cg(0.8)); ctx.setLineWidth(1.5)
        let hy: CGFloat = 250
        for i in 0 ..< 12 { let y = hy + pow(CGFloat(i) / 11, 1.8) * (CGFloat(H) - hy); ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: CGFloat(W), y: y)) }
        for i in -8 ... 8 { ctx.move(to: CGPoint(x: 140 + CGFloat(i) * 12, y: hy)); ctx.addLine(to: CGPoint(x: 140 + CGFloat(i) * 70, y: CGFloat(H))) }
        ctx.strokePath()
        ctx.setFillColor(fourth.cg()); ctx.fillEllipse(in: CGRect(x: 80, y: 130, width: 120, height: 120))
        c.gradient([cols[1], cols[1]], in: CGRect(x: 0, y: hy, width: CGFloat(W), height: 0))
    case 7:     // concentric rings
        let cx = CGFloat(rng.range(40, 240)), cy = CGFloat(rng.range(120, 340))
        for i in stride(from: 14, to: 1, by: -1) {
            let r = CGFloat(i) * 30
            ctx.setFillColor((i % 2 == 0 ? third : fourth).cg(0.16 + 0.03 * CGFloat(14 - i)))
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }
    case 8:     // colour blocks
        let lines: [CGFloat] = [CGFloat(rng.int(70, 110)), CGFloat(rng.int(170, 210))]
        let rows: [CGFloat] = [CGFloat(rng.int(90, 150)), CGFloat(rng.int(300, 360))]
        let palette = [third, fourth, acc, cols[1]]
        var k = 0
        var x0: CGFloat = 0
        for x1 in lines + [CGFloat(W)] {
            var y0: CGFloat = 0
            for y1 in rows + [CGFloat(H)] {
                if rng.next() < 0.45 { c.fill(palette[k % 4].cg(), CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) }
                k += 1; y0 = y1
            }
            x0 = x1
        }
        ctx.setFillColor(RGB(0x101010).cg())
        for x in lines { ctx.fill(CGRect(x: x - 3, y: 0, width: 6, height: CGFloat(H))) }
        for y in rows { ctx.fill(CGRect(x: 0, y: y - 3, width: CGFloat(W), height: 6)) }
    case 9:     // dots
        for row in 0 ..< 16 { for col in 0 ..< 10 {
            let r: CGFloat = 5 + CGFloat((row + col) % 3)
            ctx.setFillColor(((row + col) % 2 == 0 ? third : fourth).cg(0.55))
            ctx.fillEllipse(in: CGRect(x: CGFloat(col) * 30 + (row % 2 == 0 ? 0 : 15) - r, y: CGFloat(row) * 30 - r + 8, width: r * 2, height: r * 2))
        } }
    case 10:    // skyline
        ctx.setFillColor(third.cg()); ctx.fillEllipse(in: CGRect(x: 170, y: 150, width: 70, height: 70))
        for layer in 0 ..< 2 {
            var x: CGFloat = -10
            let col = layer == 0 ? fourth.mix(cols[1], 0.5) : fourth
            while x < CGFloat(W) {
                let bw = CGFloat(rng.int(20, 44)), bh = CGFloat(rng.int(60, 190 - layer * 50))
                c.fill(col.cg(), CGRect(x: x, y: CGFloat(H) - bh - 40 + CGFloat(layer) * 40, width: bw, height: bh + 40))
                if layer == 1 {
                    for wy in stride(from: CGFloat(H) - bh + 10, to: CGFloat(H) - 8, by: 14) {
                        for wx in stride(from: x + 5, to: x + bw - 6, by: 9) where rng.next() < 0.45 {
                            c.fill(acc.cg(0.9), CGRect(x: wx, y: wy, width: 4, height: 6))
                        }
                    }
                }
                x += bw + CGFloat(rng.int(0, 6))
            }
        }
    case 11:    // topographic lines
        ctx.setLineWidth(1.6)
        for i in 0 ..< 16 {
            ctx.setStrokeColor(third.mix(fourth, CGFloat(i) / 15).cg(0.55))
            let ph = rng.range(0, 6.28), base = CGFloat(i) * 30 + 10
            ctx.beginPath()
            for x in stride(from: -4, through: W + 4, by: 4) {
                let y = base + CGFloat(sin(Double(x) * 0.03 + ph) * 12 + sin(Double(x) * 0.011 + ph * 2) * 16)
                if x == -4 { ctx.move(to: CGPoint(x: CGFloat(x), y: y)) } else { ctx.addLine(to: CGPoint(x: CGFloat(x), y: y)) }
            }
            ctx.strokePath()
        }
    case 12:    // triangles
        let step: CGFloat = 56
        for row in 0 ..< 9 { for col in 0 ..< 6 {
            let x = CGFloat(col) * step - (row % 2 == 0 ? 0 : step / 2), y = CGFloat(row) * step
            for flip in 0 ..< 2 {
                ctx.beginPath()
                if flip == 0 { ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + step, y: y)); ctx.addLine(to: CGPoint(x: x + step / 2, y: y + step)) }
                else { ctx.move(to: CGPoint(x: x + step, y: y)); ctx.addLine(to: CGPoint(x: x + step * 1.5, y: y + step)); ctx.addLine(to: CGPoint(x: x + step / 2, y: y + step)) }
                ctx.closePath()
                ctx.setFillColor(third.mix(fourth, CGFloat(rng.next())).cg(CGFloat(rng.range(0.15, 0.7)))); ctx.fillPath()
            }
        } }
    case 13:    // pixel blocks
        for row in 0 ..< 19 { for col in 0 ..< 12 where rng.next() < 0.3 {
            c.fill(third.mix(fourth, CGFloat(rng.next())).cg(CGFloat(rng.range(0.25, 0.8))), CGRect(x: col * 24, y: row * 24, width: 22, height: 22))
        } }
    case 14:    // frame with corner marks
        ctx.setStrokeColor(third.cg()); ctx.setLineWidth(3)
        ctx.stroke(CGRect(x: 10, y: 10, width: 260, height: 436).insetBy(dx: 1.5, dy: 1.5))
        ctx.setStrokeColor(fourth.cg(0.7)); ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: 18, y: 18, width: 244, height: 420))
    case 15:    // big arc
        ctx.setStrokeColor(third.cg()); ctx.setLineWidth(26); ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: 280, y: 228), radius: 190, startAngle: .pi * 0.62, endAngle: .pi * 1.38, clockwise: false); ctx.strokePath()
        ctx.setStrokeColor(fourth.cg(0.7)); ctx.setLineWidth(10)
        ctx.addArc(center: CGPoint(x: 280, y: 228), radius: 150, startAngle: .pi * 0.7, endAngle: .pi * 1.2, clockwise: false); ctx.strokePath()
    case 16:    // leaves / petals
        for _ in 0 ..< 22 {
            let x = CGFloat(rng.range(0, 280)), y = CGFloat(rng.range(0, 456)), s = CGFloat(rng.range(16, 44))
            ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: CGFloat(rng.range(0, 6.28)))
            ctx.setFillColor(third.mix(fourth, CGFloat(rng.next())).cg(0.55))
            ctx.fillEllipse(in: CGRect(x: -s / 2, y: -s / 5, width: s, height: s / 2.5))
            ctx.restoreGState()
        }
    case 17:    // horizontal bands
        var y: CGFloat = 0
        var k = 0
        while y < CGFloat(H) {
            let bh = CGFloat(rng.int(18, 64))
            c.fill([cols[0], third, cols[1], fourth][k % 4].cg(), CGRect(x: 0, y: y, width: CGFloat(W), height: bh))
            y += bh; k += 1
        }
    case 18:    // circuit traces
        ctx.setStrokeColor(third.cg(0.7)); ctx.setLineWidth(2)
        for _ in 0 ..< 26 {
            var p = CGPoint(x: CGFloat(rng.int(0, 14)) * 20, y: CGFloat(rng.int(0, 22)) * 20)
            ctx.move(to: p)
            for _ in 0 ..< rng.int(2, 4) {
                if rng.next() < 0.5 { p.x += CGFloat(rng.int(-3, 3)) * 20 } else { p.y += CGFloat(rng.int(-3, 3)) * 20 }
                ctx.addLine(to: p)
            }
            ctx.strokePath()
            ctx.setFillColor(fourth.cg()); ctx.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
        }
    case 19:    // half-and-half split
        ctx.beginPath(); ctx.move(to: CGPoint(x: 0, y: 300)); ctx.addLine(to: CGPoint(x: CGFloat(W), y: 170))
        ctx.addLine(to: CGPoint(x: CGFloat(W), y: CGFloat(H))); ctx.addLine(to: CGPoint(x: 0, y: CGFloat(H))); ctx.closePath()
        ctx.setFillColor(third.cg()); ctx.fillPath()
    default: break    // 0: plain gradient
    }
    let panel = RGB(d.fg).isDark ? CGColor(gray: 1, alpha: 0.62) : CGColor(gray: 0, alpha: 0.42)
    // Soft panel behind the bottom statistics so they stay readable on busy art.
    if !showPanel {
    } else if d.layout != .left {
        ctx.setFillColor(panel)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 6, y: 386, width: 268, height: 58), cornerWidth: 18, cornerHeight: 18, transform: nil)); ctx.fillPath()
    } else {
        ctx.setFillColor(panel)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 172, y: 104, width: 102, height: 226), cornerWidth: 18, cornerHeight: 18, transform: nil)); ctx.fillPath()
    }
}

let weekdays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
let months = ["---", "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

func jpeg(_ img: CGImage, scale: CGFloat = 1) -> Data {
    let w = Int(CGFloat(img.width) * scale), h = Int(CGFloat(img.height) * scale)
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
}

func writeHWT(title: String, category: String, screen: String, face: Face, preview: CGImage, folder: URL, file: String) throws -> Int {
    let bin = Data(face.binary())
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("facemaker-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp.appendingPathComponent("preview"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try bin.write(to: tmp.appendingPathComponent("com.huawei.watchface"))
    let desc = """
    <?xml version="1.0" encoding="UTF-8"?>
    <HwTheme>
        <title>\(title)</title>
        <title-cn>\(title)</title-cn>
        <author>lemonspitz</author>
        <designer>WatchDeck FaceMaker</designer>
        <screen>\(screen)</screen>
        <version>1.0</version>
        <font>Default</font>
        <font-cn>默认</font-cn>
        <briefinfo>{"en_US":"\(title) (\(category)) for \(screen) screens."}</briefinfo>
        <category>\(category)</category>
    </HwTheme>

    """
    try desc.write(to: tmp.appendingPathComponent("description.xml"), atomically: true, encoding: .utf8)
    try jpeg(preview).write(to: tmp.appendingPathComponent("preview/cover.jpg"))
    try jpeg(preview, scale: 0.5).write(to: tmp.appendingPathComponent("preview/icon_small.jpg"))
    let out = folder.appendingPathComponent(file)
    try? FileManager.default.removeItem(at: out)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    p.currentDirectoryURL = tmp
    p.arguments = ["-q", "-X", "-r", out.path, "com.huawei.watchface", "description.xml", "preview"]
    try p.run(); p.waitUntilExit()
    // A PNG copy of the design for browsing outside the app.
    // A small copy of the design for browsing outside the app.
    try jpeg(preview, scale: 0.5).write(to: folder.appendingPathComponent("previews/" + file.replacingOccurrences(of: ".hwt", with: ".jpg")))
    return bin.count
}

// MARK: - The 50 designs

func D(_ t: String, _ bg: Int, _ colors: [Int], _ fg: Int, _ accent: Int, _ font: String, _ layout: Layout) -> Design {
    Design(title: t, bg: bg, colors: colors, fg: fg, accent: accent, font: font, layout: layout, seed: abs(t.hashValueStable))
}

extension String {
    var hashValueStable: Int { unicodeScalars.reduce(5381) { ($0 &* 33) ^ Int($1.value) } & 0x7FFF_FFFF }
}

let designs: [Design] = [
    D("Midnight Bold", 0, [0x000000, 0x101820], 0xFFFFFF, 0x4DA3FF, "HelveticaNeue-CondensedBlack", .stack),
    D("Sunset Drive", 1, [0x2B1055, 0xF2709C, 0xFFD166], 0xFFFFFF, 0xFFE28A, "Futura-Bold", .bottom),
    D("Alpine Dawn", 2, [0xFDB99B, 0xCF8BF3, 0x5B4B8A, 0x241E4E], 0xFFFFFF, 0xFFF1C9, "AvenirNext-Heavy", .stack),
    D("Pacific Swell", 3, [0x0F2027, 0x203A43, 0x2C7DA0, 0x61C9E8], 0xFFFFFF, 0x9BF6FF, "rounded", .stack),
    D("Starlit", 4, [0x050A1F, 0x1B1F4B, 0xFFE9A8], 0xFFFFFF, 0xFFD86B, "thin", .stack),
    D("Racing Stripe", 5, [0x111111, 0x1C1C1C, 0xE10600], 0xFFFFFF, 0xFF3B30, "DINCondensed-Bold", .split),
    D("Neon Grid", 6, [0x12002B, 0x2A0A4A, 0xFF2BD6, 0xFFB000], 0xF8F8FF, 0x00F0FF, "Futura-CondensedExtraBold", .bottom),
    D("Ripple", 7, [0x0B132B, 0x1C2541, 0x5BC0BE, 0x6FFFE9], 0xFFFFFF, 0x6FFFE9, "AvenirNextCondensed-Heavy", .left),
    D("Bauhaus", 8, [0xF4EDE0, 0xF4EDE0, 0xD62828, 0x1D4E89], 0x111111, 0xD62828, "Futura-Bold", .stack),
    D("Polka Pop", 9, [0xFFF1E6, 0xFDE2E4, 0xFF8FAB, 0x84DCC6], 0x33272A, 0xE5446D, "ArialRoundedMTBold", .stack),
    D("City Lights", 10, [0x0B0C2A, 0x30235E, 0xFFE8A3, 0x0A0A18], 0xFFFFFF, 0xFFC857, "DINAlternate-Bold", .stack),
    D("Contour", 11, [0x0D1B1E, 0x12343B, 0x2D9596, 0x9AD0C2], 0xF1FAEE, 0xECF4D6, "mono", .left),
    D("Prism", 12, [0x16003B, 0x241468, 0xF73D93, 0x00DFA2], 0xFFFFFF, 0xF9F871, "GillSans-UltraBold", .split),
    D("Pixel Rain", 13, [0x001219, 0x002B36, 0x0A9396, 0x94D2BD], 0xE9D8A6, 0xEE9B00, "Menlo-Bold", .inline),
    D("Gallery Frame", 14, [0x1B1B1B, 0x1B1B1B, 0xC9A227, 0xC9A227], 0xF5F0E1, 0xE6C35C, "Didot-Bold", .stack),
    D("Orbit", 15, [0x000000, 0x0A0A0A, 0xFF9F1C, 0x2EC4B6], 0xFFFFFF, 0xFF9F1C, "rounded", .left),
    D("Petal", 16, [0xFFF0F3, 0xFFCCD5, 0xFF8FA3, 0xC9184A], 0x590D22, 0xC9184A, "Georgia-Bold", .stack),
    D("Strata", 17, [0x264653, 0x2A9D8F, 0xE9C46A, 0xF4A261], 0xFFFFFF, 0x1D1D1D, "Impact", .split),
    D("Circuit", 18, [0x04130B, 0x062B16, 0x1DB954, 0x9BE564], 0xD7FFE0, 0x39FF88, "Menlo-Bold", .left),
    D("Diagonal", 19, [0xF8F9FA, 0xE9ECEF, 0x212529], 0xFF6B35, 0x212529, "HelveticaNeue-CondensedBlack", .split),
    D("Ember", 0, [0x1A0000, 0x7A1E00], 0xFFE8D6, 0xFF7B00, "Impact", .stack),
    D("Glacier", 0, [0xE0FBFC, 0x98C1D9], 0x293241, 0x3D5A80, "AvenirNext-Heavy", .stack),
    D("Forest Trail", 2, [0xDDE5B6, 0xADC178, 0x6C8C4A, 0x283618], 0xFEFAE0, 0xFFFFFF, "AmericanTypewriter-Bold", .stack),
    D("Lagoon", 3, [0xCAF0F8, 0x90E0EF, 0x0096C7, 0x023E8A], 0x03045E, 0x0077B6, "rounded", .inline),
    D("Deep Space", 4, [0x000000, 0x10002B, 0xC77DFF], 0xE0AAFF, 0xFFFFFF, "Futura-Bold", .split),
    D("Candy Cane", 5, [0xFFFFFF, 0xFFF5F5, 0xE63946], 0x1D3557, 0xE63946, "ArialRoundedMTBold", .inline),
    D("Outrun", 6, [0x0D0221, 0x261447, 0x2DE2E6, 0xFF3864], 0xFFFFFF, 0xF9C80E, "DINCondensed-Bold", .bottom),
    D("Sonar", 7, [0x001D3D, 0x003566, 0xFFC300, 0xFFD60A], 0xFFFFFF, 0xFFD60A, "mono", .stack),
    D("De Stijl", 8, [0xFAFAFA, 0xFAFAFA, 0x0077B6, 0xFFB703], 0x111111, 0x0077B6, "HelveticaNeue-CondensedBlack", .left),
    D("Confetti", 9, [0x22223B, 0x4A4E69, 0xF2E9E4, 0xC9ADA7], 0xFFFFFF, 0xFFD166, "MarkerFelt-Wide", .stack),
    D("Metro Dusk", 10, [0xFF9E7A, 0x8E5572, 0xFFF3B0, 0x2B193D], 0xFFFFFF, 0xFFF3B0, "AvenirNextCondensed-Heavy", .stack),
    D("Dune", 11, [0xF6BD60, 0xF28482, 0x84503A, 0xFFF1D0], 0x3D1F12, 0xFFFFFF, "Optima-ExtraBlack", .stack),
    D("Kaleido", 12, [0x003049, 0x00507A, 0xFCBF49, 0xF77F00], 0xEAE2B7, 0xFCBF49, "Futura-CondensedExtraBold", .inline),
    D("Arcade", 13, [0x0F0F1B, 0x1A1A2E, 0xE94560, 0x0F3460], 0xFFFFFF, 0x16C79A, "Menlo-Bold", .stack),
    D("Ivory Classic", 14, [0xF7F3E9, 0xF7F3E9, 0x2F2F2F, 0x8D7B68], 0x2F2F2F, 0x8D7B68, "Baskerville-Bold", .stack),
    D("Halo", 15, [0x10002B, 0x240046, 0xFF6D00, 0xFF9E00], 0xFFFFFF, 0xFFB703, "AvenirNext-Heavy", .left),
    D("Autumn", 16, [0x3C1518, 0x69140E, 0xD58936, 0xF2F3AE], 0xF2F3AE, 0xFFB627, "Georgia-Bold", .stack),
    D("Layer Cake", 17, [0x5F0F40, 0x9A031E, 0xFB8B24, 0xE36414], 0xFFFFFF, 0xFFF3B0, "GillSans-UltraBold", .inline),
    D("Mainframe", 18, [0x000814, 0x001D3D, 0x00B4D8, 0x90E0EF], 0xCAF0F8, 0x48CAE4, "mono", .split),
    D("Slash", 19, [0x101010, 0x1A1A1A, 0xFFD60A], 0xFFFFFF, 0xFF4D6D, "Impact", .stack),
    D("Minimal White", 0, [0xFFFFFF, 0xF2F2F2], 0x111111, 0xFF3B30, "thin", .stack),
    D("Minimal Black", 0, [0x000000, 0x000000], 0xFFFFFF, 0x8E8E93, "thin", .inline),
    D("Royal", 14, [0x10162F, 0x10162F, 0xD4AF37, 0xD4AF37], 0xFFFFFF, 0xD4AF37, "Copperplate-Bold", .stack),
    D("Mint Chip", 9, [0xD8F3DC, 0xB7E4C7, 0x52B788, 0x1B4332], 0x1B4332, 0x2D6A4F, "rounded", .split),
    D("Volcano", 2, [0x370617, 0x9D0208, 0xDC2F02, 0x03071E], 0xFFBA08, 0xFFFFFF, "Futura-CondensedExtraBold", .stack),
    D("Aurora", 3, [0x03071E, 0x14213D, 0x38B000, 0x70E000], 0xFFFFFF, 0xCCFF33, "AvenirNextCondensed-Heavy", .bottom),
    D("Moonrise", 4, [0x1D2D44, 0x3E5C76, 0xF0EBD8], 0xF0EBD8, 0xFFFFFF, "serif", .bottom),
    D("Chalkboard", 0, [0x1F3A2D, 0x18301F], 0xF5F5F0, 0xFFE066, "ChalkboardSE-Bold", .stack),
    D("Typewriter", 0, [0xF2E8CF, 0xE9DDB9], 0x2B2118, 0xA4161A, "AmericanTypewriter-Bold", .inline),
    D("Hazard", 5, [0xFFD60A, 0xFFC300, 0x111111], 0xFFFFFF, 0xFFFFFF, "HelveticaNeue-CondensedBlack", .stack),
]

// MARK: - Main

/// Every screen Huawei and Honor use for custom watch faces (codes that share a size get one set).
let screens: [(code: String, w: Int, h: Int, round: Bool)] = [
    ("HWHD06", 280, 456, false),   // Watch Fit
    ("HWHD07", 194, 368, false),   // Band 6/7/8/9/10, Honor Band 6/7 (HNHD02)
    ("HWHD05", 188, 460, false),
    ("HNHD05", 256, 402, false),   // Honor Band 9/10 (QXHD01)
    ("HWHD14", 286, 482, false),
    ("HWHD11", 336, 480, false),   // Watch Fit 2
    ("HWHD10", 320, 360, false),
    ("HNHD03", 390, 450, false),
    ("HWHD13", 408, 480, false),   // Watch Fit 3/4/4 Pro/5
    ("QXHD02", 410, 502, false),
    ("HWHD12", 240, 240, true),
    ("HWHD08", 320, 320, true),
    ("HWHD01", 390, 390, true),    // GT 2 42 mm and similar
    ("HWHD02", 454, 454, true),    // GT / GT 2 46 mm, Honor (HNHD04)
    ("HWHD09", 466, 466, true),    // GT 2 Pro, GT 3/4/5 46 mm, Watch 3/4, Honor (HNHD01)
]

/// The original 50 digital designs, built by the same layout engine as the rest.
let digitalDesigns: [Design2] = designs.map {
    Design2(title: $0.title, kind: .digital, bg: $0.bg, colors: $0.colors, dial: nil, fg: $0.fg, accent: $0.accent,
            second: $0.accent, font: $0.font, variant: 0, layout: $0.layout)
}
let allDesigns = digitalDesigns + designs2 + designs3

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: facemaker <output folder> [screen code or WxH] [design number]"); exit(2) }
let root = URL(fileURLWithPath: args[1])
let screenFilter = args.count > 2 ? args[2] : nil
let only = args.count > 3 ? Int(args[3]) : nil
func fileName(_ n: Int, _ title: String) -> String {
    String(format: "%03d-%@.hwt", n, title.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "\u{E9}", with: "e"))
}
var grand = 0
for sc in screens where screenFilter == nil || screenFilter == sc.code || screenFilter == "\(sc.w)x\(sc.h)" {
    let folder = root.appendingPathComponent("\(sc.code)-\(sc.w)x\(sc.h)")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("previews"), withIntermediateDirectories: true)
    let frame = Frame(width: sc.w, height: sc.h, round: sc.round)
    var total = 0
    for (i, d) in allDesigns.enumerated() where only == nil || only == i + 1 {
        try autoreleasepool {
            let (face, preview) = build2(d, frame: frame)
            total += try writeHWT(title: d.title, category: d.category, screen: sc.code, face: face, preview: preview,
                                  folder: folder, file: fileName(i + 1, d.title))
        }
    }
    grand += total
    print(String(format: "%@ %4d x %-4d  %@  %3d faces  %6d KB", sc.code as NSString, sc.w, sc.h, sc.round ? "round" : "rect ",
                 only == nil ? allDesigns.count : 1, total / 1024))
}
print("Done: \(grand / 1024 / 1024) MB of face data in \(root.path)")
