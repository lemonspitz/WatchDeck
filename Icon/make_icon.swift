// Draws the WatchDeck app icon in one of several styles.
// Usage: make_icon <output folder> [style]   -> icon_16.png ... icon_1024.png
// Styles: glass (default), pulse, analog, rings, glyph
import AppKit
import CoreImage

func rgb(_ h: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}

struct Style {
    var tile: [Int]          // tile gradient, top-left to bottom-right
    var glow: Int?
    var strap: [Int]
    var rim: [Int]           // case gradient
    var screen: Int
    var content: String      // pulse, analog, rings, glyph
}

let styles: [String: Style] = [
    "pulse": Style(tile: [0x1E3A8A, 0x0E7490, 0x0B1530], glow: 0x22D3EE, strap: [0x1F2937, 0x374151, 0x1F2937],
                   rim: [0xE5E7EB, 0x9CA3AF, 0x4B5563, 0xD1D5DB], screen: 0x000000, content: "pulse"),
    "analog": Style(tile: [0xF97316, 0xDB2777, 0x6D28D9], glow: 0xFDE68A, strap: [0x7C2D12, 0x9A3412, 0x7C2D12],
                    rim: [0xFDE68A, 0xD4A017, 0x8A6A12, 0xF5D06F], screen: 0xFFF8EE, content: "analog"),
    "rings": Style(tile: [0x111827, 0x1F2937, 0x030712], glow: 0x84CC16, strap: [0x0F172A, 0x1E293B, 0x0F172A],
                   rim: [0x64748B, 0x334155, 0x0F172A, 0x475569], screen: 0x000000, content: "rings"),
    "glyph": Style(tile: [0xFFFFFF, 0xEEF2F6, 0xDDE3EA], glow: nil, strap: [0x111111, 0x111111, 0x111111],
                   rim: [0x111111, 0x111111, 0x111111, 0x111111], screen: 0x111111, content: "glyph"),
]

