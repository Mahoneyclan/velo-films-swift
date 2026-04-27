import SwiftUI

// MARK: - Camera model

private struct CameraConfig {
    let key: String
    let displayName: String
    let folderName: String   // prefix used in output filenames: Fly12Sport_001.MP4
    let volumeURL: URL
    var sourcePath: URL { volumeURL.appending(path: "DCIM/100_Ride") }
}

private let cameras: [CameraConfig] = [
    CameraConfig(key: "fly12", displayName: "Fly12 Sport", folderName: "Fly12Sport",
                 volumeURL: URL(filePath: "/Volumes/FLY12S")),
    CameraConfig(key: "fly6",  displayName: "Fly6 Pro",    folderName: "Fly6Pro",
                 volumeURL: URL(filePath: "/Volumes/FLY6PRO")),
]

// MARK: - View

struct CopyVideosView: View {
    var onComplete: (() -> Void)? = nil

    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var rideName: String = ""
    @State private var rideDate: Date  = Date()
    @State private var selected: Set<String> = ["fly12", "fly6"]

    // Per-camera state — refreshed whenever date or destination changes
    @State private var mounted:      [String: Bool] = [:]
    @State private var sourceCounts: [String: Int]  = [:]   // files on SD matching this date
    @State private var destCounts:   [String: Int]  = [:]   // files already copied to destination

    @State private var isCopying = false
    @State private var copied    = 0
    @State private var total     = 0
    @State private var logLines: [(String, Bool)] = []

