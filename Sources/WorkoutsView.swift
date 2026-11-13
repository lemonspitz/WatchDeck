import SwiftUI
import Charts
import MapKit
import UniformTypeIdentifiers

// MARK: - Route map

/// Apple Maps view showing a workout route, with start/finish pins and an optional highlighted position.
struct RouteMap: NSViewRepresentable {
    var track: [TrackPoint]
    var highlight: TrackPoint?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.showsCompass = true
        m.showsScale = true
        context.coordinator.load(track, into: m)
        return m
    }

    func updateNSView(_ m: MKMapView, context: Context) {
        let c = context.coordinator
        if c.loaded != track.first?.t { c.load(track, into: m) }
        if let h = highlight {
            let coord = CLLocationCoordinate2D(latitude: h.lat, longitude: h.lon)
            if let dot = c.dot { dot.coordinate = coord } else {
                let a = MKPointAnnotation(); a.coordinate = coord; a.title = "here"
                c.dot = a; m.addAnnotation(a)
            }
        } else if let dot = c.dot {
            m.removeAnnotation(dot); c.dot = nil
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var loaded: Date?
        var dot: MKPointAnnotation?

        func load(_ track: [TrackPoint], into m: MKMapView) {
            m.removeOverlays(m.overlays); m.removeAnnotations(m.annotations); dot = nil
            loaded = track.first?.t
            // One polyline per segment between pauses.
            var seg: [CLLocationCoordinate2D] = []
            func flush() { if seg.count > 1 { m.addOverlay(MKPolyline(coordinates: seg, count: seg.count)) }; seg = [] }
            for p in track {
                seg.append(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon))
                if p.pause { flush() }
            }
            flush()
            if let f = track.first, let l = track.last {
                let s = MKPointAnnotation(); s.coordinate = CLLocationCoordinate2D(latitude: f.lat, longitude: f.lon); s.title = "Start"
                let e = MKPointAnnotation(); e.coordinate = CLLocationCoordinate2D(latitude: l.lat, longitude: l.lon); e.title = "Finish"
                m.addAnnotations([s, e])
            }
            var rect = MKMapRect.null
            for o in m.overlays { rect = rect.union(o.boundingMapRect) }
            if !rect.isNull { m.setVisibleMapRect(rect, edgePadding: NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: false) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let r = MKPolylineRenderer(overlay: overlay)
            r.strokeColor = NSColor.systemOrange
            r.lineWidth = 5
            r.lineCap = .round; r.lineJoin = .round
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let id = annotation.title ?? "pin"
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: id ?? "pin") ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            v.annotation = annotation
            let color: NSColor = id == "Start" ? .systemGreen : id == "Finish" ? .systemRed : .white
            let size: CGFloat = id == "here" ? 16 : 14
            v.image = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
                NSColor.black.withAlphaComponent(0.35).setFill(); NSBezierPath(ovalIn: r).fill()
                color.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 2, dy: 2)).fill()
                if id == "here" { NSColor.systemOrange.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 5, dy: 5)).fill() }
                return true
            }
            v.canShowCallout = id != "here"
            return v
        }
    }
}

// MARK: - Workouts tab

struct WorkoutsView: View {
    @EnvironmentObject var session: WatchSession
    @State private var selectedId: String?

