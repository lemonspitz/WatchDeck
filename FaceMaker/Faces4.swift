// Faces 451-500: "Sporty" — clean, easy-to-read faces with big slanted digits, one strong accent colour
// and a different typeface for every design.
import AppKit

let slantT: CGFloat = 0.2     // horizontal lean per unit of height (about 11°)

extension Builder {
    func isItalic(_ font: String) -> Bool { font.contains("Italic") || font.contains("Oblique") }

    /// Draws `draw` leaning right around the box centre (skipped for fonts that are already italic).
    func leaning(_ c: Canvas, _ r: CGRect, font: String, _ draw: () -> Void) {
        c.ctx.saveGState()
        if !isItalic(font) {
            c.ctx.translateBy(x: r.midX, y: r.midY)
            c.ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: -slantT, d: 1, tx: 0, ty: 0))
            c.ctx.translateBy(x: -r.midX, y: -r.midY)
        }
        draw()
        c.ctx.restoreGState()
    }

    /// align: 0 = hug the left edge (ones digit), 1 = centred, 2 = hug the right edge (tens digit), so pairs sit together.
    func slantDigits(_ w: Int, _ h: Int, color: RGB, font: String, outline: Bool = false, align: Int = 1) -> [String] {
        let extra = isItalic(font) ? CGFloat(h) * 0.12 : CGFloat(h) * slantT
        let size = fitFont(font, CGFloat(w) - 6 - extra, CGFloat(h) - 6)
        let clear = CGColor(gray: 0, alpha: 0)
        return glyphs(w, h) { [self] c, n, r in
            let box = r.insetBy(dx: extra / 2 + 3, dy: 0)
            leaning(c, r, font: font) {
                if outline { c.text(String(n), font: font, size: size, color: clear, in: box, align: align, stroke: color.cg(), strokeWidth: 2.5, fixedSize: true) }
                else { c.text(String(n), font: font, size: size, color: color.cg(), in: box, align: align, fixedSize: true) }
            }
        }
    }

    /// Time from four digit sets so each pair hugs: tens right-aligned, ones left-aligned.
    func sportClock(_ w: Int, _ h: Int, hourColor: RGB, minuteColor: RGB, font: String, _ pos: [(Int, Int)]) {
        let hT = slantDigits(w, h, color: hourColor, font: font, align: 2), hO = slantDigits(w, h, color: hourColor, font: font, align: 0)
        let mT = hourColor.bytes == minuteColor.bytes ? hT : slantDigits(w, h, color: minuteColor, font: font, align: 2)
        let mO = hourColor.bytes == minuteColor.bytes ? hO : slantDigits(w, h, color: minuteColor, font: font, align: 0)
        face.time += [sel(Array(hT[0 ... 2]), pos[0].0, pos[0].1, VT.hourHi, label: 1, show: 1), sel(hO, pos[1].0, pos[1].1, VT.hourLo, label: 1, show: 0),
                      sel(Array(mT[0 ... 5]), pos[2].0, pos[2].1, VT.minHi, label: 1, show: 0), sel(mO, pos[3].0, pos[3].1, VT.minLo, label: 1, show: 9)]
    }

    func slantLabels(_ strings: [String], _ w: Int, _ h: Int, color: RGB, font: String, size: CGFloat) -> [String] {
        let p = uid("sl")
        return strings.enumerated().map { i, s in
            let c = cv(CGFloat(w), CGFloat(h))
            let r = CGRect(x: 2, y: 1, width: w - 4, height: h - 2)
            leaning(c, r, font: font) { c.text(s, font: font, size: size, color: color.cg(), in: r, align: 0) }
            return face.add("\(p)_\(i)", c)
        }
    }

    /// Weekday, day and month in the design's font, leaning like the time.
    func sportDate(x: Int, y: Int, font: String, week: RGB, ink: RGB, size: CGFloat = 20) {
        let wk = slantLabels(weekdays, 56, 28, color: week, font: font, size: size)
        let dd = slantLabels((0 ... 9).map(String.init), 16, 28, color: ink, font: font, size: size)
        let mo = slantLabels(months, 56, 28, color: ink, font: font, size: size)
        face.date += [sel(wk, x, y, VT.week, label: 2, show: 5), sel(Array(dd[0 ... 3]), x + 58, y, VT.dayHi, label: 2, show: 1),
                      sel(dd, x + 74, y, VT.dayLo, label: 2, show: 3), sel(mo, x + 96, y, VT.month, label: 2, show: 11)]
    }

    func parallelogram(_ r: CGRect, _ c: CGColor, lean: CGFloat = slantT) {
        let dx = r.height * lean
        poly([CGPoint(x: r.minX + dx, y: r.minY), CGPoint(x: r.maxX + dx, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)], c)
    }

    /// Battery level as ten leaning segments.
    func slantBattery(x: Int, y: Int, w: Int, h: Int, on: RGB) -> Layer {
        let levels = (0 ... 10).map { lvl -> String in
            let c = cv(CGFloat(w), CGFloat(h))
            let seg = (CGFloat(w) - CGFloat(h) * slantT) / 10
            for i in 0 ..< 10 {
                let r = CGRect(x: CGFloat(i) * seg, y: 0, width: seg - 3, height: CGFloat(h))
                let dx = r.height * slantT
                poly([CGPoint(x: r.minX + dx, y: r.minY), CGPoint(x: r.maxX + dx, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)],
                     on.cg(i < lvl ? 1 : 0.16), on: c)
            }
            return face.add(uid("sb"), c)
        }
        return sel(levels, x, y, VT.batteryLevel, label: 3, show: 9)
    }

    /// A clean stats row: icon over value, thin dividers, no panel.
    func sportStats(y: Int, _ items: [Stat], ink: RGB, divider: RGB) {
        statRow(y: y, items, height: 62, panel: false, ink: ink, cell: { [self] r in
            if r.minX > 20 { seg(CGPoint(x: r.minX - 3 + 6, y: r.minY + 10), CGPoint(x: r.minX - 3, y: r.maxY - 10), 1.5, divider.cg(0.35)) }
        })
    }

    // 1. Stacked: big hours over offset minutes.
    func sSportStack(_ v: Int) {
        let f0 = d.font
        if v % 2 == 0 { parallelogram(CGRect(x: 22, y: 64, width: 6, height: 300), acc.cg(0.9)) }
        sportDate(x: 24, y: 24, font: f0, week: acc, ink: fg, size: 19)
        container([196, 14, 74, 44], DT.battery, [icon("bolt", [200, 26, 16, 20], acc), text([216, 22, 52, 28], VT.battery, "88", fg)])
        sportClock(104, 154, hourColor: acc, minuteColor: fg, font: f0, [(36, 62), (136, 62), (60, 212), (160, 212)])
        sportStats(y: 380, [.heart, .steps, .calories], ink: fg, divider: fg)
    }

    // 2. One line: time, seconds, battery bar.
    func sSportLine(_ v: Int) {
        let f0 = d.font
        container([40, 18, 200, 56], DT.weather, [weatherIcon(40, 74, 24), text([120, 28, 64, 36], VT.temperature, "24°", fg), unit(184, 34)])
        sportClock(62, 118, hourColor: fg, minuteColor: fg, font: f0, [(8, 104), (70, 104), (148, 104), (210, 104)])
        parallelogram(CGRect(x: 134, y: 136, width: 10, height: 10), acc.cg()); parallelogram(CGRect(x: 128, y: 174, width: 10, height: 10), acc.cg())
        seconds(slantDigits(34, 56, color: acc, font: f0), (202, 228), (234, 228))
        sportDate(x: 18, y: 240, font: f0, week: acc, ink: fg.mix(col(0), 0.25), size: 19)
        container([18, 290, 244, 40], DT.battery, [slantBattery(x: 22, y: 300, w: 236, h: 18, on: acc)])
        sportStats(y: 372, [.heart, .steps, .calories], ink: fg, divider: fg)
    }

    // 3. Diagonal band carrying the date between hours and minutes.
    func sSportBand(_ v: Int) {
        let f0 = d.font
        let (x0, x1) = (-f.ox - 10, 280 + f.ox + 10)
        poly([CGPoint(x: x0, y: 252), CGPoint(x: x1, y: 196), CGPoint(x: x1, y: 246), CGPoint(x: x0, y: 302)], acc.cg())
        let bandInk = acc.isDark ? RGB(0xFFFFFF) : RGB(0x111111)
        sportClock(100, 134, hourColor: fg, minuteColor: fg, font: f0, [(38, 52), (138, 52), (42, 296), (142, 296)])
        sportDate(x: 70, y: 222, font: f0, week: bandInk, ink: bandInk, size: 19)
        let hdx = b_inset([12, 8, 92, 44]), bdx = b_inset([176, 8, 92, 44])
        container([12 + hdx, 8, 92, 44], DT.heart, [icon("heart", [20 + hdx, 20, 18, 18], acc), text([42 + hdx, 14, 60, 30], VT.heart, "72", fg)])
        container([176 + bdx, 8, 92, 44], DT.activity, [icon("steps", [184 + bdx, 20, 18, 18], acc), text([204 + bdx, 14, 62, 30], VT.steps, "8426", fg)])
        container([90, 432 - 4, 100, 30], DT.battery, [icon("bolt", [104, 432, 14, 18], acc), text([120, 428, 60, 26], VT.battery, "88", fg)])
    }
    func b_inset(_ r: [Int]) -> Int { inset(r) }

    // 4. Activity ring around the time.
    func sSportRing(_ v: Int) {
        let f0 = d.font
        let cx = 140, cy = 196
        for i in 0 ..< 40 {
            let deg = 220 + CGFloat(i) * 7
            if deg > 500 { break }
            dot(CGPoint(x: CGFloat(cx) + sin(deg * .pi / 180) * 132, y: CGFloat(cy) - cos(deg * .pi / 180) * 132), 1.4, fg.cg(0.35))
        }
        let ring = arc(cx: cx, cy: cy, r: 120, lw: 11, start: 220, end: 500, color: acc, value: VT.stepsRatio, sample: 0.68)
        sportClock(48, 90, hourColor: fg, minuteColor: acc, font: f0, [(36, 150), (86, 150), (144, 150), (194, 150)])
        parallelogram(CGRect(x: 135, y: 172, width: 7, height: 7), fg.cg()); parallelogram(CGRect(x: 130, y: 206, width: 7, height: 7), fg.cg())
        let wk = slantLabels(weekdays, 56, 26, color: acc, font: f0, size: 18)
        let dd = slantLabels((0 ... 9).map(String.init), 16, 26, color: fg, font: f0, size: 18)
        face.date += [sel(wk, 86, 112, VT.week, label: 2, show: 5), sel(Array(dd[0 ... 3]), 146, 112, VT.dayHi, label: 2, show: 1), sel(dd, 162, 112, VT.dayLo, label: 2, show: 3)]
        container([60, 60, 160, 260], DT.activity, [ring, icon("steps", [104, 252, 20, 20], acc), text([126, 248, 70, 28], VT.steps, "8426", fg)])
        statRow(y: 372, [.heart, .battery, .weather], height: 64, panel: v % 2 == 0, ink: fg)
    }

    // 5. Racing stripes beside hours over minutes.
    func sSportStripe(_ v: Int) {
        let f0 = d.font
        let (y0, y1): (CGFloat, CGFloat) = (-f.oy - 10, 366)
        for (i, c) in [acc, sec, fg].enumerated() {
            let x = CGFloat(206 + i * 18), lean = (y1 - y0) * 0.18
            poly([CGPoint(x: x + lean, y: y0), CGPoint(x: x + lean + 12, y: y0), CGPoint(x: x + 12, y: y1), CGPoint(x: x, y: y1)], c.cg(i == 2 ? 0.25 : 0.9))
        }
        bg.fill(fg.cg(0.25), CGRect(x: 20, y: 372, width: 240, height: 1.5))
        sportDate(x: 20, y: 24, font: f0, week: acc, ink: fg, size: 19)
        sportClock(96, 144, hourColor: acc, minuteColor: fg, font: f0, [(12, 64), (110, 64), (12, 214), (110, 214)])
        sportStats(y: 380, [.heart, .steps, .battery], ink: fg, divider: fg)
    }
}

