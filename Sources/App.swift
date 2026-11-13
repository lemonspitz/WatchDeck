import SwiftUI
import Charts
import UniformTypeIdentifiers

@main
struct WatchDeckApp: App {
    @StateObject private var session = WatchSession()

    init() {
        if CommandLine.arguments.contains("--selftest") { exit(runSelfTest() ? 0 : 1) }
    }

    var body: some Scene {
        WindowGroup("WatchDeck") {
            RootView()
                .environmentObject(session)
                .environmentObject(session.scanner)
                .frame(minWidth: 820, minHeight: 560)
                .task {
                    let args = CommandLine.arguments
                    if let i = args.firstIndex(of: "--connect"), i + 1 < args.count { session.autoConnect(matching: args[i + 1]) }
                    if let i = args.firstIndex(of: "--install"), i + 1 < args.count {
                        for _ in 0 ..< 90 where !session.isReady { try? await Task.sleep(nanoseconds: 1_000_000_000) }
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if session.isReady { session.install(HWT.describe(URL(fileURLWithPath: args[i + 1]))) }
                    }
                    if args.contains("--sync") {
                        for _ in 0 ..< 90 where !session.isReady { try? await Task.sleep(nanoseconds: 1_000_000_000) }
                        if session.isReady { session.syncHealth(days: 7) }
                    }
                }
        }
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case device = "Device", health = "Health", sleep = "Sleep", workouts = "Workouts", notify = "Notifications", faces = "Watch Faces"
    case alarms = "Alarms", settings = "Settings", log = "Log"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .device: return "applewatch"
        case .health: return "heart.fill"
        case .sleep: return "bed.double.fill"
        case .workouts: return "figure.run"
        case .notify: return "bell.badge.fill"
        case .faces: return "clock.fill"
        case .alarms: return "alarm.fill"
        case .settings: return "gearshape.fill"
        case .log: return "terminal.fill"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var session: WatchSession
    @State private var pane: Pane? = {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--pane"), i + 1 < a.count, let p = Pane.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(a[i + 1].lowercased()) }) { return p }
        return .device
    }()

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) { StatusBadge().padding(10) }
        } detail: {
            VStack(spacing: 0) {
                if let e = session.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text(e).font(.callout).lineLimit(2)
                        Spacer()
                        Button("Dismiss") { session.lastError = nil }.buttonStyle(.link)
                    }
                    .padding(10).background(.yellow.opacity(0.12))
                }
                if session.findingPhone {
                    HStack {
                        Image(systemName: "speaker.wave.3.fill")
                        Text("Your watch is looking for this Mac.")
                        Spacer()
                        Button("Stop") { session.stopFindPhone() }
                    }
                    .padding(10).background(.blue.opacity(0.15))
                }
                Group {
                    switch pane ?? .device {
                    case .device: DeviceView()
                    case .health: HealthView()
                    case .sleep: SleepView()
                    case .workouts: WorkoutsView()
                    case .notify: Gate { NotifyView() }
                    case .faces: FacesView()
                    case .alarms: Gate { AlarmsView() }
                    case .settings: Gate { SettingsView() }
                    case .log: LogView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct StatusBadge: View {
    @EnvironmentObject var session: WatchSession
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(text).font(.callout.weight(.medium))
                if session.isReady, let b = session.battery { Text("Battery \(b)%").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
    }
    var color: Color {
        switch session.status {
        case .ready: return .green
        case .connecting, .pairing: return .orange
        case .failed: return .red
        case .disconnected: return .gray
        }
    }
    var text: String {
        switch session.status {
        case .ready: return session.deviceName
        case .connecting: return "Connecting…"
        case .pairing: return "Pairing…"
        case .failed: return "Connection failed"
        case .disconnected: return "Not connected"
        }
    }
}

/// Shows a placeholder until a watch is connected.
struct Gate<Content: View>: View {
    @EnvironmentObject var session: WatchSession
    @ViewBuilder var content: () -> Content
    var body: some View {
        if session.isReady { content() } else {
            VStack(spacing: 10) {
                Image(systemName: "applewatch.slash").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Connect a watch first").font(.title3)
                Text("Open the Device tab to scan and pair.").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Device

struct DeviceView: View {
    @EnvironmentObject var session: WatchSession
    @EnvironmentObject var scanner: DeviceScanner
    @State private var macs: [String: String] = [:]
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if session.isReady { connected } else { picker }
            }
            .padding(24).frame(maxWidth: 720, alignment: .leading)
        }
    }

    var connected: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "applewatch").font(.system(size: 64)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.deviceName).font(.title2.bold())
                    if !session.model.isEmpty { Text("Model \(session.model)").foregroundStyle(.secondary) }
                    if !session.firmware.isEmpty { Text("Firmware \(session.firmware)").foregroundStyle(.secondary) }
                    if !session.serial.isEmpty { Text("Serial \(session.serial)").foregroundStyle(.secondary).textSelection(.enabled) }
                }
                Spacer()
                if let b = session.battery {
                    VStack {
                        Gauge(value: Double(b), in: 0 ... 100) { Text("") } currentValueLabel: { Text("\(b)%") }
                            .gaugeStyle(.accessoryCircular).tint(b < 20 ? .red : .green)
                        Text("Battery").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            GroupBox("Actions") {
                HStack {
                    Button { session.findWatch(start: true) } label: { Label("Find watch", systemImage: "dot.radiowaves.left.and.right") }
                    Button("Stop ringing") { session.findWatch(start: false) }
                    Button { session.refreshBatteryNow() } label: { Label("Refresh battery", systemImage: "arrow.clockwise") }
                    Button { session.syncTimeNow() } label: { Label("Sync time", systemImage: "clock.arrow.2.circlepath") }
                    Spacer()
                }.padding(6)
            }
            HStack {
                Button("Disconnect") { session.disconnect() }
                Spacer()
                Button("Factory reset watch…", role: .destructive) { confirmReset = true }
            }
            .confirmationDialog("Erase the watch and restore factory settings?", isPresented: $confirmReset) {
                Button("Erase watch", role: .destructive) { session.factoryReset() }
            } message: { Text("All data on the watch is deleted. This cannot be undone.") }
        }
    }

    /// One row per watch: a watch seen over both Bluetooth LE and classic Bluetooth is listed once,
    /// using the connection its model actually needs.
    var uniqueDevices: [FoundDevice] {
        var seen: [String: FoundDevice] = [:]
        var order: [String] = []
        for d in scanner.devices {
            let want: TransportKind = (ModelInfo.match(d.name)?.usesLE ?? (d.kind == .le)) ? .le : .classic
            if let old = seen[d.name] {
                if old.kind != want && d.kind == want { seen[d.name] = d }
            } else { seen[d.name] = d; order.append(d.name) }
        }
        return order.compactMap { seen[$0] }
    }

    func describe(_ d: FoundDevice) -> String {
        guard let m = ModelInfo.match(d.name) else {
            return "Unknown model · " + (d.kind == .le ? "Bluetooth LE" : "classic Bluetooth")
        }
        var parts = [m.displayName, m.usesLE ? "Bluetooth LE" : "classic Bluetooth"]
        if !m.usesLE { parts.append(d.paired || WatchSession.pairedClassicAddress(name: d.name) != nil ? "paired with this Mac" : "pair in System Settings first") }
        if m.pake { parts.append("Honor secure pairing") }
        return parts.joined(separator: " · ")
    }

    var picker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your watch").font(.title2.bold())
            Text("Watch Fit 2 and newer use classic Bluetooth: pair the watch once in System Settings › Bluetooth, then connect here. A watch that was set up with Huawei Health on a phone must be factory-reset before it accepts a new companion.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if let p = scanner.bluetoothProblem { Label(p, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            switch session.status {
            case .connecting, .pairing:
                HStack { ProgressView().controlSize(.small); Text(session.statusDetail.isEmpty ? "Working…" : session.statusDetail)
                    Spacer(); Button("Cancel") { session.disconnect() } }
            case .failed(let m):
                Label(m, systemImage: "xmark.octagon.fill").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            default: EmptyView()
            }

            HStack {
                Button { scanner.scanning ? scanner.stop() : scanner.start() } label: {
                    Label(scanner.scanning ? "Stop scanning" : "Scan for watches", systemImage: "antenna.radiowaves.left.and.right")
                }
                if scanner.scanning { ProgressView().controlSize(.small) }
                Spacer()
                Button("Open Bluetooth Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
                }
            }

            if scanner.devices.isEmpty {
                Text(scanner.scanning ? "Searching…" : "No Huawei or Honor wearables found yet.")
                    .foregroundStyle(.secondary).padding(.vertical, 20)
            }
            ForEach(uniqueDevices) { d in
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "applewatch")
                            VStack(alignment: .leading) {
                                Text(d.name).font(.headline)
                                Text(describe(d)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Forget") { session.forgetPairing(d.id) }.buttonStyle(.link)
                            Button("Connect") { session.connect(d, watchMac: macs[d.id] ?? session.storedMac(for: d.id)) }
                                .buttonStyle(.borderedProminent)
                                .disabled(session.status == .connecting || session.status == .pairing)
                        }
                        if d.kind == .le {
                            TextField("Optional: watch Bluetooth address (only older models need it), e.g. A1:B2:C3:D4:E5:F6",
                                      text: Binding(get: { macs[d.id] ?? session.storedMac(for: d.id) }, set: { macs[d.id] = $0 }))
                                .textFieldStyle(.roundedBorder).font(.callout)
                        }
                    }.padding(4)
                }
            }
        }
        .onAppear { if scanner.devices.isEmpty { scanner.start() } }
    }
}