    private var dateStr: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: rideDate)
    }
    private var folderName: String {
        "\(dateStr) \(rideName)".trimmingCharacters(in: .whitespaces)
    }
    private var destFolder: URL? {
        guard !rideName.trimmingCharacters(in: .whitespaces).isEmpty,
              let base = GlobalSettings.shared.inputBaseDir else { return nil }
        return base.appending(path: folderName)
    }

    // Cameras active based on user's setup
    private var activeCameras: [CameraConfig] {
        let s = GlobalSettings.shared
        return cameras.filter { cam in
            switch cam.key {
            case "fly12": return s.hasFly12Sport
            case "fly6":  return s.hasFly6Pro
            default:      return false
            }
        }
    }

    // Only cameras that are both selected and mounted (with files for this date)
    private var readyToMount: Set<String> {
        activeCameras.filter { cam in
            selected.contains(cam.key)
            && (mounted[cam.key] == true)
            && (sourceCounts[cam.key] ?? 0) > 0
        }.map(\.key).reduce(into: Set()) { $0.insert($1) }
    }

    private var canStart: Bool {
        !rideName.trimmingCharacters(in: .whitespaces).isEmpty
        && !readyToMount.isEmpty
        && !isCopying
    }

    // Are all expected cameras done?
    private var allCopied: Bool {
        activeCameras.allSatisfy { (destCounts[$0.key] ?? 0) > 0 }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isCopying {
                    copyProgress
                } else {
                    setupForm
                }
            }
            .navigationTitle("Copy Camera Videos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 440)
        .task { refresh() }
        .onChange(of: rideDate) { refresh() }
        .onChange(of: rideName) { refreshDestCounts() }
    }

    // MARK: - Setup form

    private var setupForm: some View {
        Form {
            Section("Ride") {
                DatePicker("Date", selection: $rideDate, displayedComponents: .date)
                TextField("Ride name (e.g. Wahgunyah)", text: $rideName)
            }

            Section {
                ForEach(activeCameras, id: \.key) { cam in
                    cameraRow(cam)
                }
            } header: {
                Text("Cameras")
            } footer: {
                Text("Insert one SD card at a time. Copy from each card separately — files are added to the same destination folder.")
                    .font(.caption)
            }

            if let dest = destFolder {
                Section("Destination") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(dest.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        if allCopied {
                            Label("All cameras copied", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.callout)
                        } else if destCounts.values.contains(where: { $0 > 0 }) {
                            Label("Partial — insert the next SD card and copy again",
                                  systemImage: "sdcard")
                                .foregroundStyle(.orange).font(.callout)
                        }
                    }
                }
            }

            Section {
                Button(action: startCopy) {
                    Label("Copy from Mounted Camera", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }
        }
    }

    @ViewBuilder
    private func cameraRow(_ cam: CameraConfig) -> some View {
        let isMtd    = mounted[cam.key] == true
        let srcCount = sourceCounts[cam.key] ?? 0
        let dstCount = destCounts[cam.key] ?? 0

        Toggle(isOn: Binding(
            get: { selected.contains(cam.key) },
            set: { on in if on { selected.insert(cam.key) } else { selected.remove(cam.key) } }
        )) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isMtd ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(cam.displayName).font(.body)

                    if isMtd {
                        if srcCount > 0 {
                            Text("\(srcCount) clip\(srcCount == 1 ? "" : "s") found for \(dateStr)")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("No clips for \(dateStr) — check date or card")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    } else {
                        Text("Not mounted — insert SD card")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if dstCount > 0 {
                        Label("\(dstCount) file\(dstCount == 1 ? "" : "s") already copied",
                              systemImage: "checkmark.circle.fill")
                            .font(.caption2).foregroundStyle(.green)
                    }
                }
            }
        }
        .disabled(!isMtd || srcCount == 0)
    }

    // MARK: - Progress view

    private var copyProgress: some View {
        VStack(spacing: 0) {
            if total > 0 {
                ProgressView(value: Double(copied), total: Double(total))
                    .padding(.horizontal).padding(.top, 12)
                Text("\(copied) / \(total) files").font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            } else {
                ProgressView("Starting…").padding()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { i, line in
                            Text(line.0)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.1 ? .red : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .background(logBackground)
                .onChange(of: logLines.count) {
                    proxy.scrollTo(logLines.count - 1, anchor: .bottom)
                }
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

    // MARK: - State refresh

    private func refresh() {
        refreshMountedState()
        refreshDestCounts()
    }

    private func refreshMountedState() {
        let fm  = FileManager.default
        let cal = Calendar.current
        let targetDay = cal.startOfDay(for: rideDate)
        var newMounted:  [String: Bool] = [:]
        var newCounts:   [String: Int]  = [:]

        for cam in activeCameras {
            let isMtd = fm.fileExists(atPath: cam.sourcePath.path)
            newMounted[cam.key] = isMtd
            guard isMtd else { continue }
            let files = (try? fm.contentsOfDirectory(
                at: cam.sourcePath,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles)) ?? []
            newCounts[cam.key] = files.filter { url in
                guard url.pathExtension.uppercased() == "MP4",
                      let mtime = try? url.resourceValues(
                          forKeys: [.contentModificationDateKey]).contentModificationDate
                else { return false }
                return cal.startOfDay(for: mtime) == targetDay
            }.count
        }
        mounted      = newMounted
        sourceCounts = newCounts
    }

    private func refreshDestCounts() {
        guard let dest = destFolder else { destCounts = [:]; return }
        let fm = FileManager.default
        var counts: [String: Int] = [:]
        for cam in activeCameras {
            let files = (try? fm.contentsOfDirectory(
                at: dest, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            counts[cam.key] = files.filter {
                $0.lastPathComponent.hasPrefix(cam.folderName + "_")
                && $0.pathExtension.uppercased() == "MP4"
            }.count
        }
        destCounts = counts
    }

    // MARK: - Copy

    private func startCopy() {
        guard let inputBase = GlobalSettings.shared.inputBaseDir else {
            logLines.append(("❌ Input Videos folder not set — open Settings and choose a folder", true))
            return
        }
        // Pre-flight: verify we can actually write to the destination volume
        let probe = inputBase.appending(path: ".velofilms_writetest")
        do {
            try "ok".write(to: probe, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: probe)
        } catch {
            logLines = [(
                "❌ Cannot write to \(inputBase.path)\n" +
                "   • If this is an NTFS drive, macOS mounts it read-only by default.\n" +
                "     Use exFAT or APFS, or install a driver such as Paragon NTFS.\n" +
                "   • If it is an external drive, make sure it is fully mounted and not locked.\n" +
                "   • Error: \(error.localizedDescription)",
                true
            )]
            return
        }
        isCopying = true
        copied = 0; total = 0
        logLines = []
        Task { await runCopy(inputBase: inputBase) }
    }

    private func runCopy(inputBase: URL) async {
        let fm  = FileManager.default
        let cal = Calendar.current
        let targetDay = cal.startOfDay(for: rideDate)
        let dest = inputBase.appending(path: folderName)

        log("=== Starting Import ===")
        log("Destination: \(dest.path)")

        // Collect files only from cameras that are selected AND mounted
        var filesToCopy: [(src: URL, dst: URL, cam: CameraConfig)] = []
        for cam in activeCameras where selected.contains(cam.key) && mounted[cam.key] == true {
            let files = (try? fm.contentsOfDirectory(
                at: cam.sourcePath,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles)) ?? []
            let matching = files.filter { url in
                guard url.pathExtension.uppercased() == "MP4",
                      let mtime = try? url.resourceValues(
                          forKeys: [.contentModificationDateKey]).contentModificationDate
                else { return false }
                return cal.startOfDay(for: mtime) == targetDay
            }
            log("Found \(matching.count) clip\(matching.count == 1 ? "" : "s") from \(cam.displayName)")
            for src in matching.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let outName = outputName(for: src, camera: cam)
                filesToCopy.append((src: src, dst: dest.appending(path: outName), cam: cam))
            }
        }

        guard !filesToCopy.isEmpty else {
            log("⚠️ No clips found for \(dateStr) on any mounted camera", error: true)
            finishCopy()
            return
        }

        total = filesToCopy.count
        log("📁 \(total) clip\(total == 1 ? "" : "s") to copy")

        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        } catch {
            log("❌ Could not create destination: \(error.localizedDescription)", error: true)
            finishCopy()
            return
        }

        var totalBytes = 0
        var totalSecs  = 0.0
        for (i, item) in filesToCopy.enumerated() {
            let fileSize = (try? item.src.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let start    = Date()
            do {
                try await copyFile(from: item.src, to: item.dst)
                let elapsed = Date().timeIntervalSince(start)
                let speed   = elapsed > 0 ? Double(fileSize) / elapsed : 0
                totalBytes += fileSize; totalSecs += elapsed
                copied = i + 1
                log("✓ [\(i+1)/\(total)] \(item.dst.lastPathComponent) (\(formatSize(fileSize)) in \(String(format: "%.1f", elapsed))s @ \(formatSpeed(speed)))")
            } catch {
                log("❌ \(item.src.lastPathComponent): \(error.localizedDescription)", error: true)
            }
        }

        log("=== Copy Complete ===")
        let avgSpeed = totalSecs > 0 ? Double(totalBytes) / totalSecs : 0
        log("✓ Copied \(copied) clips  •  \(formatSize(totalBytes))  •  avg \(formatSpeed(avgSpeed))")

        // Create/update project in projects root
        if let root = GlobalSettings.shared.projectsRoot {
            let projURL = root.appending(path: folderName)
            let project = Project(name: folderName, folderURL: projURL)
            try? ProjectFileManager.createDirectoryStructure(for: project)
            if !store.projects.contains(where: { $0.name == folderName }) {
                store.add(project)
                log("✓ Project '\(folderName)' added")
            } else {
                log("✓ Project '\(folderName)' updated")
            }
        }

        finishCopy()
    }

    @MainActor
    private func finishCopy() {
        isCopying = false
        refresh()   // update mounted + dest counts so UI reflects new state
    }

    private func copyFile(from src: URL, to dst: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: src, to: dst)
        }.value
    }

    // MARK: - Helpers

    private func outputName(for src: URL, camera: CameraConfig) -> String {
        let stem   = src.deletingPathExtension().lastPathComponent
        let number = stem.contains("_") ? (stem.components(separatedBy: "_").last ?? stem) : stem
        return "\(camera.folderName)_\(number).MP4"
    }

    private func log(_ msg: String, error: Bool = false) {
        logLines.append((msg, error))
    }

    private func formatSize(_ bytes: Int) -> String {
        let d = Double(bytes)
        if d < 1024          { return String(format: "%.0fB", d) }
        if d < 1_048_576     { return String(format: "%.1fKB", d / 1024) }
        if d < 1_073_741_824 { return String(format: "%.1fMB", d / 1_048_576) }
        return String(format: "%.2fGB", d / 1_073_741_824)
    }

    private func formatSpeed(_ bps: Double) -> String { "\(formatSize(Int(bps)))/s" }
}
