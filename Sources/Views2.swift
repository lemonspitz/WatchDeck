import SwiftUI
import Charts
import UniformTypeIdentifiers

func hm(_ minutes: Int) -> String { "\(minutes / 60) h \(minutes % 60) min" }

// MARK: - Sleep

struct SleepView: View {
    @EnvironmentObject var session: WatchSession
    @State private var selected: Date?
    @State private var hoverStage: Date?
    @State private var hoverNight: Date?

    var nights: [Night] { session.nights }
    var current: Night? { nights.first { $0.day == selected } ?? nights.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Sleep").font(.title2.bold())
                    Spacer()
                    Button { session.syncHealth(days: 7) } label: { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(session.syncing || !session.isReady)
                    if session.syncing { ProgressView().controlSize(.small) }
                }
                Text((session.lastSync.map { "Last synced " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not synced yet")
                     + " · \(nights.count) nights stored on this Mac" + (session.isReady ? "" : " · connect the watch to sync"))
                    .font(.caption).foregroundStyle(.secondary)

                if let n = current {
                    HStack(spacing: 12) {
                        Stat(title: "Total sleep", value: hm(n.total), icon: "bed.double.fill", color: .indigo)
                        Stat(title: "Deep", value: hm(n.deep), icon: "moon.zzz.fill", color: .purple)
                        Stat(title: "Light", value: hm(n.light), icon: "moon.fill", color: .blue)
                        Stat(title: "Bedtime → wake", value: n.bedtime.formatted(date: .omitted, time: .shortened) + " → "
                             + n.wake.formatted(date: .omitted, time: .shortened), icon: "clock.fill", color: .teal)
                    }
                    GroupBox("Night ending " + n.day.formatted(date: .complete, time: .omitted)) {
                        let seg = hoverStage.flatMap { t in n.segments.first { $0.start <= t && t < $0.end } }
                            ?? nearest(n.segments, to: hoverStage) { $0.start.addingTimeInterval($0.end.timeIntervalSince($0.start) / 2) }
                        Chart {
                            ForEach(n.segments) { s in
                                BarMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end), y: .value("Stage", s.isDeep ? "Deep" : "Light"))
                                    .foregroundStyle((s.isDeep ? Color.purple : Color.blue).opacity(seg == nil || seg == s ? 1 : 0.4))
                            }
                            if let seg {
                                RuleMark(x: .value("Time", seg.start.addingTimeInterval(seg.end.timeIntervalSince(seg.start) / 2))).foregroundStyle(.clear)
                                    .annotation(position: .top, alignment: tipAlignment(n.segments, seg) { $0.start }) {
                                        ChartTip(value: (seg.isDeep ? "Deep sleep · " : "Light sleep · ") + hm(seg.minutes),
                                                 detail: seg.start.formatted(date: .omitted, time: .shortened) + " – " + seg.end.formatted(date: .omitted, time: .shortened),
                                                 color: seg.isDeep ? .purple : .blue)
                                    }
                            }
                        }
                        .hoverDate($hoverStage).frame(height: 110).padding(.top, 34).padding(6)
                    }
                    GroupBox("Recent nights") {
                        let recent = Array(nights.suffix(14))
                        let hit = nearest(recent, to: hoverNight.map { $0.addingTimeInterval(-43200) }) { $0.day }
                        Chart {
                            ForEach(recent) { night in
                                BarMark(x: .value("Day", night.day, unit: .day), y: .value("Hours", Double(night.deep) / 60))
                                    .foregroundStyle(by: .value("Stage", "Deep")).opacity(hit == nil || hit?.day == night.day ? 1 : 0.4)
                                BarMark(x: .value("Day", night.day, unit: .day), y: .value("Hours", Double(night.light) / 60))
                                    .foregroundStyle(by: .value("Stage", "Light")).opacity(hit == nil || hit?.day == night.day ? 1 : 0.4)
                            }
                            if let hit {
                                RuleMark(x: .value("Day", hit.day, unit: .day)).foregroundStyle(.clear)
                                    .annotation(position: .top, alignment: tipAlignment(recent, hit) { $0.day }) {
                                        ChartTip(value: hm(hit.total) + " asleep",
                                                 detail: hit.day.tipDay + " · deep " + hm(hit.deep) + " · light " + hm(hit.light), color: .indigo)
                                    }
                            }
                        }
                        .hoverDate($hoverNight).padding(.top, 34)
                        .chartForegroundStyleScale(["Deep": Color.purple, "Light": Color.blue])
                        .frame(height: 180).padding(6)
                    }
                    GroupBox("History") {
                        VStack(spacing: 0) {
                            ForEach(nights.reversed()) { night in
                                Button { selected = night.day } label: {
                                    HStack {
                                        Text(night.day.formatted(date: .abbreviated, time: .omitted)).frame(width: 130, alignment: .leading)
                                        Text(hm(night.total)).monospacedDigit().frame(width: 110, alignment: .leading)
                                        Text("deep " + hm(night.deep)).foregroundStyle(.secondary)
                                        Spacer()
                                        if night.day == n.day { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                    }.padding(.vertical, 5).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }.padding(6)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "bed.double").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("No sleep recorded yet").font(.title3)
                        Text("Wear the watch overnight, then press Sync. Nights are kept on this Mac after each sync.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.top, 60)
                }
            }.padding(24)
        }
    }
}

// MARK: - Watch faces

/// A watch-shaped preview: tall rounded rectangle, or a circle for round screens.
struct FacePreview: View {
    var image: NSImage?
    var screen: String = "280 × 456"

    var dims: (CGFloat, CGFloat) {
        let n = screen.split(separator: " ").compactMap { Double($0) }
        return n.count == 2 && n[0] > 0 ? (n[0], n[1]) : (280, 456)
    }
    var round: Bool { dims.0 == dims.1 }

    var body: some View {
        let (w, h) = dims
        let scale = min(140 / w, 182 / h)
        let shape = round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 22 * scale * w / 140 + 8))
        ZStack {
            shape.fill(Color.black)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo").font(.title)
                    Text("No preview").font(.caption2)
                }.foregroundStyle(.gray)
            }
        }
        .frame(width: w * scale, height: h * scale)
        .clipShape(shape)
        .overlay(shape.stroke(.gray.opacity(0.5), lineWidth: 3))
        .frame(width: 140, height: 182)
    }
}

