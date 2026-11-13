// Faces 51-150: ten face types with different layouts and data, ten designs each.
import AppKit

enum Kind2: String {
    case digital = "Digital"
    case classic = "Analog", sport = "Analog Sport", hybrid = "Hybrid", seconds = "Digital Seconds"
    case dashboard = "Dashboard", weather = "Weather", rings = "Activity Rings", lcd = "Retro LCD"
    case minimal = "Minimal Analog", orbit = "Orbit"
}

struct Design2 {
    var title: String
    var kind: Kind2
    var bg: Int                 // background style (see drawBackground)
    var colors: [Int]
    var dial: Int?              // dial disc (analog) or LCD panel colour
    var fg: Int                 // hands, digits, text
    var accent: Int
    var second: Int
    var font: String
    var variant: Int = 0
    var layout: Layout = .stack
}

/// Value types (what live data a layer shows) and container data types (what a tap opens).
enum VT {
    static let hourHi = 59, hourLo = 60, minHi = 61, minLo = 62, secHi = 63, secLo = 64
    static let week = 52, month = 51, dayHi = 70, dayLo = 71
    static let weather = 53, tempUnit = 73, batteryLevel = 54
    static let hourHand = 150, minuteHand = 153, secondHand = 154
    static let stepsRatio = 161, heartRatio = 157, batteryRatio = 163
    static let steps = 0, calories = 1, heart = 2, temperature = 4, battery = 9
}
enum DT { static let heart = 11, activity = 33, battery = 17, weather = 21 }

/// Sample values shown in previews: 10:09:30, Friday 13 November.
let previewHour: CGFloat = 10, previewMinute: CGFloat = 9, previewSecond: CGFloat = 30

/// Where the 280 x 456 design block sits on a real screen.
struct Frame {
    let pw: Int, ph: Int          // screen pixels
    let round: Bool
    let s: CGFloat                // pixels per design unit
    let ox: CGFloat, oy: CGFloat  // design-block origin inside the frame, in design units

    init(width: Int, height: Int, round: Bool) {
        pw = width; ph = height; self.round = round
        if round { s = CGFloat(height) * 0.93 / 456 } else { s = min(CGFloat(width) / 280, CGFloat(height) / 456) }
        ox = (CGFloat(width) / s - 280) / 2
        oy = (CGFloat(height) / s - 456) / 2
    }

    func x(_ v: CGFloat) -> Int { Int(((v + ox) * s).rounded()) }
    func y(_ v: CGFloat) -> Int { Int(((v + oy) * s).rounded()) }
    func len(_ v: CGFloat) -> Int { max(1, Int((v * s).rounded())) }

    /// Horizontal room (design units, block coordinates) for a band from y0 to y1, keeping `margin` from the screen edge.
    func span(_ y0: CGFloat, _ y1: CGFloat, margin: CGFloat = 8) -> (CGFloat, CGFloat) {
        let dw = CGFloat(pw) / s, dh = CGFloat(ph) / s
        if !round { return (-ox + margin, 280 + ox - margin) }
        let r = dw / 2, c = dh / 2
        let dy = max(abs(y0 + oy - c), abs(y1 + oy - c))
        let half = dy >= r ? 0 : (r * r - dy * dy).squareRoot() - margin
        return (dw / 2 - half - ox, dw / 2 + half - ox)
    }
}

final class Builder {
    let d: Design2
    let f: Frame
    let face: Face
    let fg: RGB, acc: RGB, sec: RGB
    let bg: Canvas
    var ops: [Int: [(Canvas) -> Void]] = [0: [], 1: [], 2: [], 3: []]
    private var counter = 0
    private var labelCache: [String: [String]] = [:]

    init(_ d: Design2, frame: Frame) {
        self.d = d
        f = frame
        face = Face(d.title)
        fg = RGB(d.fg); acc = RGB(d.accent); sec = RGB(d.second)
        bg = Canvas(frame.pw, frame.ph)
    }

    func uid(_ p: String) -> String { counter += 1; return "\(p)\(counter)" }

    /// A canvas measured in design units, rendered at the screen's pixel density.
    func cv(_ w: CGFloat, _ h: CGFloat) -> Canvas { Canvas(design: w, h, scale: f.s) }

