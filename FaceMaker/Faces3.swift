// Faces 151-450: thirty styles drawn from the whole history of watch faces (tool watches, complications,
// dress dials, novelty dials, retro tech displays and graphic art), ten designs each.
import AppKit

func I(_ v: CGFloat) -> Int { Int(v.rounded()) }

/// Where an analog dial sits. Round screens get a full-screen dial; tall screens a dial with room above and below.
struct AL {
    let cx: CGFloat, cy: CGFloat, R: CGFloat, round: Bool
    var k: CGFloat { R / 130 }
    var c: CGPoint { CGPoint(x: cx, y: cy) }
}

enum HK { case baton, lumeBaton, sword, tapered, dauphine, leaf, breguet, arrow, needle, skeleton, planet, ringPlanet, pencil, line }
enum SK { case stick, lollipop, railway, arrow, dot }

/// One colour scheme: background colours, dial / card colour, ink, accent and seconds colour.
struct Look {
    let name: String; let bg: [Int]; let dial: Int; let fg: Int; let acc: Int; let sec: Int; let font: String?
}
func L(_ n: String, _ bg: [Int], _ dial: Int, _ fg: Int, _ acc: Int, _ sec: Int, _ font: String? = nil) -> Look {
    Look(name: n, bg: bg, dial: dial, fg: fg, acc: acc, sec: sec, font: font)
}

struct Style3 {
    let name: String
    let category: String
    let fonts: [String]
    let looks: [Look]
    let build: (Builder, Int) -> Void
}

extension Builder {
    var dialRGB: RGB { RGB(d.dial ?? d.colors[0]) }
    func col(_ i: Int) -> RGB { RGB(d.colors[min(i, d.colors.count - 1)]) }

    func analogLayout() -> AL {
        if f.round { return AL(cx: 140, cy: 228, R: CGFloat(f.pw) / 2 / f.s - 2, round: true) }
        return AL(cx: 140, cy: 196, R: 130, round: false)
    }

    // MARK: Drawing primitives (background canvas, block coordinates)

    func P(_ a: AL, _ deg: CGFloat, _ r: CGFloat) -> CGPoint {
        CGPoint(x: a.cx + sin(deg * .pi / 180) * r, y: a.cy - cos(deg * .pi / 180) * r)
    }
    func seg(_ p0: CGPoint, _ p1: CGPoint, _ w: CGFloat, _ c: CGColor, cap: CGLineCap = .butt, on cvs: Canvas? = nil) {
        let ctx = (cvs ?? bg).ctx
        ctx.setStrokeColor(c); ctx.setLineWidth(w); ctx.setLineCap(cap)
        ctx.beginPath(); ctx.move(to: p0); ctx.addLine(to: p1); ctx.strokePath()
    }
    func radial(_ a: AL, _ deg: CGFloat, _ r0: CGFloat, _ r1: CGFloat, _ w: CGFloat, _ c: CGColor, cap: CGLineCap = .butt) {
        seg(P(a, deg, r0), P(a, deg, r1), w, c, cap: cap)
    }
    func dot(_ p: CGPoint, _ r: CGFloat, _ c: CGColor, on cvs: Canvas? = nil) {
        let ctx = (cvs ?? bg).ctx
        ctx.setFillColor(c); ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }
    func ring(_ p: CGPoint, _ r: CGFloat, _ w: CGFloat, _ c: CGColor, on cvs: Canvas? = nil) {
        let ctx = (cvs ?? bg).ctx
        ctx.setStrokeColor(c); ctx.setLineWidth(w); ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }
    func poly(_ pts: [CGPoint], _ c: CGColor, on cvs: Canvas? = nil) {
        let ctx = (cvs ?? bg).ctx
        ctx.setFillColor(c); ctx.beginPath(); ctx.addLines(between: pts); ctx.closePath(); ctx.fillPath()
    }
    func rrect(_ r: CGRect, _ radius: CGFloat, fill: CGColor? = nil, stroke: CGColor? = nil, lw: CGFloat = 1.5, on cvs: Canvas? = nil) {
        let ctx = (cvs ?? bg).ctx
        let path = CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
        if let fill { ctx.setFillColor(fill); ctx.addPath(path); ctx.fillPath() }
        if let stroke { ctx.setStrokeColor(stroke); ctx.setLineWidth(lw); ctx.addPath(path); ctx.strokePath() }
    }
    /// Text centred on a point.
    func word(_ s: String, _ p: CGPoint, _ size: CGFloat, _ c: CGColor, font: String? = nil, w: CGFloat? = nil, on cvs: Canvas? = nil) {
        let bw = w ?? size * CGFloat(max(2, s.count)) * 0.85
        (cvs ?? bg).text(s, font: font ?? d.font, size: size, color: c, in: CGRect(x: p.x - bw / 2, y: p.y - size * 0.62, width: bw, height: size * 1.24))
    }
    /// A ring segment with square ends (compass degrees, clockwise from 12).
    func band(_ a: AL, _ r0: CGFloat, _ r1: CGFloat, _ d0: CGFloat, _ d1: CGFloat, _ c: CGColor) {
        let ctx = bg.ctx
        ctx.setFillColor(c)
        ctx.beginPath()
        let n = max(4, Int(abs(d1 - d0) / 2))
        for i in 0 ... n { let p = P(a, d0 + (d1 - d0) * CGFloat(i) / CGFloat(n), r1); i == 0 ? ctx.move(to: p) : ctx.addLine(to: p) }
        for i in stride(from: n, through: 0, by: -1) { ctx.addLine(to: P(a, d0 + (d1 - d0) * CGFloat(i) / CGFloat(n), r0)) }
        ctx.closePath(); ctx.fillPath()
    }
    func disc(_ a: AL, _ r: CGFloat, _ c: CGColor) { dot(a.c, r, c) }
    /// Clipped vertical gradient inside a path.
    func gradientIn(_ path: CGPath, _ colors: [RGB], _ rect: CGRect, on cvs: Canvas? = nil) {
        let c = cvs ?? bg
        c.ctx.saveGState(); c.ctx.addPath(path); c.ctx.clip(); c.gradient(colors, in: rect); c.ctx.restoreGState()
    }
    func minuteTrack(_ a: AL, r: CGFloat, len: CGFloat, w: CGFloat, _ c: CGColor, skipFive: Bool = true) {
        for i in 0 ..< 60 where !(skipFive && i % 5 == 0) { radial(a, CGFloat(i) * 6, r - len, r, w, c) }
    }

    // MARK: Hands

    func hand3(_ k: HK, len: CGFloat, tail: CGFloat, width wd: CGFloat, color: RGB, alt: RGB) -> (Canvas, Int, Int) {
        let big = k == .ringPlanet ? 2.0 : 1.7
        let w = CGFloat(Int(wd * big) / 2 * 2 + 8), h = len + tail + 8 + (k == .planet || k == .ringPlanet ? wd / 2 : 0)
        let c = cv(w, h)
        let ctx = c.ctx
        let cx = w / 2, top: CGFloat = 4, py = top + len, bottom = py + tail
        let cc = color.cg()
        func Q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x, y: y) }
        switch k {
        case .baton:
            rrect(CGRect(x: cx - wd / 2, y: top, width: wd, height: bottom - top), wd / 2, fill: cc, on: c)
        case .lumeBaton:
            rrect(CGRect(x: cx - wd / 2, y: top, width: wd, height: bottom - top), wd / 2, fill: cc, on: c)
            rrect(CGRect(x: cx - wd / 2 + max(2, wd * 0.2), y: top + 3, width: wd - 2 * max(2, wd * 0.2), height: len * 0.62), wd / 3, fill: alt.cg(), on: c)
        case .sword:
            poly([Q(0, top), Q(wd / 2, top + wd * 1.6), Q(wd * 0.3, bottom), Q(-wd * 0.3, bottom), Q(-wd / 2, top + wd * 1.6)], cc, on: c)
        case .tapered:
            poly([Q(-wd * 0.22, top), Q(wd * 0.22, top), Q(wd / 2, bottom), Q(-wd / 2, bottom)], cc, on: c)
        case .dauphine:
            let m = py - len * 0.06
            poly([Q(0, top), Q(-wd / 2, m), Q(0, bottom)], cc, on: c)
            poly([Q(0, top), Q(wd / 2, m), Q(0, bottom)], color.mix(RGB(0), 0.3).cg(), on: c)
        case .leaf:
            ctx.setFillColor(cc); ctx.beginPath(); ctx.move(to: Q(0, top))
            ctx.addQuadCurve(to: Q(0, bottom), control: Q(wd * 1.0, top + len * 0.62))
            ctx.addQuadCurve(to: Q(0, top), control: Q(-wd * 1.0, top + len * 0.62)); ctx.fillPath()
        case .breguet:
            let rc = top + len * 0.24, rr = wd * 0.55
            ctx.setFillColor(cc); ctx.fill(CGRect(x: cx - wd * 0.15, y: rc + rr, width: wd * 0.3, height: bottom - rc - rr))
            ring(Q(0, rc), rr, max(1.4, wd * 0.2), cc, on: c)
            poly([Q(0, top), Q(wd * 0.16, rc - rr + 1), Q(-wd * 0.16, rc - rr + 1)], cc, on: c)
            dot(Q(0, py), wd * 0.45, cc, on: c)
        case .arrow:
            rrect(CGRect(x: cx - wd * 0.2, y: top + wd, width: wd * 0.4, height: bottom - top - wd), wd * 0.2, fill: cc, on: c)
            poly([Q(0, top), Q(wd * 0.8, top + wd * 1.5), Q(-wd * 0.8, top + wd * 1.5)], cc, on: c)
            poly([Q(0, top + wd * 0.4), Q(wd * 0.4, top + wd * 1.2), Q(-wd * 0.4, top + wd * 1.2)], alt.cg(), on: c)
        case .needle:
            poly([Q(0, top), Q(wd / 2, py), Q(-wd / 2, py)], alt.cg(), on: c)
            poly([Q(-wd / 2, py), Q(wd / 2, py), Q(0, bottom)], cc, on: c)
        case .skeleton:
            let pts = [Q(0, top + 1), Q(wd / 2 - 1, top + wd * 1.6), Q(wd * 0.3, bottom - 1), Q(-wd * 0.3, bottom - 1), Q(-wd / 2 + 1, top + wd * 1.6)]
            ctx.setStrokeColor(cc); ctx.setLineWidth(max(1.6, wd * 0.18)); ctx.setLineJoin(.round)
            ctx.beginPath(); ctx.addLines(between: pts); ctx.closePath(); ctx.strokePath()
            poly([Q(0, top + wd * 0.5), Q(wd * 0.28, top + wd * 1.6), Q(wd * 0.2, top + len * 0.55), Q(-wd * 0.2, top + len * 0.55), Q(-wd * 0.28, top + wd * 1.6)], alt.cg(), on: c)
        case .planet, .ringPlanet:
            seg(Q(0, py), Q(0, top + wd), 1.2, color.cg(0.35), on: c)
            dot(Q(0, top + wd / 2), wd / 2, cc, on: c)
            dot(Q(-wd * 0.16, top + wd * 0.36), wd * 0.2, alt.cg(0.75), on: c)
            if k == .ringPlanet {
                ctx.setStrokeColor(alt.cg()); ctx.setLineWidth(max(1.2, wd * 0.08))
                ctx.strokeEllipse(in: CGRect(x: cx - wd * 0.95, y: top + wd / 2 - wd * 0.22, width: wd * 1.9, height: wd * 0.44))
            }
        case .pencil:
            ctx.setFillColor(cc); ctx.fill(CGRect(x: cx - wd / 2, y: top + wd * 1.4, width: wd, height: bottom - top - wd * 1.4))
            poly([Q(0, top), Q(wd / 2, top + wd * 1.4), Q(-wd / 2, top + wd * 1.4)], alt.cg(), on: c)
        case .line:
            rrect(CGRect(x: cx - max(1, wd * 0.15), y: top, width: max(2, wd * 0.3), height: bottom - top), 1, fill: cc, on: c)
        }
        return (c, c.w / 2, Int((py * f.s).rounded()))
    }

    func second3(_ k: SK, len: CGFloat, tail: CGFloat, color: RGB, s: CGFloat) -> (Canvas, Int, Int) {
        let w = 24 * s, h = len + tail + 10 * s
        let c = cv(w, h)
        let cx = w / 2, top: CGFloat = 5 * s, py = top + len
        let cc = color.cg()
        func Q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x, y: y) }
        let lw = max(1.8, 2.4 * s)
        if k != .dot { c.ctx.setFillColor(cc); c.ctx.fill(CGRect(x: cx - lw / 2, y: top, width: lw, height: len + tail)) }
        switch k {
        case .stick: dot(Q(0, py + tail - 4 * s), 4.5 * s, cc, on: c)
        case .lollipop: ring(Q(0, top + len * 0.2), 5 * s, 2 * s, cc, on: c); dot(Q(0, py + tail - 5 * s), 5 * s, cc, on: c)
        case .railway: dot(Q(0, top + len * 0.2), 8.5 * s, cc, on: c)
        case .arrow: poly([Q(0, top - 2 * s), Q(6 * s, top + 12 * s), Q(-6 * s, top + 12 * s)], cc, on: c); dot(Q(0, py + tail - 4 * s), 4 * s, cc, on: c)
        case .dot: dot(Q(0, top + 2 * s), 5 * s, cc, on: c)
        }
        if k != .dot { dot(Q(0, py), 3.5 * s, cc, on: c) }
        return (c, c.w / 2, Int((py * f.s).rounded()))
    }

    var hourAngle: CGFloat { (previewHour + previewMinute / 60) * 30 }
    var minuteAngle: CGFloat { (previewMinute + previewSecond / 60) * 6 }

    func cap3(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, outer: RGB, inner: RGB) {
        let cap = cv(2 * r + 2, 2 * r + 2)
        dot(CGPoint(x: r + 1, y: r + 1), r, outer.cg(), on: cap)
        dot(CGPoint(x: r + 1, y: r + 1), r * 0.45, inner.cg(), on: cap)
        let n = face.add(uid("cap"), cap)
        let px = f.x(x) - cap.w / 2, py = f.y(y) - cap.h / 2
        face.time.append(Layer(kind: .single(n, px, py)))
        let img = cgImage(n)
        ops[1]!.append { $0.draw(img, at: CGPoint(x: px, y: py)) }
    }

    func hands3(_ a: AL, _ hk: HK, _ sk: SK?, minute mk: HK? = nil, hourLen: CGFloat = 0.56, minLen: CGFloat = 0.86, hourW: CGFloat = 0.1,
                minW: CGFloat = 0.075, color: RGB? = nil, alt: RGB? = nil, cap: Bool = true, secLen: CGFloat = 0.9) {
        let c = color ?? fg, al = alt ?? acc, R = a.R
        addHand(hand3(hk, len: R * hourLen, tail: R * 0.1, width: R * hourW, color: c, alt: al), cx: I(a.cx), cy: I(a.cy), value: VT.hourHand, angle: hourAngle)
        addHand(hand3(mk ?? hk, len: R * minLen, tail: R * 0.1, width: R * minW, color: c, alt: al), cx: I(a.cx), cy: I(a.cy), value: VT.minuteHand, angle: minuteAngle)
        if let sk {
            addHand(second3(sk, len: R * secLen, tail: R * 0.2, color: sec, s: a.k), cx: I(a.cx), cy: I(a.cy), value: VT.secondHand, angle: previewSecond * 6)
        }
        if cap { cap3(a.cx, a.cy, 8 * a.k, outer: c, inner: sk == nil ? al : sec) }
    }

    // MARK: Complications

    /// A small dial showing one statistic: live progress arc (where the watch has one), icon and value.
    func statDial(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ s: Stat, _ color: RGB, face fc: CGColor? = nil, ink: RGB? = nil, ticks: Bool = false) {
        let center = CGPoint(x: x, y: y)
        if let fc { dot(center, r, fc) }
        if ticks { for i in 0 ..< 12 { seg(CGPoint(x: x + sin(CGFloat(i) * .pi / 6) * r * 0.98, y: y - cos(CGFloat(i) * .pi / 6) * r * 0.98),
                                           CGPoint(x: x + sin(CGFloat(i) * .pi / 6) * r * 0.86, y: y - cos(CGFloat(i) * .pi / 6) * r * 0.86), 1.2, (ink ?? fg).cg(0.6)) } }
        let ic = I(r * 0.42)
        let tr = [I(x - r * 0.78), I(y - r * 0.02), I(r * 1.56), I(r * 0.5)]
        let ink = ink ?? fg
        var layers: [Layer] = []
        var dt = DT.activity
        func ratioArc(_ v: Int, _ sample: CGFloat) {
            layers.append(arc(cx: I(x), cy: I(y), r: I(r * 0.8), lw: max(3, I(r * 0.13)), start: 0, end: 360, color: color, value: v, sample: sample))
        }
        switch s {
        case .steps: ratioArc(VT.stepsRatio, 0.72); layers += [icon("steps", [I(x) - ic / 2, I(y - r * 0.5), ic, ic], color), text(tr, VT.steps, "8426", ink)]
        case .heart: dt = DT.heart; ratioArc(VT.heartRatio, 0.38); layers += [icon("heart", [I(x) - ic / 2, I(y - r * 0.5), ic, ic], color), text(tr, VT.heart, "72", ink)]
        case .battery: dt = DT.battery; ratioArc(VT.batteryRatio, 0.88); layers += [icon("bolt", [I(x) - ic / 2, I(y - r * 0.5), ic, ic], color), text(tr, VT.battery, "88", ink)]
        case .calories: layers += [icon("flame", [I(x) - ic / 2, I(y - r * 0.5), ic, ic], color), text(tr, VT.calories, "326", ink)]
        case .weather:
            dt = DT.weather
            let ws = I(r * 0.62)
            layers += [weatherIcon(ws, I(x) - ws / 2, I(y - r * 0.66)), text([I(x - r * 0.78), I(y + r * 0.02), I(r * 1.56), I(r * 0.5)], VT.temperature, "24°", ink)]
        }
        container([I(x - r), I(y - r), I(2 * r), I(2 * r)], dt, layers)
    }

    /// Day-of-month window (optionally with weekday) with its top-left corner at x, y.
    func dateWindow(_ x: CGFloat, _ y: CGFloat, k: CGFloat, fill: RGB, ink: RGB, frame: RGB? = nil, weekday: Bool = false) {
        let dw = 14 * k, h = 26 * k
        let ww: CGFloat = weekday ? 46 * k : 0
        let r = CGRect(x: x, y: y, width: ww + 2 * dw + 12 * k, height: h + 4 * k)
        rrect(r, 3 * k, fill: fill.cg(), stroke: (frame ?? acc).cg(0.8), lw: max(1, 1.5 * k))
        if weekday {
            let wk = labels(weekdays, I(46 * k), I(h), acc, size: 16 * k, outline: false)
            face.date.append(sel(wk, I(x + 4 * k), I(y + 2 * k), VT.week, label: 2, show: 5))
        }
        let dd = labels((0 ... 9).map(String.init), I(dw), I(h), ink, size: 19 * k, outline: false)
        face.date += [sel(Array(dd[0 ... 3]), I(x + ww + 6 * k), I(y + 2 * k), VT.dayHi, label: 2, show: 1),
                      sel(dd, I(x + ww + 6 * k + dw), I(y + 2 * k), VT.dayLo, label: 2, show: 3)]
    }

    /// Statistics in a row, with an optional custom frame drawn behind each cell.
    func statRow(y: Int, _ items: [Stat], height: Int = 64, panel: Bool = true, ink: RGB? = nil, cell: ((CGRect) -> Void)? = nil) {
        let (a, b) = f.span(CGFloat(y), CGFloat(y + height), margin: 8)
        let x0 = Int(a.rounded(.up)), total = Int(b.rounded(.down)) - x0
        if panel { self.panel(CGRect(x: x0, y: y, width: total, height: height)) }
        let w = total / items.count
        for (i, s) in items.enumerated() {
            let cx0 = x0 + i * w
            cell?(CGRect(x: cx0 + 3, y: y, width: w - 6, height: height))
            let (dt, layers) = statLayers(s, col: cx0, width: w, y: y + (height - 60) / 2, ink: ink)
            container([cx0 + 2, y + 2, w - 4, height - 4], dt, layers)
        }
    }

    /// Rectangular screens: date above the dial and a stats strip below. Round screens: nothing (the dial fills the screen).
    func tallExtras(_ a: AL, date: Bool = true, _ items: [Stat] = [.heart, .steps, .battery]) {
        guard !a.round else { return }
        if date { topDate() }
        if !items.isEmpty { strip(y: 372, items) }
    }

    /// Ink that reads well on the screen background (outside any dial).
    var bgInk: RGB { col(0).isDark ? RGB(0xF2F2F2) : RGB(0x1A1A1A) }

    func topDate(font: String = "system") {
        let wk = acc.isDark == col(0).isDark ? bgInk : acc
        dateRow(x: 140 - Builder.dateWidth(month: true) / 2, y: 22, font: font, weekColor: wk, outline: false, ink: bgInk)
    }

    // MARK: Digit glyphs

    func fitFont(_ font: String, _ w: CGFloat, _ h: CGFloat) -> CGFloat {
        var size = h * 1.3
        while size > 6 {
            let fnt = makeFont(font, size)
            let ok = (0 ... 9).allSatisfy { n in
                let b = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(NSAttributedString(string: String(n), attributes: [.font: fnt])), .useGlyphPathBounds)
                return b.width <= w && b.height <= h
            }
            if ok { break }
            size -= 1
        }
        return size
    }

    func glyphs(_ w: Int, _ h: Int, _ draw: (Canvas, Int, CGRect) -> Void) -> [String] {
        let p = uid("gx")
        return (0 ... 9).map { n in
            let c = cv(CGFloat(w), CGFloat(h))
            draw(c, n, CGRect(x: 0, y: 0, width: w, height: h))
            return face.add("\(p)_\(n)", c)
        }
    }

    static let font5x7: [[String]] = [
        ["01110", "10001", "10011", "10101", "11001", "10001", "01110"], ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        ["01110", "10001", "00001", "00010", "00100", "01000", "11111"], ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
        ["00010", "00110", "01010", "10010", "11111", "00010", "00010"], ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        ["00110", "01000", "10000", "11110", "10001", "10001", "01110"], ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        ["01110", "10001", "10001", "01110", "10001", "10001", "01110"], ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    ]

    func matrixDigits(_ w: Int, _ h: Int, on: RGB, off: CGColor?, square: Bool, shadow: CGColor? = nil) -> [String] {
        glyphs(w, h) { [self] c, n, r in
            let cell = min(r.width / 5, r.height / 7)
            let x0 = (r.width - cell * 5) / 2, y0 = (r.height - cell * 7) / 2
            for (row, bits) in Builder.font5x7[n].enumerated() {
                for (colI, ch) in bits.enumerated() {
                    let rr = CGRect(x: x0 + CGFloat(colI) * cell, y: y0 + CGFloat(row) * cell, width: cell, height: cell)
                    if ch == "1" {
                        if square {
                            if let shadow { c.fill(shadow, rr.offsetBy(dx: cell * 0.18, dy: cell * 0.18).insetBy(dx: 0.5, dy: 0.5)) }
                            c.fill(on.cg(), rr.insetBy(dx: 0.5, dy: 0.5))
                        } else {
                            dot(CGPoint(x: rr.midX, y: rr.midY), cell * 0.5, on.cg(0.25), on: c)
                            dot(CGPoint(x: rr.midX, y: rr.midY), cell * 0.38, on.cg(), on: c)
                        }
                    } else if let off {
                        if square { c.fill(off, rr.insetBy(dx: 0.5, dy: 0.5)) } else { dot(CGPoint(x: rr.midX, y: rr.midY), cell * 0.36, off, on: c) }
                    }
                }
            }
        }
    }

    func glowDigits(_ w: Int, _ h: Int, glow: RGB, core: RGB, font: String, outline: Bool, ghosts: Bool = false) -> [String] {
        let size = fitFont(font, CGFloat(w) - 16, CGFloat(h) - 16)
        let clear = CGColor(gray: 0, alpha: 0)
        return glyphs(w, h) { c, n, r in
            if ghosts {
                for g in [8, 3, 0, 6] where g != n { c.text(String(g), font: font, size: size, color: clear, in: r, stroke: glow.cg(0.07), strokeWidth: 1.2, fixedSize: true) }
            }
            for (lw, al) in [(11.0, 0.08), (7.0, 0.14), (4.0, 0.3)] as [(CGFloat, CGFloat)] {
                c.text(String(n), font: font, size: size, color: clear, in: r, stroke: glow.cg(al), strokeWidth: lw, fixedSize: true)
            }
            if outline { c.text(String(n), font: font, size: size, color: clear, in: r, stroke: core.cg(), strokeWidth: 2.2, fixedSize: true) }
            else { c.text(String(n), font: font, size: size, color: core.cg(), in: r, fixedSize: true) }
        }
    }

    func flipDigits(_ w: Int, _ h: Int, card: RGB, ink: RGB, font: String) -> [String] {
        let size = fitFont(font, CGFloat(w) * 0.78, CGFloat(h) * 0.74)
        return glyphs(w, h) { [self] c, n, r in
            let body = r.insetBy(dx: 1, dy: 1)
            rrect(body, 8, fill: card.mix(RGB(0), 0.12).cg(), on: c)
            rrect(CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height / 2), 8, fill: card.cg(), on: c)
            c.fill(card.cg(), CGRect(x: body.minX, y: body.midY - 8, width: body.width, height: 8))
            c.text(String(n), font: font, size: size, color: ink.cg(), in: r, fixedSize: true)
            c.fill(CGColor(gray: 0, alpha: 0.55), CGRect(x: body.minX, y: body.midY - 1, width: body.width, height: 2))
            c.fill(CGColor(gray: 0, alpha: 0.6), CGRect(x: body.minX, y: body.midY - 5, width: 3, height: 10))
            c.fill(CGColor(gray: 0, alpha: 0.6), CGRect(x: body.maxX - 3, y: body.midY - 5, width: 3, height: 10))
        }
    }

    func binaryDigits(_ w: Int, _ h: Int, on: RGB, off: RGB) -> [String] {
        glyphs(w, h) { [self] c, n, r in
            let step = r.height / 4, rad = min(r.width, step) * 0.36
            for bit in 0 ..< 4 {
                let p = CGPoint(x: r.midX, y: step * (CGFloat(bit) + 0.5))
                if n & (8 >> bit) != 0 { dot(p, rad * 1.18, on.cg(0.25), on: c); dot(p, rad, on.cg(), on: c) }
                else { ring(p, rad - 1.5, 2.5, off.cg(0.55), on: c) }
            }
        }
    }

    func stencilDigits(_ w: Int, _ h: Int, color: RGB, font: String) -> [String] {
        let size = fitFont(font, CGFloat(w) - 8, CGFloat(h) - 8)
        return glyphs(w, h) { c, n, r in
            c.text(String(n), font: font, size: size, color: color.cg(), in: r, fixedSize: true)
            c.ctx.setBlendMode(.clear)
            c.fill(CGColor(gray: 0, alpha: 1), CGRect(x: 0, y: r.height * 0.49, width: r.width, height: max(2, r.height * 0.045)))
            c.fill(CGColor(gray: 0, alpha: 1), CGRect(x: r.midX - r.width * 0.035, y: 0, width: r.width * 0.07, height: r.height * 0.24))
            c.fill(CGColor(gray: 0, alpha: 1), CGRect(x: r.midX - r.width * 0.035, y: r.height * 0.76, width: r.width * 0.07, height: r.height * 0.24))
            c.ctx.setBlendMode(.normal)
        }
    }

    func popDigits(_ w: Int, _ h: Int, fill: RGB, ink: RGB, font: String) -> [String] {
        let size = fitFont(font, CGFloat(w) - 18, CGFloat(h) - 18)
        return glyphs(w, h) { c, n, r in
            c.text(String(n), font: font, size: size, color: ink.cg(), in: r.offsetBy(dx: 5, dy: 5), stroke: ink.cg(), strokeWidth: 7, fixedSize: true)
            c.text(String(n), font: font, size: size, color: fill.cg(), in: r, stroke: ink.cg(), strokeWidth: 7, fixedSize: true)
            c.text(String(n), font: font, size: size, color: fill.cg(), in: r, fixedSize: true)
        }
    }

    func gradientDigits(_ w: Int, _ h: Int, _ colors: [RGB], edge: RGB?, font: String) -> [String] {
        let size = fitFont(font, CGFloat(w) - 10, CGFloat(h) - 10)
        return glyphs(w, h) { c, n, r in
            if let edge { c.text(String(n), font: font, size: size, color: edge.cg(), in: r, stroke: edge.cg(), strokeWidth: 5, fixedSize: true) }
            let mask = Canvas(design: r.width, r.height, scale: self.f.s)
            mask.text(String(n), font: font, size: size, color: CGColor(gray: 1, alpha: 1), in: r, fixedSize: true)
            mask.ctx.setBlendMode(.sourceAtop); mask.gradient(colors, in: r); mask.ctx.setBlendMode(.normal)
            c.ctx.saveGState(); c.ctx.scaleBy(x: 1 / self.f.s, y: 1 / self.f.s); c.draw(mask.image, at: .zero); c.ctx.restoreGState()
        }
    }

    /// Digits turned a quarter turn clockwise (read by tilting the head to the right).
    func rotatedDigits(_ w: Int, _ h: Int, color: RGB, font: String, outline: Bool = false) -> [String] {
        let size = fitFont(font, CGFloat(h) - 8, CGFloat(w) - 8)
        return glyphs(w, h) { c, n, r in
            c.ctx.saveGState()
            c.ctx.translateBy(x: r.midX, y: r.midY); c.ctx.rotate(by: .pi / 2)
            c.text(String(n), font: font, size: size, color: color.cg(), in: CGRect(x: -r.height / 2, y: -r.width / 2, width: r.height, height: r.width),
                   stroke: outline ? color.outline : nil, strokeWidth: 3, fixedSize: true)
            c.ctx.restoreGState()
        }
    }

    func rotatedLabels(_ strings: [String], _ w: Int, _ h: Int, color: RGB, font: String, size: CGFloat) -> [String] {
        let p = uid("rl")
        return strings.enumerated().map { i, s in
            let c = cv(CGFloat(w), CGFloat(h))
            c.ctx.saveGState()
            c.ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2); c.ctx.rotate(by: .pi / 2)
            c.text(s, font: font, size: size, color: color.cg(), in: CGRect(x: -CGFloat(h) / 2, y: -CGFloat(w) / 2, width: CGFloat(h), height: CGFloat(w)))
            c.ctx.restoreGState()
            return face.add("\(p)_\(i)", c)
        }
    }

    func plainDigits(_ w: Int, _ h: Int, color: RGB, font: String, outlineOnly: Bool = false, lw: CGFloat = 2.5) -> [String] {
        let size = fitFont(font, CGFloat(w) - 8, CGFloat(h) - 8)
        let clear = CGColor(gray: 0, alpha: 0)
        return glyphs(w, h) { c, n, r in
            if outlineOnly { c.text(String(n), font: font, size: size, color: clear, in: r, stroke: color.cg(), strokeWidth: lw, fixedSize: true) }
            else { c.text(String(n), font: font, size: size, color: color.cg(), in: r, fixedSize: true) }
        }
    }

    /// Four digits in a row with the colon drawn by `colon`.
    func row4(_ hh: [String], _ mm: [String], x: [Int], y: Int) {
        clock(hh, mm, x.map { ($0, y) })
    }
}