struct FacesView: View {
    @EnvironmentObject var session: WatchSession
    @State private var toDelete: WatchFace?
    @State private var renaming: WatchFace?
    @State private var newName = ""
    @State private var category = "All"
    @State private var search = ""
    @State private var making = false
    @State private var makeError: String?

    var categories: [String] { ["All"] + Array(Set(session.library.map(\.category))).sorted() }

    var shownLibrary: [LibraryFace] {
        session.library.filter { item in
            (category == "All" || item.category == category)
                && (search.isEmpty || item.title.localizedCaseInsensitiveContains(search))
        }
    }
    let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    /// Active face first, then faces with a known design, then the rest.
    var sortedFaces: [WatchFace] {
        func rank(_ f: WatchFace) -> Int { f.isCurrent ? 0 : session.faceMeta[f.fileName]?.preview != nil ? 1 : 2 }
        return session.faces.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Watch faces").font(.title2.bold())
                        if !session.faceSize.isEmpty { Text("Watch screen \(session.faceSize)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if let p = session.uploadProgress { ProgressView(value: p).frame(width: 140); Text("\(Int(p * 100))%").monospacedDigit() }
                    Button { session.refreshFacesNow() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(!session.isReady)
                }

                Text("On the watch").font(.headline)
                if !session.isReady {
                    Text("Connect the watch to see and switch the faces stored on it.").foregroundStyle(.secondary)
                } else if session.faces.isEmpty {
                    Text("The watch reported no watch faces.").foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(sortedFaces) { f in
                            VStack(spacing: 6) {
                                FacePreview(image: session.previewImage(for: f), screen: session.faceSize.isEmpty ? "280 × 456" : session.faceSize)
                                    .overlay(alignment: .topTrailing) {
                                        if f.isCurrent {
                                            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.white, .green).padding(6)
                                        }
                                    }
                                Text(session.displayTitle(for: f)).font(.callout.weight(.medium)).lineLimit(1)
                                Text(f.isFactory ? "Built-in" : "v\(f.version)").font(.caption2).foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    if f.isCurrent { Text("Active").font(.caption).foregroundStyle(.green) }
                                    else { Button("Use") { session.faceOperation(f, delete: false) }.controlSize(.small) }
                                    Menu {
                                        Button("Choose picture…") { choosePicture(for: f) }
                                        Button("Rename…") { newName = session.displayTitle(for: f); renaming = f }
                                        if !f.isFactory { Divider(); Button("Delete from watch", role: .destructive) { toDelete = f } }
                                    } label: { Image(systemName: "ellipsis.circle") }
                                        .menuStyle(.borderlessButton).fixedSize()
                                }
                            }
                        }
                    }
                    Text("The watch does not send artwork for faces already on it. Use ⋯ › Choose picture to attach a photo or screenshot; faces you install from the library below show their design automatically.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }

                Divider().padding(.vertical, 4)
                HStack {
                    Text("Library on this Mac").font(.headline)
                    Text("\(shownLibrary.count) of \(session.library.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { makeFaces() } label: {
                        Label(making ? "Making faces…" : "Make 500 faces for \(targetSize)", systemImage: "wand.and.stars")
                    }
                    .disabled(making)
                    .help("Draws WatchDeck's 500 designs for this screen size on this Mac")
                    Button { addFiles() } label: { Label("Add .hwt files…", systemImage: "plus") }
                    Button { addFolder() } label: { Label("Add folder…", systemImage: "folder.badge.plus") }
                    Button("Show folder") { NSWorkspace.shared.open(session.faceFolders.last ?? Storage.faces) }
                }
                if !session.library.isEmpty || !session.librarySizes.isEmpty {
                    HStack {
                        Picker("Screen", selection: $session.librarySize) {
                            ForEach(["All"] + session.librarySizes, id: \.self) { size in
                                Text(size == session.faceSize ? "\(size) (this watch)" : size).tag(size)
                            }
                        }
                        .frame(width: 230)
                        .onChange(of: session.librarySize) { v in
                            UserDefaults.standard.set(v, forKey: "librarySize")
                            session.reloadLibrary()
                        }
                        Picker("Type", selection: $category) { ForEach(categories, id: \.self) { Text($0).tag($0) } }
                            .frame(width: 220)
                        TextField("Search by name", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                        Spacer()
                    }
                }
                if let makeError { Text(makeError).font(.caption).foregroundStyle(.orange) }
                if session.library.isEmpty {
                    Text("Press Make 500 faces to draw WatchDeck's designs for your watch, or add Huawei watch-face files (.hwt) to browse their designs here and install them with one click.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(shownLibrary) { item in
                            VStack(spacing: 6) {
                                FacePreview(image: item.preview.flatMap { NSImage(contentsOf: $0) }, screen: item.screen)
                                Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                                Text(item.category + (item.screen.isEmpty ? "" : " · " + item.screen)).font(.caption2)
                                    .foregroundStyle(mismatch(item) ? .orange : .secondary).lineLimit(1)
                                HStack(spacing: 6) {
                                    Button("Install") { session.install(item) }.controlSize(.small)
                                        .disabled(!session.isReady || session.uploadProgress != nil)
                                    Button(role: .destructive) { session.removeFromLibrary(item) } label: { Image(systemName: "trash") }
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }.padding(24)
        }
        .onAppear { session.reloadLibrary() }
        .confirmationDialog("Delete this watch face from the watch?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Delete", role: .destructive) { if let f = toDelete { session.faceOperation(f, delete: true) }; toDelete = nil }
        }
        .alert("Rename watch face", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { if let f = renaming { session.rename(f, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    func mismatch(_ item: LibraryFace) -> Bool {
        !item.screen.isEmpty && !session.faceSize.isEmpty && item.screen != session.faceSize
    }

    /// The screen size faces are made for: the connected watch's, else the size picked in the library.
    var targetSize: String {
        if !session.faceSize.isEmpty { return session.faceSize }
        return session.librarySize == "All" ? "280 × 456" : session.librarySize
    }

    /// Runs the bundled facemaker tool for one screen size into the app's own face folder.
    func makeFaces() {
        let tool = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/facemaker")
        let size = targetSize.replacingOccurrences(of: " × ", with: "x")
        making = true; makeError = nil
        Task.detached {
            let p = Process()
            p.executableURL = tool
            p.arguments = [Storage.faces.path, size]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            var message: String?
            do {
                try p.run(); p.waitUntilExit()
                let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if p.terminationStatus != 0 { message = "Making faces failed: " + out.suffix(200) }
                else if !out.contains(" faces ") { message = "WatchDeck has no designs for a \(size) screen yet." }
            } catch { message = "Could not run the face maker: \(error.localizedDescription)" }
            await MainActor.run {
                making = false; makeError = message
                session.librarySize = targetSize
                session.reloadLibrary()
            }
        }
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder of watch faces (it may contain size folders such as HWHD06-280x456)"
        if panel.runModal() == .OK, let url = panel.url { session.addFaceFolder(url) }
    }

    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "hwt") ?? .data, .data]
        panel.message = "Choose Huawei watch-face files (.hwt)"
        if panel.runModal() == .OK { session.addToLibrary(panel.urls) }
    }

    func choosePicture(for face: WatchFace) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a picture of this watch face"
        if panel.runModal() == .OK, let url = panel.url { session.setPicture(url, for: face) }
    }
}