    func cgImage(_ name: String) -> CGImage {
        let im = face.images.first { $0.name == name }!
        return CGImage(width: im.w, height: im.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: im.w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: CGDataProvider(data: Data(im.rgba) as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// Preview drawing of an image at a block position.
    func stamp(_ label: Int, _ name: String, _ x: Int, _ y: Int) {
        let img = cgImage(name)
        let px = f.x(CGFloat(x)), py = f.y(CGFloat(y))
        ops[label]!.append { $0.draw(img, at: CGPoint(x: px, y: py)) }
    }

    /// A selectable image layer (digit, weekday, icon set...) at a block position, with its preview.
    func sel(_ names: [String], _ x: Int, _ y: Int, _ value: Int, label: Int, show: Int) -> Layer {
        stamp(label, names[show], x, y)
        return Layer(kind: .selected(names, f.x(CGFloat(x)), f.y(CGFloat(y)), value))
    }

    /// Block rect -> screen pixel rect.
    func px(_ r: [Int]) -> [Int] {
        let x0 = f.x(CGFloat(r[0])), y0 = f.y(CGFloat(r[1]))
        return [x0, y0, max(1, f.x(CGFloat(r[0] + r[2])) - x0), max(1, f.y(CGFloat(r[1] + r[3])) - y0)]
    }

    /// Horizontal shift (block units) that keeps a rect inside the screen, for corner widgets on round screens.
    func inset(_ r: [Int], margin: CGFloat = 6) -> Int {
        let (x0, x1) = f.span(CGFloat(r[1]), CGFloat(r[1] + r[3]), margin: margin)
        if CGFloat(r[0]) < x0 { return Int((x0 - CGFloat(r[0])).rounded(.up)) }
        if CGFloat(r[0] + r[2]) > x1 { return -Int((CGFloat(r[0] + r[2]) - x1).rounded(.up)) }
        return 0
    }

    // MARK: Colours

    /// Panel colour that keeps `fg` readable.
    var panelColor: CGColor { fg.isDark ? CGColor(gray: 1, alpha: 0.62) : CGColor(gray: 0, alpha: 0.42) }
    var iconColor: RGB { acc.isDark == fg.isDark ? acc : fg }
    var dim: RGB { fg.mix(fg.isDark ? RGB(0xFFFFFF) : RGB(0), 0.4) }

    func panel(_ r: CGRect, radius: CGFloat = 18) {
        bg.ctx.setFillColor(panelColor)
        bg.ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        bg.ctx.fillPath()
    }

    /// Background art scaled to cover the whole screen; afterwards the background canvas works in block coordinates.
    func baseBackground() {
        let base = Design(title: d.title, bg: d.bg, colors: d.colors, fg: d.fg, accent: d.accent, font: d.font, layout: d.layout,
                          seed: abs(d.title.hashValueStable))
        let k = max(CGFloat(f.pw) / 280, CGFloat(f.ph) / 456)
        let art = Canvas(design: 280, 456, scale: k)
        drawBackground(art, base, panel: false)
        bg.draw(art.image, at: CGPoint(x: (f.pw - art.w) / 2, y: (f.ph - art.h) / 2))
        bg.ctx.scaleBy(x: f.s, y: f.s)
        bg.ctx.translateBy(x: f.ox, y: f.oy)
    }

    func finishBackground() {
        face.add("bg", bg)
        face.background = [Layer(kind: .single("bg", 0, 0))]
        let img = bg.image
        ops[0]!.append { $0.draw(img, at: .zero) }
    }

    // MARK: Digits and labels

    func fontDigits(_ color: RGB, _ w: Int, _ h: Int, font: String? = nil, outline: Bool = true) -> [String] {
        let fontName = font ?? d.font
        var size = CGFloat(h) * 1.25
        while size > 8 {
            let fnt = makeFont(fontName, size)
            let ok = (0 ... 9).allSatisfy { n in
                let b = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(NSAttributedString(string: String(n), attributes: [.font: fnt])), .useGlyphPathBounds)
                return b.width <= CGFloat(w - 8) && b.height <= CGFloat(h - 8)
            }
            if ok { break }
            size -= 1
        }
        let p = uid("dg")
        return (0 ... 9).map { n in
            let c = cv(CGFloat(w), CGFloat(h))
            c.text(String(n), font: fontName, size: size, color: color.cg(), in: CGRect(x: 0, y: 0, width: w, height: h),
                   stroke: outline ? color.outline : nil, strokeWidth: 3, fixedSize: true)
            return face.add("\(p)_\(n)", c)
        }
    }

    func segmentDigits(_ color: RGB, _ w: Int, _ h: Int) -> [String] {
        let p = uid("sg")
        return (0 ... 9).map { n in
            let c = cv(CGFloat(w), CGFloat(h))
            sevenSegment(c, n, CGRect(x: 3, y: 3, width: w - 6, height: h - 6), color.cg(), thickness: CGFloat(w) * 0.17)
            return face.add("\(p)_\(n)", c)
        }
    }

    func labels(_ strings: [String], _ w: Int, _ h: Int, _ color: RGB, font: String = "system", size: CGFloat = 19, outline: Bool = true) -> [String] {
        let key = "\(strings.joined())\(w)\(h)\(color.bytes)\(font)\(size)\(outline)"
        if let hit = labelCache[key] { return hit }
        let p = uid("lb")
        let names = strings.enumerated().map { i, s -> String in
            let c = cv(CGFloat(w), CGFloat(h))
            c.text(s, font: font, size: size, color: color.cg(), in: CGRect(x: 0, y: 1, width: w, height: h - 2),
                   stroke: outline ? color.outline : nil, strokeWidth: 3)
            return face.add("\(p)_\(i)", c)
        }
        labelCache[key] = names
        return names
    }

    /// Time as four digit images. Positions are hour tens, hour ones, minute tens, minute ones.
    func clock(_ hours: [String], _ minutes: [String], _ pos: [(Int, Int)]) {
        face.time += [
            sel(Array(hours[0 ... 2]), pos[0].0, pos[0].1, VT.hourHi, label: 1, show: 1),
            sel(hours, pos[1].0, pos[1].1, VT.hourLo, label: 1, show: 0),
            sel(Array(minutes[0 ... 5]), pos[2].0, pos[2].1, VT.minHi, label: 1, show: 0),
            sel(minutes, pos[3].0, pos[3].1, VT.minLo, label: 1, show: 9),
        ]
    }

    func seconds(_ digits: [String], _ p0: (Int, Int), _ p1: (Int, Int)) {
        face.time += [sel(Array(digits[0 ... 5]), p0.0, p0.1, VT.secHi, label: 1, show: 3),
                      sel(digits, p1.0, p1.1, VT.secLo, label: 1, show: 0)]
    }

    func colon(_ r: CGRect, _ color: RGB, size: CGFloat) {
        bg.text(":", font: d.font, size: size, color: color.cg(), in: r, stroke: color.outline, strokeWidth: 3)
    }

    static func dateWidth(month: Bool) -> Int { 52 + 6 + 28 + (month ? 6 + 52 : 0) }

    /// Weekday, day of month and (optionally) month, starting at x.
    func dateRow(x: Int, y: Int, month: Bool = true, font: String = "system", weekColor: RGB? = nil, outline: Bool = true) {
        let wk = labels(weekdays, 52, 26, weekColor ?? acc, font: font, outline: outline)
        let dd = labels((0 ... 9).map(String.init), 14, 26, fg, font: font, outline: outline)
        face.date += [sel(wk, x, y, VT.week, label: 2, show: 5),
                      sel(Array(dd[0 ... 3]), x + 58, y, VT.dayHi, label: 2, show: 1),
                      sel(dd, x + 72, y, VT.dayLo, label: 2, show: 3)]
        if month {
            let mo = labels(months, 52, 26, fg, font: font, outline: outline)
            face.date.append(sel(mo, x + 92, y, VT.month, label: 2, show: 11))
        }
    }

    func centeredDate(y: Int, month: Bool = true, font: String = "system") {
        dateRow(x: (W - Builder.dateWidth(month: month)) / 2, y: y, month: month, font: font)
    }

    // MARK: Widgets

    func text(_ r: [Int], _ value: Int, _ sample: String, _ color: RGB? = nil, size: CGFloat? = nil) -> Layer {
        let col = color ?? fg
        let pr = px(r)
        let sz = (size ?? CGFloat(r[3]) * 0.8) * f.s
        ops[3]!.append { $0.text(sample, font: "system", size: sz, color: col.cg(), in: CGRect(x: pr[0], y: pr[1], width: pr[2], height: pr[3])) }
        return Layer(kind: .text(pr, col.bytes, value))
    }

    func icon(_ name: String, _ r: [Int], _ color: RGB? = nil) -> Layer {
        let c = cv(CGFloat(r[2]), CGFloat(r[3]))
        drawIcon(name, c, CGRect(x: 1, y: 1, width: r[2] - 2, height: r[3] - 2), (color ?? iconColor).cg(), acc.cg())
        let n = face.add(uid("ic"), c)
        stamp(3, n, r[0], r[1])
        return Layer(kind: .single(n, f.x(CGFloat(r[0])), f.y(CGFloat(r[1]))))
    }

    func weatherIcons(_ size: Int) -> [String] {
        let p = uid("wx")
        return weatherIconNames.enumerated().map { i, name in
            let c = cv(CGFloat(size), CGFloat(size))
            drawIcon(name, c, CGRect(x: 2, y: 2, width: size - 4, height: size - 4), fg.cg(), acc.cg())
            return face.add("\(p)_\(i)", c)
        }
    }

    func weatherIcon(_ size: Int, _ x: Int, _ y: Int) -> Layer { sel(weatherIcons(size), x, y, VT.weather, label: 3, show: 1) }

    func unit(_ x: Int, _ y: Int, _ w: Int = 30, _ h: Int = 26, size: CGFloat = 18) -> Layer {
        sel(labels(["°C", "°F"], w, h, fg, size: size), x, y, VT.tempUnit, label: 3, show: 0)
    }

    /// A tappable widget area. The watch wants at least 44 x 44 pixels, kept inside the screen.
    func container(_ r: [Int], _ dt: Int, _ layers: [Layer]) {
        var p = px(r)
        for (i, limit) in [(0, f.pw), (1, f.ph)] where p[i + 2] < 44 {
            let grow = 44 - p[i + 2]
            p[i] = max(0, min(limit - 44, p[i] - grow / 2)); p[i + 2] = 44
        }
        face.containers.append(Container(rect: p, dataType: dt, layers: layers))
    }

    enum Stat { case heart, steps, calories, battery, weather }

    func statLayers(_ s: Stat, col x0: Int, width w: Int, y: Int) -> (Int, [Layer]) {
        let cx = x0 + w / 2
        let iconRect = [cx - 10, y + 8, 20, 20]
        let textRect = [x0 + 4, y + 30, w - 8, 28]
        switch s {
        case .heart: return (DT.heart, [icon("heart", iconRect), text(textRect, VT.heart, "72")])
        case .steps: return (DT.activity, [icon("steps", iconRect), text(textRect, VT.steps, "8426")])
        case .calories: return (DT.activity, [icon("flame", iconRect), text(textRect, VT.calories, "326")])
        case .battery: return (DT.battery, [icon("bolt", iconRect), text(textRect, VT.battery, "88")])
        case .weather: return (DT.weather, [weatherIcon(22, cx - 11, y + 7), text(textRect, VT.temperature, "24°")])
        }
    }

    /// A row of statistics on a soft panel, as wide as the screen allows at that height.
    func strip(y: Int, _ items: [Stat]) {
        let (a, b) = f.span(CGFloat(y), CGFloat(y + 64), margin: 8)
        let x0 = Int(a.rounded(.up)), total = Int(b.rounded(.down)) - x0
        panel(CGRect(x: x0, y: y, width: total, height: 64))
        let w = total / items.count
        for (i, s) in items.enumerated() {
            let cx0 = x0 + i * w
            let (dt, layers) = statLayers(s, col: cx0, width: w, y: y)
            container([cx0 + 2, y + 2, w - 4, 60], dt, layers)
        }
    }

    // MARK: Analog parts

    func strokeArc(_ c: Canvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ lw: CGFloat, _ a0: CGFloat, _ a1: CGFloat, _ color: CGColor) {
        let ctx = c.ctx
        ctx.setStrokeColor(color); ctx.setLineWidth(lw); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.beginPath()
        let n = max(2, Int(abs(a1 - a0) / 2))
        for i in 0 ... n {
            let a = (a0 + (a1 - a0) * CGFloat(i) / CGFloat(n)) * .pi / 180
            let p = CGPoint(x: cx + sin(a) * r, y: cy - cos(a) * r)
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.strokePath()
    }

    /// A progress arc (angles in compass degrees, 0 = 12 o'clock, clockwise) with its track baked into the background.
    func arc(cx: Int, cy: Int, r: Int, lw: Int, start: Int, end: Int, color: RGB, value: Int, sample: CGFloat) -> Layer {
        strokeArc(bg, CGFloat(cx), CGFloat(cy), CGFloat(r), CGFloat(lw), CGFloat(start), CGFloat(end), color.cg(0.22))
        let size = 2 * (r + lw) + 2
        let c = cv(CGFloat(size), CGFloat(size))
        strokeArc(c, CGFloat(size) / 2, CGFloat(size) / 2, CGFloat(r), CGFloat(lw), CGFloat(start), CGFloat(end), color.cg())
        let n = face.add(uid("arc"), c)
        let pcx = f.x(CGFloat(cx)), pcy = f.y(CGFloat(cy)), pr = f.len(CGFloat(r)), plw = f.len(CGFloat(lw))
        var l = Layer(kind: .arc(n, [pcx - c.w / 2, pcy - c.h / 2, c.w, c.h], c.w / 2, c.h / 2, pr, plw, start, end))
        l.arcValue = value
        ops[3]!.append { [self] pv in
            strokeArc(pv, CGFloat(pcx), CGFloat(pcy), CGFloat(pr), CGFloat(plw), CGFloat(start),
                      CGFloat(start) + CGFloat(end - start) * sample, color.cg())
        }
        return l
    }

    func dial(cx: CGFloat, cy: CGFloat, R discR: CGFloat, markers: Int, disc: RGB?, skip: Set<Int> = [], ink: RGB? = nil, markerInset: CGFloat = 0) {
        var R = discR
        let ctx = bg.ctx
        let ink = ink ?? fg
        if let disc {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
            ctx.fillEllipse(in: CGRect(x: cx - R - 4, y: cy - R - 2, width: 2 * R + 8, height: 2 * R + 8))
            ctx.setFillColor(disc.cg()); ctx.fillEllipse(in: CGRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R))
            ctx.setStrokeColor(acc.cg(0.6)); ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: cx - R + 1, y: cy - R + 1, width: 2 * R - 2, height: 2 * R - 2))
        }
        R = discR - markerInset
        func pt(_ deg: CGFloat, _ r: CGFloat) -> CGPoint {
            CGPoint(x: cx + sin(deg * .pi / 180) * r, y: cy - cos(deg * .pi / 180) * r)
        }
        func tick(_ deg: CGFloat, _ r0: CGFloat, _ r1: CGFloat, _ w: CGFloat, _ col: CGColor) {
            ctx.setStrokeColor(col); ctx.setLineWidth(w); ctx.setLineCap(.butt)
            ctx.beginPath(); ctx.move(to: pt(deg, r0)); ctx.addLine(to: pt(deg, r1)); ctx.strokePath()
        }
        let style = markers % 5
        if style != 1 {
            for i in 0 ..< 60 where i % 5 != 0 { tick(CGFloat(i) * 6, R - 9, R - 3, 1.5, ink.cg(0.7)) }
        }
        let roman = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
        for h in 0 ..< 12 where !skip.contains(h) {
            let deg = CGFloat(h) * 30
            switch style {
            case 0:
                if h == 0 { tick(-2.2, R - 4, R - 24, 4, acc.cg()); tick(2.2, R - 4, R - 24, 4, acc.cg()) }
                else { tick(deg, R - 4, R - (h % 3 == 0 ? 24 : 18), h % 3 == 0 ? 6 : 4, ink.cg()) }
            case 1:
                for i in 0 ..< 60 where i % 5 != 0 {
                    let p = pt(CGFloat(i) * 6, R - 7); ctx.setFillColor(ink.cg(0.6)); ctx.fillEllipse(in: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3))
                }
                if h == 0 {
                    let a = pt(0, R - 6), b = pt(-4, R - 24), c = pt(4, R - 24)
                    ctx.beginPath(); ctx.move(to: a); ctx.addLine(to: b); ctx.addLine(to: c); ctx.closePath()
                    ctx.setFillColor(acc.cg()); ctx.fillPath()
                } else {
                    let p = pt(deg, R - 14), r: CGFloat = h % 3 == 0 ? 7 : 5
                    ctx.setFillColor(ink.cg()); ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                }
            case 2:
                let p = pt(deg, R - 28)
                bg.text(h == 0 ? "12" : String(h), font: d.font, size: 24, color: (h == 0 ? acc : ink).cg(),
                        in: CGRect(x: p.x - 18, y: p.y - 13, width: 36, height: 26))
            case 3:
                let p = pt(deg, R - 28)
                bg.text(roman[h], font: d.font, size: 19, color: (h == 0 ? acc : ink).cg(),
                        in: CGRect(x: p.x - 22, y: p.y - 11, width: 44, height: 22))
            default:
                if h % 3 == 0 {
                    let p = pt(deg, R - 32)
                    bg.text(h == 0 ? "12" : String(h), font: d.font, size: 36, color: (h == 0 ? acc : ink).cg(),
                            in: CGRect(x: p.x - 24, y: p.y - 19, width: 48, height: 38))
                } else { tick(deg, R - 4, R - 18, 5, ink.cg()) }
            }
        }
    }

    /// A hand image pointing to 12 o'clock. Returns the image and its pivot in pixels.
    func handImage(len: CGFloat, tail: CGFloat, width: CGFloat, color: RGB, style: Int) -> (Canvas, Int, Int) {
        let w = CGFloat(Int(width) / 2 * 2 + 8), h = len + tail + 8
        let c = cv(w, h)
        let ctx = c.ctx
        let cx = w / 2, top: CGFloat = 4, py = top + len, bottom = py + tail
        ctx.setFillColor(color.cg())
        switch style % 5 {
        case 0:
            ctx.addPath(CGPath(roundedRect: CGRect(x: cx - width / 2, y: top, width: width, height: bottom - top),
                               cornerWidth: width / 2, cornerHeight: width / 2, transform: nil)); ctx.fillPath()
        case 1:
            ctx.beginPath(); ctx.move(to: CGPoint(x: cx, y: top)); ctx.addLine(to: CGPoint(x: cx + width / 2, y: py - len * 0.3))
            ctx.addLine(to: CGPoint(x: cx + width * 0.3, y: bottom)); ctx.addLine(to: CGPoint(x: cx - width * 0.3, y: bottom))
            ctx.addLine(to: CGPoint(x: cx - width / 2, y: py - len * 0.3)); ctx.closePath(); ctx.fillPath()
        case 2:
            ctx.beginPath(); ctx.move(to: CGPoint(x: cx, y: top)); ctx.addLine(to: CGPoint(x: cx + width / 2, y: py - len * 0.12))
            ctx.addLine(to: CGPoint(x: cx, y: bottom)); ctx.addLine(to: CGPoint(x: cx - width / 2, y: py - len * 0.12))
            ctx.closePath(); ctx.fillPath()
        case 3:
            ctx.setStrokeColor(color.cg()); ctx.setLineWidth(2.5)
            ctx.addPath(CGPath(roundedRect: CGRect(x: cx - width / 2 + 1.5, y: top + 1.5, width: width - 3, height: bottom - top - 3),
                               cornerWidth: width / 2 - 1, cornerHeight: width / 2 - 1, transform: nil)); ctx.strokePath()
            ctx.setFillColor(acc.cg())
            ctx.addPath(CGPath(roundedRect: CGRect(x: cx - width / 2 + 3, y: top + 4, width: width - 6, height: len * 0.32),
                               cornerWidth: 2, cornerHeight: 2, transform: nil)); ctx.fillPath()
        default:
            ctx.fill(CGRect(x: cx - width * 0.2, y: top + width * 1.2, width: width * 0.4, height: bottom - top - width * 1.2))
            ctx.beginPath(); ctx.move(to: CGPoint(x: cx, y: top)); ctx.addLine(to: CGPoint(x: cx + width / 2, y: top + width * 1.6))
            ctx.addLine(to: CGPoint(x: cx - width / 2, y: top + width * 1.6)); ctx.closePath(); ctx.fillPath()
        }
        return (c, c.w / 2, Int((py * f.s).rounded()))
    }

    func secondHandImage(len: CGFloat, tail: CGFloat, color: RGB, dotOnly: Bool = false) -> (Canvas, Int, Int) {
        let c = cv(14, len + tail + 10)
        let ctx = c.ctx
        let cx: CGFloat = 7, top: CGFloat = 5, py = top + len
        ctx.setFillColor(color.cg())
        if dotOnly {
            ctx.fillEllipse(in: CGRect(x: cx - 6, y: top - 4, width: 12, height: 12))
        } else {
            ctx.fill(CGRect(x: cx - 1.25, y: top, width: 2.5, height: len + tail))
            ctx.fillEllipse(in: CGRect(x: cx - 5, y: py + tail - 5, width: 10, height: 10))
            ctx.fillEllipse(in: CGRect(x: cx - 4, y: top + len * 0.12, width: 8, height: 8))
        }
        return (c, c.w / 2, Int((py * f.s).rounded()))
    }

    func addHand(_ img: (Canvas, Int, Int), cx: Int, cy: Int, value: Int, angle: CGFloat) {
        let (c, px, py) = img
        let n = face.add(uid("hand"), c)
        let pcx = f.x(CGFloat(cx)), pcy = f.y(CGFloat(cy))
        let half = min(max(py, c.h - py) + c.w / 2 + 2, min(pcx, pcy, f.pw - pcx, f.ph - pcy))
        face.time.append(Layer(kind: .hand(n, [pcx - half, pcy - half, 2 * half, 2 * half], px, py, value)))
        let cg = cgImage(n)
        ops[1]!.append { pv in
            pv.ctx.saveGState()
            pv.ctx.translateBy(x: CGFloat(pcx), y: CGFloat(pcy))
            pv.ctx.rotate(by: angle * .pi / 180)
            pv.draw(cg, at: CGPoint(x: -px, y: -py))
            pv.ctx.restoreGState()
        }
    }

    func hands(cx: Int, cy: Int, R: CGFloat, style: Int, secondStyle: Int = 0) {
        let hourAngle = (previewHour + previewMinute / 60) * 30, minuteAngle = (previewMinute + previewSecond / 60) * 6
        addHand(handImage(len: R * 0.55, tail: R * 0.12, width: 13, color: fg, style: style), cx: cx, cy: cy, value: VT.hourHand, angle: hourAngle)
        addHand(handImage(len: R * 0.84, tail: R * 0.12, width: 10, color: fg, style: style), cx: cx, cy: cy, value: VT.minuteHand, angle: minuteAngle)
        if secondStyle >= 0 {
            addHand(secondHandImage(len: R * 0.9, tail: R * 0.2, color: sec, dotOnly: secondStyle == 1), cx: cx, cy: cy,
                    value: VT.secondHand, angle: previewSecond * 6)
        }
        let cap = cv(18, 18)
        cap.ctx.setFillColor(fg.cg()); cap.ctx.fillEllipse(in: CGRect(x: 1, y: 1, width: 16, height: 16))
        cap.ctx.setFillColor(sec.cg()); cap.ctx.fillEllipse(in: CGRect(x: 5, y: 5, width: 8, height: 8))
        let n = face.add(uid("cap"), cap)
        let x = f.x(CGFloat(cx)) - cap.w / 2, y = f.y(CGFloat(cy)) - cap.h / 2
        face.time.append(Layer(kind: .single(n, x, y)))
        let img = cgImage(n)
        ops[1]!.append { $0.draw(img, at: CGPoint(x: x, y: y)) }
    }

    func render() -> CGImage {
        let pv = Canvas(f.pw, f.ph)
        for label in face.order { for op in ops[label] ?? [] { op(pv) } }
        if f.round {
            // Show only what a round screen displays.
            let out = Canvas(f.pw, f.ph)
            out.fill(CGColor(gray: 0, alpha: 1), CGRect(x: 0, y: 0, width: f.pw, height: f.ph))
            out.ctx.addEllipse(in: CGRect(x: 0, y: 0, width: f.pw, height: f.ph)); out.ctx.clip()
            out.draw(pv.image, at: .zero)
            return out.image
        }
        return pv.image
    }
}