// MARK: - Health

struct HealthView: View {
    @EnvironmentObject var session: WatchSession
    @State private var days = 1
    @State private var hoverSteps: Date?
    @State private var hoverHR: Date?
    @State private var hoverSpO2: Date?


    struct Bucket: Identifiable { var id: Date { hour }; var hour: Date; var steps: Int }

    var shown: [StepSample] {
        let from = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-Double(days - 1) * 86400)
        return session.samples.filter { $0.time >= from }
    }

    var today: DayTotal? { session.dayTotals[Storage.dayKey(Date())] }

    var buckets: [Bucket] {
        let cal = Calendar.current
        var m: [Date: Int] = [:]
        for s in shown {
            let h = cal.dateInterval(of: days > 2 ? .day : .hour, for: s.time)?.start ?? s.time
            m[h, default: 0] += s.steps
        }
        return m.map { Bucket(hour: $0.key, steps: $0.value) }.sorted { $0.hour < $1.hour }
    }

    var body: some View {
        ScrollView { content }
    }

    var content: some View {
        Group {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Today").font(.title2.bold())
                    Spacer()
                    Picker("", selection: $days) {
                        Text("Today").tag(1); Text("3 days").tag(3); Text("7 days").tag(7)
                    }.pickerStyle(.segmented).frame(width: 220)
                    Button { session.syncHealth(days: days) } label: { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(session.syncing || !session.isReady)
                    if session.syncing { ProgressView().controlSize(.small) }
                }
                Text((session.lastSync.map { "Last synced " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not synced yet")
                     + " · \(session.samples.count) readings stored on this Mac" + (session.isReady ? "" : " · connect the watch to sync"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Stat(title: "Steps", value: (session.totalSteps ?? today?.steps).map { "\($0)" } ?? "–", icon: "figure.walk", color: .green)
                    Stat(title: "Calories", value: (session.totalCalories ?? today?.calories).map { "\($0) kcal" } ?? "–", icon: "flame.fill", color: .orange)
                    Stat(title: "Distance", value: (session.totalDistance ?? today?.distance).map { String(format: "%.2f km", Double($0) / 1000) } ?? "–",
                         icon: "map.fill", color: .blue)
                    Stat(title: "Latest heart rate", value: shown.last(where: { $0.heartRate != nil })?.heartRate.map { "\($0) bpm" } ?? "–",
                         icon: "heart.fill", color: .red)
                }
                if shown.isEmpty {
                    Text("Press Sync to download step and heart-rate history from the watch.").foregroundStyle(.secondary)
                } else {
                    let unit: Calendar.Component = days > 2 ? .day : .hour
                    GroupBox("Steps") {
                        let hit = nearest(buckets, to: hoverSteps.map { $0.addingTimeInterval(unit == .day ? -43200 : -1800) }) { $0.hour }
                        Chart {
                            ForEach(buckets) { b in
                                BarMark(x: .value("Time", b.hour, unit: unit), y: .value("Steps", b.steps))
                                    .foregroundStyle(.green.opacity(hit == nil || hit?.hour == b.hour ? 1 : 0.35))
                            }
                            if let hit {
                                RuleMark(x: .value("Time", hit.hour, unit: unit)).foregroundStyle(.clear)
                                    .annotation(position: .top, alignment: tipAlignment(buckets, hit) { $0.hour }) {
                                        ChartTip(value: "\(hit.steps) steps",
                                                 detail: unit == .day ? hit.hour.tipDay
                                                     : hit.hour.tipTime + "–" + hit.hour.addingTimeInterval(3600).formatted(date: .omitted, time: .shortened),
                                                 color: .green)
                                    }
                            }
                        }
                        .hoverDate($hoverSteps).frame(height: 180).padding(.top, 34).padding(6)
                    }
                    GroupBox("Heart rate") {
                        let hr = shown.filter { $0.heartRate != nil }
                        let hit = nearest(hr, to: hoverHR) { $0.time }
                        Chart {
                            ForEach(hr) { LineMark(x: .value("Time", $0.time), y: .value("bpm", $0.heartRate ?? 0)).foregroundStyle(.red) }
                            if let hit, let v = hit.heartRate {
                                RuleMark(x: .value("Time", hit.time)).foregroundStyle(.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                PointMark(x: .value("Time", hit.time), y: .value("bpm", v)).foregroundStyle(.red).symbolSize(80)
                                    .annotation(position: .top, alignment: tipAlignment(hr, hit) { $0.time }) {
                                        ChartTip(value: "\(v) bpm", detail: hit.time.tipTime, color: .red)
                                    }
                            }
                        }
                        .chartYScale(domain: 40 ... 180).hoverDate($hoverHR).frame(height: 180).padding(.top, 34).padding(6)
                    }
                    let spo = shown.filter { $0.spo2 != nil }
                    if !spo.isEmpty {
                        GroupBox("Blood oxygen") {
                            let hit = nearest(spo, to: hoverSpO2) { $0.time }
                            Chart {
                                ForEach(spo) { PointMark(x: .value("Time", $0.time), y: .value("%", $0.spo2 ?? 0)).foregroundStyle(.cyan) }
                                if let hit, let v = hit.spo2 {
                                    RuleMark(x: .value("Time", hit.time)).foregroundStyle(.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    PointMark(x: .value("Time", hit.time), y: .value("%", v)).foregroundStyle(.cyan).symbolSize(90)
                                        .annotation(position: .top, alignment: tipAlignment(spo, hit) { $0.time }) {
                                            ChartTip(value: "\(v)% SpO₂", detail: hit.time.tipTime, color: .cyan)
                                        }
                                }
                            }
                            .chartYScale(domain: 80 ... 100).hoverDate($hoverSpO2).frame(height: 140).padding(.top, 34).padding(6)
                        }
                    }
                }
            }.padding(24)
        }
    }
}

struct Stat: View {
    var title: String, value: String, icon: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(color)
            Text(value).font(.title3.bold().monospacedDigit())
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Notifications

struct NotifyView: View {
    @EnvironmentObject var session: WatchSession
    @State private var title = "Reminder"
    @State private var sender = "Mac"
    @State private var text = ""
    @State private var type = 0x7F

    var body: some View {
        Form {
            Section("Send a message to the watch") {
                Picker("Style", selection: $type) {
                    Text("App notification").tag(0x7F); Text("Text message").tag(0x02); Text("Email").tag(0x0F)
                }
                TextField("Title", text: $title)
                TextField("From", text: $sender)
                TextField("Message", text: $text, axis: .vertical).lineLimit(3 ... 6)
                HStack {
                    Spacer()
                    Button("Send to watch") { session.sendNotification(title: title, sender: sender, body: text, type: type) }
                        .buttonStyle(.borderedProminent).disabled(text.isEmpty && title.isEmpty)
                }
            }
            Section {
                Text("macOS does not let apps read other apps' notifications, so WatchDeck sends the messages you type here. Automatic mirroring of Mac notifications is not included.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

// MARK: - Alarms

struct AlarmsView: View {
    @EnvironmentObject var session: WatchSession
    @State private var draft: [WatchAlarm] = []
    static let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Alarms").font(.title2.bold())
                Spacer()
                Button { draft.append(WatchAlarm(index: draft.count + 1)) } label: { Label("Add", systemImage: "plus") }.disabled(draft.count >= 5)
                Button("Save to watch") { session.saveAlarms(draft) }.buttonStyle(.borderedProminent)
            }
            if draft.isEmpty { Text("No alarms. The watch stores up to five.").foregroundStyle(.secondary) }
            ForEach($draft) { $a in
                GroupBox {
                    HStack(spacing: 12) {
                        Toggle("", isOn: $a.enabled).labelsHidden()
                        Picker("", selection: $a.hour) { ForEach(0 ..< 24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 64)
                        Text(":")
                        Picker("", selection: $a.minute) { ForEach(0 ..< 60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 64)
                        TextField("Name", text: $a.name).frame(width: 110)
                        ForEach(0 ..< 7, id: \.self) { d in
                            Toggle(Self.days[d], isOn: Binding(get: { a.repeatMask & (1 << d) != 0 },
                                                               set: { a.repeatMask = $0 ? a.repeatMask | (1 << d) : a.repeatMask & ~(1 << d) }))
                                .toggleStyle(.button).controlSize(.small)
                        }
                        Spacer()
                        Button(role: .destructive) { draft.removeAll { $0.index == a.index } } label: { Image(systemName: "trash") }
                    }.padding(4)
                }
            }
            Spacer()
        }
        .padding(24)
        .onAppear { draft = session.alarms }
        .onChange(of: session.alarms) { draft = $0 }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var session: WatchSession
    @AppStorage("set.raise") private var raise = true
    @AppStorage("set.gpsAssist") private var gpsAssist = true
    @AppStorage("set.rotate") private var rotate = false
    @AppStorage("set.right") private var wearRight = false
    @AppStorage("set.hr") private var autoHR = true
    @AppStorage("set.spo") private var autoSpO = false
    @AppStorage("set.24h") private var is24h = true
    @AppStorage("set.datefmt") private var dateFormat = 1
    @AppStorage("set.locale") private var locale = "en-GB"
    @AppStorage("set.imperial") private var imperial = false
    @AppStorage("set.goal") private var goal = 10000
    @AppStorage("set.dnd") private var dnd = false
    @AppStorage("set.dndStart") private var dndStart = 22
    @AppStorage("set.dndEnd") private var dndEnd = 7

    var body: some View {
        Form {
            Section("Display & wearing") {
                Toggle("Raise wrist to wake screen", isOn: $raise).onChange(of: raise) { session.setRaiseToWake($0) }
                Toggle("Rotate wrist to switch screens", isOn: $rotate).onChange(of: rotate) { session.setRotateToSwitch($0) }
                Picker("Worn on", selection: $wearRight) { Text("Left wrist").tag(false); Text("Right wrist").tag(true) }
                    .onChange(of: wearRight) { session.setWearRight($0) }
            }
            Section("Time & language") {
                Toggle("24-hour clock", isOn: $is24h).onChange(of: is24h) { session.setTimeFormat(is24h: $0, dateFormat: dateFormat) }
                Picker("Date format", selection: $dateFormat) {
                    Text("Year / Month / Day").tag(1); Text("Month / Day / Year").tag(2); Text("Day / Month / Year").tag(3)
                }.onChange(of: dateFormat) { session.setTimeFormat(is24h: is24h, dateFormat: $0) }
                Picker("Language", selection: $locale) {
                    ForEach(["en-GB", "en-US", "id-ID", "ja-JP", "zh-CN", "zh-TW", "ko-KR", "de-DE", "fr-FR", "es-ES", "it-IT", "nl-NL", "pt-PT", "ru-RU", "th-TH", "vi-VN", "ms-MY"], id: \.self) {
                        Text(Locale.current.localizedString(forIdentifier: $0) ?? $0).tag($0)
                    }
                }.onChange(of: locale) { session.setLanguage($0, imperial: imperial) }
                Picker("Units", selection: $imperial) { Text("Metric").tag(false); Text("Imperial").tag(true) }
                    .onChange(of: imperial) { session.setLanguage(locale, imperial: $0) }
                Button("Sync time from this Mac") { session.syncTimeNow() }
            }
            Section("GPS assist") {
                Toggle("Send this Mac's location and exact time to the watch", isOn: $gpsAssist)
                Text(session.gpsAssistStatus).font(.callout).foregroundStyle(.secondary)
                Button("Send now") { Task { await session.sendGPSAssist() } }
                Text("Sent when the watch connects and every 30 minutes while connected. It helps most if you start an outdoor workout soon after leaving the Mac; the watch still needs open sky for its first satellites.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Health monitoring") {
                Toggle("Continuous heart-rate monitoring", isOn: $autoHR).onChange(of: autoHR) { session.setAutoHeartRate($0) }
                Toggle("Automatic SpO₂ measurement", isOn: $autoSpO).onChange(of: autoSpO) { session.setAutoSpO2($0) }
                Stepper("Daily step goal: \(goal)", value: $goal, in: 1000 ... 50000, step: 500)
                Button("Send step goal") { session.setStepGoal(goal) }
            }
            Section("Do not disturb") {
                Toggle("Scheduled every day", isOn: $dnd)
                Stepper("From \(String(format: "%02d:00", dndStart))", value: $dndStart, in: 0 ... 23)
                Stepper("Until \(String(format: "%02d:00", dndEnd))", value: $dndEnd, in: 0 ... 23)
                Button("Apply do-not-disturb schedule") {
                    session.setDoNotDisturb(enabled: dnd, startHour: dndStart, startMinute: 0, endHour: dndEnd, endMinute: 0)
                }
            }
            Section {
                Text("The watch does not report these settings back, so the switches show what WatchDeck last sent.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

// MARK: - Log

struct LogView: View {
    @EnvironmentObject var session: WatchSession
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Protocol log").font(.title2.bold())
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.log.joined(separator: "\n"), forType: .string)
                }
                Button("Clear") { session.log.removeAll() }
            }.padding(20)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(session.log.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).id(i)
                        }
                    }.padding(.horizontal, 20)
                }
                .onChange(of: session.log.count) { n in proxy.scrollTo(n - 1, anchor: .bottom) }
            }
        }
    }
}