// MARK: - Analog styles

extension Builder {
    func sPilot(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        minuteTrack(a, r: R - 3 * k, len: 8 * k, w: 1.6 * k, fg.cg(0.85))
        let typeB = v % 2 == 1
        if typeB {
            for i in 1 ..< 12 { word(String(format: "%02d", i * 5), P(a, CGFloat(i) * 30, R - 9 * k), 11 * k, fg.cg(0.9), font: "system", w: 22 * k) }
            ring(a.c, R - 19 * k, 1.2 * k, fg.cg(0.5))
            for h in 1 ..< 12 where h != 3 { word(String(h), P(a, CGFloat(h) * 30, R - 46 * k), 30 * k, fg.cg()) }
        } else {
            for h in 1 ..< 12 where h != 3 { word(String(h), P(a, CGFloat(h) * 30, R - 34 * k), 38 * k, fg.cg()) }
        }
        let ty = a.cy - R + (typeB ? 22 : 8) * k
        poly([CGPoint(x: a.cx - 13 * k, y: ty), CGPoint(x: a.cx + 13 * k, y: ty), CGPoint(x: a.cx, y: ty + 30 * k)], fg.cg())
        dot(CGPoint(x: a.cx - 21 * k, y: ty + 4 * k), 3.5 * k, fg.cg()); dot(CGPoint(x: a.cx + 21 * k, y: ty + 4 * k), 3.5 * k, fg.cg())
        dateWindow(a.cx + R * (typeB ? 0.52 : 0.6), a.cy - 15 * k, k: k, fill: dialRGB.mix(fg, 0.1), ink: fg, frame: fg.mix(dialRGB, 0.5))
        word(["FLIEGER", "TYPE B", "NAVIGATOR", "AIRCREW", "OBSERVER"][v % 5], CGPoint(x: a.cx, y: a.cy + R * 0.36), 10 * k, acc.cg(), font: "system", w: 90 * k)
        tallExtras(a)
        hands3(a, v % 3 == 2 ? .pencil : .sword, .stick, hourW: 0.11, minW: 0.08, alt: acc)
    }

    func sDiver(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        let bezel = col(2), inner = R * 0.8
        disc(a, R, bezel.cg())
        if v % 3 == 1 { band(a, inner, R, 0, 90, sec.cg(0.75)) }
        let bink = bezel.isDark ? RGB(0xF2F2F2) : RGB(0x111111)
        for i in 0 ..< 60 {
            let d = CGFloat(i) * 6
            if i == 0 {
                let p = P(a, 0, R - 4 * k), q0 = P(a, -6, inner + 6 * k), q1 = P(a, 6, inner + 6 * k)
                poly([q0, q1, p], bink.cg()); dot(P(a, 0, inner + 14 * k), 3.5 * k, sec.cg())
            } else if i % 10 == 0 { word(String(i), P(a, d, (R + inner) / 2), 17 * k, bink.cg(), w: 30 * k) }
            else if i % 5 == 0 { radial(a, d, inner + 5 * k, R - 5 * k, 5 * k, bink.cg()) }
            else if i < 15 { radial(a, d, R - 10 * k, R - 4 * k, 1.5 * k, bink.cg(0.8)) }
            else { dot(P(a, d, R - 7 * k), 1.6 * k, bink.cg(0.6)) }
        }
        disc(a, inner - 2 * k, dialRGB.cg())
        minuteTrack(a, r: inner - 4 * k, len: 6 * k, w: 1.3 * k, fg.cg(0.6))
        let lume = fg, rim = acc
        for h in 0 ..< 12 where h != 3 {
            let d = CGFloat(h) * 30
            if h == 0 {
                let t = P(a, 0, inner - 12 * k)
                poly([CGPoint(x: t.x - 12 * k, y: t.y), CGPoint(x: t.x + 12 * k, y: t.y), P(a, 0, inner - 36 * k)], lume.cg())
            } else if h == 6 || h == 9 {
                radial(a, d, inner - 12 * k, inner - 36 * k, 11 * k, rim.cg()); radial(a, d, inner - 14 * k, inner - 34 * k, 7 * k, lume.cg())
            } else {
                dot(P(a, d, inner - 20 * k), 8 * k, rim.cg()); dot(P(a, d, inner - 20 * k), 6.3 * k, lume.cg())
            }
        }
        dateWindow(a.cx + inner * 0.52, a.cy - 15 * k, k: k, fill: RGB(0xFFFFFF), ink: RGB(0x111111), frame: rim)
        word(v % 2 == 0 ? "300 M" : "DIVER 200 M", CGPoint(x: a.cx, y: a.cy + inner * 0.38), 10 * k, acc.cg(), font: "system", w: 100 * k)
        tallExtras(a, [.heart, .steps, .weather])
        let pairs: [(HK, HK)] = [(.arrow, .sword), (.lumeBaton, .lumeBaton), (.sword, .sword)]
        let (h1, m1) = pairs[v % 3]
        hands3(a, h1, .lollipop, minute: m1, hourLen: 0.5 * inner / R, minLen: 0.9 * inner / R, hourW: 0.12, minW: 0.085, alt: fg.mix(acc, 0.3), secLen: 0.95 * inner / R)
    }

    func sChrono(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        let tachy = v % 2 == 0
        if tachy {
            band(a, R * 0.86, R, 0, 360, dialRGB.mix(RGB(0), 0.35).cg())
            for n in [500, 400, 300, 250, 200, 150, 120, 100, 90, 80, 70, 65, 60] {
                let d = 3600 / CGFloat(n) * 6
                if n != 60 { word(String(n), P(a, d, R * 0.93), 8.5 * k, fg.cg(0.9), font: "system", w: 24 * k) }
            }
            word("TACHY", P(a, 0, R * 0.93), 8 * k, acc.cg(), font: "system", w: 30 * k)
        }
        let tr = tachy ? R * 0.85 : R - 2 * k
        for i in 0 ..< 240 { let d = CGFloat(i) * 1.5; radial(a, d, tr - (i % 4 == 0 ? 7 : 3.5) * k, tr, (i % 4 == 0 ? 1.4 : 0.8) * k, fg.cg(0.6)) }
        for h in 0 ..< 12 where ![3, 6, 9].contains(h) {
            let d = CGFloat(h) * 30
            radial(a, d, tr - 12 * k, tr - 32 * k, (h == 0 ? 9 : 6) * k, fg.cg())
            radial(a, d, tr - 14 * k, tr - 30 * k, 2 * k, acc.cg(0.8))
        }
        let panda = v % 3 == 0
        let subFace: CGColor = panda ? (dialRGB.isDark ? RGB(0xF2F2F2) : RGB(0x1A1A1A)).cg() : dialRGB.mix(fg, 0.08).cg()
        let subInk = panda ? (dialRGB.isDark ? RGB(0x111111) : RGB(0xF2F2F2)) : fg
        let sr = R * 0.2, off = R * 0.42
        // 9 o'clock: running small seconds.
        let s9 = CGPoint(x: a.cx - off, y: a.cy)
        dot(s9, sr, subFace); ring(s9, sr, 1.2 * k, acc.cg(0.7))
        for i in 0 ..< 12 { let d = CGFloat(i) * 30 * .pi / 180
            seg(CGPoint(x: s9.x + sin(d) * sr * 0.95, y: s9.y - cos(d) * sr * 0.95), CGPoint(x: s9.x + sin(d) * sr * (i % 3 == 0 ? 0.68 : 0.8), y: s9.y - cos(d) * sr * (i % 3 == 0 ? 0.68 : 0.8)), 1.3 * k, subInk.cg(0.8)) }
        for (i, n) in ["60", "20", "40"].enumerated() { let d = CGFloat(i) * 120 * .pi / 180
            word(n, CGPoint(x: s9.x + sin(d) * sr * 0.45, y: s9.y - cos(d) * sr * 0.45), 7 * k, subInk.cg(0.8), font: "system", w: 14 * k) }
        statDial(a.cx + off, a.cy, sr, .battery, acc, face: subFace, ink: subInk)
        statDial(a.cx, a.cy + off, sr, .steps, sec, face: subFace, ink: subInk)
        // Chronograph seconds hand parked at 12.
        radial(a, 0, -R * 0.18, tr - 4 * k, 1.6 * k, sec.cg())
        word(["CHRONOGRAPH", "AUTOMATIC", "RACING", "PANDA", "TACHYMETRE"][v % 5], CGPoint(x: a.cx, y: a.cy - R * 0.36), 9 * k, fg.cg(0.85), font: "system", w: 110 * k)
        addHand(second3(.stick, len: sr * 0.85, tail: sr * 0.2, color: sec, s: k * 0.7), cx: I(s9.x), cy: I(s9.y), value: VT.secondHand, angle: previewSecond * 6)
        tallExtras(a, [.heart, .calories, .weather])
        hands3(a, v % 2 == 0 ? .baton : .dauphine, nil, hourW: 0.085, minW: 0.065, alt: acc)
    }

    func sField(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        minuteTrack(a, r: R - 3 * k, len: 7 * k, w: 1.4 * k, fg.cg(0.8))
        for h in 0 ..< 12 { radial(a, CGFloat(h) * 30, R - 3 * k, R - 13 * k, 3 * k, fg.cg()) }
        for h in 1 ... 12 { word(String(h), P(a, CGFloat(h) * 30, R * 0.72), 30 * k, fg.cg()) }
        for h in 13 ... 24 { word(String(h == 24 ? 0 : h), P(a, CGFloat(h - 12) * 30, R * 0.5), 11 * k, acc.cg(), font: "system", w: 20 * k) }
        if v % 2 == 1 { dateWindow(a.cx - 22 * k, a.cy + R * 0.2, k: k, fill: dialRGB.mix(RGB(0), 0.3), ink: fg) }
        word(["FIELD", "INFANTRY", "SCOUT", "RANGER", "EXPLORER"][v % 5], CGPoint(x: a.cx, y: a.cy - R * 0.28), 9 * k, fg.cg(0.75), font: "system", w: 80 * k)
        tallExtras(a, [.steps, .weather, .battery])
        hands3(a, v % 3 == 0 ? .pencil : .lumeBaton, .stick, hourW: 0.1, minW: 0.075, alt: acc)
    }