let sportStyles: [Style3] = [
    Style3(name: "Sport Stack", category: "Sporty", fonts: [
        "AvenirNextCondensed-HeavyItalic", "Futura-CondensedExtraBold", "DINCondensed-Bold", "Impact", "HelveticaNeue-CondensedBlack",
        "Rockwell-BoldItalic", "AvenirNext-Heavy", "Optima-ExtraBlack", "Superclarendon-BlackItalic", "Avenir-BlackOblique"], looks: [
        L("Volt Stack", [0x0A0A0A, 0x121212], 0, 0xFFFFFF, 0xC6FF00, 0xC6FF00),
        L("Coral Stack", [0x101820, 0x0A1016], 0, 0xF4F4F4, 0xFF6F61, 0xFF6F61),
        L("Ice Stack", [0x0B1D2E, 0x06121D], 0, 0xFFFFFF, 0x4FC3F7, 0x4FC3F7),
        L("Blaze Stack", [0x111111, 0x1A1A1A], 0, 0xFFFFFF, 0xFF5722, 0xFF5722),
        L("Chalk Stack", [0xF2F2EF, 0xE6E6E1], 0, 0x111111, 0xE53935, 0xE53935),
        L("Mint Stack", [0x0E1F1A, 0x081310], 0, 0xEFFFF8, 0x3DDC97, 0x3DDC97),
        L("Gold Stack", [0x0D0D0D, 0x161616], 0, 0xF5F5F5, 0xFFC93C, 0xFFC93C),
        L("Violet Stack", [0x120B1E, 0x0B0614], 0, 0xFFFFFF, 0xB388FF, 0xB388FF),
        L("Navy Stack", [0x0A1A3A, 0x061128], 0, 0xFFFFFF, 0xFFB300, 0xFFB300),
        L("Rose Stack", [0x1A0E12, 0x10080B], 0, 0xFFF5F7, 0xFF4F81, 0xFF4F81),
    ], build: { $0.sSportStack($1) }),
    Style3(name: "Sport Line", category: "Sporty", fonts: [
        "AvenirNext-HeavyItalic", "DINAlternate-Bold", "Futura-Bold", "Arial-BoldItalicMT", "Trebuchet-BoldItalic",
        "Verdana-BoldItalic", "HelveticaNeue-BoldItalic", "GillSans-BoldItalic", "PTSans-BoldItalic", "Menlo-BoldItalic"], looks: [
        L("Pace", [0x000000, 0x0A0A0A], 0, 0xFFFFFF, 0x00E676, 0x00E676),
        L("Tempo", [0x0D1117, 0x161B22], 0, 0xF0F6FC, 0x58A6FF, 0x58A6FF),
        L("Sprint", [0x1B1B1B, 0x0F0F0F], 0, 0xFFFFFF, 0xFF3D00, 0xFF3D00),
        L("Interval", [0xFAFAFA, 0xEEEEEE], 0, 0x101010, 0x2962FF, 0x2962FF),
        L("Cadence", [0x0F1A14, 0x08100C], 0, 0xF1FFF6, 0xFFD600, 0xFFD600),
        L("Split", [0x170F24, 0x0E0817], 0, 0xFFFFFF, 0x00E5FF, 0x00E5FF),
        L("Stride", [0x1C1410, 0x120C09], 0, 0xFFF4EC, 0xFF9100, 0xFF9100),
        L("Lap", [0x0A1628, 0x050E1A], 0, 0xFFFFFF, 0xFF4081, 0xFF4081),
        L("Rally", [0xE8EEF2, 0xD6DEE4], 0, 0x0E2233, 0xFF6D00, 0xFF6D00),
        L("Glide", [0x101010, 0x181818], 0, 0xE0E0E0, 0xA7FFEB, 0xA7FFEB),
    ], build: { $0.sSportLine($1) }),
    Style3(name: "Sport Band", category: "Sporty", fonts: [
        "Futura-CondensedExtraBold", "AvenirNextCondensed-BoldItalic", "Impact", "DINCondensed-Bold", "Seravek-Bold",
        "Optima-BoldItalic", "Didot-Bold", "Charter-BlackItalic", "HelveticaNeue-CondensedBlack", "Georgia-BoldItalic"], looks: [
        L("Red Band", [0x0E0E0E, 0x161616], 0, 0xFFFFFF, 0xE10600, 0xE10600),
        L("Lime Band", [0x111411, 0x0A0C0A], 0, 0xFFFFFF, 0xB2FF59, 0xB2FF59),
        L("Sky Band", [0x0D1B2A, 0x08131F], 0, 0xFFFFFF, 0x4DD0E1, 0x4DD0E1),
        L("Sun Band", [0x161009, 0x0E0A05], 0, 0xFFFFFF, 0xFFB300, 0xFFB300),
        L("White Band", [0x1A1A1A, 0x111111], 0, 0xFFFFFF, 0xF5F5F5, 0xF5F5F5),
        L("Paper Band", [0xF4F1EA, 0xEAE6DC], 0, 0x1A1A1A, 0x1A1A1A, 0x1A1A1A),
        L("Magenta Band", [0x14060F, 0x0C030A], 0, 0xFFFFFF, 0xFF2D95, 0xFF2D95),
        L("Teal Band", [0x06201F, 0x031413], 0, 0xEFFFFE, 0x1DE9B6, 0x1DE9B6),
        L("Cobalt Band", [0x0A0F2C, 0x060A1E], 0, 0xFFFFFF, 0x3D5AFE, 0x3D5AFE),
        L("Orange Band", [0xF2F2F2, 0xE5E5E5], 0, 0x151515, 0xFF6D00, 0xFF6D00),
    ], build: { $0.sSportBand($1) }),
    Style3(name: "Sport Ring", category: "Sporty", fonts: [
        "Avenir-HeavyOblique", "Futura-MediumItalic", "DINAlternate-Bold", "AvenirNextCondensed-HeavyItalic", "rounded",
        "Futura-Bold", "Rockwell-BoldItalic", "Tahoma-Bold", "ArialRoundedMTBold", "Palatino-BoldItalic"], looks: [
        L("Move Ring", [0x000000, 0x0A0A0A], 0, 0xFFFFFF, 0xFF2D55, 0xFF2D55),
        L("Energy Ring", [0x0B0B0B, 0x141414], 0, 0xFFFFFF, 0xFFD60A, 0xFFD60A),
        L("Aqua Ring", [0x041824, 0x020F17], 0, 0xFFFFFF, 0x00D2FF, 0x00D2FF),
        L("Leaf Ring", [0x0A1A0E, 0x061008], 0, 0xFFFFFF, 0x34C759, 0x34C759),
        L("Peach Ring", [0xFFF4EC, 0xFBE6D6], 0, 0x2A1A12, 0xFF7A45, 0xFF7A45),
        L("Ultra Ring", [0x130A26, 0x0B0617], 0, 0xFFFFFF, 0xA06BFF, 0xA06BFF),
        L("Flame Ring", [0x1A0A05, 0x100603], 0, 0xFFF1E8, 0xFF6B1A, 0xFF6B1A),
        L("Steel Ring", [0x1C2128, 0x12161B], 0, 0xF5F7FA, 0x9AA5B1, 0x9AA5B1),
        L("Cloud Ring", [0xF5F7FA, 0xE4E9EF], 0, 0x1A2330, 0x0A84FF, 0x0A84FF),
        L("Sakura Ring", [0x1E0E14, 0x13080D], 0, 0xFFF0F5, 0xFF8FB1, 0xFF8FB1),
    ], build: { $0.sSportRing($1) }),
    Style3(name: "Sport Stripe", category: "Sporty", fonts: [
        "HelveticaNeue-CondensedBlack", "AvenirNext-BoldItalic", "Futura-CondensedExtraBold", "Impact", "Superclarendon-BlackItalic",
        "DINCondensed-Bold", "Avenir-BlackOblique", "Baskerville-BoldItalic", "Avenir-Black", "Cochin-BoldItalic"], looks: [
        L("Le Mans", [0x0C2340, 0x07172C], 0, 0xFFFFFF, 0xFFFFFF, 0xE10600),
        L("Gulf Stripe", [0x101010, 0x181818], 0, 0xFFFFFF, 0x7EC8E3, 0xFF8C1A),
        L("Rosso", [0x8B0000, 0x5E0000], 0, 0xFFFFFF, 0xFFD400, 0xFFFFFF),
        L("Silver Arrow", [0x1E2226, 0x14171A], 0, 0xFFFFFF, 0xC0C7CF, 0x00D2BE),
        L("British Green", [0x0B3B24, 0x072816], 0, 0xF5F0E1, 0xF5F0E1, 0xE9C46A),
        L("Papaya", [0x111111, 0x1A1A1A], 0, 0xFFFFFF, 0xFF8000, 0x47C7FC),
        L("Bianco", [0xF5F5F5, 0xE8E8E8], 0, 0x111111, 0xD62828, 0x1D4ED8),
        L("Nero Oro", [0x050505, 0x0D0D0D], 0, 0xF5E6B3, 0xD4AF37, 0xD4AF37),
        L("Azzurro", [0x0047AB, 0x00347D], 0, 0xFFFFFF, 0xFFFFFF, 0xFFD400),
        L("Night Racer", [0x0A0014, 0x12002A], 0, 0xFFFFFF, 0xFF00C8, 0x00F0FF),
    ], build: { $0.sSportStripe($1) }),
]