// MARK: - The ten face types

func build2(_ d: Design2, frame: Frame) -> (face: Face, preview: CGImage) {
    let b = Builder(d, frame: frame)
    b.baseBackground()
    let v = d.variant
    switch d.kind {
    case .classic:
        b.face.order = [0, 2, 3, 1]
        let cx = 140, cy = 192, R: CGFloat = 126
        b.dial(cx: CGFloat(cx), cy: CGFloat(cy), R: R, markers: v, disc: d.dial.map(RGB.init), skip: [3])
        // Date window at 3 o'clock and weekday under 12.
        let win = CGRect(x: 198, y: 178, width: 40, height: 28)
        b.bg.fill(RGB(d.dial ?? 0).mix(b.fg, 0.12).cg(), win)
        b.bg.ctx.setStrokeColor(b.acc.cg()); b.bg.ctx.setLineWidth(1.5); b.bg.ctx.stroke(win)
        let dd = b.labels((0 ... 9).map(String.init), 14, 24, b.fg, size: 18, outline: false)
        b.face.date += [b.sel(Array(dd[0 ... 3]), 204, 180, VT.dayHi, label: 2, show: 1), b.sel(dd, 218, 180, VT.dayLo, label: 2, show: 3)]
        let wk = b.labels(weekdays, 52, 22, b.acc, size: 15, outline: false)
        b.face.date.append(b.sel(wk, cx - 26, cy - 72, VT.week, label: 2, show: 5))
        let mo = b.labels(months, 52, 26, b.fg.isDark == RGB(d.colors[0]).isDark ? b.acc : b.fg, size: 18)
        b.face.date.append(b.sel(mo, cx - 26, 22, VT.month, label: 2, show: 11))
        b.strip(y: 368, [.heart, .steps, .battery])
        b.hands(cx: cx, cy: cy, R: R, style: v + 1)
    case .sport:
        b.face.order = [0, 2, 3, 1]
        let cx = 140, cy = 200, R: CGFloat = 128
        b.dial(cx: CGFloat(cx), cy: CGFloat(cy), R: R, markers: [0, 1, 4][v % 3], disc: d.dial.map(RGB.init), skip: [6], markerInset: 16)
        let ring = b.arc(cx: cx, cy: cy, r: 120, lw: 6, start: 220, end: 500, color: b.acc, value: VT.stepsRatio, sample: 0.72)
        let stepsIcon = b.icon("steps", [cx - 9, cy + 44, 18, 18])
        let stepsText = b.text([cx - 32, cy + 62, 64, 24], VT.steps, "8426")
        b.container([12, 72, 256, 256], DT.activity, [ring, stepsIcon, stepsText])
        b.centeredDate(y: 24)
        b.strip(y: 370, [.heart, .calories, .battery])
        b.hands(cx: cx, cy: cy, R: R - 18, style: v + 2)
    case .hybrid:
        b.face.order = [0, 2, 3, 1]
        let cx = 140, cy = 144, R: CGFloat = 108
        b.dial(cx: CGFloat(cx), cy: CGFloat(cy), R: R, markers: v, disc: d.dial.map(RGB.init))
        let hh = b.fontDigits(b.acc, 44, 70), mm = b.fontDigits(b.fg, 44, 70)
        b.colon(CGRect(x: 131, y: 274, width: 18, height: 64), b.fg, size: 56)
        b.clock(hh, mm, [(43, 272), (87, 272), (149, 272), (193, 272)])
        b.centeredDate(y: 350)
        b.strip(y: 384, [.heart, .steps, .battery])
        b.hands(cx: cx, cy: cy, R: R, style: v + 3)
    case .seconds:
        let ddx = b.inset([16, 22, Builder.dateWidth(month: true), 26])
        b.dateRow(x: 16 + ddx, y: 22)
        let bdx = b.inset([200, 10, 72, 44])
        let bat = [b.icon("bolt", [208 + bdx, 22, 18, 20]), b.text([226 + bdx, 18, 46, 28], VT.battery, "88")]
        b.container([200 + bdx, 10, 72, 44], DT.battery, bat)
        let hh = b.fontDigits(b.acc, 60, 112), mm = b.fontDigits(b.fg, 60, 112)
        b.colon(CGRect(x: 128, y: 104, width: 24, height: 96), b.fg, size: 90)
        b.clock(hh, mm, [(8, 96), (68, 96), (152, 96), (212, 96)])
        let ss = b.fontDigits(b.acc, 36, 60)
        b.seconds(ss, (172, 216), (208, 216))
        b.bg.text("SEC", font: "system", size: 13, color: b.dim.cg(), in: CGRect(x: 120, y: 238, width: 46, height: 18), align: 2)
        b.bg.fill(b.acc.cg(0.8), CGRect(x: 16, y: 290, width: 248, height: 3))
        b.strip(y: 372, [.heart, .steps, .calories])
    case .dashboard:
        let hh = b.fontDigits(b.acc, 46, 80), mm = b.fontDigits(b.fg, 46, 80)
        b.colon(CGRect(x: 130, y: 26, width: 20, height: 72), b.fg, size: 64)
        b.clock(hh, mm, [(38, 22), (84, 22), (150, 22), (196, 22)])
        b.centeredDate(y: 110)
        let (ta, tb) = b.f.span(148, 340, margin: 10)
        let tx0 = Int(ta.rounded(.up)), tw = (Int(tb.rounded(.down)) - tx0 - 8) / 2
        let tiles: [(Int, Int, String, String, Int, Int, String)] = [
            (tx0, 148, "heart", "HEART", VT.heart, DT.heart, "72"), (tx0 + tw + 8, 148, "steps", "STEPS", VT.steps, DT.activity, "8426"),
            (tx0, 248, "flame", "KCAL", VT.calories, DT.activity, "326"), (tx0 + tw + 8, 248, "bolt", "BATTERY", VT.battery, DT.battery, "88"),
        ]
        for (x, y, ic, label, value, dt, sample) in tiles {
            b.panel(CGRect(x: x, y: y, width: tw, height: 92), radius: 16)
            b.bg.text(label, font: "system", size: 13, color: b.dim.cg(), in: CGRect(x: x + 42, y: y + 14, width: tw - 50, height: 20), align: 0)
            b.container([x, y, tw, 92], dt, [b.icon(ic, [x + 12, y + 12, 24, 24]), b.text([x + 8, y + 44, tw - 16, 38], value, sample)])
        }
        let (wa, wb) = b.f.span(352, 436, margin: 10)
        let wx0 = Int(wa.rounded(.up)), ww = Int(wb.rounded(.down)) - wx0
        b.panel(CGRect(x: wx0, y: 352, width: ww, height: 84), radius: 16)
        if ww >= 260 { b.bg.text("WEATHER", font: "system", size: 13, color: b.dim.cg(), in: CGRect(x: wx0 + ww - 78, y: 384, width: 70, height: 20), align: 0) }
        b.container([wx0, 352, ww, 84], DT.weather, [b.weatherIcon(48, wx0 + 14, 370), b.text([wx0 + 72, 372, 72, 40], VT.temperature, "24"), b.unit(wx0 + 144, 380)])
    case .weather:
        let wx = b.weatherIcon(112, 84, 22)
        b.container([40, 16, 200, 200], DT.weather, [wx, b.text([66, 146, 104, 44], VT.temperature, "24", size: 38), b.unit(172, 156, 32, 28, size: 20)])
        let hh = b.fontDigits(b.acc, 56, 100), mm = b.fontDigits(b.fg, 56, 100)
        b.colon(CGRect(x: 130, y: 232, width: 20, height: 88), b.fg, size: 80)
        b.clock(hh, mm, [(18, 226), (74, 226), (150, 226), (206, 226)])
        b.centeredDate(y: 338)
        b.strip(y: 378, [.heart, .steps, .battery])
    case .rings:
        let hh = b.fontDigits(b.acc, 56, 100), mm = b.fontDigits(b.fg, 56, 100)
        b.colon(CGRect(x: 130, y: 40, width: 20, height: 88), b.fg, size: 80)
        b.clock(hh, mm, [(18, 34), (74, 34), (150, 34), (206, 34)])
        b.centeredDate(y: 146)
        let ringColors = [b.acc, b.sec, b.fg.mix(b.acc, 0.5)]
        let gauges: [(Int, String, String, Int, Int, Int, String, CGFloat)] = [
            (50, "steps", "STEPS", VT.stepsRatio, VT.steps, DT.activity, "8426", 0.72),
            (140, "heart", "PULSE", VT.heartRatio, VT.heart, DT.heart, "72", 0.38),
            (230, "bolt", "POWER", VT.batteryRatio, VT.battery, DT.battery, "88", 0.88),
        ]
        for (i, (gx, ic, label, ratio, value, dt, sample, frac)) in gauges.enumerated() {
            let a = b.arc(cx: gx, cy: 262, r: 34, lw: 9, start: 0, end: 360, color: ringColors[i], value: ratio, sample: frac)
            b.bg.text(label, font: "system", size: 12, color: b.dim.cg(), in: CGRect(x: gx - 40, y: 306, width: 80, height: 18))
            b.container([gx - 44, 214, 88, 112], dt, [a, b.icon(ic, [gx - 9, 238, 18, 18], ringColors[i]), b.text([gx - 30, 258, 60, 22], value, sample)])
        }
        let (ra, rb) = b.f.span(356, 436, margin: 10)
        let rx0 = Int(ra.rounded(.up)), rw = Int(rb.rounded(.down)) - rx0
        b.panel(CGRect(x: rx0, y: 356, width: rw, height: 80), radius: 16)
        if rw >= 260 { b.bg.text("TODAY", font: "system", size: 13, color: b.dim.cg(), in: CGRect(x: rx0 + rw - 78, y: 386, width: 70, height: 20), align: 0) }
        b.container([rx0, 356, rw, 80], DT.weather, [b.weatherIcon(44, rx0 + 16, 374), b.text([rx0 + 70, 376, 72, 38], VT.temperature, "24"), b.unit(rx0 + 142, 384)])
    case .lcd:
        let lcd = RGB(d.dial ?? 0x9EAD86)
        b.bg.ctx.setFillColor(CGColor(gray: 0, alpha: 0.5))
        b.bg.ctx.addPath(CGPath(roundedRect: CGRect(x: 6, y: 50, width: 268, height: 258), cornerWidth: 22, cornerHeight: 22, transform: nil))
        b.bg.ctx.fillPath()
        b.bg.ctx.setFillColor(lcd.cg())
        b.bg.ctx.addPath(CGPath(roundedRect: CGRect(x: 12, y: 56, width: 256, height: 246), cornerWidth: 16, cornerHeight: 16, transform: nil))
        b.bg.ctx.fillPath()
        let ghost = b.fg.cg(0.08)
        for x in [18, 76, 150, 208] { sevenSegment(b.bg, 8, CGRect(x: x + 3, y: 115, width: 48, height: 94), ghost, thickness: 54 * 0.17, ghost: true) }
        for x in [194, 226] { sevenSegment(b.bg, 8, CGRect(x: x + 3, y: 233, width: 22, height: 42), ghost, thickness: 28 * 0.17, ghost: true) }
        b.bg.fill(b.fg.cg(), CGRect(x: 135, y: 140, width: 9, height: 9)); b.bg.fill(b.fg.cg(), CGRect(x: 135, y: 176, width: 9, height: 9))
        let big = b.segmentDigits(b.fg, 54, 100)
        b.clock(big, big, [(18, 112), (76, 112), (150, 112), (208, 112)])
        b.seconds(b.segmentDigits(b.fg, 28, 48), (194, 230), (226, 230))
        b.dateRow(x: 24, y: 70, font: "mono", weekColor: b.fg)
        // Battery level as an 11-step segmented bar.
        let levels = (0 ... 10).map { lvl -> String in
            let c = b.cv(124, 22)
            c.ctx.setStrokeColor(b.fg.cg()); c.ctx.setLineWidth(2); c.ctx.stroke(CGRect(x: 1, y: 3, width: 114, height: 16))
            c.fill(b.fg.cg(), CGRect(x: 116, y: 8, width: 6, height: 6))
            for i in 0 ..< 10 { c.fill(b.fg.cg(i < lvl ? 1 : 0.08), CGRect(x: 4 + i * 11, y: 6, width: 9, height: 10)) }
            return b.face.add(b.uid("lvl"), c)
        }
        b.bg.text("BATT", font: "mono", size: 11, color: b.fg.cg(0.7), in: CGRect(x: 24, y: 268, width: 40, height: 16), align: 0)
        b.container([20, 238, 132, 48], DT.battery, [b.sel(levels, 24, 244, VT.batteryLevel, label: 3, show: 9)])
        b.strip(y: 372, [.heart, .steps, .calories])
    case .digital:
        var box = (w: 100, h: 132)
        var pos: [(Int, Int)] = []
        var datePos = (x: 66, y: 34)
        var colonRect: CGRect?
        switch d.layout {
        case .stack: pos = [(40, 78), (140, 78), (40, 222), (140, 222)]; datePos = (66, 34)
        case .inline: box = (58, 104); pos = [(10, 176), (68, 176), (154, 176), (212, 176)]; datePos = (66, 300); colonRect = CGRect(x: 126, y: 176, width: 28, height: 104)
        case .left: box = (76, 110); pos = [(12, 64), (88, 64), (12, 184), (88, 184)]; datePos = (12, 316)
        case .bottom: box = (58, 104); pos = [(10, 262), (68, 262), (154, 262), (212, 262)]; datePos = (66, 226); colonRect = CGRect(x: 126, y: 262, width: 28, height: 104)
        case .split: box = (92, 124); pos = [(12, 48), (104, 48), (84, 236), (176, 236)]; datePos = (120, 186)
        }
        if let r = colonRect { b.colon(r.insetBy(dx: 2, dy: 14), b.fg, size: CGFloat(box.h)) }
        b.clock(b.fontDigits(b.acc, box.w, box.h), b.fontDigits(b.fg, box.w, box.h), pos)
        b.dateRow(x: datePos.x, y: datePos.y)
        if d.layout == .left {
            b.panel(CGRect(x: 172, y: 104, width: 102, height: 226))
            for (i, stat) in ([.heart, .steps, .battery] as [Builder.Stat]).enumerated() {
                let y = 108 + i * 74
                let (dt, layers) = b.statLayers(stat, col: 174, width: 98, y: y)
                b.container([174, y, 98, 70], dt, layers)
            }
        } else {
            b.strip(y: 380, [.heart, .steps, .battery])
        }
    case .minimal:
        b.face.order = [0, 2, 3, 1]
        let cx = 140, cy = 210, R: CGFloat = 122
        b.dial(cx: CGFloat(cx), cy: CGFloat(cy), R: R, markers: v % 2 == 0 ? 1 : 0, disc: nil, ink: b.acc)
        let wkDay = Builder.dateWidth(month: false)
        b.dateRow(x: (W - wkDay) / 2, y: 370, month: false, weekColor: b.fg, outline: false)
        b.container([100, 10, 80, 44], DT.battery, [b.icon("bolt", [108, 22, 16, 18]), b.text([126, 18, 50, 28], VT.battery, "88")])
        b.container([100, 404, 80, 44], DT.heart, [b.icon("heart", [108, 416, 16, 16]), b.text([126, 410, 50, 28], VT.heart, "72")])
        b.hands(cx: cx, cy: cy, R: R, style: v % 2 == 0 ? 0 : 2, secondStyle: 1)
    case .orbit:
        b.face.order = [0, 2, 3, 1]
        let cx = 140, cy = 214
        for i in 0 ..< 60 {
            let a = CGFloat(i) * 6 * .pi / 180, long = i % 5 == 0
            let r0: CGFloat = long ? 112 : 118, r1: CGFloat = 128
            b.bg.ctx.setStrokeColor((i == 0 ? b.acc : b.fg).cg(long ? 1 : 0.5)); b.bg.ctx.setLineWidth(long ? 3 : 1.5)
            b.bg.ctx.beginPath()
            b.bg.ctx.move(to: CGPoint(x: CGFloat(cx) + sin(a) * r0, y: CGFloat(cy) - cos(a) * r0))
            b.bg.ctx.addLine(to: CGPoint(x: CGFloat(cx) + sin(a) * r1, y: CGFloat(cy) - cos(a) * r1)); b.bg.ctx.strokePath()
        }
        let hh = b.fontDigits(b.acc, 44, 78), mm = b.fontDigits(b.fg, 44, 78)
        b.colon(CGRect(x: 132, y: 180, width: 16, height: 68), b.fg, size: 60)
        b.clock(hh, mm, [(44, 176), (88, 176), (152, 176), (196, 176)])
        b.centeredDate(y: 268)
        let hdx = b.inset([10, 10, 100, 48]), bdx = b.inset([170, 10, 100, 48])
        b.container([10 + hdx, 10, 100, 48], DT.heart, [b.icon("heart", [18 + hdx, 24, 20, 20]), b.text([42 + hdx, 20, 64, 28], VT.heart, "72")])
        b.container([170 + bdx, 10, 100, 48], DT.battery, [b.icon("bolt", [178 + bdx, 24, 20, 20]), b.text([202 + bdx, 20, 64, 28], VT.battery, "88")])
        b.strip(y: 372, [.steps, .calories, .weather])
        let dot = b.secondHandImage(len: 106, tail: 0, color: b.sec, dotOnly: true)
        b.addHand(dot, cx: cx, cy: cy, value: VT.secondHand, angle: previewSecond * 6)
    }
    b.finishBackground()
    return (b.face, b.render())
}