    func sRailway(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        if v % 2 == 1 { ring(a.c, R - 2 * k, 4 * k, fg.cg()) }
        for i in 0 ..< 60 {
            if i % 5 == 0 { radial(a, CGFloat(i) * 6, R - 9 * k, R * 0.72, 11 * k, fg.cg()) }
            else { radial(a, CGFloat(i) * 6, R - 9 * k, R - 21 * k, 3.6 * k, fg.cg()) }
        }
        if a.round { dateRow(x: 140 - Builder.dateWidth(month: false) / 2, y: I(a.cy + R * 0.32), month: false, weekColor: fg, outline: false) }
        tallExtras(a)
        hands3(a, .tapered, .railway, hourLen: 0.62, minLen: 0.9, hourW: 0.11, minW: 0.08, color: fg, alt: fg, cap: false, secLen: 0.72)
        cap3(a.cx, a.cy, 5 * k, outer: sec, inner: sec)
    }

    func sBauhaus(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        for i in 0 ..< 60 { radial(a, CGFloat(i) * 6, R - 4 * k, R - (i % 5 == 0 ? 14 : 8) * k, (i % 5 == 0 ? 1.8 : 1) * k, fg.cg(0.9)) }
        for h in 1 ... 12 where h != 6 { word(String(h), P(a, CGFloat(h) * 30, R * 0.76), 17 * k, fg.cg()) }
        let s6 = CGPoint(x: a.cx, y: a.cy + R * 0.45), sr = R * 0.2
        ring(s6, sr, 1 * k, fg.cg(0.6))
        for i in 0 ..< 60 where i % 5 == 0 { let d = CGFloat(i) * 6 * .pi / 180
            seg(CGPoint(x: s6.x + sin(d) * sr, y: s6.y - cos(d) * sr), CGPoint(x: s6.x + sin(d) * sr * 0.82, y: s6.y - cos(d) * sr * 0.82), 1 * k, fg.cg(0.8)) }
        addHand(second3(.stick, len: sr * 0.85, tail: sr * 0.15, color: sec, s: k * 0.6), cx: I(s6.x), cy: I(s6.y), value: VT.secondHand, angle: previewSecond * 6)
        if v % 2 == 0 { dateWindow(a.cx + R * 0.32, a.cy - 15 * k, k: k * 0.9, fill: dialRGB, ink: fg, frame: fg.mix(dialRGB, 0.6)) }
        word(["form", "MAX", "dessau", "weimar", "linie"][v % 5], CGPoint(x: a.cx, y: a.cy - R * 0.38), 11 * k, fg.cg(0.8), font: d.font, w: 80 * k)
        tallExtras(a)
        hands3(a, v % 3 == 2 ? .leaf : .baton, nil, hourLen: 0.55, minLen: 0.88, hourW: 0.045, minW: 0.035, alt: acc, cap: false)
        cap3(a.cx, a.cy, 4 * k, outer: fg, inner: fg)
    }

    func sSector(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        let zone = dialRGB.mix(acc, 0.22), inner = dialRGB.mix(RGB(dialRGB.isDark ? 0xFFFFFF : 0), 0.07)
        band(a, R * 0.84, R, 0, 360, zone.cg())
        disc(a, R * 0.5, inner.cg())
        for r in [R * 0.84, R * 0.5] { ring(a.c, r, 1.2 * k, fg.cg(0.7)) }
        for i in 0 ..< 60 { radial(a, CGFloat(i) * 6, R * 0.84, R * (i % 5 == 0 ? 0.92 : 0.88), (i % 5 == 0 ? 2 : 1) * k, fg.cg()) }
        for i in 1 ... 12 { word(String(i * 5), P(a, CGFloat(i) * 30, R * 0.955), 9.5 * k, fg.cg(), font: "system", w: 18 * k) }
        let numerals = v % 2 == 0
        for h in 1 ... 12 {
            if numerals { word(String(h), P(a, CGFloat(h) * 30, R * 0.67), 22 * k, fg.cg()) }
            else { radial(a, CGFloat(h) * 30, R * 0.56, R * 0.78, (h % 3 == 0 ? 7 : 4) * k, fg.cg()) }
        }
        seg(CGPoint(x: a.cx - R * 0.5, y: a.cy), CGPoint(x: a.cx + R * 0.5, y: a.cy), 0.8 * k, fg.cg(0.45))
        seg(CGPoint(x: a.cx, y: a.cy - R * 0.5), CGPoint(x: a.cx, y: a.cy + R * 0.5), 0.8 * k, fg.cg(0.45))
        ring(a.c, R * 0.25, 0.8 * k, fg.cg(0.45))
        let wk = labels(weekdays, I(46 * k), I(22 * k), acc, size: 14 * k, outline: false)
        face.date.append(sel(wk, I(a.cx - 23 * k), I(a.cy - R * 0.4), VT.week, label: 2, show: 5))
        tallExtras(a, date: false, [.heart, .steps, .battery])
        if !a.round { topDate() }
        hands3(a, v % 3 == 1 ? .sword : .dauphine, .stick, hourW: 0.08, minW: 0.06, alt: acc)
    }

    func sGMT(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        let inner = R * 0.8
        band(a, inner, R, -90, 90, col(2).cg())
        band(a, inner, R, 90, 270, col(3).cg())
        for h in stride(from: 2, through: 22, by: 2) {
            let night = h > 6 && h < 18
            let ink = (night ? col(3) : col(2)).isDark ? RGB(0xF4F4F4) : RGB(0x111111)
            word(String(h), P(a, CGFloat(h) * 15, (R + inner) / 2), 14 * k, ink.cg(), w: 24 * k)
        }
        for h in stride(from: 1, through: 23, by: 2) {
            let night = h > 6 && h < 18
            dot(P(a, CGFloat(h) * 15, (R + inner) / 2), 2 * k, ((night ? col(3) : col(2)).isDark ? RGB(0xF4F4F4) : RGB(0x111111)).cg())
        }
        poly([P(a, -5, R - 4 * k), P(a, 5, R - 4 * k), P(a, 0, inner + 4 * k)], acc.cg())
        disc(a, inner - 2 * k, dialRGB.cg())
        minuteTrack(a, r: inner - 4 * k, len: 5 * k, w: 1.2 * k, fg.cg(0.6), skipFive: false)
        for h in 0 ..< 12 where h != 3 {
            let d = CGFloat(h) * 30
            if h == 0 { poly([P(a, -7, inner - 10 * k), P(a, 7, inner - 10 * k), P(a, 0, inner - 34 * k)], fg.cg()) }
            else { radial(a, d, inner - 10 * k, inner - (h % 3 == 0 ? 34 : 28) * k, (h % 3 == 0 ? 10 : 8) * k, fg.cg()) }
        }
        dateWindow(a.cx + inner * 0.52, a.cy - 15 * k, k: k, fill: RGB(0xFFFFFF), ink: RGB(0x111111), frame: acc)
        statDial(a.cx - inner * 0.42, a.cy, inner * 0.2, .weather, acc, face: dialRGB.mix(fg, 0.07).cg())
        word("GMT", CGPoint(x: a.cx, y: a.cy + inner * 0.4), 12 * k, acc.cg(), font: "system", w: 50 * k)
        tallExtras(a, [.heart, .steps, .battery])
        hands3(a, v % 2 == 0 ? .arrow : .lumeBaton, .arrow, minute: .lumeBaton, hourLen: 0.48, minLen: 0.76, hourW: 0.1, minW: 0.07, alt: acc, secLen: 0.78)
    }

    func sEnamel(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        ring(a.c, R - 3 * k, 1.5 * k, acc.cg())
        ring(a.c, R * 0.86, 0.9 * k, fg.cg(0.8)); ring(a.c, R * 0.93, 0.9 * k, fg.cg(0.8))
        for i in 0 ..< 60 { radial(a, CGFloat(i) * 6, R * 0.86, R * 0.93, (i % 5 == 0 ? 2 : 0.8) * k, fg.cg(0.85)) }
        for i in 0 ..< 12 { dot(P(a, CGFloat(i) * 30, R * 0.895), 2.2 * k, fg.cg()) }
        let roman = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
        for h in 0 ..< 12 {
            let s = v % 2 == 0 ? roman[h] : String(h == 0 ? 12 : h)
            word(s, P(a, CGFloat(h) * 30, R * 0.72), (v % 2 == 0 ? 19 : 24) * k, fg.cg(), w: 42 * k)
        }
        // Moon-phase aperture above 6.
        let mc = CGPoint(x: a.cx, y: a.cy + R * 0.42), mw = R * 0.27
        let win = CGMutablePath()
        win.addArc(center: CGPoint(x: mc.x, y: mc.y + mw * 0.35), radius: mw, startAngle: .pi, endAngle: 0, clockwise: false)
        win.closeSubpath()
        bg.ctx.saveGState(); bg.ctx.addPath(win); bg.ctx.clip()
        bg.gradient([RGB(0x0B1A40), RGB(0x1E3A7A)], in: CGRect(x: mc.x - mw, y: mc.y - mw, width: 2 * mw, height: 2 * mw))
        for (dx, dy) in [(-0.6, -0.1), (-0.3, -0.45), (0.5, -0.3), (0.75, 0.0), (0.1, -0.7), (-0.8, 0.2)] as [(CGFloat, CGFloat)] {
            dot(CGPoint(x: mc.x + dx * mw, y: mc.y + mw * 0.35 + dy * mw), 1.1 * k, RGB(0xFFFFFF).cg(0.9))
        }
        dot(CGPoint(x: mc.x + mw * 0.22, y: mc.y - mw * 0.12), mw * 0.32, RGB(0xF2C94C).cg())
        bg.ctx.restoreGState()
        dot(CGPoint(x: mc.x - mw * 0.98, y: mc.y + mw * 0.35), mw * 0.36, dialRGB.cg())
        dot(CGPoint(x: mc.x + mw * 0.98, y: mc.y + mw * 0.35), mw * 0.36, dialRGB.cg())
        ring(CGPoint(x: mc.x, y: mc.y + mw * 0.35), mw, 1.2 * k, acc.cg())
        dateWindow(a.cx - 22 * k, a.cy - R * 0.45, k: k, fill: dialRGB.mix(RGB(0xFFFFFF), 0.4), ink: fg, frame: acc)
        tallExtras(a, date: false, [.heart, .steps, .weather])
        if !a.round { topDate(font: d.font) }
        hands3(a, .breguet, v % 3 == 0 ? nil : .stick, hourLen: 0.52, minLen: 0.82, hourW: 0.07, minW: 0.055, color: fg.mix(RGB(0x1D3B8F), 0.6), alt: acc)
    }

    func gear(_ c: CGPoint, _ r: CGFloat, teeth: Int, _ color: RGB, hole: RGB, k: CGFloat) {
        let ctx = bg.ctx
        ctx.setFillColor(color.cg()); ctx.beginPath()
        for i in 0 ..< teeth * 4 {
            let ang = CGFloat(i) / CGFloat(teeth * 4) * 2 * .pi
            let rr = (i % 4 == 0 || i % 4 == 1) ? r : r - max(2.5, r * 0.1)
            let p = CGPoint(x: c.x + cos(ang) * rr, y: c.y + sin(ang) * rr)
            i == 0 ? ctx.move(to: p) : ctx.addLine(to: p)
        }
        ctx.closePath(); ctx.fillPath()
        dot(c, r * 0.72, hole.cg())
        for i in 0 ..< 5 { let ang = CGFloat(i) / 5 * 2 * .pi
            seg(c, CGPoint(x: c.x + cos(ang) * r * 0.74, y: c.y + sin(ang) * r * 0.74), max(1.5, r * 0.12), color.cg()) }
        dot(c, max(2.5, r * 0.18), color.cg()); dot(c, max(1.2, r * 0.07), RGB(0xC0392B).cg())
    }

    func sSkeleton(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        let hole = dialRGB, metal = col(2), metal2 = col(3)
        disc(a, R, hole.cg())
        var rng = RNG(abs(d.title.hashValueStable))
        // Bridges.
        bg.ctx.setLineCap(.round)
        seg(P(a, 200, R * 0.75), P(a, 20, R * 0.75), 14 * k, metal2.cg(0.9), cap: .round)
        seg(P(a, 120, R * 0.7), P(a, 300, R * 0.55), 11 * k, metal2.cg(0.9), cap: .round)
        let gears: [(CGFloat, CGFloat, CGFloat, Int)] = [(40, 0.5, 0.3, 18), (150, 0.45, 0.24, 14), (260, 0.5, 0.26, 16), (330, 0.42, 0.16, 10), (0, 0, 0.18, 12), (95, 0.6, 0.15, 10)]
        for (deg, dist, rad, t) in gears { gear(P(a, deg, R * dist), R * rad, teeth: t, rng.next() > 0.5 ? metal : metal2, hole: hole, k: k) }
        // Balance wheel.
        let bw = P(a, 215, R * 0.5)
        ring(bw, R * 0.17, 3 * k, metal.cg()); seg(CGPoint(x: bw.x - R * 0.17, y: bw.y), CGPoint(x: bw.x + R * 0.17, y: bw.y), 2 * k, metal.cg())
        for i in 0 ..< 8 { let p = P(a, CGFloat(i) * 45 + 22, R * 0.62); dot(p, 3 * k, RGB(0xB3122E).cg()); dot(CGPoint(x: p.x - 0.8 * k, y: p.y - 0.8 * k), 1 * k, RGB(0xFFFFFF).cg(0.7)) }
        for i in 0 ..< 4 { let p = P(a, CGFloat(i) * 90 + 45, R * 0.78); dot(p, 3.5 * k, metal.cg()); seg(CGPoint(x: p.x - 2.5 * k, y: p.y), CGPoint(x: p.x + 2.5 * k, y: p.y), 1 * k, hole.cg()) }
        band(a, R * 0.84, R, 0, 360, col(1).mix(metal, 0.25).cg())
        ring(a.c, R * 0.84, 1.5 * k, metal.cg())
        for i in 0 ..< 60 { radial(a, CGFloat(i) * 6, R * 0.86, R * (i % 5 == 0 ? 0.97 : 0.91), (i % 5 == 0 ? 3.5 : 1) * k, fg.cg()) }
        if v % 2 == 1 { for h in [12, 3, 6, 9] { word(String(h), P(a, CGFloat(h) * 30, R * 0.77), 15 * k, fg.cg()) } }
        tallExtras(a)
        hands3(a, .skeleton, .stick, hourW: 0.13, minW: 0.1, alt: acc)
    }

    func sRegulator(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        ring(a.c, R * 0.84, 1 * k, fg.cg(0.7))
        for i in 0 ..< 60 { radial(a, CGFloat(i) * 6, R * 0.84, R * (i % 5 == 0 ? 0.76 : 0.8), (i % 5 == 0 ? 2.2 : 1) * k, fg.cg()) }
        for i in 1 ... 12 { word(String(i * 5), P(a, CGFloat(i) * 30, R * 0.92), 14 * k, fg.cg(), w: 26 * k) }
        let hc = CGPoint(x: a.cx, y: a.cy - R * 0.4), hr = R * 0.28
        let sc = CGPoint(x: a.cx, y: a.cy + R * 0.4), sr = R * 0.26
        let sub = dialRGB.mix(fg, 0.08)
        for (c, r) in [(hc, hr), (sc, sr)] { dot(c, r, sub.cg()); ring(c, r, 1.2 * k, acc.cg()) }
        for h in 0 ..< 12 { let ang = CGFloat(h) * .pi / 6
            if h % 3 == 0 { word(String(h == 0 ? 12 : h), CGPoint(x: hc.x + sin(ang) * hr * 0.66, y: hc.y - cos(ang) * hr * 0.66), 11 * k, fg.cg(), w: 18 * k) }
            else { dot(CGPoint(x: hc.x + sin(ang) * hr * 0.8, y: hc.y - cos(ang) * hr * 0.8), 1.6 * k, fg.cg()) } }
        for i in 0 ..< 12 { let ang = CGFloat(i) * .pi / 6
            seg(CGPoint(x: sc.x + sin(ang) * sr * 0.95, y: sc.y - cos(ang) * sr * 0.95), CGPoint(x: sc.x + sin(ang) * sr * 0.78, y: sc.y - cos(ang) * sr * 0.78), 1.2 * k, fg.cg()) }
        word("REGULATEUR", CGPoint(x: a.cx - R * 0.48, y: a.cy), 7.5 * k, acc.cg(), font: "system", w: 64 * k)
        tallExtras(a)
        let hk: HK = v % 2 == 0 ? .breguet : .baton
        addHand(hand3(hk, len: hr * 0.72, tail: hr * 0.15, width: R * 0.06, color: fg, alt: acc), cx: I(hc.x), cy: I(hc.y), value: VT.hourHand, angle: hourAngle)
        addHand(second3(.stick, len: sr * 0.85, tail: sr * 0.18, color: sec, s: k * 0.7), cx: I(sc.x), cy: I(sc.y), value: VT.secondHand, angle: previewSecond * 6)
        addHand(hand3(hk, len: R * 0.86, tail: R * 0.12, width: R * 0.055, color: fg, alt: acc), cx: I(a.cx), cy: I(a.cy), value: VT.minuteHand, angle: minuteAngle)
        cap3(a.cx, a.cy, 6 * k, outer: fg, inner: acc)
    }

    func sSingle(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        for i in 0 ..< 144 {
            let d = CGFloat(i) * 2.5
            let (len, w): (CGFloat, CGFloat) = i % 12 == 0 ? (22, 3.2) : i % 6 == 0 ? (15, 2) : i % 3 == 0 ? (11, 1.4) : (7, 1)
            radial(a, d, R - 4 * k, R - (4 + len) * k, w * k, (i % 12 == 0 ? acc : fg).cg(i % 12 == 0 ? 1 : 0.85))
        }
        for h in 1 ... 12 { word(String(h), P(a, CGFloat(h) * 30, R * 0.66), 26 * k, fg.cg()) }
        word(["ONE HAND", "SLOW", "UNO", "HOURS ONLY", "CALM"][v % 5], CGPoint(x: a.cx, y: a.cy - R * 0.3), 9 * k, fg.cg(0.7), font: "system", w: 90 * k)
        dateRow(x: 140 - Builder.dateWidth(month: false) / 2, y: I(a.cy + R * 0.3), month: false, weekColor: acc, outline: false)
        tallExtras(a, date: false)
        addHand(hand3(v % 2 == 0 ? .needle : .pencil, len: R * 0.92, tail: R * 0.16, width: R * 0.06, color: fg, alt: acc), cx: I(a.cx), cy: I(a.cy),
                value: VT.hourHand, angle: hourAngle)
        cap3(a.cx, a.cy, 7 * k, outer: fg, inner: acc)
    }

    func sCompass(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        for i in 0 ..< 72 { let d = CGFloat(i) * 5
            radial(a, d, R - 3 * k, R - (i % 6 == 0 ? 14 : 8) * k, (i % 6 == 0 ? 2 : 1) * k, fg.cg(0.85)) }
        for i in 0 ..< 12 where i % 3 != 0 { word(String(i * 30), P(a, CGFloat(i) * 30, R * 0.8), 10 * k, fg.cg(0.8), font: "system", w: 24 * k) }
        for (i, s) in ["N", "E", "S", "W"].enumerated() { word(s, P(a, CGFloat(i) * 90, R * 0.8), 20 * k, (i == 0 ? sec : fg).cg(), w: 24 * k) }
        let light = acc, dark = acc.mix(RGB(0), 0.45)
        for i in 0 ..< 8 {
            let d = CGFloat(i) * 45, len = (i % 2 == 0 ? 0.62 : 0.38) * R, wdeg: CGFloat = i % 2 == 0 ? 9 : 12
            let tip = P(a, d, len), l = P(a, d - wdeg * 2.2, len * 0.22), r = P(a, d + wdeg * 2.2, len * 0.22)
            poly([a.c, tip, l], (i % 2 == 0 ? light : light.mix(dialRGB, 0.4)).cg())
            poly([a.c, tip, r], (i % 2 == 0 ? dark : dark.mix(dialRGB, 0.4)).cg())
        }
        ring(a.c, R * 0.22, 1 * k, fg.cg(0.6))
        tallExtras(a, [.steps, .weather, .battery])
        addHand(hand3(.needle, len: R * 0.5, tail: R * 0.15, width: R * 0.08, color: fg, alt: sec), cx: I(a.cx), cy: I(a.cy), value: VT.hourHand, angle: hourAngle)
        addHand(hand3(.needle, len: R * 0.84, tail: R * 0.18, width: R * 0.065, color: fg, alt: sec), cx: I(a.cx), cy: I(a.cy), value: VT.minuteHand, angle: minuteAngle)
        addHand(second3(.arrow, len: R * 0.92, tail: R * 0.1, color: sec, s: k), cx: I(a.cx), cy: I(a.cy), value: VT.secondHand, angle: previewSecond * 6)
        cap3(a.cx, a.cy, 7 * k, outer: fg.mix(RGB(0x888888), 0.4), inner: fg)
    }

