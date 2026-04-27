import SwiftUI

struct CopyVideosView: View {
    var onComplete: (() -> Void)? = nil

    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let settings = GlobalSettings.shared

    private struct CamSource: Identifiable {
        let id: String
        let displayName: String
        let folderName: String
        let sourceURL: URL
    }

    @State private var enabledCameras: Set<String> = ["fly12", "fly6"]
    @State private var rideName: String = ""
    @State private var selectedDate: Date? = nil
    @State private var availableDates: [(date: Date, count: Int)] = []
    @State private var isScanning = false
    @State private var isCopying = false
    @State private var totalFiles = 0
    @State private var copiedFiles = 0
    @State private var logLines: [(String, Bool)] = []
    @State private var copyDoneMessage: String? = nil

    private var configuredCameras: [CamSource] {
        var result: [CamSource] = []
        if settings.hasFly12Sport, let url = settings.fly12SourceURL {
            result.append(CamSource(id: "fly12", displayName: "Fly12 Sport",
                                    folderName: "Fly12Sport", sourceURL: url))
        }
        if settings.hasFly6Pro, let url = settings.fly6SourceURL {
            result.append(CamSource(id: "fly6", displayName: "Fly6 Pro",
                                    folderName: "Fly6Pro", sourceURL: url))
        }
        return result
    }

    private var activeCameras: [CamSource] {
        configuredCameras.filter { enabledCameras.contains($0.id) }
    }

    private var isConfigured: Bool { !configuredCameras.isEmpty }