// MARK: - The 100 designs

func E(_ t: String, _ k: Kind2, _ bg: Int, _ colors: [Int], _ dial: Int?, _ fg: Int, _ accent: Int, _ second: Int, _ font: String, _ v: Int) -> Design2 {
    Design2(title: t, kind: k, bg: bg, colors: colors, dial: dial, fg: fg, accent: accent, second: second, font: font, variant: v)
}

let designs2: [Design2] = [
    // Analog: dial with date window, weekday, month, three hands, stats strip.
    E("Heritage", .classic, 11, [0x1B2A41, 0x0F1A2B, 0x2E4A6B, 0x3D5A80], 0xF3EBDD, 0x1B1B1B, 0x8C1C13, 0xC0392B, "Didot-Bold", 3),
    E("Navy Officer", .classic, 0, [0x0B1D3A, 0x06101F], 0x14305C, 0xF5F5F5, 0xD4AF37, 0xFF6B35, "Futura-Bold", 0),
    E("Ivory Roman", .classic, 14, [0x2B2B2B, 0x1E1E1E, 0xC9A227, 0xC9A227], 0xFFFFF0, 0x222222, 0x6B4E16, 0x1D4E89, "Baskerville-Bold", 3),
    E("Emerald Club", .classic, 16, [0x0B3D2E, 0x062419, 0x1E6F50, 0x2E8B57], 0x0F5132, 0xF4F1DE, 0xE9C46A, 0xE76F51, "Optima-ExtraBlack", 2),
    E("Graphite", .classic, 12, [0x1C1C1E, 0x2C2C2E, 0x3A3A3C, 0x48484A], 0x2C2C2E, 0xEDEDED, 0xFF9F0A, 0xFF9F0A, "AvenirNext-Heavy", 1),
    E("Salmon Dial", .classic, 9, [0x3B2F2F, 0x2A2020, 0x6D4C41, 0x8D6E63], 0xF4B5A0, 0x2B1A14, 0x5D2E1F, 0x1D3557, "Georgia-Bold", 2),
    E("Pilot", .classic, 0, [0x111111, 0x0A0A0A], 0x111111, 0xFFFFFF, 0xFFFFFF, 0xFFCC00, "DINCondensed-Bold", 4),
    E("Opaline", .classic, 7, [0xDDE6ED, 0xC5D1DB, 0x9DB2BF, 0x526D82], 0xF8F9FA, 0x27374D, 0x526D82, 0xD62828, "thin", 0),
    E("Midnight Dial", .classic, 4, [0x050A1F, 0x0B1033, 0xFFE9A8], 0x0E1A40, 0xE8EEF7, 0xFFD86B, 0xFFD86B, "serif", 2),
    E("Copper", .classic, 17, [0x3E2723, 0x4E342E, 0x6D4C41, 0x8D6E63], 0xB87333, 0x1E120C, 0xFFF3E0, 0x1E120C, "Copperplate-Bold", 4),
    // Analog Sport: dial with a steps progress ring, steps count, heart rate, calories, battery.
    E("Tachy", .sport, 0, [0x0D0D0D, 0x1A1A1A], 0x111111, 0xFFFFFF, 0xFF3B30, 0xFF3B30, "DINAlternate-Bold", 0),
    E("Diver Blue", .sport, 3, [0x02111B, 0x03203A, 0x0A4D68, 0x088395], 0x0A2647, 0xFFFFFF, 0x00B4D8, 0xFFB703, "Futura-CondensedExtraBold", 4),
    E("Trail Runner", .sport, 2, [0xF1FAEE, 0xA8DADC, 0x457B9D, 0x1D3557], 0x1D3557, 0xF1FAEE, 0xA8DADC, 0xE63946, "AvenirNextCondensed-Heavy", 1),
    E("Volt", .sport, 5, [0x0A0A0A, 0x111111, 0xD4FF00], 0x0A0A0A, 0xFFFFFF, 0xD4FF00, 0xD4FF00, "HelveticaNeue-CondensedBlack", 0),
    E("Coral Reef", .sport, 9, [0x003049, 0x002233, 0xF77F00, 0xFCBF49], 0x003049, 0xFFFFFF, 0xFF7F51, 0xFCBF49, "rounded", 2),
    E("Track Day", .sport, 19, [0x1A1A1A, 0x101010, 0xE10600], 0x1A1A1A, 0xFFFFFF, 0xE10600, 0xFFFFFF, "Impact", 4),
    E("Arctic Sport", .sport, 0, [0xE0FBFC, 0xC2DFE3], 0xFFFFFF, 0x1B263B, 0x00A6FB, 0xFF006E, "DINAlternate-Bold", 1),
    E("Lava Run", .sport, 2, [0x370617, 0x6A040F, 0x9D0208, 0x03071E], 0x1A0505, 0xFFE8D6, 0xFF5400, 0xFFBD00, "Futura-Bold", 0),
    E("Jungle Sport", .sport, 16, [0x081C15, 0x1B4332, 0x2D6A4F, 0x52B788], 0x081C15, 0xD8F3DC, 0x95D5B2, 0xFFD60A, "AvenirNext-Heavy", 2),
    E("Pro Black", .sport, 13, [0x000000, 0x050505, 0x1C1C1C, 0x2A2A2A], 0x000000, 0xFFFFFF, 0x34C759, 0x34C759, "mono", 3),
    // Hybrid: analog dial on top, digital time and date below.
    E("Dual Time", .hybrid, 0, [0x16213E, 0x0F3460], 0x1A1A2E, 0xFFFFFF, 0xE94560, 0xE94560, "Futura-Bold", 0),
    E("Bridge", .hybrid, 10, [0x1F2041, 0x4B3F72, 0xFFC857, 0x119DA4], 0x1F2041, 0xFFFFFF, 0xFFC857, 0x19647E, "DINCondensed-Bold", 1),
    E("Twin Cream", .hybrid, 0, [0xF5EBE0, 0xE3D5CA], 0xFFFBF5, 0x3D3029, 0xB08968, 0x9B2226, "Georgia-Bold", 3),
    E("Ocean Hybrid", .hybrid, 3, [0x012A4A, 0x013A63, 0x01497C, 0x2A6F97], 0x012A4A, 0xE0F2FF, 0x89C2D9, 0xFF8500, "rounded", 2),
    E("Studio", .hybrid, 8, [0xFAF3E0, 0xFAF3E0, 0xE76F51, 0x264653], 0xFFFFFF, 0x111111, 0xE76F51, 0x264653, "HelveticaNeue-CondensedBlack", 4),
    E("Sandstone", .hybrid, 11, [0xE9C46A, 0xD4A373, 0xBC6C25, 0xFEFAE0], 0xFEFAE0, 0x4A2C14, 0xBC6C25, 0x283618, "Optima-ExtraBlack", 3),
    E("Nightfall", .hybrid, 4, [0x10002B, 0x240046, 0xE0AAFF], 0x240046, 0xF3E8FF, 0xC77DFF, 0xFFD60A, "thin", 1),
    E("Teal Duo", .hybrid, 7, [0x004E64, 0x00303D, 0x25A18E, 0x7AE582], 0x00303D, 0xFFFFFF, 0x7AE582, 0xFFFFFF, "AvenirNextCondensed-Heavy", 0),
    E("Brick", .hybrid, 17, [0x6A040F, 0x9D0208, 0xD00000, 0x370617], 0xFFF3E6, 0x370617, 0xD00000, 0x370617, "Impact", 4),
    E("Lilac", .hybrid, 9, [0xE7C6FF, 0xC8B6FF, 0xB8C0FF, 0xBBD0FF], 0xFFFFFF, 0x3C096C, 0x7B2CBF, 0xFF006E, "ArialRoundedMTBold", 2),
    // Digital Seconds: large time with running seconds, battery, heart rate, steps, calories.
    E("Stopwatch", .seconds, 0, [0x000000, 0x0A0A0A], nil, 0xFFFFFF, 0xFF9F0A, 0xFF9F0A, "DINAlternate-Bold", 0),
    E("Pulse Red", .seconds, 6, [0x1A0000, 0x330000, 0xFF2E2E, 0xFF8A8A], nil, 0xFFFFFF, 0xFF2E2E, 0xFF2E2E, "Futura-CondensedExtraBold", 0),
    E("Ticker", .seconds, 17, [0x0B132B, 0x1C2541, 0x3A506B, 0x5BC0BE], nil, 0xFFFFFF, 0x6FFFE9, 0x6FFFE9, "mono", 0),
    E("Mono Sec", .seconds, 0, [0xFFFFFF, 0xF0F0F0], nil, 0x111111, 0x111111, 0x111111, "thin", 0),
    E("Lime Sec", .seconds, 5, [0x111111, 0x151515, 0x2B2B2B], nil, 0xFFFFFF, 0xC6FF00, 0xC6FF00, "HelveticaNeue-CondensedBlack", 0),
    E("Blueprint", .seconds, 6, [0x0A2463, 0x0A2463, 0x3E92CC, 0x3E92CC], nil, 0xFFFFFF, 0xD8E1E9, 0xD8E1E9, "Menlo-Bold", 0),
    E("Rose Sec", .seconds, 16, [0xFFE5EC, 0xFFC2D1, 0xFB6F92, 0xFF8FAB], nil, 0x590D22, 0xFB6F92, 0xFB6F92, "Didot-Bold", 0),
    E("Signal", .seconds, 19, [0xFFBE0B, 0xFB5607, 0x3A86FF], nil, 0xFFFFFF, 0x1D1D1D, 0x1D1D1D, "Impact", 0),
    E("Dusk Sec", .seconds, 1, [0x2D00F7, 0xF20089, 0xFFB600], nil, 0xFFFFFF, 0xFFE066, 0xFFE066, "AvenirNext-Heavy", 0),
    E("Paper", .seconds, 0, [0xF2E8CF, 0xEDE0C8], nil, 0x2B2118, 0xBC4749, 0xBC4749, "AmericanTypewriter-Bold", 0),
    // Dashboard: compact time plus heart rate, steps, calories, battery and weather tiles.
    E("Cockpit", .dashboard, 0, [0x0B0F14, 0x111821], nil, 0xFFFFFF, 0x00E5FF, 0x00E5FF, "DINAlternate-Bold", 0),
    E("Control Room", .dashboard, 18, [0x03071E, 0x0B132B, 0x1C7C54, 0x73E2A7], nil, 0xE8FFF4, 0x73E2A7, 0x73E2A7, "mono", 0),
    E("Stats Light", .dashboard, 0, [0xF8F9FA, 0xE9ECEF], nil, 0x212529, 0x0D6EFD, 0x0D6EFD, "AvenirNext-Heavy", 0),
    E("Carbon", .dashboard, 12, [0x121212, 0x1E1E1E, 0x2A2A2A, 0x383838], nil, 0xFFFFFF, 0xFF4D00, 0xFF4D00, "HelveticaNeue-CondensedBlack", 0),
    E("Ocean Panel", .dashboard, 3, [0x03045E, 0x023E8A, 0x0077B6, 0x00B4D8], nil, 0xFFFFFF, 0x90E0EF, 0x90E0EF, "rounded", 0),
    E("Grape", .dashboard, 7, [0x2D1B4E, 0x3C1F66, 0x7B2CBF, 0xC77DFF], nil, 0xFFFFFF, 0xE0AAFF, 0xE0AAFF, "Futura-Bold", 0),
    E("Dash Sand", .dashboard, 11, [0xEDE0D4, 0xE6CCB2, 0xDDB892, 0xB08968], nil, 0x3E2723, 0x9C6644, 0x9C6644, "Optima-ExtraBlack", 0),
    E("Mission", .dashboard, 4, [0x000814, 0x001D3D, 0xFFC300], nil, 0xFFFFFF, 0xFFC300, 0xFFC300, "DINCondensed-Bold", 0),
    E("Forest Panel", .dashboard, 2, [0x2F3E46, 0x354F52, 0x52796F, 0x84A98C], nil, 0xFFFFFF, 0xCAD2C5, 0xCAD2C5, "AvenirNextCondensed-Heavy", 0),
    E("Sunrise Panel", .dashboard, 1, [0xFF9E00, 0xFF6D00, 0xFFE066], nil, 0xFFFFFF, 0xFFE066, 0xFFE066, "Futura-CondensedExtraBold", 0),
    // Weather: big live weather icon and temperature, time, date, stats.
    E("Forecast", .weather, 0, [0x1E3C72, 0x2A5298], nil, 0xFFFFFF, 0xFFD166, 0xFFD166, "AvenirNext-Heavy", 0),
    E("Sky Blue", .weather, 0, [0x89CFF0, 0x4FA3D1], nil, 0xFFFFFF, 0xFFE14D, 0xFFE14D, "rounded", 0),
    E("Storm", .weather, 3, [0x232526, 0x414345, 0x5C6B73, 0x9DB4C0], nil, 0xFFFFFF, 0x9DB4C0, 0x9DB4C0, "Impact", 0),
    E("Meadow", .weather, 2, [0xD8F3DC, 0xB7E4C7, 0x74C69D, 0x2D6A4F], nil, 0x1B4332, 0xF4A261, 0xF4A261, "Georgia-Bold", 0),
    E("Polar", .weather, 0, [0xE0FBFC, 0xBEE9E8], nil, 0x1B263B, 0x62B6CB, 0x62B6CB, "thin", 0),
    E("Monsoon", .weather, 11, [0x0D1B2A, 0x1B263B, 0x415A77, 0x778DA9], nil, 0xE0E1DD, 0x8ECAE6, 0x8ECAE6, "AvenirNextCondensed-Heavy", 0),
    E("Desert Sun", .weather, 0, [0x780116, 0xC32F27], nil, 0xFFFFFF, 0xF7B538, 0xF7B538, "Futura-Bold", 0),
    E("Nimbus", .weather, 16, [0xEDF2F4, 0xD9E2EA, 0x8D99AE, 0xADB5BD], nil, 0x2B2D42, 0xEF233C, 0xEF233C, "DINAlternate-Bold", 0),
    E("Twilight Sky", .weather, 4, [0x0F0C29, 0x302B63, 0xE0C3FC], nil, 0xFFFFFF, 0xE0C3FC, 0xE0C3FC, "serif", 0),
    E("Breeze", .weather, 3, [0xE0F7FA, 0xB2EBF2, 0x4DD0E1, 0x0097A7], nil, 0x004D61, 0xFF8A65, 0xFF8A65, "ArialRoundedMTBold", 0),
    // Activity Rings: steps, heart-rate and battery progress rings, weather.
    E("Triple Ring", .rings, 0, [0x000000, 0x0A0A0A], nil, 0xFFFFFF, 0xA6FF00, 0xFF2D55, "AvenirNext-Heavy", 0),
    E("Move", .rings, 0, [0x111111, 0x1C1C1C], nil, 0xFFFFFF, 0xFF375F, 0x30D158, "Futura-Bold", 0),
    E("Neon Rings", .rings, 0, [0x12002B, 0x2A0A4A, 0xFF2BD6, 0x00F0FF], nil, 0xFFFFFF, 0x00F0FF, 0xFF2BD6, "Futura-CondensedExtraBold", 0),
    E("Gauge Light", .rings, 0, [0xFFFFFF, 0xF1F3F5], nil, 0x212529, 0x2F9E44, 0xE8590C, "DINAlternate-Bold", 0),
    E("Ember Rings", .rings, 0, [0x1A0B00, 0x2B1100], nil, 0xFFE8D6, 0xFF7B00, 0xFFD000, "Impact", 0),
    E("Mint Rings", .rings, 9, [0x0B3D3A, 0x0B2E2B, 0x1F7A70, 0x57CC99], nil, 0xFFFFFF, 0x80ED99, 0xFFE66D, "rounded", 0),
    E("Steel Rings", .rings, 12, [0x22313F, 0x1B262F, 0x34495E, 0x5D6D7E], nil, 0xECF0F1, 0x5DADE2, 0xF5B041, "HelveticaNeue-CondensedBlack", 0),
    E("Berry Rings", .rings, 16, [0x3C0919, 0x2A0612, 0x9D174D, 0xDB2777], nil, 0xFFF0F6, 0xF472B6, 0xA78BFA, "Georgia-Bold", 0),
    E("Ocean Rings", .rings, 3, [0x001219, 0x002233, 0x005F73, 0x0A9396], nil, 0xE9D8A6, 0x94D2BD, 0xEE9B00, "AvenirNextCondensed-Heavy", 0),
    E("Gold Rings", .rings, 14, [0x0B0B0B, 0x0B0B0B, 0xD4AF37, 0xB8860B], nil, 0xF5E6B3, 0xD4AF37, 0xFFFFFF, "Didot-Bold", 0),
    // Retro LCD: seven-segment time with seconds, battery bar, stats.
    E("Classic LCD", .lcd, 0, [0x2B2B2B, 0x1A1A1A], 0x9EAD86, 0x1C2414, 0x1C2414, 0x1C2414, "mono", 0),
    E("Amber LCD", .lcd, 0, [0x111111, 0x0A0A0A], 0x1A0F00, 0xFFB000, 0xFFB000, 0xFFB000, "mono", 0),
    E("Blue Glow", .lcd, 0, [0x0A1128, 0x001F54], 0x7FB7E8, 0x0A1128, 0x0A1128, 0x0A1128, "mono", 0),
    E("Pocket Green", .lcd, 0, [0x8B8B83, 0x6E6E66], 0x9BBC0F, 0x0F380F, 0x306230, 0x0F380F, "mono", 0),
    E("Red LED", .lcd, 0, [0x0D0D0D, 0x050505], 0x140000, 0xFF2A2A, 0xFF2A2A, 0xFF2A2A, "mono", 0),
    E("Inverted LCD", .lcd, 0, [0x3A3A3A, 0x222222], 0x111111, 0xC8D6B9, 0xC8D6B9, 0xC8D6B9, "mono", 0),
    E("Ice LCD", .lcd, 0, [0x1B263B, 0x0D1B2A], 0xCDE7F0, 0x0B3954, 0x087E8B, 0x0B3954, "mono", 0),
    E("Pink LCD", .lcd, 0, [0x3D0C2C, 0x2A0820], 0xFFC8DD, 0x590D22, 0x590D22, 0x590D22, "mono", 0),
    E("Matrix LCD", .lcd, 13, [0x000000, 0x020A02, 0x003B00, 0x008F11], 0x000A00, 0x00FF41, 0x00FF41, 0x00FF41, "mono", 0),
    E("Sunlight LCD", .lcd, 17, [0xF4D35E, 0xEE964B, 0xF95738, 0x0D3B66], 0xE8E4C9, 0x2E2A1F, 0x2E2A1F, 0x2E2A1F, "mono", 0),
    // Minimal Analog: hour markers only, two hands and an orbiting seconds dot.
    E("Bare", .minimal, 0, [0xFFFFFF, 0xF5F5F5], nil, 0x111111, 0x111111, 0xFF3B30, "thin", 0),
    E("Dots", .minimal, 0, [0x000000, 0x000000], nil, 0xFFFFFF, 0x8E8E93, 0xFF9F0A, "thin", 1),
    E("Linen", .minimal, 0, [0xF0EAD6, 0xE8DFCA], nil, 0x3D3B30, 0x8A817C, 0xBC4749, "serif", 2),
    E("Charcoal", .minimal, 0, [0x2F3437, 0x1F2326], nil, 0xF0F0F0, 0x6C757D, 0x4CC9F0, "thin", 3),
    E("Sage", .minimal, 0, [0xB5C99A, 0x97A97C], nil, 0x2F3E1F, 0x4F6D3A, 0xFFFFFF, "serif", 4),
    E("Blush", .minimal, 0, [0xFADADD, 0xF5C6CB], nil, 0x6D2E46, 0xA26769, 0x6D2E46, "thin", 5),
    E("Indigo", .minimal, 7, [0x1A1B4B, 0x10113A, 0x2E2F7A, 0x3C3DA8], nil, 0xFFFFFF, 0x9FA0FF, 0xFFD166, "thin", 6),
    E("Sand", .minimal, 11, [0xE6CCB2, 0xDDB892, 0xB08968, 0x7F5539], nil, 0x3E2A1E, 0x7F5539, 0xFFFFFF, "serif", 7),
    E("Snow", .minimal, 0, [0xF8F9FA, 0xDEE2E6], nil, 0x343A40, 0xADB5BD, 0x1C7ED6, "thin", 8),
    E("Ink", .minimal, 0, [0x0B0B0F, 0x15151E], nil, 0xE5E5E5, 0x5A5A6E, 0xE5383B, "serif", 9),
    // Orbit: digital time inside a 60-tick ring with an orbiting seconds dot, plus weather.
    E("Satellite", .orbit, 0, [0x000000, 0x0B0B1A], nil, 0xFFFFFF, 0x64B5F6, 0x64B5F6, "AvenirNext-Heavy", 0),
    E("Comet", .orbit, 0, [0x0D1321, 0x1D2D44], nil, 0xF0EBD8, 0x748CAB, 0xFFB703, "Futura-Bold", 0),
    E("Gravity", .orbit, 7, [0x000000, 0x0A0A0A, 0x1F1F1F, 0x2E2E2E], nil, 0xFFFFFF, 0xFF006E, 0xFF006E, "HelveticaNeue-CondensedBlack", 0),
    E("Eclipse", .orbit, 0, [0x000000, 0x1A0A00], nil, 0xFFFFFF, 0xFF7B00, 0xFFFFFF, "DINCondensed-Bold", 0),
    E("Nebula", .orbit, 12, [0x10002B, 0x240046, 0x7B2CBF, 0xE0AAFF], nil, 0xFFFFFF, 0xE0AAFF, 0x72EFDD, "Futura-CondensedExtraBold", 0),
    E("Lunar", .orbit, 11, [0x1D2D44, 0x0D1321, 0x3E5C76, 0x748CAB], nil, 0xF0EBD8, 0xA9B4C2, 0xF0EBD8, "serif", 0),
    E("Solar", .orbit, 0, [0x03071E, 0x370617], nil, 0xFFFFFF, 0xFFBA08, 0xFFBA08, "Impact", 0),
    E("Pulsar", .orbit, 0, [0x03001C, 0x301E67], nil, 0xFFFFFF, 0xB6EADA, 0xB6EADA, "mono", 0),
    E("Quasar", .orbit, 9, [0x1B1A17, 0x242320, 0xF0A500, 0xE45826], nil, 0xF0E3CA, 0xF0A500, 0xE45826, "rounded", 0),
    E("Zenith", .orbit, 0, [0xFFFFFF, 0xEDEDED], nil, 0x111111, 0xC1121F, 0xC1121F, "AvenirNext-Heavy", 0),
]