    func sRadar(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        for i in 1 ... 4 { ring(a.c, R * CGFloat(i) / 4.2, 1.2 * k, acc.cg(0.4)) }
        seg(CGPoint(x: a.cx - R, y: a.cy), CGPoint(x: a.cx + R, y: a.cy), 1 * k, acc.cg(0.35))
        seg(CGPoint(x: a.cx, y: a.cy - R), CGPoint(x: a.cx, y: a.cy + R), 1 * k, acc.cg(0.35))
        for i in 0 ..< 72 { radial(a, CGFloat(i) * 5, R - 2 * k, R - (i % 6 == 0 ? 12 : 6) * k, (i % 6 == 0 ? 1.8 : 1) * k, acc.cg(0.8)) }
        for i in 0 ..< 4 { word(String(i * 90).leftPad(3), P(a, CGFloat(i) * 90 + 8, R * 0.86), 9 * k, acc.cg(0.8), font: "mono", w: 26 * k) }
        var rng = RNG(abs(d.title.hashValueStable) + 7)
        for _ in 0 ..< 7 {
            let p = P(a, CGFloat(rng.range(0, 360)), R * CGFloat(rng.range(0.2, 0.75)))
            dot(p, 6 * k, sec.cg(0.18)); dot(p, 3 * k, sec.cg())
        }
        // Data read-outs inside the scope.
        let ink = fg
        for (i, (lbl, s)) in [("HR", Stat.heart), ("STP", Stat.steps)].enumerated() {
            let x = a.cx + (i == 0 ? -1 : 1) * R * 0.42, y = a.cy + R * 0.48
            word(lbl, CGPoint(x: x, y: y - 9 * k), 8 * k, acc.cg(0.8), font: "mono", w: 30 * k)
            let tr = [I(x - 32 * k), I(y - 2 * k), I(64 * k), I(22 * k)]
            container([I(x - 34 * k), I(y - 18 * k), I(68 * k), I(44 * k)], s == .heart ? DT.heart : DT.activity,
                      [text(tr, s == .heart ? VT.heart : VT.steps, s == .heart ? "72" : "8426", ink)])
        }
        tallExtras(a, date: true, [])
        if !a.round { statRow(y: 372, [.battery, .calories, .weather], panel: false, ink: fg, cell: { [self] r in rrect(r, 6, stroke: acc.cg(0.6), lw: 1.2) }) }
        // Sweep: a fading wedge trailing the seconds line.
        let sw = R * 0.96, spread: CGFloat = 50
        let w = 2 * sw * sin(spread * .pi / 180) + 8, h = sw + 8
        let c = cv(w, h)
        let pv = CGPoint(x: w / 2, y: 4 + sw)
        for i in 0 ..< 25 {
            let a0 = -spread * CGFloat(i + 1) / 25, a1 = -spread * CGFloat(i) / 25
            c.ctx.setFillColor(acc.cg(0.34 * (1 - CGFloat(i) / 25)))
            c.ctx.beginPath(); c.ctx.move(to: pv)
            c.ctx.addLine(to: CGPoint(x: pv.x + sin(a0 * .pi / 180) * sw, y: pv.y - cos(a0 * .pi / 180) * sw))
            c.ctx.addLine(to: CGPoint(x: pv.x + sin(a1 * .pi / 180) * sw, y: pv.y - cos(a1 * .pi / 180) * sw)); c.ctx.closePath(); c.ctx.fillPath()
        }
        seg(pv, CGPoint(x: pv.x, y: 4), 2 * k, acc.cg(), on: c)
        addHand((c, c.w / 2, Int((pv.y * f.s).rounded())), cx: I(a.cx), cy: I(a.cy), value: VT.secondHand, angle: previewSecond * 6)
        addHand(hand3(.line, len: R * 0.5, tail: 0, width: R * 0.1, color: fg, alt: fg), cx: I(a.cx), cy: I(a.cy), value: VT.hourHand, angle: hourAngle)
        addHand(hand3(.line, len: R * 0.8, tail: 0, width: R * 0.07, color: fg, alt: fg), cx: I(a.cx), cy: I(a.cy), value: VT.minuteHand, angle: minuteAngle)
        cap3(a.cx, a.cy, 4 * k, outer: acc, inner: fg)
    }

    func sPlanets(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        var rng = RNG(abs(d.title.hashValueStable) + 3)
        let (sx0, sx1) = (-f.ox, 280 + f.ox), (sy0, sy1) = (-f.oy, 456 + f.oy)
        for _ in 0 ..< 90 { dot(CGPoint(x: rng.range(Double(sx0), Double(sx1)), y: rng.range(Double(sy0), Double(sy1))), CGFloat(rng.range(0.4, 1.3)), RGB(0xFFFFFF).cg(CGFloat(rng.range(0.3, 0.9)))) }
        let rh = R * 0.46, rm = R * 0.72, rs = R * 0.93
        for r in [rh, rm, rs] { ring(a.c, r, 1 * k, fg.cg(0.22)) }
        for i in 0 ..< 12 { dot(P(a, CGFloat(i) * 30, rs), (i % 3 == 0 ? 3 : 1.6) * k, fg.cg(i % 3 == 0 ? 0.9 : 0.5)) }
        for (i, s) in ["12", "3", "6", "9"].enumerated() { word(s, P(a, CGFloat(i) * 90, R * 0.83), 13 * k, fg.cg(0.7), font: "system", w: 22 * k) }
        let sun = col(2)
        for i in 0 ..< 6 { dot(a.c, R * (0.2 - CGFloat(i) * 0.02), sun.cg(0.12 + CGFloat(i) * 0.1)) }
        dot(a.c, R * 0.09, sun.mix(RGB(0xFFFFFF), 0.4).cg())
        tallExtras(a)
        addHand(hand3(v % 3 == 1 ? .ringPlanet : .planet, len: rh, tail: 0, width: R * 0.15, color: acc, alt: acc.mix(RGB(0xFFFFFF), 0.5)),
                cx: I(a.cx), cy: I(a.cy), value: VT.hourHand, angle: hourAngle)
        addHand(hand3(v % 3 == 2 ? .ringPlanet : .planet, len: rm, tail: 0, width: R * 0.1, color: sec, alt: sec.mix(RGB(0xFFFFFF), 0.5)),
                cx: I(a.cx), cy: I(a.cy), value: VT.minuteHand, angle: minuteAngle)
        addHand(second3(.dot, len: rs, tail: 0, color: fg, s: k * 0.8), cx: I(a.cx), cy: I(a.cy), value: VT.secondHand, angle: previewSecond * 6)
    }

    func sVinyl(_ v: Int) {
        face.order = [0, 2, 3, 1]
        let a = analogLayout(), R = a.R, k = a.k
        disc(a, R, dialRGB.cg())
        var r = R * 0.98
        var i = 0
        while r > R * 0.36 { ring(a.c, r, 1 * k, fg.cg(i % 3 == 0 ? 0.09 : 0.04)); r -= 2.6 * k; i += 1 }
        for (d0, d1) in [(25.0, 55.0), (205.0, 235.0)] as [(CGFloat, CGFloat)] { band(a, R * 0.38, R * 0.97, d0, d1, RGB(0xFFFFFF).cg(0.05)) }
        for h in 0 ..< 12 { radial(a, CGFloat(h) * 30, R - 1 * k, R - (h % 3 == 0 ? 12 : 7) * k, (h % 3 == 0 ? 3 : 1.6) * k, fg.cg(0.85)) }
        if !a.round {
            // Tone arm resting on the record.
            let pivot = CGPoint(x: a.cx + R * 0.92, y: a.cy - R * 0.92)
            dot(pivot, 13 * k, col(2).cg()); dot(pivot, 6 * k, col(3).cg())
            seg(pivot, CGPoint(x: a.cx + R * 0.62, y: a.cy - R * 0.2), 4 * k, col(3).cg(), cap: .round)
            rrect(CGRect(x: a.cx + R * 0.55, y: a.cy - R * 0.24, width: 18 * k, height: 26 * k), 3 * k, fill: col(2).cg())
        }
        tallExtras(a, [.heart, .steps, .battery])
        // The label turns once a minute as the seconds hand.
        let lr = R * 0.34, size = 2 * lr + 4
        let c = cv(size, size)
        let lc = CGPoint(x: size / 2, y: size / 2)
        dot(lc, lr, acc.cg(), on: c)
        ring(lc, lr * 0.8, 0.8, sec.cg(0.6), on: c)
        word(["SIDE A", "SIDE B", "LP", "B-SIDES", "LIVE"][v % 5], CGPoint(x: lc.x, y: lc.y - lr * 0.5), lr * 0.22, sec.cg(), font: d.font, w: lr * 1.3, on: c)
        word("33⅓ RPM", CGPoint(x: lc.x, y: lc.y + lr * 0.52), lr * 0.15, sec.cg(0.85), font: "system", w: lr * 1.2, on: c)
        dot(lc, lr * 0.07, dialRGB.cg(), on: c)
        addHand((c, c.w / 2, c.h / 2), cx: I(a.cx), cy: I(a.cy), value: VT.secondHand, angle: previewSecond * 6)
        addHand(hand3(.tapered, len: R * 0.58, tail: 0, width: R * 0.05, color: fg, alt: fg), cx: I(a.cx), cy: I(a.cy), value: VT.hourHand, angle: hourAngle)
        addHand(hand3(.tapered, len: R * 0.9, tail: 0, width: R * 0.035, color: fg, alt: fg), cx: I(a.cx), cy: I(a.cy), value: VT.minuteHand, angle: minuteAngle)
        cap3(a.cx, a.cy, 4 * k, outer: fg, inner: dialRGB)
    }
}

extension String {
    func leftPad(_ n: Int) -> String { count >= n ? self : String(repeating: "0", count: n - count) + self }
}

// MARK: - Digital and graphic styles

extension Builder {
    func colonDots(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ r: CGFloat, _ c: CGColor, glow: CGColor? = nil, square: Bool = false) {
        for y in [y0, y1] {
            if let glow { dot(CGPoint(x: x, y: y), r * 2.2, glow) }
            if square { bg.fill(c, CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) } else { dot(CGPoint(x: x, y: y), r, c) }
        }
    }

    func sNixie(_ v: Int) {
        let plate = col(2)
        rrect(CGRect(x: 8, y: 100, width: 264, height: 196), 18, fill: plate.cg(), stroke: plate.mix(RGB(0xFFFFFF), 0.2).cg(), lw: 2)
        for i in 0 ..< 4 { let x = CGFloat(18 + i * 66) + (i >= 2 ? 0 : 0); dot(CGPoint(x: x + 8, y: 112), 3, plate.mix(RGB(0), 0.4).cg()) }
        let xs = [16, 74, 150, 208]
        for x in xs {
            let r = CGRect(x: CGFloat(x), y: 116, width: 56, height: 162)
            rrect(r, 27, fill: RGB(0xFFFFFF).cg(0.05), stroke: RGB(0xFFFFFF).cg(0.28), lw: 1.5)
            for gx in stride(from: r.minX + 8, to: r.maxX - 6, by: 6) { seg(CGPoint(x: gx, y: r.minY + 22), CGPoint(x: gx, y: r.maxY - 16), 0.5, RGB(0xFFFFFF).cg(0.06)) }
            rrect(CGRect(x: r.minX + 6, y: r.minY + 14, width: 5, height: r.height - 40), 2.5, fill: RGB(0xFFFFFF).cg(0.12))
            bg.fill(plate.mix(RGB(0), 0.5).cg(), CGRect(x: r.minX + 10, y: r.maxY - 6, width: r.width - 20, height: 8))
        }
        colonDots(140, 176, 222, 4, acc.mix(RGB(0xFFFFFF), 0.3).cg(), glow: acc.cg(0.25))
        let dg = glowDigits(48, 118, glow: acc, core: acc.mix(RGB(0xFFFFFF), 0.45), font: d.font, outline: v % 2 == 1, ghosts: true)
        row4(dg, dg, x: xs.map { $0 + 4 }, y: 136)
        // Seconds in two small tubes.
        for x in [104, 144] {
            rrect(CGRect(x: CGFloat(x), y: 304, width: 34, height: 62), 16, fill: RGB(0xFFFFFF).cg(0.05), stroke: RGB(0xFFFFFF).cg(0.25), lw: 1.2)
        }
        seconds(glowDigits(30, 50, glow: acc, core: acc.mix(RGB(0xFFFFFF), 0.45), font: d.font, outline: v % 2 == 1), (106, 310), (146, 310))
        dateRow(x: 140 - Builder.dateWidth(month: true) / 2, y: 52, font: "mono", weekColor: acc, outline: false)
        statRow(y: 380, [.heart, .steps, .battery], height: 60, panel: false, ink: acc.mix(RGB(0xFFFFFF), 0.4))
    }

    func sFlip(_ v: Int) {
        let card = dialRGB
        let dg = flipDigits(v % 2 == 0 ? 104 : 60, v % 2 == 0 ? 146 : 104, card: card, ink: fg, font: d.font)
        if v % 2 == 0 {
            clock(dg, dg, [(34, 72), (142, 72), (34, 226), (142, 226)])
            dateRow(x: 140 - Builder.dateWidth(month: true) / 2, y: 30, weekColor: acc)
            statRow(y: 384, [.heart, .steps, .battery], height: 60)
        } else {
            clock(dg, dg, [(14, 120), (76, 120), (144, 120), (206, 120)])
            colonDots(140, 156, 190, 4, fg.cg())
            let sc = flipDigits(40, 66, card: card, ink: acc, font: d.font)
            seconds(sc, (98, 244), (142, 244))
            dateRow(x: 140 - Builder.dateWidth(month: true) / 2, y: 70, weekColor: acc)
            let wx = 18
            container([wx, 18, 244, 44], DT.weather, [weatherIcon(32, 92, 22), text([128, 22, 60, 30], VT.temperature, "24°")])
            statRow(y: 330, [.heart, .steps, .calories], height: 60)
            statRow(y: 394, [.battery], height: 54, panel: false)
        }
    }

    func sDotMatrix(_ v: Int) {
        let panelC = col(2)
        rrect(CGRect(x: 6, y: 96, width: 268, height: 196), 14, fill: panelC.cg(), stroke: acc.cg(0.3), lw: 1.5)
        for gy in stride(from: CGFloat(106), to: 286, by: 7) { for gx in stride(from: CGFloat(14), to: 268, by: 7) { dot(CGPoint(x: gx, y: gy), 1.2, acc.cg(0.07)) } }
        let off: CGColor? = v % 2 == 0 ? acc.cg(0.12) : nil
        let big = matrixDigits(54, 76, on: acc, off: off, square: v % 3 == 2)
        clock(big, big, [(14, 120), (70, 120), (156, 120), (212, 120)])
        colonDots(140, 142, 176, 4, acc.cg(), glow: acc.cg(0.2), square: v % 3 == 2)
        let small = matrixDigits(26, 38, on: sec, off: v % 2 == 0 ? sec.cg(0.12) : nil, square: v % 3 == 2)
        seconds(small, (196, 236), (224, 236))
        dateRow(x: 20, y: 242, font: "mono", weekColor: sec, outline: false)
        container([30, 22, 220, 60], DT.weather, [weatherIcon(44, 76, 30), text([128, 34, 80, 36], VT.temperature, "24°", acc)])
        statRow(y: 372, [.heart, .steps, .battery], ink: acc, cell: { [self] r in
            for gy in stride(from: r.minY + 4, to: r.maxY, by: 6) { seg(CGPoint(x: r.minX, y: gy), CGPoint(x: r.maxX, y: gy), 0.6, acc.cg(0.05)) }
        })
    }

    func pixelArt(_ rows: [String], at p: CGPoint, cell: CGFloat, _ colors: [Character: CGColor]) {
        for (j, row) in rows.enumerated() { for (i, ch) in row.enumerated() { if let c = colors[ch] { bg.fill(c, CGRect(x: p.x + CGFloat(i) * cell, y: p.y + CGFloat(j) * cell, width: cell, height: cell)) } } }
    }