func draw(_ ctx: CGContext, _ st: Style) {
    let S: CGFloat = 1024
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)        // top-left origin
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func grad(_ cols: [Int], _ a: CGPoint, _ b: CGPoint) {
        let locs = (0 ..< cols.count).map { CGFloat($0) / CGFloat(max(1, cols.count - 1)) }
        ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: cols.map { rgb($0) } as CFArray, locations: locs)!, start: a, end: b, options: [])
    }
    func rounded(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }

    // macOS tile.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0, 0.35))
    ctx.addPath(rounded(tile, 185)); ctx.setFillColor(rgb(st.tile.last!)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(rounded(tile, 185)); ctx.clip()
    grad(st.tile, CGPoint(x: 100, y: 100), CGPoint(x: 924, y: 924))
    if let g = st.glow {
        let glow = CGGradient(colorsSpace: space, colors: [rgb(g, 0.35), rgb(g, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 500), startRadius: 0, endCenter: CGPoint(x: 512, y: 500), endRadius: 420, options: [])
    }
    let glyph = st.content == "glyph"
    // Straps.
    for r in [CGRect(x: 392, y: 60, width: 240, height: 260), CGRect(x: 392, y: 700, width: 240, height: 280)] {
        let rr = glyph ? r.insetBy(dx: 20, dy: 0) : r
        ctx.saveGState(); ctx.addPath(rounded(rr, 40)); ctx.clip()
        grad(st.strap, CGPoint(x: rr.minX, y: 0), CGPoint(x: rr.maxX, y: 0))
        if !glyph, r.minY > 500 {
            ctx.setFillColor(rgb(0x000000, 0.45))
            for i in 0 ..< 3 { ctx.fillEllipse(in: CGRect(x: 498, y: 790 + CGFloat(i) * 52, width: 28, height: 28)) }
        }
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // Case.
    let body = CGRect(x: 322, y: 222, width: 380, height: 580)
    ctx.saveGState()
    if !glyph { ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0, 0.55)) }
    ctx.addPath(rounded(body, 110)); ctx.setFillColor(rgb(st.rim[1])); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(rounded(body, 110)); ctx.clip()
    grad(st.rim, CGPoint(x: body.minX, y: body.minY), CGPoint(x: body.maxX, y: body.maxY))
    ctx.restoreGState()
    ctx.addPath(rounded(CGRect(x: 694, y: 430, width: 26, height: 90), 10)); ctx.setFillColor(rgb(st.rim[1])); ctx.fillPath()

    // Screen.
    let screen = body.insetBy(dx: glyph ? 34 : 22, dy: glyph ? 34 : 22)
    let screenPath = rounded(screen, glyph ? 78 : 90)
    ctx.addPath(screenPath); ctx.setFillColor(rgb(glyph ? 0xFFFFFF : st.screen)); ctx.fillPath()
    ctx.saveGState(); ctx.addPath(screenPath); ctx.clip()

    let c = CGPoint(x: 512, y: 470)
    func arc(_ center: CGPoint, _ r: CGFloat, _ w: CGFloat, _ a0: CGFloat, _ a1: CGFloat, _ col: CGColor) {
        ctx.setStrokeColor(col); ctx.setLineWidth(w); ctx.setLineCap(.round); ctx.beginPath()
        let n = 90
        for i in 0 ... n {
            let a = (a0 + (a1 - a0) * CGFloat(i) / CGFloat(n)) * .pi / 180
            let p = CGPoint(x: center.x + sin(a) * r, y: center.y - cos(a) * r)
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.strokePath()
    }
    func text(_ s: String, size: CGFloat, color: CGColor, center: CGPoint) {
        let f = NSFont.systemFont(ofSize: size, weight: .heavy)
        let font = NSFont(descriptor: f.fontDescriptor.withDesign(.rounded) ?? f.fontDescriptor, size: size) ?? f
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color]))
        let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.saveGState()
        ctx.translateBy(x: center.x - b.midX, y: center.y + b.midY); ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero; CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
    func hand(_ deg: CGFloat, _ len: CGFloat, _ w: CGFloat, _ col: CGColor, at center: CGPoint) {
        let a = deg * .pi / 180
        ctx.setStrokeColor(col); ctx.setLineWidth(w); ctx.setLineCap(.round); ctx.beginPath()
        ctx.move(to: center); ctx.addLine(to: CGPoint(x: center.x + sin(a) * len, y: center.y - cos(a) * len)); ctx.strokePath()
    }

    switch st.content {
    case "analog":
        let cc = CGPoint(x: 512, y: 512)
        for i in 0 ..< 12 {
            let a = CGFloat(i) * 30 * .pi / 180, major = i % 3 == 0
            ctx.setStrokeColor(rgb(major ? 0x7C2D12 : 0xB45309)); ctx.setLineWidth(major ? 16 : 9); ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cc.x + sin(a) * (major ? 112 : 124), y: cc.y - cos(a) * (major ? 112 : 124)))
            ctx.addLine(to: CGPoint(x: cc.x + sin(a) * 146, y: cc.y - cos(a) * 146)); ctx.strokePath()
        }
        hand(304.5, 86, 24, rgb(0x3B1F0E), at: cc)
        hand(57, 128, 16, rgb(0x3B1F0E), at: cc)
        hand(180, 136, 6, rgb(0xDB2777), at: cc)
        ctx.setFillColor(rgb(0xDB2777)); ctx.fillEllipse(in: CGRect(x: cc.x - 16, y: cc.y - 16, width: 32, height: 32))
    case "rings":
        arc(c, 150, 30, 0, 360, rgb(0x84CC16, 0.2)); arc(c, 150, 30, 0, 290, rgb(0x84CC16))
        arc(c, 112, 30, 0, 360, rgb(0xF43F5E, 0.2)); arc(c, 112, 30, 0, 220, rgb(0xF43F5E))
        arc(c, 74, 30, 0, 360, rgb(0x22D3EE, 0.2)); arc(c, 74, 30, 0, 320, rgb(0x22D3EE))
        text("10:09", size: 64, color: rgb(0xFFFFFF), center: CGPoint(x: 512, y: 694))
    case "glyph":
        // A dot with radio waves on a clean face: "control your watch".
        ctx.setFillColor(rgb(0xF97316)); ctx.fillEllipse(in: CGRect(x: 512 - 34, y: 512 - 34, width: 68, height: 68))
        for (i, r) in ([92, 150] as [CGFloat]).enumerated() {
            arc(CGPoint(x: 512, y: 512), r, 26, 50, 130, rgb(0x111111, i == 0 ? 1 : 0.55))
            arc(CGPoint(x: 512, y: 512), r, 26, 230, 310, rgb(0x111111, i == 0 ? 1 : 0.55))
        }
    default:
        arc(c, 132, 26, 0, 360, rgb(0x22D3EE, 0.18)); arc(c, 132, 26, -10, 250, rgb(0x22D3EE))
        text("10", size: 118, color: rgb(0xFFFFFF), center: CGPoint(x: 512, y: 418))
        text("09", size: 118, color: rgb(0x22D3EE), center: CGPoint(x: 512, y: 526))
        ctx.setStrokeColor(rgb(0xF43F5E)); ctx.setLineWidth(16); ctx.setLineJoin(.round); ctx.setLineCap(.round)
        ctx.beginPath()
        let pts: [(CGFloat, CGFloat)] = [(380, 686), (450, 686), (478, 640), (512, 726), (544, 662), (566, 686), (644, 686)]
        ctx.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
        ctx.strokePath()
    }
    if !glyph {
        let shine = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(shine, start: CGPoint(x: screen.minX, y: screen.minY), end: CGPoint(x: screen.midX, y: screen.midY), options: [])
    }
    ctx.restoreGState()
}