    private var outputFolderName: String {
        var parts: [String] = []
        if let d = selectedDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            parts.append(f.string(from: d))
        }
        let name = rideName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { parts.append(name) }
        return parts.joined(separator: " ")
    }

    private var canStart: Bool {
        !isCopying && !activeCameras.isEmpty &&
        settings.inputBaseDir != nil &&
        selectedDate != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isCopying {
                    copyProgressView
                        .navigationTitle("Copying…")
                } else if !isConfigured {
                    notConfiguredView
                        .navigationTitle("Copy Camera Videos")
                } else {
                    setupView
                        .navigationTitle("Copy Camera Videos")
                        .onAppear { Task { await scanSources() } }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 440)
        .alert("Copy Complete", isPresented: Binding(
            get: { copyDoneMessage != nil },
            set: { if !$0 { copyDoneMessage = nil } }
        )) {
            Button("OK") { copyDoneMessage = nil }
        } message: {
            Text(copyDoneMessage ?? "")
        }
    }

    // MARK: - Not configured

    private var notConfiguredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sdcard")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera sources not set")
                .font(.title2.bold())
            Text("Set your Fly12 Sport and Fly6 Pro source folders in Settings → Cameras.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
#if os(macOS)
            Text("Open **VeloFilms → Settings…** or press **⌘,** to get started.")
                .multilineTextAlignment(.center)
#endif
        }
        .padding(40)
    }

    // MARK: - Setup form

    private var setupView: some View {
        Form {
            Section("Source Camera") {
                ForEach(configuredCameras) { cam in
                    cameraRow(cam)
                }
            }

            Section(header: HStack {
                Text("Select Date")
                Spacer()
                Button { Task { await scanSources() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                }
                .disabled(isScanning || activeCameras.isEmpty)
            }) {
                if isScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scanning…").foregroundStyle(.secondary)
                    }
                } else if activeCameras.isEmpty {
                    Text("Select at least one camera above")
                        .foregroundStyle(.secondary).font(.caption)
                } else if availableDates.isEmpty {
                    Text("No MP4 files found — check source folders in Settings")
                        .foregroundStyle(.secondary).font(.caption)
                } else {
                    dateRow(date: nil,
                            count: availableDates.reduce(0) { $0 + $1.count },
                            label: "All dates")
                    ForEach(availableDates, id: \.date) { item in
                        dateRow(date: item.date, count: item.count)
                    }
                }
            }

            Section("Ride Details") {
                HStack {
                    Text("Name")
                    TextField("e.g. Wahgunyah Loop", text: $rideName)
                }
                HStack {
                    Text("Output folder").foregroundStyle(.secondary)
                    Spacer()
                    Text(outputFolderName.isEmpty ? "—" : outputFolderName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section("Destination Drive") {
                if let dest = settings.inputBaseDir {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dest.lastPathComponent).font(.body)
                        Text(dest.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text("Not set — configure Input Videos in Settings").foregroundStyle(.red)
                }
            }

            Section {
                Button(action: startCopy) {
                    Label("Copy to Destination", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }
        }
    }

    // MARK: - Camera row

    @ViewBuilder
    private func cameraRow(_ cam: CamSource) -> some View {
        Toggle(cam.displayName, isOn: Binding(
            get: { enabledCameras.contains(cam.id) },
            set: { on in
                if on { enabledCameras.insert(cam.id) }
                else  { enabledCameras.remove(cam.id) }
                Task { await scanSources() }
            }
        ))
    }

    // MARK: - Date row

    @ViewBuilder
    private func dateRow(date: Date?, count: Int, label: String? = nil) -> some View {
        Button { selectedDate = date } label: {
            HStack {
                if let label {
                    Text(label)
                } else if let d = date {
                    Text(d, format: .dateTime.weekday(.wide).day().month(.wide).year())
                }
                Spacer()
                Text("\(count) file\(count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary).font(.caption)
                if selectedDate == date {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Progress view

    private var copyProgressView: some View {
        VStack(spacing: 0) {
            if totalFiles > 0 {
                VStack(spacing: 4) {
                    ProgressView(value: Double(copiedFiles), total: Double(totalFiles))
                        .padding(.horizontal).padding(.top, 12)
                    Text("\(copiedFiles) / \(totalFiles) files")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            } else {
                ProgressView("Preparing…").padding()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { i, entry in
                            Text(entry.0)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(entry.1 ? .red : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .background(logBackground)
                .onChange(of: logLines.count) { proxy.scrollTo(logLines.count - 1, anchor: .bottom) }
            }
        }
    }

    private var logBackground: Color {
#if os(macOS)
        Color(nsColor: .textBackgroundColor)
#else
        Color(uiColor: .secondarySystemBackground)
#endif
    }

    // MARK: - Scan

    private func scanSources() async {
        isScanning = true
        var combined: [Date: Int] = [:]
        let cal = Calendar.current
        let fm = FileManager.default
        for cam in activeCameras {
            let files = (try? fm.contentsOfDirectory(
                at: cam.sourceURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles)) ?? []
            for url in files {
                guard url.pathExtension.uppercased() == "MP4",
                      let mtime = try? url.resourceValues(
                          forKeys: [.contentModificationDateKey]).contentModificationDate
                else { continue }
                let day = cal.startOfDay(for: mtime)
                combined[day, default: 0] += 1
            }
        }
        let sorted = combined.map { (date: $0.key, count: $0.value) }.sorted { $0.date < $1.date }
        availableDates = sorted
        if let current = selectedDate, !sorted.contains(where: { $0.date == current }) {
            selectedDate = sorted.last?.date
        } else if selectedDate == nil {
            selectedDate = sorted.last?.date
        }
        isScanning = false
    }

    // MARK: - Copy

    private func startCopy() {
        guard let destBase = settings.inputBaseDir, !outputFolderName.isEmpty else { return }
        isCopying = true; copiedFiles = 0; totalFiles = 0; logLines = []
        Task { await runCopy(destBase: destBase) }
    }

    @MainActor
    private func runCopy(destBase: URL) async {
        let destFolder = destBase.appending(path: outputFolderName)
        let fm = FileManager.default
        let cal = Calendar.current

        append("=== Cycliq Copy ===")
        if let d = selectedDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            append("Date filter: \(f.string(from: d))")
        }
        append("Output: \(destFolder.path)")

        var allJobs: [(src: URL, dst: URL)] = []
        for cam in activeCameras {
            let files = (try? fm.contentsOfDirectory(
                at: cam.sourceURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles)) ?? []
            var matching: [URL] = files.filter { url in
                guard url.pathExtension.uppercased() == "MP4" else { return false }
                if let target = selectedDate {
                    guard let mtime = try? url.resourceValues(
                              forKeys: [.contentModificationDateKey]).contentModificationDate,
                          cal.startOfDay(for: mtime) == cal.startOfDay(for: target)
                    else { return false }
                }
                return true
            }
            matching.sort { $0.lastPathComponent < $1.lastPathComponent }
            append("\(cam.displayName): \(matching.count) file\(matching.count == 1 ? "" : "s") found")

            for src in matching {
                let stem = src.deletingPathExtension().lastPathComponent
                let number = stem.components(separatedBy: "_").last ?? stem
                let outName = "\(cam.folderName)_\(number).MP4"
                allJobs.append((src: src, dst: destFolder.appending(path: outName)))
            }
        }

        guard !allJobs.isEmpty else {
            append("⚠️ Nothing to copy.", error: true)
            isCopying = false
            return
        }
        totalFiles = allJobs.count

        do {
            try fm.createDirectory(at: destFolder, withIntermediateDirectories: true)
        } catch {
            append("❌ Could not create output folder: \(error.localizedDescription)", error: true)
            isCopying = false
            return
        }

        var totalBytes = 0; var totalSecs = 0.0
        for (i, job) in allJobs.enumerated() {
            let fileSize = (try? job.src.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let start = Date()
            let src = job.src; let dst = job.dst
            do {
                try await Task.detached(priority: .userInitiated) {
                    if FileManager.default.fileExists(atPath: dst.path) {
                        try FileManager.default.removeItem(at: dst)
                    }
                    try FileManager.default.copyItem(at: src, to: dst)
                }.value
                let elapsed = Date().timeIntervalSince(start)
                let speed = elapsed > 0 ? Double(fileSize) / elapsed : 0
                totalBytes += fileSize; totalSecs += elapsed
                copiedFiles = i + 1
                append("✓ \(dst.lastPathComponent) (\(formatSize(fileSize)) @ \(formatSpeed(speed)))")
            } catch {
                append("❌ \(src.lastPathComponent): \(error.localizedDescription)", error: true)
            }
        }

        let avgSpeed = totalSecs > 0 ? Double(totalBytes) / totalSecs : 0
        append("=== Done ===")
        append("✓ \(copiedFiles) files  •  \(formatSize(totalBytes))  •  avg \(formatSpeed(avgSpeed))")
        isCopying = false

        // Create project pointing at the destination folder as the video source
        if let root = settings.projectsRoot {
            let projURL = root.appending(path: outputFolderName)
            let project = Project(name: outputFolderName, folderURL: projURL,
                                  sourceVideoURL: destFolder)
            try? ProjectFileManager.createDirectoryStructure(for: project)
            if !store.projects.contains(where: { $0.name == outputFolderName }) {
                store.add(project)
                append("✓ Project '\(outputFolderName)' added")
            }
        }

        copyDoneMessage = "\(copiedFiles) file\(copiedFiles == 1 ? "" : "s") copied" +
                          "\n\(formatSize(totalBytes)) at avg \(formatSpeed(avgSpeed))"
    }

    private func append(_ msg: String, error: Bool = false) { logLines.append((msg, error)) }

    private func formatSize(_ bytes: Int) -> String {
        let d = Double(bytes)
        if d < 1024          { return String(format: "%.0fB", d) }
        if d < 1_048_576     { return String(format: "%.1fKB", d / 1024) }
        if d < 1_073_741_824 { return String(format: "%.1fMB", d / 1_048_576) }
        return String(format: "%.2fGB", d / 1_073_741_824)
    }

    private func formatSpeed(_ bps: Double) -> String { "\(formatSize(Int(bps)))/s" }
}