    func sPixel(_ v: Int) {
        let sky = [col(0), col(1)]
        for i in 0 ..< 6 { bg.fill(sky[0].mix(sky[1], CGFloat(i) / 5).cg(), CGRect(x: -f.ox, y: CGFloat(i) * 56 - f.oy, width: 280 + 2 * f.ox, height: 56 + (i == 5 ? f.oy : 0))) }
        let cloud = ["..XXX....", ".XXXXX.XX", "XXXXXXXXX", ".XXXXXXX."]
        pixelArt(cloud, at: CGPoint(x: 24, y: 40), cell: 6, ["X": RGB(0xFFFFFF).cg(0.92)])
        pixelArt(cloud, at: CGPoint(x: 176, y: 70), cell: 5, ["X": RGB(0xFFFFFF).cg(0.8)])
        let sun = ["..XXX..", ".XXXXX.", "XXXXXXX", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX.."]
        pixelArt(sun, at: CGPoint(x: 214, y: 18), cell: 5, ["X": col(3).cg()])
        // Ground.
        let gy: CGFloat = 330
        bg.fill(RGB(0x3E8E41).mix(acc, 0.15).cg(), CGRect(x: -f.ox, y: gy, width: 280 + 2 * f.ox, height: 12))
        var rng = RNG(abs(d.title.hashValueStable))
        for row in 0 ..< 12 { for colI in 0 ..< 20 {
            let shade = rng.next() > 0.7 ? 0.15 : 0
            bg.fill(RGB(0x8B5A2B).mix(RGB(0), CGFloat(shade)).cg(), CGRect(x: CGFloat(colI) * 14 - f.ox, y: gy + 12 + CGFloat(row) * 14, width: 14, height: 14))
        } }
        let shadow = RGB(0).cg(0.35)
        let big = matrixDigits(55, 77, on: fg, off: nil, square: true, shadow: shadow)
        clock(big, big, [(12, 112), (68, 112), (156, 112), (212, 112)])
        bg.fill(fg.cg(), CGRect(x: 135, y: 132, width: 10, height: 10)); bg.fill(fg.cg(), CGRect(x: 135, y: 164, width: 10, height: 10))
        dateRow(x: 140 - Builder.dateWidth(month: true) / 2, y: 204, font: "Silom", weekColor: acc)
        // HUD: pixel heart, coin and battery with live values.
        let heart = [".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]
        let coin = [".XXX.", "XXYXX", "XXYXX", "XXYXX", ".XXX."]
        let batt = ["XXXXXXX.", "XYYYY.XX", "XYYYY.XX", "XXXXXXX."]
        let hud: [(CGFloat, [String], [Character: CGColor], Int, Int, String, Int)] = [
            (22, heart, ["X": RGB(0xE53935).cg()], VT.heart, DT.heart, "72", 4),
            (110, coin, ["X": RGB(0xFBC02D).cg(), "Y": RGB(0xF57F17).cg()], VT.steps, DT.activity, "8426", 4),
            (192, batt, ["X": fg.cg(), "Y": RGB(0x7CB342).cg()], VT.battery, DT.battery, "88", 4),
        ]
        for (x, art, cols, value, dt, sample, cell) in hud {
            pixelArt(art, at: CGPoint(x: x, y: 252), cell: CGFloat(cell), cols)
            container([I(x) - 4, 244, 80, 44], dt, [text([I(x) + 32, 248, 46, 30], value, sample, fg)])
        }
        statRow(y: 380, [.calories, .weather], height: 56, panel: true)
    }

    func sBinary(_ v: Int) {
        let xs = [26, 82, 154, 210]
        for (i, lbl) in ["8", "4", "2", "1"].enumerated() { word(lbl, CGPoint(x: 14, y: 106 + CGFloat(i) * 46), 12, fg.cg(0.5), font: "mono", w: 16) }
        for x in xs { rrect(CGRect(x: CGFloat(x) - 2, y: 80, width: 48, height: 192), 24, fill: fg.cg(0.05)) }
        let on = acc, off = fg
        let hh = binaryDigits(44, 184, on: on, off: off), mm = binaryDigits(44, 184, on: sec, off: off)
        clock(hh, mm, xs.map { ($0, 84) })
        let small = plainDigits(30, 36, color: fg.mix(dialRGB, 0.3), font: "mono")
        clock(small, small, xs.map { ($0 + 7, 280) })
        word(["BCD", "BINARY", "0b", "BITS", "1010"][v % 5], CGPoint(x: 140, y: 330), 10, fg.cg(0.5), font: "mono", w: 80)
        dateRow(x: 140 - Builder.dateWidth(month: true) / 2, y: 36, font: "mono", weekColor: acc, outline: false)
        statRow(y: 372, [.heart, .steps, .battery])
    }

    func sTerminal(_ v: Int) {
        let dim = fg.cg(0.55)
        for y in stride(from: -f.oy, to: 456 + f.oy, by: 3) { bg.fill(RGB(0).cg(0.18), CGRect(x: -f.ox, y: y, width: 280 + 2 * f.ox, height: 1)) }
        let user = ["user@wrist", "root@watch", "you@fit", "guest@time", "dev@band"][v % 5]
        func line(_ s: String, _ y: CGFloat, _ c: CGColor) { bg.text(s, font: "mono", size: 12, color: c, in: CGRect(x: 14, y: y, width: 252, height: 16), align: 0) }
        line("\(user):~$ date +%H:%M", 26, dim)
        let dg = plainDigits(58, 100, color: fg, font: d.font)
        clock(dg, dg, [(10, 48), (66, 48), (156, 48), (212, 48)])
        colonDots(140, 82, 120, 5, fg.cg(), square: true)
        line("\(user):~$ cal --today", 160, dim)
        dateRow(x: 14, y: 180, font: "mono", weekColor: acc, outline: false)
        line("\(user):~$ vitals", 220, dim)
        let rows: [(String, Int, Int, String)] = [("heart_bpm", VT.heart, DT.heart, "72"), ("steps    ", VT.steps, DT.activity, "8426"),
                                                  ("battery_%", VT.battery, DT.battery, "88"), ("kcal     ", VT.calories, DT.activity, "326")]
        for (i, (k, value, dt, sample)) in rows.enumerated() {
            let y = 242 + CGFloat(i) * 30
            line("  \(k) =", y + 6, fg.cg(0.8))
            container([14, I(y), 252, 30], dt, [text([136, I(y) + 2, 110, 26], value, sample, acc)])
        }
        line("\(user):~$", 372, dim)
        bg.fill(fg.cg(0.85), CGRect(x: 104, y: 372, width: 9, height: 16))
        container([20, 398, 240, 44], DT.weather, [weatherIcon(30, 30, 404), text([70, 404, 80, 30], VT.temperature, "24°", fg), unit(150, 406, 30, 26)])
    }

    func brickWall(_ base: RGB, mortar: RGB) {
        bg.fill(mortar.cg(), CGRect(x: -f.ox, y: -f.oy, width: 280 + 2 * f.ox, height: 456 + 2 * f.oy))
        var rng = RNG(abs(d.title.hashValueStable))
        var row = 0
        for y in stride(from: -f.oy, to: 456 + f.oy, by: 15) {
            let off: CGFloat = row % 2 == 0 ? 0 : 17
            for x in stride(from: -f.ox - off, to: 280 + f.ox, by: 34) {
                bg.fill(base.mix(RGB(0), CGFloat(rng.range(0, 0.25))).cg(), CGRect(x: x + 1, y: y + 1, width: 32, height: 12))
            }
            row += 1
        }
    }

    func sNeon(_ v: Int) {
        brickWall(col(2), mortar: col(3))
        bg.fill(RGB(0).cg(0.35), CGRect(x: -f.ox, y: -f.oy, width: 280 + 2 * f.ox, height: 456 + 2 * f.oy))
        let frame = CGRect(x: 12, y: 110, width: 256, height: 168)
        for (lw, al) in [(12.0, 0.08), (7.0, 0.15), (3.0, 0.5)] as [(CGFloat, CGFloat)] { rrect(frame, 26, stroke: sec.cg(al), lw: lw) }
        rrect(frame, 26, stroke: sec.mix(RGB(0xFFFFFF), 0.5).cg(), lw: 1.5)
        let dg = glowDigits(58, 112, glow: acc, core: acc.mix(RGB(0xFFFFFF), 0.55), font: d.font, outline: v % 2 == 0)
        clock(dg, dg, [(20, 136), (76, 136), (148, 136), (204, 136)])
        colonDots(140, 174, 214, 4, acc.mix(RGB(0xFFFFFF), 0.5).cg(), glow: acc.cg(0.25))
        let wk = glowLabels(weekdays, 120, 40, glow: sec, font: d.font)
        face.date.append(sel(wk, 80, 48, VT.week, label: 2, show: 5))
        statRow(y: 300, [.heart, .steps], height: 60, panel: false, ink: sec.mix(RGB(0xFFFFFF), 0.4), cell: { [self] r in
            rrect(r.insetBy(dx: 8, dy: 2), 14, stroke: acc.cg(0.25), lw: 4); rrect(r.insetBy(dx: 8, dy: 2), 14, stroke: acc.mix(RGB(0xFFFFFF), 0.4).cg(0.8), lw: 1.2)
        })
        statRow(y: 376, [.battery, .weather], height: 60, panel: false, ink: sec.mix(RGB(0xFFFFFF), 0.4), cell: { [self] r in
            rrect(r.insetBy(dx: 8, dy: 2), 14, stroke: sec.cg(0.25), lw: 4); rrect(r.insetBy(dx: 8, dy: 2), 14, stroke: sec.mix(RGB(0xFFFFFF), 0.4).cg(0.8), lw: 1.2)
        })
    }

    func glowLabels(_ strings: [String], _ w: Int, _ h: Int, glow: RGB, font: String) -> [String] {
        let p = uid("gl")
        let clear = CGColor(gray: 0, alpha: 0)
        return strings.enumerated().map { i, s in
            let c = cv(CGFloat(w), CGFloat(h))
            let r = CGRect(x: 6, y: 4, width: w - 12, height: h - 8)
            for (lw, al) in [(8.0, 0.1), (4.0, 0.25)] as [(CGFloat, CGFloat)] { c.text(s, font: font, size: CGFloat(h) * 0.7, color: clear, in: r, stroke: glow.cg(al), strokeWidth: lw) }
            c.text(s, font: font, size: CGFloat(h) * 0.7, color: glow.mix(RGB(0xFFFFFF), 0.5).cg(), in: r)
            return face.add("\(p)_\(i)", c)
        }
    }

    func sTypo(_ v: Int) {
        let mode = v % 3
        let hh = mode == 2 ? plainDigits(126, 200, color: acc, font: d.font, outlineOnly: true, lw: 3) : plainDigits(126, 200, color: mode == 0 ? fg : acc, font: d.font)
        let mm = mode == 1 ? plainDigits(126, 200, color: fg, font: d.font) : plainDigits(126, 200, color: mode == 0 ? acc : fg, font: d.font, outlineOnly: true, lw: 3)
        clock(hh, mm, [(14, 18), (140, 18), (14, 176), (140, 176)])
        bg.fill(fg.cg(0.8), CGRect(x: 18, y: 386, width: 244, height: 1.5))
        dateRow(x: 18, y: 396, font: d.font, weekColor: acc, outline: false)
        container([196, 392, 70, 40], DT.battery, [icon("bolt", [198, 400, 16, 20], acc), text([214, 396, 52, 30], VT.battery, "88", fg)])
        bg.text(["No. 24", "VOL. II", "ISSUE 09", "EDITION", "FOLIO"][v % 5], font: "system", size: 10, color: fg.cg(0.6), in: CGRect(x: 18, y: 432, width: 120, height: 14), align: 0)
        container([150, 426, 116, 26], DT.heart, [icon("heart", [176, 430, 14, 14], acc), text([194, 426, 60, 22], VT.heart, "72", fg)])
    }

    func sSideways(_ v: Int) {
        let dg = rotatedDigits(160, 84, color: fg, font: d.font), ac = rotatedDigits(160, 84, color: acc, font: d.font)
        clock(ac, dg, [(20, 20), (20, 104), (20, 210), (20, 294)])
        for x in [80.0, 120.0] as [CGFloat] { dot(CGPoint(x: x, y: 199), 6, fg.cg()) }
        bg.fill(acc.cg(0.6), CGRect(x: 196, y: 20, width: 2, height: 360))
        let wk = rotatedLabels(weekdays, 34, 70, color: acc, font: d.font, size: 22)
        let dd = rotatedLabels((0 ... 9).map(String.init), 34, 22, color: fg, font: d.font, size: 22)
        face.date += [sel(wk, 214, 24, VT.week, label: 2, show: 5), sel(Array(dd[0 ... 3]), 214, 100, VT.dayHi, label: 2, show: 1), sel(dd, 214, 122, VT.dayLo, label: 2, show: 3)]
        let mo = rotatedLabels(months, 34, 70, color: fg, font: d.font, size: 22)
        face.date.append(sel(mo, 214, 152, VT.month, label: 2, show: 11))
        container([206, 240, 54, 60], DT.heart, [icon("heart", [222, 246, 22, 22], acc), text([206, 270, 54, 26], VT.heart, "72", fg)])
        container([206, 310, 54, 60], DT.battery, [icon("bolt", [222, 316, 22, 22], acc), text([206, 340, 54, 26], VT.battery, "88", fg)])
        statRow(y: 388, [.steps, .calories, .weather], height: 60, panel: v % 2 == 0)
    }

    func sStencil(_ v: Int) {
        var rng = RNG(abs(d.title.hashValueStable))
        for i in 0 ..< 46 {
            let c = col(1 + i % 3)
            let cx = CGFloat(rng.range(-30, 310)), cy = CGFloat(rng.range(-30, 486)), r = CGFloat(rng.range(18, 46))
            bg.ctx.setFillColor(c.cg()); bg.ctx.beginPath()
            for j in 0 ..< 9 { let ang = CGFloat(j) / 9 * 2 * .pi, rr = r * CGFloat(rng.range(0.6, 1.1))
                let p = CGPoint(x: cx + cos(ang) * rr * 1.4, y: cy + sin(ang) * rr); j == 0 ? bg.ctx.move(to: p) : bg.ctx.addLine(to: p) }
            bg.ctx.closePath(); bg.ctx.fillPath()
        }
        let plate = dialRGB
        for r in [CGRect(x: 10, y: 96, width: 260, height: 180), CGRect(x: 10, y: 286, width: 260, height: 44)] {
            rrect(r, 6, fill: plate.cg(), stroke: plate.mix(RGB(0), 0.4).cg(), lw: 2)
            for p in [CGPoint(x: r.minX + 9, y: r.minY + 9), CGPoint(x: r.maxX - 9, y: r.minY + 9), CGPoint(x: r.minX + 9, y: r.maxY - 9), CGPoint(x: r.maxX - 9, y: r.maxY - 9)] {
                dot(p, 3.5, plate.mix(RGB(0), 0.35).cg()); dot(CGPoint(x: p.x - 1, y: p.y - 1), 1.3, plate.mix(RGB(0xFFFFFF), 0.4).cg())
            }
        }
        bg.text(["UNIT 07 · TIME", "SECTOR 4 · CLOCK", "CREW · CHRONO", "OPS · LOCAL", "FIELD · HRS"][v % 5], font: "Phosphate-Solid", size: 12, color: fg.cg(0.75),
                in: CGRect(x: 28, y: 104, width: 224, height: 16))
        let dg = stencilDigits(58, 110, color: fg, font: d.font), ac = stencilDigits(58, 110, color: acc, font: d.font)
        clock(ac, dg, [(18, 136), (76, 136), (146, 136), (204, 136)])
        colonDots(140, 172, 212, 5, fg.cg(), square: true)
        dateRow(x: 140 - Builder.dateWidth(month: true) / 2, y: 295, font: "Phosphate-Solid", weekColor: acc, outline: false)
        container([60, 26, 160, 56], DT.weather, [weatherIcon(40, 82, 32), text([128, 38, 80, 34], VT.temperature, "24°", fg.isDark == plate.isDark ? RGB(0xFFFFFF) : fg)])
        statRow(y: 372, [.heart, .steps, .battery])
    }

    func sPop(_ v: Int) {
        let base = col(0), dotsC = col(2)
        bg.fill(base.cg(), CGRect(x: -f.ox, y: -f.oy, width: 280 + 2 * f.ox, height: 456 + 2 * f.oy))
        var row = 0
        for y in stride(from: -f.oy, to: 456 + f.oy, by: 11) {
            let t = (y + f.oy) / (456 + 2 * f.oy)
            for x in stride(from: -f.ox + (row % 2 == 0 ? 0 : 5.5), to: 280 + f.ox, by: 11) { dot(CGPoint(x: x, y: y), 1 + 3.2 * t, dotsC.cg()) }
            row += 1
        }
        let c = CGPoint(x: 140, y: 196)
        var star: [CGPoint] = []
        for i in 0 ..< 32 { let ang = CGFloat(i) / 32 * 2 * .pi, r: CGFloat = i % 2 == 0 ? 150 : 104
            star.append(CGPoint(x: c.x + cos(ang) * r, y: c.y + sin(ang) * r * 0.82)) }
        poly(star, RGB(0x111111).cg()); poly(star.map { CGPoint(x: c.x + ($0.x - c.x) * 0.95, y: c.y + ($0.y - c.y) * 0.95) }, acc.cg())
        let ink = RGB(0x111111)
        let dg = popDigits(62, 112, fill: fg, ink: ink, font: d.font)
        clock(dg, dg, [(14, 140), (72, 140), (146, 140), (204, 140)])
        colonDots(140, 178, 214, 6, ink.cg())
        // Speech bubble with the date.
        bg.ctx.setFillColor(RGB(0xFFFFFF).cg()); bg.ctx.setStrokeColor(ink.cg()); bg.ctx.setLineWidth(3)
        let bub = CGRect(x: 24, y: 18, width: 232, height: 62)
        bg.ctx.addEllipse(in: bub); bg.ctx.drawPath(using: .fillStroke)
        poly([CGPoint(x: 190, y: 74), CGPoint(x: 214, y: 104), CGPoint(x: 172, y: 78)], ink.cg()); poly([CGPoint(x: 192, y: 72), CGPoint(x: 208, y: 96), CGPoint(x: 176, y: 74)], RGB(0xFFFFFF).cg())
        dateRow(x: 140 - Builder.dateWidth(month: true) / 2, y: 36, font: d.font, weekColor: RGB(0xD62828), outline: false, ink: ink)
        word(["POW!", "ZAP!", "BAM!", "WOW!", "BOOM!"][v % 5], CGPoint(x: 140, y: 306), 24, sec.cg(), w: 120)
        statRow(y: 362, [.heart, .steps, .battery], height: 76, panel: false, ink: ink, cell: { [self] r in
            bg.fill(RGB(0xFFFFFF).cg(), r); bg.ctx.setStrokeColor(ink.cg()); bg.ctx.setLineWidth(3); bg.ctx.stroke(r)
        })
    }

    func sChalk(_ v: Int) {
        let wood = col(2), board = col(0)
        bg.fill(wood.cg(), CGRect(x: -f.ox, y: -f.oy, width: 280 + 2 * f.ox, height: 456 + 2 * f.oy))
        let br = CGRect(x: 8 - f.ox, y: 8 - f.oy, width: 264 + 2 * f.ox, height: 440 + 2 * f.oy)
        rrect(br, 6, fill: board.cg())
        var rng = RNG(abs(d.title.hashValueStable))
        for _ in 0 ..< 10 { dot(CGPoint(x: rng.range(10, 270), y: rng.range(10, 440)), CGFloat(rng.range(20, 60)), RGB(0xFFFFFF).cg(0.025)) }
        let chalk = fg
        let font = d.font
        bg.text(["Today is", "Hello!", "Class time", "Note:", "Don't forget"][v % 5], font: font, size: 18, color: chalk.cg(0.7), in: CGRect(x: 22, y: 22, width: 160, height: 26), align: 0)
        // Doodle sun.
        let sc = CGPoint(x: 236, y: 42)
        ring(sc, 12, 2, acc.cg(0.8))
        for i in 0 ..< 8 { let ang = CGFloat(i) / 8 * 2 * .pi
            seg(CGPoint(x: sc.x + cos(ang) * 17, y: sc.y + sin(ang) * 17), CGPoint(x: sc.x + cos(ang) * 24, y: sc.y + sin(ang) * 24), 2, acc.cg(0.8), cap: .round) }
        dateRow(x: 22, y: 54, font: font, weekColor: acc, outline: false)
        let dg = plainDigits(60, 112, color: chalk.mix(board, 0.08), font: font), ac = plainDigits(60, 112, color: acc, font: font)
        clock(ac, dg, [(16, 100), (76, 100), (146, 100), (206, 100)])
        word(":", CGPoint(x: 140, y: 150), 60, chalk.cg(0.9), font: font, w: 20)
        // Wavy underline.
        bg.ctx.setStrokeColor(sec.cg(0.85)); bg.ctx.setLineWidth(3); bg.ctx.setLineCap(.round); bg.ctx.beginPath()
        for i in 0 ... 48 { let x = 24 + CGFloat(i) * 4.8, y = 226 + sin(CGFloat(i) * 0.7) * 3; i == 0 ? bg.ctx.move(to: CGPoint(x: x, y: y)) : bg.ctx.addLine(to: CGPoint(x: x, y: y)) }
        bg.ctx.strokePath()
        statRow(y: 250, [.heart, .steps], height: 66, panel: false, ink: chalk, cell: { [self] r in rrect(r.insetBy(dx: 4, dy: 2), 12, stroke: chalk.cg(0.55), lw: 2) })
        statRow(y: 326, [.weather, .battery], height: 66, panel: false, ink: chalk, cell: { [self] r in rrect(r.insetBy(dx: 4, dy: 2), 12, stroke: chalk.cg(0.55), lw: 2) })
        bg.fill(wood.mix(RGB(0), 0.25).cg(), CGRect(x: 30, y: 412, width: 220, height: 10))
        bg.fill(RGB(0xFFFFFF).cg(0.9), CGRect(x: 60, y: 406, width: 26, height: 7)); bg.fill(acc.cg(0.9), CGRect(x: 96, y: 406, width: 18, height: 7))
    }

    func sBlueprint(_ v: Int) {
        let line = fg
        let (x0, x1, y0, y1) = (-f.ox, 280 + f.ox, -f.oy, 456 + f.oy)
        for x in stride(from: x0, through: x1, by: 10) { seg(CGPoint(x: x, y: y0), CGPoint(x: x, y: y1), 0.6, line.cg(Int((x - x0).rounded()) % 50 == 0 ? 0.22 : 0.08)) }
        for y in stride(from: y0, through: y1, by: 10) { seg(CGPoint(x: x0, y: y), CGPoint(x: x1, y: y), 0.6, line.cg(Int((y - y0).rounded()) % 50 == 0 ? 0.22 : 0.08)) }
        rrect(CGRect(x: 8, y: 8, width: 264, height: 440), 2, stroke: line.cg(0.8), lw: 1.5)
        // Dimension line above the time.
        let dy: CGFloat = 112
        seg(CGPoint(x: 22, y: dy), CGPoint(x: 258, y: dy), 1, line.cg(0.8))
        poly([CGPoint(x: 22, y: dy), CGPoint(x: 30, y: dy - 3.5), CGPoint(x: 30, y: dy + 3.5)], line.cg(0.8))
        poly([CGPoint(x: 258, y: dy), CGPoint(x: 250, y: dy - 3.5), CGPoint(x: 250, y: dy + 3.5)], line.cg(0.8))
        bg.fill(col(0).cg(), CGRect(x: 100, y: dy - 8, width: 80, height: 16))
        bg.text("TIME · 1:1", font: "mono", size: 10, color: line.cg(), in: CGRect(x: 100, y: dy - 7, width: 80, height: 14))
        for y in [126.0, 246.0] as [CGFloat] { for x in stride(from: CGFloat(14), to: 266, by: 8) { seg(CGPoint(x: x, y: y), CGPoint(x: x + 4, y: y), 0.8, line.cg(0.5)) } }
        let dg = plainDigits(58, 116, color: line, font: d.font, outlineOnly: true, lw: 2), ac = plainDigits(58, 116, color: acc, font: d.font, outlineOnly: true, lw: 2)
        clock(ac, dg, [(18, 128), (76, 128), (146, 128), (204, 128)])
        for y in [168.0, 206.0] as [CGFloat] { ring(CGPoint(x: 140, y: y), 4, 1.5, line.cg()); seg(CGPoint(x: 133, y: y), CGPoint(x: 147, y: y), 0.8, line.cg()); seg(CGPoint(x: 140, y: y - 7), CGPoint(x: 140, y: y + 7), 0.8, line.cg()) }
        ring(CGPoint(x: 140, y: 300), 34, 1, line.cg(0.5)); seg(CGPoint(x: 96, y: 300), CGPoint(x: 184, y: 300), 0.7, line.cg(0.5)); seg(CGPoint(x: 140, y: 256), CGPoint(x: 140, y: 344), 0.7, line.cg(0.5))
        container([92, 262, 96, 76], DT.weather, [weatherIcon(36, 122, 266), text([104, 304, 72, 28], VT.temperature, "24°", line)])
        bg.text(["R 34", "Ø 68", "SECTION A-A", "DETAIL B", "REV. C"][v % 5], font: "mono", size: 9, color: line.cg(0.7), in: CGRect(x: 186, y: 262, width: 70, height: 12), align: 0)
        // Title block.
        let tb = CGRect(x: 14, y: 354, width: 252, height: 88)
        rrect(tb, 1, stroke: line.cg(), lw: 1.5)
        seg(CGPoint(x: tb.minX, y: tb.minY + 40), CGPoint(x: tb.maxX, y: tb.minY + 40), 1, line.cg())
        for x in [tb.minX + 84, tb.minX + 168] { seg(CGPoint(x: x, y: tb.minY + 40), CGPoint(x: x, y: tb.maxY), 1, line.cg()) }
        bg.text("DATE", font: "mono", size: 8, color: line.cg(0.7), in: CGRect(x: tb.minX + 4, y: tb.minY + 3, width: 40, height: 10), align: 0)
        dateRow(x: 72, y: 362, font: "mono", weekColor: acc, outline: false)
        let cells: [(String, Int, Int, String)] = [("HR", VT.heart, DT.heart, "72"), ("STEPS", VT.steps, DT.activity, "8426"), ("BATT", VT.battery, DT.battery, "88")]
        for (i, (lbl, value, dt, sample)) in cells.enumerated() {
            let cx = tb.minX + CGFloat(i) * 84
            bg.text(lbl, font: "mono", size: 8, color: line.cg(0.7), in: CGRect(x: cx + 4, y: tb.minY + 43, width: 60, height: 10), align: 0)
            container([I(cx) + 2, I(tb.minY) + 42, 80, 44], dt, [text([I(cx) + 6, I(tb.minY) + 54, 72, 28], value, sample, line)])
        }
    }

    func sSynth(_ v: Int) {
        let (x0, x1, y0, y1) = (-f.ox, 280 + f.ox, -f.oy, 456 + f.oy)
        let hz: CGFloat = 262
        bg.gradient([col(0), col(1)], in: CGRect(x: x0, y: y0, width: x1 - x0, height: hz - y0))
        var rng = RNG(abs(d.title.hashValueStable))
        for _ in 0 ..< 40 { dot(CGPoint(x: rng.range(Double(x0), Double(x1)), y: rng.range(Double(y0), 150)), CGFloat(rng.range(0.4, 1.2)), RGB(0xFFFFFF).cg(0.7)) }
        let sc = CGPoint(x: 140, y: 258), sr: CGFloat = 62
        let sunPath = CGPath(ellipseIn: CGRect(x: sc.x - sr, y: sc.y - sr, width: 2 * sr, height: 2 * sr), transform: nil)
        gradientIn(sunPath, [col(2), col(3)], CGRect(x: sc.x - sr, y: sc.y - sr, width: 2 * sr, height: 2 * sr))
        var gy = sc.y - 6, gh: CGFloat = 2
        while gy < hz { bg.fill(col(1).cg(), CGRect(x: sc.x - sr, y: gy, width: 2 * sr, height: gh)); gy += 9; gh += 1.2 }
        // Mountains.
        poly([CGPoint(x: x0, y: hz), CGPoint(x: 30, y: 214), CGPoint(x: 70, y: 240), CGPoint(x: 100, y: 222), CGPoint(x: 128, y: hz)], col(1).mix(RGB(0), 0.5).cg())
        poly([CGPoint(x: 160, y: hz), CGPoint(x: 196, y: 226), CGPoint(x: 222, y: 244), CGPoint(x: 252, y: 208), CGPoint(x: x1, y: 236), CGPoint(x: x1, y: hz)], col(1).mix(RGB(0), 0.5).cg())
        // Floor grid.
        bg.fill(RGB(0x0A0014).cg(), CGRect(x: x0, y: hz, width: x1 - x0, height: y1 - hz))
        var ly = hz, step: CGFloat = 4
        while ly < y1 { seg(CGPoint(x: x0, y: ly), CGPoint(x: x1, y: ly), 1.2, sec.cg(0.85)); ly += step; step *= 1.32 }
        for i in -12 ... 12 { seg(CGPoint(x: 140 + CGFloat(i) * 8, y: hz), CGPoint(x: 140 + CGFloat(i) * 70, y: y1), 1.2, sec.cg(0.7)) }
        seg(CGPoint(x: x0, y: hz), CGPoint(x: x1, y: hz), 2, sec.cg())
        let chrome = gradientDigits(62, 112, [RGB(0xFFFFFF), acc, fg], edge: RGB(0x1A0033), font: d.font)
        clock(chrome, chrome, [(12, 26), (70, 26), (148, 26), (206, 26)])
        colonDots(140, 64, 102, 5, acc.cg(), glow: acc.cg(0.25))
        let wk = glowLabels(weekdays, 90, 30, glow: sec, font: d.font)
        face.date.append(sel(wk, 50, 146, VT.week, label: 2, show: 5))
        let dd = labels((0 ... 9).map(String.init), 16, 30, sec.mix(RGB(0xFFFFFF), 0.5), font: d.font, size: 22, outline: false)
        face.date += [sel(Array(dd[0 ... 3]), 150, 146, VT.dayHi, label: 2, show: 1), sel(dd, 166, 146, VT.dayLo, label: 2, show: 3)]
        let mo = labels(months, 52, 30, sec.mix(RGB(0xFFFFFF), 0.5), font: d.font, size: 20, outline: false)
        face.date.append(sel(mo, 186, 146, VT.month, label: 2, show: 11))
        statRow(y: 372, [.heart, .steps, .battery])
    }
}

// MARK: - The designs (300 here, plus the Sporty set from Faces4.swift)

let styles3: [Style3] = baseStyles3 + sportStyles

let baseStyles3: [Style3] = [
    Style3(name: "Pilot", category: "Tool Watch", fonts: ["DINAlternate-Bold", "Futura-Bold", "AvenirNextCondensed-Heavy", "DINCondensed-Bold", "GillSans-Bold"], looks: [
        L("Aviator", [0x101010, 0x050505], 0x141414, 0xF2F2F2, 0xD9D9D9, 0xF2F2F2),
        L("Navigator", [0x0B1A2E, 0x050D18], 0x0F2340, 0xEDE6D6, 0xE8C872, 0xE8C872),
        L("Squadron", [0x1D2420, 0x111613], 0x222B25, 0xE9E4D0, 0xB9B08A, 0xE9E4D0),
        L("Night Flight", [0x050505, 0x000000], 0x0A0A0A, 0xB9F6CA, 0x69F0AE, 0xFF6E40),
        L("Desert Pilot", [0x8C6A43, 0x5E4428], 0xC8A979, 0x2B1D0E, 0x5E4428, 0x8B1E1E),
        L("Stratos", [0x23395B, 0x161D3F], 0x2E4A7D, 0xFFFFFF, 0x9CC5FF, 0xFFB000),
        L("Bronze Bomber", [0x3B2A1A, 0x241A10], 0x4A3826, 0xF3E3C3, 0xC08A4A, 0xF3E3C3),
        L("White Wing", [0xE8E8E8, 0xCFCFCF], 0xF7F7F7, 0x151515, 0x555555, 0xD62828),
        L("Slate Pilot", [0x3A4149, 0x262B30], 0x4A525C, 0xF4F4F4, 0xA9B4C2, 0xFF8C42),
        L("Copper Cockpit", [0x1B1B1B, 0x0E0E0E], 0x262220, 0xF0D9B5, 0xC87F4A, 0xC87F4A),
    ], build: { $0.sPilot($1) }),
    Style3(name: "Diver", category: "Tool Watch", fonts: ["Futura-Bold", "DINAlternate-Bold", "AvenirNext-Heavy", "HelveticaNeue-CondensedBlack", "Futura-CondensedExtraBold"], looks: [
        L("Deep Blue", [0x02111B, 0x03203A, 0x0A1F44], 0x08305C, 0xF2F7FF, 0xC9D6E3, 0xFF5A1F),
        L("Abyss", [0x050505, 0x000000, 0x111111], 0x0B0B0B, 0xE8FFE8, 0xBFC7C9, 0xFF3B30),
        L("Reef Green", [0x032B23, 0x011A14, 0x0B3D2E], 0x0E4D3A, 0xF0FFF6, 0xD8D8D8, 0xFFD60A),
        L("Pepsi Bezel", [0x0B1730, 0x060E1E, 0x1B2A6B], 0x0D1B3A, 0xFFFFFF, 0xD0D0D0, 0xE63946),
        L("Sunburst Orange", [0x2A1406, 0x170A02, 0x111111], 0xE8590C, 0xFFFFFF, 0xF2F2F2, 0xFFFFFF),
        L("Tropic Yellow", [0x1C1C1C, 0x0D0D0D, 0x101010], 0xF4C430, 0x111111, 0x111111, 0x111111),
        L("Arctic Diver", [0xDDE7EE, 0xBACBD6, 0x1E2A38], 0xF6FAFC, 0x14212E, 0x14212E, 0x1E88E5),
        L("Bronze Diver", [0x2B2016, 0x17110B, 0x5B4126], 0x2E3B2C, 0xF0E7D0, 0xB08D57, 0xF0E7D0),
        L("Turquoise", [0x062A30, 0x03171A, 0x0A3D44], 0x0FA3A3, 0xFFFFFF, 0xEFEFEF, 0xFF6F61),
        L("Gilt Black", [0x0A0A0A, 0x000000, 0x1A1508], 0x0A0A0A, 0xF5E6B3, 0xD4AF37, 0xD4AF37),
    ], build: { $0.sDiver($1) }),
    Style3(name: "Chronograph", category: "Complications", fonts: ["AvenirNext-Heavy", "DINAlternate-Bold", "Futura-Bold", "HelveticaNeue-CondensedBlack", "Optima-ExtraBlack"], looks: [
        L("Panda", [0x1A1A1A, 0x0D0D0D], 0xF2F0EA, 0x161616, 0x161616, 0xD62828),
        L("Reverse Panda", [0x1A1A1A, 0x0D0D0D], 0x111111, 0xF2F2F2, 0xD9D9D9, 0xFF3B30),
        L("Racing Green", [0x0B2418, 0x06140D], 0x123524, 0xF4EFE1, 0xE9C46A, 0xF4A261),
        L("Grand Prix", [0x1C1C1C, 0x0A0A0A], 0xF7F7F7, 0x111111, 0xE10600, 0xE10600),
        L("Navy Chrono", [0x0B1A33, 0x050D1A], 0x13284D, 0xFFFFFF, 0x8FB3FF, 0xFFB703),
        L("Salmon Chrono", [0x2B1E1A, 0x1A1210], 0xF2B8A2, 0x2B1A14, 0x5D2E1F, 0x1D3557),
        L("Silver Sun", [0x2A2D31, 0x16181A], 0xD9DDE1, 0x1F2933, 0x3E4C59, 0xD62828),
        L("Teal Chrono", [0x062A2E, 0x02171A], 0x0B4F55, 0xF0FFFE, 0x7FE7DC, 0xFFB4A2),
        L("Chocolate", [0x2B1B12, 0x170E09], 0x4A2E1F, 0xF5E6D3, 0xD9A066, 0xD9A066),
        L("Ice Chrono", [0x1F3A4D, 0x0F1E28], 0xDCEEF7, 0x0E2A3B, 0x2B6C8F, 0xE76F51),
    ], build: { $0.sChrono($1) }),
    Style3(name: "Field", category: "Tool Watch", fonts: ["DINCondensed-Bold", "Futura-Bold", "AvenirNextCondensed-Heavy", "GillSans-Bold", "Rockwell-Bold"], looks: [
        L("Khaki Field", [0x3B3A26, 0x26251A], 0x4A4A30, 0xF1EBD8, 0xE7B75F, 0xE76F51),
        L("Olive Drab", [0x2F3524, 0x1C2015], 0x3D4630, 0xF0F0E0, 0xC5D86D, 0xFF7F50),
        L("Sand Field", [0x9C8463, 0x6E5B42], 0xD9C7A3, 0x2E2516, 0x7A5C33, 0xA62B1F),
        L("Black Field", [0x101010, 0x060606], 0x141414, 0xF3F3F3, 0xFFB000, 0xFFB000),
        L("Infantry Blue", [0x1A2433, 0x0E141D], 0x203148, 0xF5F1E6, 0xA3C4F3, 0xFFC857),
        L("Cream Field", [0xD6CBB5, 0xB5A98F], 0xF2EAD8, 0x1F1A12, 0x8C2F39, 0x8C2F39),
        L("Forest Scout", [0x14281D, 0x0B170F], 0x1C3829, 0xEDF6E9, 0x95D5B2, 0xFF9F1C),
        L("Rust Ranger", [0x3A1F14, 0x22120B], 0x5A2E1D, 0xF7E7D6, 0xF4A261, 0xF4A261),
        L("Slate Field", [0x2D3436, 0x1B2021], 0x3D4648, 0xEDEDED, 0x81ECEC, 0xFDCB6E),
        L("Tan Expedition", [0x5C4A32, 0x3A2F20], 0x7A6445, 0xFFF4E0, 0xFFD27F, 0xFFFFFF),
    ], build: { $0.sField($1) }),
    Style3(name: "Railway", category: "Dress & Design", fonts: ["HelveticaNeue-CondensedBlack"], looks: [
        L("Platform", [0xD9D9D9, 0xBFBFBF], 0xFFFFFF, 0x111111, 0x111111, 0xD62828),
        L("Night Platform", [0x111111, 0x050505], 0x121212, 0xF2F2F2, 0xF2F2F2, 0xFF3B30),
        L("Station Cream", [0xC9BFA8, 0xA89F88], 0xF4EEDF, 0x1F1F1F, 0x1F1F1F, 0xC1121F),
        L("Signal Yellow", [0x2A2A2A, 0x111111], 0xF6C343, 0x111111, 0x111111, 0x111111),
        L("Blue Line", [0x0C2340, 0x061224], 0xFFFFFF, 0x0C2340, 0x0C2340, 0xE63946),
        L("Green Line", [0x0D3B2E, 0x062018], 0xF4F4F0, 0x0D3B2E, 0x0D3B2E, 0xF77F00),
        L("Concourse", [0x6C757D, 0x495057], 0xF8F9FA, 0x212529, 0x212529, 0x0D6EFD),
        L("Red Line", [0x590D0D, 0x330606], 0xFFFFFF, 0x111111, 0x111111, 0xC1121F),
        L("Terminal Grey", [0x3A3A3A, 0x1F1F1F], 0x2B2B2B, 0xEDEDED, 0xEDEDED, 0xFFB703),
        L("Mint Station", [0xA8DADC, 0x7FB7BA], 0xF1FAEE, 0x1D3557, 0x1D3557, 0xE63946),
    ], build: { $0.sRailway($1) }),
    Style3(name: "Bauhaus", category: "Dress & Design", fonts: ["Futura-Medium", "HelveticaNeue-Thin", "Avenir-Light", "GillSans-Light", "AvenirNext-UltraLight"], looks: [
        L("Dessau", [0xE9E5DC, 0xD5D0C4], 0xF5F2EA, 0x1A1A1A, 0xC1121F, 0xC1121F),
        L("Weimar", [0x1A1A1A, 0x0D0D0D], 0x1E1E1E, 0xF2F2F2, 0xF2C230, 0xF2C230),
        L("Max", [0xF1EFE9, 0xDAD6CC], 0xFBFAF7, 0x222222, 0x2B59C3, 0xE4572E),
        L("Linie", [0x23395B, 0x172640], 0xF7F5EF, 0x23395B, 0x23395B, 0xF46036),
        L("Form", [0xD8C3A5, 0xBFA888], 0xEFE3CF, 0x3B2F2F, 0x8E443D, 0x8E443D),
        L("Kandinsky Blue", [0x0F4C81, 0x0A3459], 0x0F4C81, 0xFFFFFF, 0xF2C230, 0xF25C54),
        L("Graphite Bauhaus", [0x3C3C3C, 0x2A2A2A], 0x464646, 0xEFEFEF, 0xA0A0A0, 0xFF7F11),
        L("Sage Bauhaus", [0xA3B18A, 0x87956E], 0xDAD7CD, 0x344E41, 0x588157, 0xBC4749),
        L("Rose Bauhaus", [0xE8C4C4, 0xD4A5A5], 0xF6E7E7, 0x4A2B2B, 0x9E4A4A, 0x2B4A9E),
        L("Black Bauhaus", [0x000000, 0x000000], 0x000000, 0xFFFFFF, 0xFFFFFF, 0xFF2D2D),
    ], build: { $0.sBauhaus($1) }),
    Style3(name: "Sector", category: "Dress & Design", fonts: ["Futura-Bold", "GillSans-Bold", "AvenirNext-Heavy", "Didot-Bold", "DINAlternate-Bold"], looks: [
        L("Sector Silver", [0x2F3236, 0x1C1E21], 0xE6E4DE, 0x1B1B1B, 0x8A8A8A, 0x1D4ED8),
        L("Sector Black", [0x0D0D0D, 0x050505], 0x141414, 0xF2EEE3, 0x3A3A3A, 0xE9C46A),
        L("Sector Salmon", [0x3A2A26, 0x221815], 0xF0B8A0, 0x2B1A14, 0xC97B63, 0x1D3557),
        L("Sector Blue", [0x0E1F3A, 0x081325], 0x1F3B6B, 0xF2F2F2, 0x3E5F96, 0xFFB703),
        L("Sector Cream", [0x8C7B62, 0x5E5241], 0xF2E8D5, 0x2E2A24, 0xC9B79C, 0x9B2226),
        L("Sector Green", [0x15291F, 0x0B1610], 0x1E3D2E, 0xEFF5EC, 0x3E6B55, 0xF4A261),
        L("Sector Grey", [0x52575D, 0x373B40], 0xC9CDD1, 0x1D1F21, 0x8D949C, 0xD62828),
        L("Sector Teal", [0x093C3F, 0x042325], 0xD7EFEF, 0x093C3F, 0x6FB7B7, 0xE76F51),
        L("Sector Ivory", [0x3B3B3B, 0x262626], 0xFFFDF5, 0x222222, 0xD8D2C0, 0xC1121F),
        L("Sector Plum", [0x2A1530, 0x170B1B], 0x4A2654, 0xF7EEFA, 0x7B4A87, 0xFFD166),
    ], build: { $0.sSector($1) }),
    Style3(name: "GMT", category: "Tool Watch", fonts: ["Futura-Bold", "DINAlternate-Bold", "AvenirNext-Heavy", "HelveticaNeue-CondensedBlack"], looks: [
        L("Day Night", [0x0A0A0A, 0x000000, 0x1E5AA8, 0x111111], 0x0A0A0A, 0xFFFFFF, 0xFFC300, 0xFFC300),
        L("Root Beer", [0x1A0F08, 0x0D0704, 0xB5835A, 0x3B2414], 0x111111, 0xF5E6D3, 0xD4A373, 0xD4A373),
        L("Batman Style", [0x0A0A0A, 0x000000, 0x111111, 0x1E3A8A], 0x0B0B0B, 0xFFFFFF, 0x4C8DFF, 0x4C8DFF),
        L("Sprite", [0x0A0A0A, 0x000000, 0x1E7B3C, 0x111111], 0x0B0B0B, 0xFFFFFF, 0x2ECC71, 0x2ECC71),
        L("Coke Bezel", [0x0A0A0A, 0x000000, 0xC1121F, 0x111111], 0x0B0B0B, 0xFFFFFF, 0xC1121F, 0xC1121F),
        L("Polar GMT", [0x2B2B2B, 0x151515, 0xE9ECEF, 0x343A40], 0xF8F9FA, 0x111111, 0xFF6B00, 0xFF6B00),
        L("Ocean GMT", [0x04263D, 0x021624, 0x5FA8D3, 0x0B2545], 0x0B2545, 0xFFFFFF, 0xF4D35E, 0xF4D35E),
        L("Dawn GMT", [0x1B1B1B, 0x0E0E0E, 0xFFB4A2, 0x2D3047], 0x2D3047, 0xFFFFFF, 0xFF8C61, 0xFF8C61),
        L("Gilt GMT", [0x0A0A0A, 0x000000, 0xC9A227, 0x231A05], 0x0A0A0A, 0xF5E6B3, 0xD4AF37, 0xD4AF37),
        L("Meteor GMT", [0x1F2326, 0x101314, 0x9AA5B1, 0x3E4C59], 0x323F4B, 0xF5F7FA, 0x7BD3EA, 0x7BD3EA),
    ], build: { $0.sGMT($1) }),
    Style3(name: "Enamel", category: "Complications", fonts: ["Didot-Bold", "BodoniSvtyTwoITCTT-Bold", "Baskerville-Bold", "HoeflerText-Black", "Cochin-Bold"], looks: [
        L("Grand Feu", [0x2B2B2B, 0x1A1A1A], 0xFBF8EF, 0x1A1A1A, 0xC9A227, 0x1D3B8F),
        L("Porcelain", [0x3E3A36, 0x262320], 0xFFFFFF, 0x2B2B2B, 0xB08D57, 0x1D3B8F),
        L("Midnight Enamel", [0x05091A, 0x02040D], 0x0D1A3A, 0xF2E6C9, 0xD4AF37, 0xD4AF37),
        L("Celadon", [0x2E3B36, 0x1C2421], 0xCFE3D6, 0x1F2E28, 0x8C7853, 0x8C2F39),
        L("Burgundy Enamel", [0x2A0A10, 0x16050A], 0x5C1424, 0xF5E6D3, 0xD4AF37, 0xF5E6D3),
        L("Ivory Breguet", [0x4A4034, 0x2E2820], 0xF6EFDF, 0x2A2420, 0x8B6B3D, 0x2D4D8B),
        L("Slate Enamel", [0x22272C, 0x13171A], 0x3D4650, 0xF0F0F0, 0xC0C7CF, 0xE8C872),
        L("Rose Gold", [0x3A2A28, 0x221816], 0xF7E1D7, 0x4A2C2A, 0xB76E79, 0x4A2C2A),
        L("Black Lacquer", [0x000000, 0x000000], 0x070707, 0xF2F2F2, 0xC9A227, 0xC9A227),
        L("Lapis", [0x0B1E4A, 0x061230], 0x163A85, 0xF5F0E1, 0xE5C76B, 0xE5C76B),
    ], build: { $0.sEnamel($1) }),
    Style3(name: "Skeleton", category: "Complications", fonts: ["Optima-ExtraBlack", "Didot-Bold", "Futura-Bold", "AvenirNext-Heavy"], looks: [
        L("Open Heart", [0x0A0A0A, 0x050505, 0xB8B8B8, 0x6E6E6E], 0x0B0B0B, 0xF2F2F2, 0x5DADE2, 0xE74C3C),
        L("Rose Movement", [0x150B0B, 0x0B0505, 0xD4A08A, 0x8C5A4A], 0x120909, 0xF7E1D7, 0xF7E1D7, 0xE8C872),
        L("Gilded Works", [0x0D0A04, 0x060402, 0xD4AF37, 0x8C6D1F], 0x0D0A04, 0xF5E6B3, 0xF5E6B3, 0xF5E6B3),
        L("Blue Steel", [0x05080F, 0x020408, 0x7FA7D9, 0x3A5A8C], 0x060A12, 0xE6EEF8, 0xE6EEF8, 0xFF8C42),
        L("Gunmetal", [0x101214, 0x08090A, 0x8A9097, 0x4A5057], 0x111315, 0xF2F2F2, 0xFFB703, 0xFFB703),
        L("Bronze Gears", [0x120D08, 0x080503, 0xC08A4A, 0x7A5530], 0x120D08, 0xF3E3C3, 0xF3E3C3, 0x2EC4B6),
        L("Titanium", [0x1A1D20, 0x0E1011, 0xC9CED3, 0x7D848B], 0x1B1E21, 0xFFFFFF, 0x4CC9F0, 0x4CC9F0),
        L("Ruby Jewels", [0x140507, 0x0A0203, 0xBFBFBF, 0x7A2A35], 0x140507, 0xFFFFFF, 0xFF4D6D, 0xFF4D6D),
        L("Green Works", [0x07120D, 0x030906, 0x9CC5A1, 0x49796B], 0x07120D, 0xEFFFF4, 0xEFFFF4, 0xFFC857),
        L("White Skeleton", [0xE8E8E8, 0xD0D0D0, 0x7A7A7A, 0xA8A8A8], 0xF3F3F3, 0x1A1A1A, 0x1D4ED8, 0xD62828),
    ], build: { $0.sSkeleton($1) }),
    Style3(name: "Regulator", category: "Complications", fonts: ["Didot-Bold", "Baskerville-Bold", "Futura-Bold", "DINAlternate-Bold", "GillSans-Bold"], looks: [
        L("Regulateur", [0x2A2A2A, 0x161616], 0xF6F1E5, 0x1C1C1C, 0x8C2F39, 0x1D3B8F),
        L("Observatory", [0x050B1A, 0x02050D], 0x0F1E3D, 0xEFE6D2, 0xD4AF37, 0xD4AF37),
        L("Chronometer", [0x1E1E1E, 0x0F0F0F], 0xFFFFFF, 0x111111, 0x555555, 0xC1121F),
        L("Marine", [0x0A2340, 0x051426], 0xE9EEF2, 0x0A2340, 0x2E5C8A, 0xE63946),
        L("Sage Regulator", [0x2A3328, 0x161C15], 0xD8E2D0, 0x1F2A1C, 0x5A7A4F, 0xB5651D),
        L("Onyx Regulator", [0x050505, 0x000000], 0x0E0E0E, 0xF2F2F2, 0x9A9A9A, 0xFFB703),
        L("Cognac", [0x2A160A, 0x150A04], 0x6B3A1E, 0xF8E8D4, 0xE0A458, 0xF8E8D4),
        L("Mint Regulator", [0x1F3A36, 0x10201D], 0xCFF5EC, 0x0F2A25, 0x2A9D8F, 0xE76F51),
        L("Lavender", [0x2E2440, 0x1A1426], 0xE6DDF5, 0x2E2440, 0x7B68A6, 0xE07A5F),
        L("Steel Regulator", [0x2E353B, 0x191D21], 0x8E99A4, 0x0F1418, 0x1F2A33, 0xF4F4F4),
    ], build: { $0.sRegulator($1) }),
    Style3(name: "Single Hand", category: "Dress & Design", fonts: ["Futura-Medium", "Didot-Bold", "GillSans-Bold", "Optima-Bold", "AvenirNext-Medium"], looks: [
        L("Solo", [0x1A1A1A, 0x0D0D0D], 0xF4F1EA, 0x1A1A1A, 0xC1121F, 0xC1121F),
        L("Slow Black", [0x000000, 0x000000], 0x0A0A0A, 0xF2F2F2, 0xFF8C00, 0xFF8C00),
        L("Uno Blue", [0x0E2A47, 0x07182A], 0x153D66, 0xF7F7F7, 0xFFD166, 0xFFD166),
        L("Calm Sage", [0x3E4A3D, 0x272F26], 0xC8D5B9, 0x2F3E2E, 0x8F5E3B, 0x8F5E3B),
        L("Hours Sand", [0x6E5C45, 0x4A3D2D], 0xE9DCC5, 0x3B2F22, 0xB5523B, 0xB5523B),
        L("Slow Red", [0x3A0A0A, 0x220505], 0x8B1E1E, 0xFFF1E6, 0xFFD6A5, 0xFFD6A5),
        L("Lazy Grey", [0x4A4E54, 0x30333A], 0xD9DCE0, 0x1F2226, 0x2E86AB, 0x2E86AB),
        L("Moss", [0x1E2A1C, 0x111810], 0x2E4029, 0xEEF5E6, 0xC9E265, 0xC9E265),
        L("Pebble", [0xB8B2A7, 0x99938A], 0xEDE9E2, 0x2B2B2B, 0xE76F51, 0xE76F51),
        L("Ink Solo", [0x0D1321, 0x060A12], 0x1D2D44, 0xF0EBD8, 0x748CAB, 0xF0EBD8),
    ], build: { $0.sSingle($1) }),
    Style3(name: "Compass", category: "Tool Watch", fonts: ["Futura-Bold", "GillSans-Bold", "Copperplate-Bold", "Optima-ExtraBlack", "DINAlternate-Bold"], looks: [
        L("True North", [0x1A1A1A, 0x0D0D0D], 0xEFE8D8, 0x1E1E1E, 0x5C4B37, 0xC1121F),
        L("Expedition", [0x1F2A1C, 0x111810], 0x2B3A28, 0xF0EAD6, 0xB8A27A, 0xE63946),
        L("Mariner", [0x0A2340, 0x051426], 0x0F3057, 0xF5F5F5, 0x7FB3D5, 0xFF6B35),
        L("Bearing", [0x2B2B2B, 0x151515], 0x1F1F1F, 0xF2F2F2, 0x9E9E9E, 0xFFB703),
        L("Desert Compass", [0x7A5C3A, 0x4E3A24], 0xE8D5B5, 0x3A2A18, 0xA0703A, 0x0B6E4F),
        L("Polar Star", [0x0B132B, 0x050A18], 0x1C2541, 0xFFFFFF, 0x5BC0BE, 0xFF5E5B),
        L("Brass Compass", [0x2A1E0E, 0x150F07], 0x3A2A12, 0xF5E6B3, 0xC9A227, 0xF25F5C),
        L("Orienteer", [0xF2F2F2, 0xD9D9D9], 0xFFFFFF, 0x111111, 0xFF6B00, 0xFF6B00),
        L("Glacier", [0xC9DCE6, 0xA6C3D1], 0xEAF4F8, 0x0E2A3B, 0x5A8FA8, 0xD62828),
        L("Trail", [0x2E3B2F, 0x1A221B], 0x3E5040, 0xF4F1DE, 0xE07A5F, 0xF2CC8F),
    ], build: { $0.sCompass($1) }),
    Style3(name: "Radar", category: "Novelty", fonts: ["mono"], looks: [
        L("Sonar", [0x020B05, 0x000000], 0x03140A, 0x7CFFB2, 0x2EE87A, 0xC6FF4D),
        L("Amber Scope", [0x0D0700, 0x000000], 0x170D00, 0xFFD38A, 0xFFB000, 0xFF6A00),
        L("Ice Radar", [0x020A12, 0x000000], 0x041826, 0xB8F2FF, 0x3FD0FF, 0xFFFFFF),
        L("Red Alert", [0x120202, 0x000000], 0x1F0505, 0xFFB3B3, 0xFF3B3B, 0xFFE066),
        L("Violet Scope", [0x0C0414, 0x000000], 0x170A26, 0xE4C8FF, 0xB15CFF, 0x7CFFB2),
        L("Weather Radar", [0x041016, 0x000000], 0x082430, 0xE0FBFC, 0x00C2A8, 0xFF8C42),
        L("Night Vision", [0x050A02, 0x000000], 0x0C1A05, 0xD8FF9E, 0x9CFF2E, 0xFFFFFF),
        L("Tactical", [0x111311, 0x060706], 0x1C211C, 0xE8EDE3, 0xA8C69F, 0xFF6B35),
        L("Ocean Sonar", [0x011627, 0x000814], 0x02253F, 0xCDEFFF, 0x2EC4F1, 0xF9C74F),
        L("Cyan Ping", [0x001014, 0x000000], 0x00222A, 0xD9FFFF, 0x00F5FF, 0xFF4D9D),
    ], build: { $0.sRadar($1) }),
    Style3(name: "Planets", category: "Novelty", fonts: ["Futura-Bold"], looks: [
        L("Solar System", [0x02030A, 0x070A1F, 0xFFB703], 0x02030A, 0xE9ECF5, 0x4EA8DE, 0xE76F51),
        L("Red Planet", [0x0A0302, 0x1A0805, 0xFF6B35], 0x0A0302, 0xFFE8D6, 0xC1440E, 0xF4A261),
        L("Gas Giant", [0x05040A, 0x14102A, 0xFFD166], 0x05040A, 0xF2EEFF, 0xE0A458, 0x8D99AE),
        L("Ice World", [0x02070C, 0x0A1A2A, 0xBDE0FE], 0x02070C, 0xE7F6FF, 0x8ECAE6, 0xFFFFFF),
        L("Nebula Orbit", [0x0B0218, 0x24063D, 0xFF5DA2], 0x0B0218, 0xF8E8FF, 0xC77DFF, 0x72EFDD),
        L("Emerald Moon", [0x010806, 0x07201A, 0xB7E4C7], 0x010806, 0xE9FFF4, 0x52B788, 0xFFD60A),
        L("Blue Giant", [0x01030D, 0x061442, 0x9EC5FF], 0x01030D, 0xFFFFFF, 0x4361EE, 0xF72585),
        L("Saturn Gold", [0x070502, 0x1A1306, 0xFFE8A3], 0x070502, 0xFFF6DB, 0xE9C46A, 0xF4A261),
        L("Deep Space", [0x000000, 0x050505, 0xFFFFFF], 0x000000, 0xF2F2F2, 0xADB5BD, 0xFF4D4D),
        L("Sunset Orbit", [0x0F0518, 0x2A0A2E, 0xFF9E00], 0x0F0518, 0xFFF0E5, 0xFF6D00, 0x00BBF9),
    ], build: { $0.sPlanets($1) }),
    Style3(name: "Vinyl", category: "Novelty", fonts: ["Futura-Bold", "AmericanTypewriter-Bold", "Cochin-Bold", "Rockwell-Bold", "GillSans-Bold"], looks: [
        L("Side A", [0x2A2A2A, 0x111111, 0xBFBFBF, 0x7A7A7A], 0x0A0A0A, 0xF2F2F2, 0xE63946, 0xFFFFFF),
        L("Blue Note", [0x0B1A33, 0x050D1A, 0xC0C0C0, 0x707070], 0x070707, 0xF2F2F2, 0x1D4ED8, 0xFFFFFF),
        L("Jazz Club", [0x1A120B, 0x0D0905, 0xD4AF37, 0x8C6D1F], 0x080604, 0xF5E6B3, 0xF2C14E, 0x2B1B0E),
        L("Pink Pressing", [0x2A0F1E, 0x170810, 0xDDDDDD, 0x888888], 0x150812, 0xFFE3F1, 0xFF4D9D, 0xFFFFFF),
        L("Green Groove", [0x0B1F14, 0x05110A, 0xCCCCCC, 0x777777], 0x060E09, 0xEFFFF4, 0x2EC27E, 0x0B1F14),
        L("Orange Label", [0x231309, 0x140A04, 0xBBBBBB, 0x666666], 0x0A0A0A, 0xFFF2E5, 0xFF7F11, 0x1A1A1A),
        L("White Album", [0xE6E6E6, 0xCCCCCC, 0x9A9A9A, 0x5A5A5A], 0x111111, 0xF2F2F2, 0xF7F7F7, 0x111111),
        L("Yellow Sub", [0x1A1A0A, 0x0D0D05, 0xBFBFBF, 0x777777], 0x0B0B0B, 0xF2F2F2, 0xFFD400, 0x111111),
        L("Purple Haze", [0x1A0B26, 0x0D0514, 0xCCCCCC, 0x777777], 0x0C0612, 0xF5E8FF, 0x9D4EDD, 0xFFFFFF),
        L("Teal Pressing", [0x062626, 0x031414, 0xCCCCCC, 0x777777], 0x041818, 0xE0FFFF, 0x14B8A6, 0xFFFFFF),
    ], build: { $0.sVinyl($1) }),
    Style3(name: "Nixie", category: "Retro Tech", fonts: ["thin", "HelveticaNeue-Thin", "GillSans-Light", "Futura-Medium", "AvenirNext-UltraLight"], looks: [
        L("Nixie Orange", [0x140B05, 0x080402, 0x2A1A0E], 0x2A1A0E, 0xFFB86B, 0xFF7A1A, 0xFF7A1A),
        L("Walnut Nixie", [0x2B1A0E, 0x170D06, 0x4A2E18], 0x4A2E18, 0xFFC285, 0xFF8A2A, 0xFF8A2A),
        L("Steel Nixie", [0x111315, 0x060708, 0x2A2E33], 0x2A2E33, 0xFFB070, 0xFF6F1A, 0xFF6F1A),
        L("Blue Glow Tube", [0x050A14, 0x02050A, 0x0F1A2E], 0x0F1A2E, 0xA8D8FF, 0x3FA9FF, 0x3FA9FF),
        L("Green Tube", [0x050F08, 0x020804, 0x10261A], 0x10261A, 0xB8FFCF, 0x29E07A, 0x29E07A),
        L("Pink Tube", [0x14050D, 0x0A0207, 0x2E0C1E], 0x2E0C1E, 0xFFB3D9, 0xFF3D9A, 0xFF3D9A),
        L("Copper Nixie", [0x1A0D06, 0x0D0603, 0x5A2E14], 0x5A2E14, 0xFFC9A3, 0xFF8C42, 0xFF8C42),
        L("Black Box", [0x000000, 0x000000, 0x141414], 0x141414, 0xFFB86B, 0xFF7A1A, 0xFF7A1A),
        L("Violet Tube", [0x0C0514, 0x05020A, 0x241040], 0x241040, 0xE3C7FF, 0xA855F7, 0xA855F7),
        L("Ice Tube", [0x06121A, 0x02080D, 0x163447], 0x163447, 0xDDF6FF, 0x67E8F9, 0x67E8F9),
    ], build: { $0.sNixie($1) }),
    Style3(name: "Flip Clock", category: "Retro Tech", fonts: ["HelveticaNeue-CondensedBlack", "Futura-Bold", "DINAlternate-Bold", "AvenirNextCondensed-Heavy", "Rockwell-Bold"], looks: [
        L("Flip Black", [0x2B2B2B, 0x151515], 0x1C1C1C, 0xF2F2F2, 0xFF9F0A, 0xFF9F0A),
        L("Flip White", [0xDADADA, 0xBDBDBD], 0xF7F7F7, 0x1A1A1A, 0xD62828, 0xD62828),
        L("Retro Orange", [0x3A2210, 0x22140A], 0xF28C28, 0xFFFFFF, 0xFFE8CC, 0xFFE8CC),
        L("Teal Flip", [0x0E3B3B, 0x072222], 0x125E5E, 0xEFFFFF, 0xFFD166, 0xFFD166),
        L("Departure", [0x0A0A0A, 0x000000], 0x161616, 0xFFD400, 0xFFFFFF, 0xFFFFFF),
        L("Mint Flip", [0xBFE8DA, 0x9BD3C1], 0x2A6F5F, 0xFFFFFF, 0x0B3D33, 0x0B3D33),
        L("Red Flip", [0x2A0606, 0x150303], 0xB3261E, 0xFFFFFF, 0xFFD6D6, 0xFFD6D6),
        L("Navy Flip", [0x0B1A33, 0x050D1A], 0x18315C, 0xF2F2F2, 0x8FB3FF, 0x8FB3FF),
        L("Wood Flip", [0x5A3A22, 0x3A2412], 0x2B1D12, 0xF5E6D3, 0xE0A458, 0xE0A458),
        L("Pastel Flip", [0xFFE5EC, 0xFFC2D1], 0xFFFFFF, 0x3D3B8E, 0xFB6F92, 0xFB6F92),
    ], build: { $0.sFlip($1) }),
    Style3(name: "Dot Matrix", category: "Retro Tech", fonts: ["mono"], looks: [
        L("LED Red", [0x0A0000, 0x000000, 0x140303], 0x140303, 0xFFB3B3, 0xFF2D2D, 0xFF8080),
        L("LED Amber", [0x0A0600, 0x000000, 0x140C00], 0x140C00, 0xFFE2B3, 0xFFB000, 0xFFD27F),
        L("LED Green", [0x000A03, 0x000000, 0x001405], 0x001405, 0xB3FFC8, 0x2DFF6A, 0x9BFFB8),
        L("LED Blue", [0x00040A, 0x000000, 0x000A1A], 0x000A1A, 0xB3D9FF, 0x2D9BFF, 0x80C4FF),
        L("LED White", [0x050505, 0x000000, 0x111111], 0x111111, 0xFFFFFF, 0xF2F2F2, 0xFFB000),
        L("Bus Sign", [0x050505, 0x000000, 0x0D0D0D], 0x0D0D0D, 0xFFE066, 0xFFC300, 0xFF7A00),
        L("Arcade", [0x0A0014, 0x000000, 0x140028], 0x140028, 0xFFD6FF, 0xFF4DFF, 0x4DFFFF),
        L("Scoreboard", [0x0A0A0A, 0x000000, 0x1A1A1A], 0x1A1A1A, 0xFFFFFF, 0xFFD000, 0xFF3D3D),
        L("Cyan LED", [0x000A0A, 0x000000, 0x001414], 0x001414, 0xB3FFFF, 0x00E5FF, 0x80F2FF),
        L("Pink LED", [0x0A0006, 0x000000, 0x14000C], 0x14000C, 0xFFB3DD, 0xFF2D95, 0xFF80C0),
    ], build: { $0.sDotMatrix($1) }),
    Style3(name: "Pixel", category: "Retro Tech", fonts: ["mono"], looks: [
        L("Overworld", [0x5C94FC, 0x9CC8FF, 0xFFFFFF, 0xFFD54F], 0, 0xFFFFFF, 0x2E7D32, 0xFFFFFF),
        L("Sunset Level", [0xFF7E5F, 0xFEB47B, 0xFFFFFF, 0xFFF176], 0, 0xFFFFFF, 0xC2185B, 0xFFFFFF),
        L("Night Level", [0x0B1026, 0x2B3A67, 0xFFFFFF, 0xF5F5F5], 0, 0xFFF59D, 0x7E57C2, 0xFFFFFF),
        L("Cave", [0x1B1B1B, 0x3A3A3A, 0xFFFFFF, 0xFFB300], 0, 0xFFE082, 0x8D6E63, 0xFFFFFF),
        L("Candy Land", [0xFFB6D9, 0xFFE0F0, 0xFFFFFF, 0xFFF59D], 0, 0x6A1B9A, 0xE91E63, 0xFFFFFF),
        L("Snow Level", [0xB3E5FC, 0xE1F5FE, 0xFFFFFF, 0xFFF9C4], 0, 0x0D47A1, 0x0288D1, 0xFFFFFF),
        L("Lava Level", [0x3E0A0A, 0x8B1E1E, 0xFFB199, 0xFFC107], 0, 0xFFE0B2, 0xFF5722, 0xFFFFFF),
        L("Forest Level", [0x2E7D32, 0x81C784, 0xFFFFFF, 0xFFEB3B], 0, 0xFFFFFF, 0x1B5E20, 0xFFFFFF),
        L("Space Level", [0x000010, 0x1A1040, 0xCCCCFF, 0xFFFFFF], 0, 0x80DEEA, 0xAB47BC, 0xFFFFFF),
        L("Desert Level", [0xFFCC80, 0xFFE0B2, 0xFFFFFF, 0xFF7043], 0, 0x4E342E, 0xBF360C, 0xFFFFFF),
    ], build: { $0.sPixel($1) }),
    Style3(name: "Binary", category: "Retro Tech", fonts: ["mono"], looks: [
        L("Bits", [0x0A0A0A, 0x000000], 0x0A0A0A, 0xF2F2F2, 0x00E5FF, 0xFF4D9D),
        L("Green Bits", [0x020A04, 0x000000], 0x020A04, 0xD9FFE4, 0x2EE87A, 0xC6FF4D),
        L("Amber Bits", [0x0D0700, 0x000000], 0x0D0700, 0xFFE6BF, 0xFFB000, 0xFF6A00),
        L("Paper Bits", [0xF4F1EA, 0xE6E1D6], 0xF4F1EA, 0x222222, 0x1D4ED8, 0xD62828),
        L("Purple Bits", [0x120720, 0x070310], 0x120720, 0xF0E0FF, 0xB15CFF, 0x5CE1E6),
        L("Red Bits", [0x140303, 0x050000], 0x140303, 0xFFE0E0, 0xFF3B3B, 0xFFB703),
        L("Ocean Bits", [0x021526, 0x000A14], 0x021526, 0xDFF3FF, 0x48CAE4, 0xF9C74F),
        L("Mono Bits", [0x1C1C1C, 0x0E0E0E], 0x1C1C1C, 0xFFFFFF, 0xFFFFFF, 0x8E8E93),
        L("Sunset Bits", [0x1A0A1A, 0x0D050D], 0x1A0A1A, 0xFFE8F0, 0xFF7B54, 0xFFD23F),
        L("Mint Bits", [0xE8F8F2, 0xD1F0E4], 0xE8F8F2, 0x0F3D2E, 0x10B981, 0x6366F1),
    ], build: { $0.sBinary($1) }),
    Style3(name: "Terminal", category: "Retro Tech", fonts: ["Menlo-Bold", "Courier-Bold", "PTMono-Bold", "mono", "AndaleMono"], looks: [
        L("Green Screen", [0x010A03, 0x000500], 0, 0x33FF66, 0xB3FFC6, 0x33FF66),
        L("Amber Screen", [0x0A0600, 0x050300], 0, 0xFFB000, 0xFFE0A3, 0xFFB000),
        L("White Phosphor", [0x0A0A0A, 0x050505], 0, 0xE8E8E8, 0xFFFFFF, 0xE8E8E8),
        L("Blue Basic", [0x1D2B8F, 0x1A257A], 0, 0xA9B8FF, 0xFFFFFF, 0xA9B8FF),
        L("Solar Dark", [0x002B36, 0x00212B], 0, 0x93A1A1, 0xB58900, 0x2AA198),
        L("Dracula Night", [0x282A36, 0x1E1F29], 0, 0xF8F8F2, 0xFF79C6, 0x50FA7B),
        L("Paper Terminal", [0xFDF6E3, 0xEEE8D5], 0, 0x586E75, 0xCB4B16, 0x268BD2),
        L("Matrix Rain", [0x000000, 0x000000], 0, 0x00FF41, 0x9BFFB8, 0x00FF41),
        L("Retro Mac", [0xEDEDED, 0xDADADA], 0, 0x111111, 0x111111, 0x111111),
        L("Cyber Pink", [0x12001A, 0x0A000F], 0, 0xFF6AD5, 0x8BE9FD, 0xFF6AD5),
    ], build: { $0.sTerminal($1) }),
    Style3(name: "Neon", category: "Art & Type", fonts: ["rounded", "Futura-Medium", "AvenirNext-Medium", "ArialRoundedMTBold", "GillSans-Light"], looks: [
        L("Neon Bar", [0x000000, 0x000000, 0x5A2A22, 0x2A1410], 0, 0xFFFFFF, 0xFF3CAC, 0x2BD2FF),
        L("Diner", [0x000000, 0x000000, 0x6B2E25, 0x2E1410], 0, 0xFFFFFF, 0x00F5D4, 0xFF4D6D),
        L("Motel", [0x000000, 0x000000, 0x3E3A5A, 0x1C1A2B], 0, 0xFFFFFF, 0xFF9F1C, 0x9B5DE5),
        L("Arcade Neon", [0x000000, 0x000000, 0x2B2B4A, 0x15152A], 0, 0xFFFFFF, 0x39FF14, 0xFF00FF),
        L("Night Club", [0x000000, 0x000000, 0x4A1F3D, 0x1F0C19], 0, 0xFFFFFF, 0xF72585, 0x4CC9F0),
        L("Cocktail", [0x000000, 0x000000, 0x5A3A22, 0x2A1A0E], 0, 0xFFFFFF, 0xFFD60A, 0xFF5D8F),
        L("Ice Neon", [0x000000, 0x000000, 0x3A4A5A, 0x1A222A], 0, 0xFFFFFF, 0x7DF9FF, 0xFFFFFF),
        L("Red Light", [0x000000, 0x000000, 0x4A1A1A, 0x220A0A], 0, 0xFFFFFF, 0xFF2E2E, 0xFFB3B3),
        L("Lime Neon", [0x000000, 0x000000, 0x2E3A22, 0x141A0E], 0, 0xFFFFFF, 0xC6FF00, 0x00E5FF),
        L("Violet Neon", [0x000000, 0x000000, 0x3A2A5A, 0x1A1230], 0, 0xFFFFFF, 0xB388FF, 0xFF80AB),
    ], build: { $0.sNeon($1) }),
    Style3(name: "Typographic", category: "Art & Type", fonts: ["Futura-CondensedExtraBold", "Didot-Bold", "HelveticaNeue-CondensedBlack", "BodoniSvtyTwoITCTT-Bold", "Impact", "Superclarendon-Black", "AvenirNextCondensed-Heavy", "Rockwell-Bold", "GillSans-Bold", "HoeflerText-Black"], looks: [
        L("Editorial", [0xF4F1EA, 0xF4F1EA], 0, 0x111111, 0xD62828, 0xD62828),
        L("Vogue Black", [0x000000, 0x000000], 0, 0xFFFFFF, 0xF2C14E, 0xF2C14E),
        L("Swiss Red", [0xE63946, 0xE63946], 0, 0xFFFFFF, 0x111111, 0x111111),
        L("Poster Blue", [0x1D3557, 0x1D3557], 0, 0xF1FAEE, 0xA8DADC, 0xA8DADC),
        L("Mustard", [0xF2C14E, 0xF2C14E], 0, 0x1A1A1A, 0xFFFFFF, 0xFFFFFF),
        L("Gazette", [0xE9E4D8, 0xE9E4D8], 0, 0x2B2B2B, 0x6B705C, 0x6B705C),
        L("Ultraviolet", [0x2D1E5F, 0x2D1E5F], 0, 0xF8F0FF, 0xFF6F91, 0xFF6F91),
        L("Mint Type", [0xCDEDE0, 0xCDEDE0], 0, 0x0B3D2E, 0xFF6B6B, 0xFF6B6B),
        L("Coral Type", [0xFF7F6A, 0xFF7F6A], 0, 0x1B1B3A, 0xFFF3E0, 0xFFF3E0),
        L("Ink Type", [0x0D1B2A, 0x0D1B2A], 0, 0xE0E1DD, 0x778DA9, 0x778DA9),
    ], build: { $0.sTypo($1) }),
    Style3(name: "Sideways", category: "Art & Type", fonts: ["Futura-CondensedExtraBold", "HelveticaNeue-CondensedBlack", "DINCondensed-Bold", "AvenirNextCondensed-Heavy", "Impact"], looks: [
        L("Tilt", [0x111111, 0x111111], 0, 0xF2F2F2, 0xFF5A36, 0xFF5A36),
        L("Lean Blue", [0x0B2545, 0x13315C], 0, 0xEEF4ED, 0x8DA9C4, 0x8DA9C4),
        L("Side Yellow", [0xFFD23F, 0xFFC300], 0, 0x111111, 0x5F0F40, 0x5F0F40),
        L("Turn White", [0xF7F7F2, 0xE4E6C3], 0, 0x222222, 0x2A9D8F, 0x2A9D8F),
        L("Quarter Pink", [0xFFC8DD, 0xFFAFCC], 0, 0x3A0CA3, 0x7209B7, 0x7209B7),
        L("Rotor Green", [0x081C15, 0x1B4332], 0, 0xD8F3DC, 0x74C69D, 0x74C69D),
        L("Lateral Red", [0x9D0208, 0x6A040F], 0, 0xFFE8D6, 0xFFBA08, 0xFFBA08),
        L("Askew Grey", [0x495057, 0x343A40], 0, 0xF8F9FA, 0xFFD166, 0xFFD166),
        L("Sideline", [0x003049, 0x001D2E], 0, 0xFCBF49, 0xF77F00, 0xF77F00),
        L("Tipped Lilac", [0xE0AAFF, 0xC77DFF], 0, 0x240046, 0xFFFFFF, 0xFFFFFF),
    ], build: { $0.sSideways($1) }),
    Style3(name: "Stencil", category: "Art & Type", fonts: ["Futura-CondensedExtraBold", "Impact", "DINCondensed-Bold", "HelveticaNeue-CondensedBlack", "Copperplate-Bold"], looks: [
        L("Woodland Camo", [0x3B4A2A, 0x2E3B20, 0x4F5F35, 0x1F2614], 0x2A3320, 0xF0E9D2, 0xE9C46A, 0xE9C46A),
        L("Desert Camo", [0xC2A878, 0xA88F60, 0xD9C397, 0x8A6E45], 0x5E4B2F, 0xF7EBD3, 0xFFB703, 0xFFB703),
        L("Urban Camo", [0x6C757D, 0x495057, 0xADB5BD, 0x343A40], 0x212529, 0xF8F9FA, 0xFF6B35, 0xFF6B35),
        L("Navy Camo", [0x1D2D44, 0x0D1321, 0x3E5C76, 0x748CAB], 0x0D1321, 0xF0EBD8, 0x9EC1E0, 0x9EC1E0),
        L("Arctic Camo", [0xE9ECEF, 0xCED4DA, 0xF8F9FA, 0xADB5BD], 0x343A40, 0xFFFFFF, 0x4DABF7, 0x4DABF7),
        L("Night Camo", [0x111111, 0x1E1E1E, 0x2B2B2B, 0x080808], 0x1A1A1A, 0xB7F2A1, 0x7FD858, 0x7FD858),
        L("Jungle Camo", [0x1B4332, 0x081C15, 0x2D6A4F, 0x40916C], 0x081C15, 0xFFFFFF, 0xFFD60A, 0xFFD60A),
        L("Tiger Stripe", [0x6B4F1D, 0x3A2A10, 0x8C6A2F, 0x1A1408], 0x1A1408, 0xF3E3C3, 0xF4A261, 0xF4A261),
        L("Pink Camo", [0xFFB3C6, 0xFF8FAB, 0xFFC2D1, 0xFB6F92], 0x590D22, 0xFFF0F3, 0xFFFFFF, 0xFFFFFF),
        L("Blue Digital", [0x5C7AEA, 0x3D56B2, 0x14279B, 0xE6E6E6], 0x14279B, 0xFFFFFF, 0xFFE066, 0xFFE066),
    ], build: { $0.sStencil($1) }),
    Style3(name: "Pop Art", category: "Art & Type", fonts: ["Impact", "Futura-CondensedExtraBold", "HelveticaNeue-CondensedBlack", "AvenirNextCondensed-Heavy", "Superclarendon-Black"], looks: [
        L("Pow Yellow", [0xFFE14D, 0xFFE14D, 0xFF4D4D], 0, 0xFFFFFF, 0xFF3B3B, 0x1D4ED8),
        L("Comic Blue", [0x4DA6FF, 0x4DA6FF, 0x1D4ED8], 0, 0xFFE14D, 0xFFFFFF, 0xFF3B3B),
        L("Bubblegum", [0xFF8FC7, 0xFF8FC7, 0xFF3D9A], 0, 0xFFFFFF, 0xFFE14D, 0x1D4ED8),
        L("Mint Pop", [0x7FFFD4, 0x7FFFD4, 0x00B386], 0, 0xFF4D6D, 0xFFFFFF, 0x1A1A1A),
        L("Orange Pop", [0xFF9F45, 0xFF9F45, 0xE85D04], 0, 0xFFFFFF, 0x6EE7F9, 0x1D4ED8),
        L("Lilac Pop", [0xC9A7FF, 0xC9A7FF, 0x8B5CF6], 0, 0xFFE14D, 0xFF5D8F, 0x111111),
        L("Red Pop", [0xFF4D4D, 0xFF4D4D, 0xB91C1C], 0, 0xFFE14D, 0xFFFFFF, 0x1D4ED8),
        L("Lime Pop", [0xC6FF4D, 0xC6FF4D, 0x65A30D], 0, 0xFF3D9A, 0xFFFFFF, 0x1A1A1A),
        L("Retro Teal", [0x2EC4B6, 0x2EC4B6, 0x0F766E], 0, 0xFFE14D, 0xFF6B6B, 0x111111),
        L("Halftone Mono", [0xF2F2F2, 0xF2F2F2, 0x9A9A9A], 0, 0xFFFFFF, 0xFFE14D, 0xFF3B3B),
    ], build: { $0.sPop($1) }),
    Style3(name: "Chalkboard", category: "Art & Type", fonts: ["Chalkduster", "ChalkboardSE-Bold", "MarkerFelt-Wide", "Noteworthy-Bold", "Chalkduster"], looks: [
        L("Classroom", [0x2F4F3E, 0x2F4F3E, 0x8B5A2B], 0, 0xF2F2F2, 0xFFE066, 0xFF8FAB),
        L("Blackboard", [0x1E1E1E, 0x1E1E1E, 0x6B4423], 0, 0xF2F2F2, 0x8EE3EF, 0xFFE066),
        L("Cafe Menu", [0x262626, 0x262626, 0x3E2723], 0, 0xFFF3E0, 0xFFB74D, 0xFF8A65),
        L("Slate Board", [0x37474F, 0x37474F, 0x8D6E63], 0, 0xECEFF1, 0x80DEEA, 0xFFAB91),
        L("Green Board", [0x1B5E20, 0x1B5E20, 0xA1887F], 0, 0xF1F8E9, 0xFFF59D, 0xF48FB1),
        L("Navy Board", [0x1A237E, 0x1A237E, 0x6D4C41], 0, 0xE8EAF6, 0xFFD54F, 0x80CBC4),
        L("Kids Board", [0x263238, 0x263238, 0xFFB300], 0, 0xFFFFFF, 0xFF80AB, 0x82B1FF),
        L("Bistro", [0x212121, 0x212121, 0x4E342E], 0, 0xFFFDE7, 0xA5D6A7, 0xFFCC80),
        L("Teal Board", [0x004D40, 0x004D40, 0x795548], 0, 0xE0F2F1, 0xFFE082, 0xFFAB91),
        L("Plum Board", [0x3E2723, 0x2B1D2B, 0x8D6E63], 0, 0xF3E5F5, 0xCE93D8, 0xFFE082),
    ], build: { $0.sChalk($1) }),
    Style3(name: "Blueprint", category: "Art & Type", fonts: ["Futura-Bold", "DINAlternate-Bold", "AvenirNext-Heavy", "Menlo-Bold", "GillSans-Bold"], looks: [
        L("Blueprint", [0x0B3D91, 0x0B3D91], 0, 0xE6F0FF, 0xFFE066, 0xFFE066),
        L("Whiteprint", [0xF5F7FA, 0xF5F7FA], 0, 0x1F4E8C, 0xD62828, 0xD62828),
        L("Cyanotype", [0x0F4C75, 0x0F4C75], 0, 0xBBE1FA, 0xFFFFFF, 0xFFFFFF),
        L("Draft Night", [0x0A1626, 0x0A1626], 0, 0x7FDBFF, 0xFF851B, 0xFF851B),
        L("Engineer Green", [0x0B3B2E, 0x0B3B2E], 0, 0xD8F3DC, 0xFFD166, 0xFFD166),
        L("Graph Paper", [0xFFFDF5, 0xFFFDF5], 0, 0x2E7D32, 0x1565C0, 0x1565C0),
        L("Red Pencil", [0xF2EFE9, 0xF2EFE9], 0, 0x3A3A3A, 0xC62828, 0xC62828),
        L("Patent", [0x1D3557, 0x1D3557], 0, 0xF1FAEE, 0xE63946, 0xE63946),
        L("Plotter", [0x111111, 0x111111], 0, 0x00E5FF, 0xFF4081, 0xFF4081),
        L("Sepia Draft", [0x3B2F2F, 0x3B2F2F], 0, 0xF2E3C9, 0xE9A23B, 0xE9A23B),
    ], build: { $0.sBlueprint($1) }),
    Style3(name: "Synthwave", category: "Art & Type", fonts: ["Futura-CondensedExtraBold", "AvenirNextCondensed-Heavy", "Impact", "HelveticaNeue-CondensedBlack", "Futura-Bold"], looks: [
        L("Outrun", [0x0D0221, 0x541388, 0xFFD319, 0xFF2975], 0, 0xFF2975, 0xFFD319, 0xFF00E4),
        L("Miami Night", [0x0B0033, 0x3D0066, 0xFFB86B, 0xFF4F8B], 0, 0x00E5FF, 0xFFB86B, 0x00E5FF),
        L("Vapor", [0x1A0A3D, 0xB967FF, 0xFFFB96, 0xFF71CE], 0, 0x01CDFE, 0xFFFB96, 0xFF71CE),
        L("Laser Grid", [0x050014, 0x2A0A5E, 0xF9F871, 0xFF6F91], 0, 0x00F5D4, 0xF9F871, 0x00F5D4),
        L("Sunset Drive 2", [0x120458, 0x7A04EB, 0xFFB000, 0xFF124F], 0, 0xFF124F, 0xFFB000, 0xFE75FE),
        L("Chrome Dusk", [0x0F0C29, 0x302B63, 0xE0E0E0, 0x9E9E9E], 0, 0x8E2DE2, 0xE0E0E0, 0x24C6DC),
        L("Hot Pink", [0x14001F, 0x5C0057, 0xFFE66D, 0xFF3CAC], 0, 0xFF3CAC, 0xFFE66D, 0x2BD2FF),
        L("Teal Horizon", [0x00121F, 0x003A4D, 0xFFD166, 0xEF476F], 0, 0x06D6A0, 0xFFD166, 0x06D6A0),
        L("Arcade Sun", [0x1B0036, 0x6A00A8, 0xFF9E00, 0xFF0054], 0, 0xFF0054, 0xFF9E00, 0x9EF01A),
        L("Midnight Run", [0x000814, 0x1D2D50, 0xFCA311, 0xE5383B], 0, 0xE5383B, 0xFCA311, 0x4CC9F0),
    ], build: { $0.sSynth($1) }),
]

let designs3: [Design2] = styles3.enumerated().flatMap { si, st in
    st.looks.enumerated().map { li, lk -> Design2 in
        var d = Design2(title: lk.name, kind: .styled, bg: 0, colors: lk.bg, dial: lk.dial, fg: lk.fg, accent: lk.acc, second: lk.sec,
                        font: lk.font ?? st.fonts[li % st.fonts.count], variant: li)
        d.style = si
        return d
    }
}
