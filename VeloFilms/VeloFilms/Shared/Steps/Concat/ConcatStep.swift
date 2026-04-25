import Foundation
import os

/// Stream-copy concat: _intro + _middle_01…N + _outro → {rideName}.mp4
/// Mirrors concat.py exactly — no re-encode, near-instant.
struct ConcatStep: PipelineStep {
    let name = "concat"
    let bridge: any FFmpegBridge

    init(bridge: any FFmpegBridge) {
        self.bridge = bridge
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 1, total: 3, message: "Collecting segments...")

        let clipsDir = project.clipsDir

        // Collect _middle_##.mp4 in order
        let allFiles = (try? FileManager.default.contentsOfDirectory(
            at: clipsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []

        let middleFiles = allFiles
            .filter { $0.lastPathComponent.hasPrefix("_middle_") && $0.pathExtension == "mp4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !middleFiles.isEmpty else {
            throw PipelineError.missingInput("No _middle_##.mp4 segments found — run build step first")
        }

        var parts: [URL] = []
        let intro = clipsDir.appending(path: "_intro.mp4")
        let outro = clipsDir.appending(path: "_outro.mp4")
        if FileManager.default.fileExists(atPath: intro.path) { parts.append(intro) }
        parts.append(contentsOf: middleFiles)
        if FileManager.default.fileExists(atPath: outro.path) { parts.append(outro) }

        // Write concat list
        let concatList = project.finalConcatList
        let listContent = parts.map { "file '\($0.path)'" }.joined(separator: "\n")
        try listContent.write(to: concatList, atomically: true, encoding: .utf8)

        await reporter.report(current: 2, total: 3, message: "Stream-copying \(parts.count) parts...")

        // Stream-copy video; re-encode audio to guard against any remaining
        // sample-rate or channel-layout drift between intro/middle/outro segments.
        _ = try await bridge.execute(arguments: [
            "-hide_banner", "-loglevel", "warning",
            "-f", "concat", "-safe", "0", "-i", concatList.path,
            "-c:v", "copy",
            "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "192k",
            "-movflags", "+faststart",
            "-y", project.finalReelURL.path
        ])

        try? FileManager.default.removeItem(at: concatList)

        let sizeMB = (try? FileManager.default
            .attributesOfItem(atPath: project.finalReelURL.path)[.size] as? Int)
            .map { Double($0) / 1_048_576 } ?? 0

        await reporter.report(current: 3, total: 3,
                              message: String(format: "Done — %.0f MB: %@",
                                             sizeMB, project.finalReelURL.lastPathComponent))
    }
}