    var selected: Workout? { session.workouts.first { $0.id == selectedId } ?? session.workouts.first }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Workouts").font(.title2.bold())
                    Spacer()
                    if session.workoutSyncing { ProgressView().controlSize(.small) }
                    Button { session.syncWorkoutsNow() } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .help("Download new workouts from the watch")
                        .disabled(!session.isReady || session.workoutSyncing)
                }
                .padding(.horizontal, 14).padding(.top, 16)
                Text(session.workoutStatus.isEmpty ? "\(session.workouts.count) stored on this Mac" : session.workoutStatus)
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
                List(session.workouts, selection: $selectedId) { w in
                    HStack(spacing: 10) {
                        Image(systemName: w.symbol).font(.title3).foregroundStyle(.orange).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name).font(.callout.weight(.medium))
                            Text(w.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            Text(durationText(w.duration) + (w.distance.map { $0 > 0 ? String(format: " · %.2f km", Double($0) / 1000) : "" } ?? "")
                                 + (w.track.isEmpty ? "" : " · route"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3).tag(w.id)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 270)
            Divider()
            if let w = selected {
                WorkoutDetail(workout: w).id(w.id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "figure.run.circle").font(.system(size: 50)).foregroundStyle(.secondary)
                    Text("No workouts yet").font(.title3)
                    Text("Record a workout on the watch, then press the sync button. Outdoor workouts include the route map.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct WorkoutDetail: View {
    @EnvironmentObject var session: WatchSession
    var workout: Workout
    @State private var hoverHR: Date?
    @State private var hoverPace: Date?
    @State private var confirmDelete = false

    /// Pace in seconds per km, from the watch's speed samples or (if missing) from the GPS track, smoothed over ~30 s.
    var paceSeries: [(t: Date, pace: Double)] {
        var pts: [(Date, Double)] = []
        let speeds = workout.samples.compactMap { s in s.speed.map { (s.t, $0) } }.filter { $0.1 > 0.3 }
        if speeds.count > 5 {
            pts = speeds.map { ($0.0, 1000 / $0.1) }
        } else if workout.track.count > 10 {
            let tr = workout.track
            var i = 0
            while i + 1 < tr.count {
                let j = min(tr.count - 1, i + 15)
                var d = 0.0
                for k in i ..< j where !tr[k + 1].pause { d += haversine(tr[k], tr[k + 1]) }
                let dt = tr[j].t.timeIntervalSince(tr[i].t)
                if d > 5, dt > 0 { pts.append((tr[j].t, dt / d * 1000)) }
                i = j
            }
        }
        return pts.filter { $0.1 < 1200 }.map { (t: $0.0, pace: $0.1) }
    }

    func trackPoint(at date: Date?) -> TrackPoint? { nearest(workout.track, to: date) { $0.t } }

    func yValue(_ p: PacePoint) -> Double { isRide ? 3600 / p.pace : p.pace / 60 }

    /// Rides read better as speed than as pace.
    var isRide: Bool { [3, 7, 141].contains(workout.type) }

    /// Kilometre splits when the watch recorded them, otherwise mile splits.
    var shownSplits: [PaceSplit] {
        let km = workout.splits.filter { $0.unit == 0 }
        return km.isEmpty ? workout.splits : km
    }

    var body: some View {
        let w = workout
        let hr = w.samples.filter { $0.hr != nil }
        let pace = paceSeries
        let hover = hoverHR ?? hoverPace
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Image(systemName: w.symbol).font(.system(size: 34)).foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(w.name).font(.title2.bold())
                        Text(w.start.formatted(date: .complete, time: .shortened) + " – " + w.end.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !w.track.isEmpty {
                        Button { exportGPX(w) } label: { Label("Export GPX…", systemImage: "square.and.arrow.up") }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.help("Delete from this Mac")
                }
                let dist = (w.distance ?? 0) > 0 ? Double(w.distance!) : w.trackDistance
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    Stat(title: "Duration", value: durationText(w.duration), icon: "timer", color: .orange)
                    if dist > 0 { Stat(title: "Distance", value: String(format: "%.2f km", dist / 1000), icon: "map.fill", color: .blue) }
                    if let p = w.avgPace ?? (dist > 50 && w.duration > 0 ? Int(Double(w.duration) / (dist / 1000)) : nil) {
                        if isRide {
                            Stat(title: "Avg speed", value: String(format: "%.1f km/h", 3600 / Double(max(p, 1))), icon: "speedometer", color: .teal)
                        } else {
                            Stat(title: "Avg pace", value: paceText(p) + " /km", icon: "speedometer", color: .teal)
                        }
                    }
                    if let a = w.avgHR { Stat(title: "Avg heart rate", value: "\(a) bpm", icon: "heart.fill", color: .red) }
                    if let m = w.hrMax ?? hr.compactMap(\.hr).max() { Stat(title: "Max heart rate", value: "\(m) bpm", icon: "heart.circle.fill", color: .pink) }
                    if let c = w.calories, c > 0 { Stat(title: "Calories", value: "\(c) kcal", icon: "flame.fill", color: .orange) }
                    if let s = w.steps, s > 0 { Stat(title: "Steps", value: "\(s)", icon: "figure.walk", color: .green) }
                    if let a = w.ascent, a > 0 { Stat(title: "Ascent", value: "\(a) m", icon: "arrow.up.right", color: .brown) }
                }
                if !w.track.isEmpty {
                    GroupBox("Route") {
                        RouteMap(track: w.track, highlight: trackPoint(at: hover))
                            .frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                if !hr.isEmpty {
                    GroupBox("Heart rate") {
                        let hit = nearest(hr, to: hoverHR) { $0.t }
                        Chart {
                            ForEach(hr) { AreaMark(x: .value("Time", $0.t), y: .value("bpm", $0.hr ?? 0)).foregroundStyle(.red.opacity(0.12)) }
                            ForEach(hr) { LineMark(x: .value("Time", $0.t), y: .value("bpm", $0.hr ?? 0)).foregroundStyle(.red) }
                            if let hit, let v = hit.hr {
                                RuleMark(x: .value("Time", hit.t)).foregroundStyle(.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                PointMark(x: .value("Time", hit.t), y: .value("bpm", v)).foregroundStyle(.red).symbolSize(80)
                                    .annotation(position: .top, alignment: tipAlignment(hr, hit) { $0.t }) {
                                        ChartTip(value: "\(v) bpm", detail: hit.t.formatted(date: .omitted, time: .standard)
                                                 + " · " + durationText(Int(hit.t.timeIntervalSince(w.start))) + " in", color: .red)
                                    }
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .hoverDate($hoverHR).frame(height: 180).padding(.top, 34).padding(6)
                    }
                }
                if pace.count > 3 {
                    GroupBox(isRide ? "Speed" : "Pace") {
                        let pts = pace.map { PacePoint(t: $0.t, pace: $0.pace) }
                        let hit = nearest(pts, to: hoverPace) { $0.t }
                        let ride = isRide
                        Chart {
                            ForEach(pts) { LineMark(x: .value("Time", $0.t), y: .value(ride ? "km/h" : "min/km", yValue($0))).foregroundStyle(.teal) }
                            if let hit {
                                RuleMark(x: .value("Time", hit.t)).foregroundStyle(.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                PointMark(x: .value("Time", hit.t), y: .value(ride ? "km/h" : "min/km", yValue(hit))).foregroundStyle(.teal).symbolSize(80)
                                    .annotation(position: .top, alignment: tipAlignment(pts, hit) { $0.t }) {
                                        ChartTip(value: ride ? String(format: "%.1f km/h", yValue(hit)) : paceText(Int(hit.pace)) + " /km",
                                                 detail: hit.t.formatted(date: .omitted, time: .standard), color: .teal)
                                    }
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false, reversed: !ride))
                        .hoverDate($hoverPace).frame(height: 160).padding(.top, 34).padding(6)
                    }
                }
                if !shownSplits.isEmpty {
                    GroupBox("Splits") {
                        let fastest = shownSplits.map(\.pace).min() ?? 1
                        VStack(spacing: 4) {
                            ForEach(shownSplits) { s in
                                HStack {
                                    Text("\(s.distance) \(s.unit == 1 ? "mi" : "km")").monospacedDigit().frame(width: 60, alignment: .leading)
                                    GeometryReader { g in
                                        RoundedRectangle(cornerRadius: 3).fill(.teal.opacity(s.pace == fastest ? 1 : 0.6))
                                            .frame(width: g.size.width * CGFloat(fastest) / CGFloat(max(s.pace, 1)))
                                    }
                                    .frame(height: 14)
                                    Text(isRide ? String(format: "%.1f km/h", (s.unit == 1 ? 5793.6 : 3600) / Double(max(s.pace, 1)))
                                         : paceText(s.pace) + (s.unit == 1 ? " /mi" : " /km"))
                                        .monospacedDigit().frame(width: 90, alignment: .trailing)
                                }
                            }
                        }
                        .padding(6)
                    }
                }
                if w.track.isEmpty && hr.isEmpty {
                    Text("This workout has no detailed data. Indoor workouts have no route.").foregroundStyle(.secondary)
                }
            }
            .padding(22)
        }
        .confirmationDialog("Delete this workout from this Mac?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { session.deleteWorkout(workout) }
        } message: { Text("It stays on the watch until the watch removes it.") }
    }

    func exportGPX(_ w: Workout) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gpx") ?? .xml]
        panel.nameFieldStringValue = "\(w.name) \(w.start.formatted(.iso8601.year().month().day())).gpx"
        if panel.runModal() == .OK, let url = panel.url { try? gpx(for: w).write(to: url, atomically: true, encoding: .utf8) }
    }
}

struct PacePoint: Identifiable { var id: Date { t }; var t: Date; var pace: Double }