// MARK: - Glass style (translucent layers, specular rims, glowing rings)

func drawGlass(_ ctx: CGContext) {
    let S: CGFloat = 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func rounded(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }
    func grad(_ cols: [CGColor], _ a: CGPoint, _ b: CGPoint) {
        let locs = (0 ..< cols.count).map { CGFloat($0) / CGFloat(max(1, cols.count - 1)) }
        ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: cols as CFArray, locations: locs)!, start: a, end: b,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = rounded(tile, 185)

    // 1. Backdrop: deep gradient with soft colour blooms, blurred so the glass above has something to refract.
    let bd = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bd.translateBy(x: 0, y: S); bd.scaleBy(x: 1, y: -1)
    bd.drawLinearGradient(CGGradient(colorsSpace: space, colors: [rgb(0x1B1F4B), rgb(0x0F2B3D), rgb(0x05070F)] as CFArray,
                                     locations: [0, 0.55, 1])!, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 924, y: 924), options: [])
    for (x, y, r, col) in [(300.0, 280.0, 260.0, 0x84CC16), (760.0, 360.0, 240.0, 0xF43F5E), (520.0, 780.0, 280.0, 0x22D3EE), (800, 820, 200, 0x8B5CF6)] as [(CGFloat, CGFloat, CGFloat, Int)] {
        let g = CGGradient(colorsSpace: space, colors: [rgb(col, 0.75), rgb(col, 0)] as CFArray, locations: [0, 1])!
        bd.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
    }
    let ci = CIContext()
    func blurred(_ img: CGImage, _ radius: Double) -> CGImage {
        let input = CIImage(cgImage: img).clampedToExtent()
        let out = input.applyingGaussianBlur(sigma: radius).cropped(to: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        return ci.createCGImage(out, from: out.extent)!
    }
    let backdrop = blurred(bd.makeImage()!, 40)
    let frosted = blurred(backdrop, 70)
    func paint(_ img: CGImage) {      // images are drawn in device space; undo our flip
        ctx.saveGState(); ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: S, height: S)); ctx.restoreGState()
    }

    // Tile with drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: rgb(0, 0.4))
    ctx.addPath(tilePath); ctx.setFillColor(rgb(0x05070F)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(tilePath); ctx.clip(); paint(backdrop); ctx.restoreGState()

    /// A frosted glass shape: blurred backdrop, white tint, top-lit sheen, bright rim fading to the bottom.
    func glass(_ path: CGPath, bounds b: CGRect, tint: CGFloat, rim: CGFloat = 4) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: rgb(0, 0.45))
        ctx.addPath(path); ctx.setFillColor(rgb(0xFFFFFF, 0.02)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        paint(frosted)
        ctx.setFillColor(rgb(0xFFFFFF, tint)); ctx.fill(b)
        grad([rgb(0xFFFFFF, 0.28), rgb(0xFFFFFF, 0.04), rgb(0xFFFFFF, 0)], CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.midX, y: b.midY + b.height * 0.2))
        ctx.restoreGState()
        // Specular rim: bright on the top-left, fading around the shape.
        ctx.saveGState()
        ctx.addPath(path); ctx.setLineWidth(rim); ctx.replacePathWithStrokedPath(); ctx.clip()
        grad([rgb(0xFFFFFF, 0.95), rgb(0xFFFFFF, 0.25), rgb(0xFFFFFF, 0.6)], CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.maxY))
        ctx.restoreGState()
    }

    // 2. Straps as frosted bands.
    for r in [CGRect(x: 396, y: 70, width: 232, height: 240), CGRect(x: 396, y: 714, width: 232, height: 260)] {
        ctx.saveGState(); ctx.addPath(tilePath); ctx.clip()
        glass(rounded(r, 46), bounds: r, tint: 0.07, rim: 3)
        ctx.restoreGState()
    }

    // 3. Watch case: thicker glass, then a dark smoked screen.
    let body = CGRect(x: 318, y: 214, width: 388, height: 596)
    glass(rounded(body, 120), bounds: body, tint: 0.16, rim: 6)
    let crown = CGRect(x: 702, y: 426, width: 24, height: 96)
    glass(rounded(crown, 11), bounds: crown, tint: 0.3, rim: 2)
    let screen = body.insetBy(dx: 26, dy: 26)
    let screenPath = rounded(screen, 96)
    ctx.saveGState(); ctx.addPath(screenPath); ctx.clip()
    paint(frosted)
    ctx.setFillColor(rgb(0x02040A, 0.82)); ctx.fill(screen)
    ctx.restoreGState()

    // 4. Rings with glow and a glossy highlight along each stroke.
    let c = CGPoint(x: 512, y: 466)
    func arcPath(_ r: CGFloat, _ a0: CGFloat, _ a1: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let n = 120
        for i in 0 ... n {
            let a = (a0 + (a1 - a0) * CGFloat(i) / CGFloat(n)) * .pi / 180
            let pt = CGPoint(x: c.x + sin(a) * r, y: c.y - cos(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
    ctx.saveGState(); ctx.addPath(screenPath); ctx.clip()
    for (r, end, col) in [(152.0, 290.0, 0x84CC16), (112.0, 220.0, 0xF43F5E), (72.0, 320.0, 0x22D3EE)] as [(CGFloat, CGFloat, Int)] {
        ctx.setLineCap(.round)
        ctx.addPath(arcPath(r, 0, 360)); ctx.setLineWidth(32); ctx.setStrokeColor(rgb(col, 0.16)); ctx.strokePath()
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 34, color: rgb(col, 0.9))
        ctx.addPath(arcPath(r, 0, end)); ctx.setLineWidth(32); ctx.setStrokeColor(rgb(col)); ctx.strokePath()
        ctx.restoreGState()
        // Glossy core: a lighter, thinner stroke along the inside of the band.
        ctx.addPath(arcPath(r - 6, 4, end - 4)); ctx.setLineWidth(8); ctx.setStrokeColor(rgb(0xFFFFFF, 0.38)); ctx.strokePath()
    }
    // Time with a soft glow.
    let f = NSFont.systemFont(ofSize: 66, weight: .heavy)
    let font = NSFont(descriptor: f.fontDescriptor.withDesign(.rounded) ?? f.fontDescriptor, size: 66) ?? f
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "10:09", attributes: [.font: font, .foregroundColor: rgb(0xFFFFFF)]))
    let tb = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18, color: rgb(0xFFFFFF, 0.55))
    ctx.translateBy(x: 512 - tb.midX, y: 700 + tb.midY); ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero; CTLineDraw(line, ctx)
    ctx.restoreGState()
    // Glass reflection sweeping across the screen.
    ctx.saveGState()
    let sweep = CGMutablePath()
    sweep.move(to: CGPoint(x: screen.minX, y: screen.minY)); sweep.addLine(to: CGPoint(x: screen.maxX, y: screen.minY))
    sweep.addLine(to: CGPoint(x: screen.maxX, y: screen.minY + 120)); sweep.addLine(to: CGPoint(x: screen.minX, y: screen.minY + 290))
    sweep.closeSubpath()
    ctx.addPath(sweep); ctx.clip()
    grad([rgb(0xFFFFFF, 0.2), rgb(0xFFFFFF, 0.02)], CGPoint(x: screen.minX, y: screen.minY), CGPoint(x: screen.minX + 80, y: screen.minY + 260))
    ctx.restoreGState()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(screenPath); ctx.setLineWidth(2); ctx.setStrokeColor(rgb(0xFFFFFF, 0.18)); ctx.strokePath()
    ctx.restoreGState()

    // 5. Tile rim highlight, like the edge of a glass pane.
    ctx.saveGState()
    ctx.addPath(rounded(tile.insetBy(dx: 1.5, dy: 1.5), 184)); ctx.setLineWidth(3); ctx.replacePathWithStrokedPath(); ctx.clip()
    grad([rgb(0xFFFFFF, 0.55), rgb(0xFFFFFF, 0.05), rgb(0xFFFFFF, 0.25)], CGPoint(x: 100, y: 100), CGPoint(x: 924, y: 924))
    ctx.restoreGState()
}

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
let styleName = args.count > 2 ? args[2] : "glass"
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let big = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
if let st = styles[styleName] { draw(big, st) } else {
    big.translateBy(x: 0, y: 1024); big.scaleBy(x: 1, y: -1)
    drawGlass(big)
}
let master = big.makeImage()!
for s in [16, 32, 64, 128, 256, 512, 1024] {
    let c = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(master, in: CGRect(x: 0, y: 0, width: s, height: s))
    try NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent("icon_\(s).png"))
}
