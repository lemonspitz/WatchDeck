// Hand-drawn vector icons (no third-party symbol sets) and seven-segment digits.
import AppKit

/// Draws an icon into `r` (top-left origin). `c1` is the main colour, `c2` a highlight (sun, rain, lightning).
func drawIcon(_ name: String, _ cv: Canvas, _ r: CGRect, _ c1: CGColor, _ c2: CGColor? = nil) {
    let ctx = cv.ctx
    let c2 = c2 ?? c1
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
    func circle(_ x: CGFloat, _ y: CGFloat, _ rad: CGFloat, _ col: CGColor) {
        let rr = rad * min(r.width, r.height)
        let c = p(x, y)
        ctx.setFillColor(col)
        ctx.fillEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
    }
    func poly(_ pts: [(CGFloat, CGFloat)], _ col: CGColor) {
        ctx.beginPath(); ctx.move(to: p(pts[0].0, pts[0].1))
        for q in pts.dropFirst() { ctx.addLine(to: p(q.0, q.1)) }
        ctx.closePath(); ctx.setFillColor(col); ctx.fillPath()
    }
    func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ w: CGFloat, _ col: CGColor) {
        ctx.setStrokeColor(col); ctx.setLineWidth(w * min(r.width, r.height)); ctx.setLineCap(.round)
        ctx.beginPath(); ctx.move(to: p(a.0, a.1)); ctx.addLine(to: p(b.0, b.1)); ctx.strokePath()
    }
    func cloud(_ dy: CGFloat, _ s: CGFloat, _ col: CGColor) {
        // A cloud in the unit box, scaled by s and shifted down by dy.
        func q(_ x: CGFloat, _ y: CGFloat) -> (CGFloat, CGFloat) { (0.5 + (x - 0.5) * s, dy + 0.5 + (y - 0.5) * s) }
        let a = q(0.3, 0.6), b = q(0.52, 0.46), c = q(0.73, 0.6)
        circle(a.0, a.1, 0.2 * s, col); circle(b.0, b.1, 0.26 * s, col); circle(c.0, c.1, 0.19 * s, col)
        let l = q(0.3, 0.6), rr = q(0.73, 0.8)
        ctx.setFillColor(col)
        ctx.addPath(CGPath(roundedRect: CGRect(x: p(l.0, l.1).x, y: p(l.0, l.1).y, width: p(rr.0, 0).x - p(l.0, 0).x,
                                               height: p(0, rr.1).y - p(0, l.1).y), cornerWidth: 2, cornerHeight: 2, transform: nil))
        ctx.fillPath()
    }
    func sun(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ col: CGColor) {
        circle(x, y, 0.2 * s, col)
        for i in 0 ..< 8 {
            let a = CGFloat(i) * .pi / 4
            line((x + cos(a) * 0.31 * s, y + sin(a) * 0.31 * s), (x + cos(a) * 0.44 * s, y + sin(a) * 0.44 * s), 0.08 * s, col)
        }
    }

    switch name {
    case "heart":
        circle(0.31, 0.36, 0.22, c1); circle(0.69, 0.36, 0.22, c1)
        poly([(0.1, 0.46), (0.9, 0.46), (0.5, 0.9)], c1)
    case "steps":
        ctx.setFillColor(c1)
        ctx.fillEllipse(in: CGRect(origin: p(0.14, 0.34), size: CGSize(width: 0.28 * r.width, height: 0.42 * r.height)))
        circle(0.28, 0.88, 0.09, c1)
        ctx.fillEllipse(in: CGRect(origin: p(0.56, 0.06), size: CGSize(width: 0.28 * r.width, height: 0.42 * r.height)))
        circle(0.7, 0.6, 0.09, c1)
    case "bolt":
        poly([(0.62, 0.0), (0.16, 0.58), (0.46, 0.58), (0.36, 1.0), (0.84, 0.4), (0.54, 0.4)], c1)
    case "flame":
        ctx.beginPath(); ctx.move(to: p(0.5, 0.0))
        ctx.addCurve(to: p(0.86, 0.62), control1: p(0.62, 0.24), control2: p(0.88, 0.38))
        ctx.addCurve(to: p(0.5, 1.0), control1: p(0.86, 0.86), control2: p(0.7, 1.0))
        ctx.addCurve(to: p(0.14, 0.62), control1: p(0.3, 1.0), control2: p(0.14, 0.86))
        ctx.addCurve(to: p(0.4, 0.3), control1: p(0.14, 0.46), control2: p(0.34, 0.42))
        ctx.addCurve(to: p(0.5, 0.0), control1: p(0.48, 0.2), control2: p(0.52, 0.1))
        ctx.closePath(); ctx.setFillColor(c1); ctx.fillPath()
        circle(0.5, 0.74, 0.13, c2)
    case "battery":
        ctx.setStrokeColor(c1); ctx.setLineWidth(max(1.5, r.width * 0.08))
        ctx.addPath(CGPath(roundedRect: CGRect(origin: p(0.04, 0.24), size: CGSize(width: 0.82 * r.width, height: 0.52 * r.height)),
                           cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.strokePath()
        ctx.setFillColor(c1); ctx.fill(CGRect(origin: p(0.88, 0.4), size: CGSize(width: 0.1 * r.width, height: 0.2 * r.height)))
        ctx.setFillColor(c2); ctx.fill(CGRect(origin: p(0.14, 0.34), size: CGSize(width: 0.5 * r.width, height: 0.32 * r.height)))
    case "thermo":
        line((0.5, 0.14), (0.5, 0.62), 0.22, c1); circle(0.5, 0.76, 0.2, c1); circle(0.5, 0.76, 0.11, c2)
    case "sunny": sun(0.5, 0.5, 1, c2)
    case "night":
        circle(0.48, 0.52, 0.36, c1)
        ctx.setBlendMode(.clear); circle(0.66, 0.38, 0.32, c1); ctx.setBlendMode(.normal)
        circle(0.78, 0.74, 0.05, c2); circle(0.86, 0.56, 0.035, c2)
    case "overcast":
        cloud(-0.1, 0.8, c1.copy(alpha: 0.55)!); cloud(0.06, 1.0, c1)
    case "cloudy":
        sun(0.66, 0.34, 0.8, c2); cloud(0.08, 0.9, c1)
    case "rain":
        cloud(-0.1, 0.9, c1)
        for x in [0.34, 0.52, 0.7] as [CGFloat] { line((x, 0.72), (x - 0.07, 0.92), 0.07, c2) }
    case "thunder":
        cloud(-0.12, 0.9, c1)
        poly([(0.56, 0.6), (0.36, 0.82), (0.5, 0.82), (0.44, 1.0), (0.66, 0.74), (0.52, 0.74)], c2)
    case "snow":
        cloud(-0.12, 0.9, c1)
        for (x, y) in [(0.34, 0.8), (0.52, 0.9), (0.7, 0.8)] as [(CGFloat, CGFloat)] { circle(x, y, 0.06, c2) }
    case "dust":
        for (i, y) in ([0.3, 0.5, 0.7] as [CGFloat]).enumerated() {
            line((0.12 + CGFloat(i) * 0.06, y), (0.78 - CGFloat(i) * 0.04, y), 0.08, c1)
            circle(0.88 - CGFloat(i) * 0.04, y, 0.04, c2)
        }
    case "haze":
        sun(0.5, 0.36, 0.7, c2)
        line((0.14, 0.72), (0.86, 0.72), 0.08, c1); line((0.24, 0.88), (0.76, 0.88), 0.08, c1)
    case "fog":
        for (i, y) in ([0.3, 0.5, 0.7] as [CGFloat]).enumerated() { line((0.14 + CGFloat(i % 2) * 0.1, y), (0.86 - CGFloat(i % 2) * 0.06, y), 0.09, c1) }
    case "unknown":
        cv.text("?", font: "system", size: r.height, color: c1, in: r)
    default: break
    }
}

/// Weather icon order used by the watch for value type 53 (index = weather code).
let weatherIconNames = ["unknown", "sunny", "night", "overcast", "cloudy", "rain", "thunder", "snow", "dust", "haze", "fog"]

/// A seven-segment digit filling `r`. `ghost` draws all segments (an "8") instead.
func sevenSegment(_ cv: Canvas, _ digit: Int, _ r: CGRect, _ color: CGColor, thickness t: CGFloat, ghost: Bool = false) {
    let on: [Int: String] = [0: "abcdef", 1: "bc", 2: "abdeg", 3: "abcdg", 4: "bcfg", 5: "acdfg", 6: "acdefg", 7: "abc", 8: "abcdefg", 9: "abcdfg"]
    let segs = ghost ? "abcdefg" : on[digit] ?? ""
    let ctx = cv.ctx
    let x0 = r.minX, x1 = r.maxX, y0 = r.minY, y1 = r.maxY, ym = r.midY
    let g: CGFloat = 1.5 // gap between segments
    func hseg(_ y: CGFloat) -> [CGPoint] {
        [CGPoint(x: x0 + g, y: y), CGPoint(x: x0 + g + t / 2, y: y - t / 2), CGPoint(x: x1 - g - t / 2, y: y - t / 2),
         CGPoint(x: x1 - g, y: y), CGPoint(x: x1 - g - t / 2, y: y + t / 2), CGPoint(x: x0 + g + t / 2, y: y + t / 2)]
    }
    func vseg(_ x: CGFloat, _ ya: CGFloat, _ yb: CGFloat) -> [CGPoint] {
        [CGPoint(x: x, y: ya + g), CGPoint(x: x + t / 2, y: ya + g + t / 2), CGPoint(x: x + t / 2, y: yb - g - t / 2),
         CGPoint(x: x, y: yb - g), CGPoint(x: x - t / 2, y: yb - g - t / 2), CGPoint(x: x - t / 2, y: ya + g + t / 2)]
    }
    let ix0 = x0 + t / 2, ix1 = x1 - t / 2, iy0 = y0 + t / 2, iy1 = y1 - t / 2
    let shapes: [Character: [CGPoint]] = [
        "a": hseg(iy0), "g": hseg(ym), "d": hseg(iy1),
        "f": vseg(ix0, iy0, ym), "b": vseg(ix1, iy0, ym), "e": vseg(ix0, ym, iy1), "c": vseg(ix1, ym, iy1),
    ]
    ctx.setFillColor(color)
    for s in segs {
        guard let pts = shapes[s] else { continue }
        ctx.beginPath(); ctx.addLines(between: pts); ctx.closePath(); ctx.fillPath()
    }
}
