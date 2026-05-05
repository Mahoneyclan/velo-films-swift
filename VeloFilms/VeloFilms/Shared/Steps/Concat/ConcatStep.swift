import Foundation
import AVFoundation

/// Joins _intro + _middle_01…N + _outro into {rideName}.mp4 with crossfade transitions.
/// Uses FFmpeg xfade/acrossfade between segments; falls back to stream copy for a single part.
struct ConcatStep: PipelineStep {
    let name = "concat"

    init() {}

    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 1, total: 3, message: "Collecting segments...")

        let clipsDir = project.clipsDir
        let allFiles = (try? FileManager.default.contentsOfDirectory(
            at: clipsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []

        let middleFiles = allFiles
            .filter { $0.lastPathComponent.hasPrefix("_middle_") && $0.pathExtension == "mp4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !middleFiles.isEmpty else {
            throw PipelineError.missingInput(
                "No _middle_##.mp4 segments found — run build step first")
        }

        var parts: [URL] = []
        let intro = clipsDir.appending(path: "_intro.mp4")
        let outro = clipsDir.appending(path: "_outro.mp4")
        if FileManager.default.fileExists(atPath: intro.path) { parts.append(intro) }
        parts.append(contentsOf: middleFiles)
        if FileManager.default.fileExists(atPath: outro.path) { parts.append(outro) }

        await reporter.report(current: 2, total: 3,
                              message: "Joining \(parts.count) segment(s) with crossfades...")

        try? FileManager.default.removeItem(at: project.finalReelURL)

        if parts.count == 1 {
            try FileManager.default.copyItem(at: parts[0], to: project.finalReelURL)
        } else {
            // Load each segment's duration for xfade offset calculation
            var durations: [Double] = []
            for url in parts {
                let asset = AVURLAsset(url: url)
                let dur = try await asset.load(.duration)
                durations.append(CMTimeGetSeconds(dur))
            }
            let bridge = makeBridge()
            try await xfadeConcat(parts: parts, durations: durations,
                                   outputURL: project.finalReelURL, bridge: bridge)
        }

        let sizeMB = (try? FileManager.default
            .attributesOfItem(atPath: project.finalReelURL.path)[.size] as? Int)
            .map { Double($0) / 1_048_576 } ?? 0

        await reporter.report(current: 3, total: 3,
                              message: String(format: "Done — %.0f MB: %@",
                                             sizeMB, project.finalReelURL.lastPathComponent))
    }

    // MARK: - FFmpeg xfade segment join

    private func xfadeConcat(parts: [URL], durations: [Double],
                              outputURL: URL, bridge: any FFmpegBridge) async throws {
        let X   = AppConfig.concatXfadeDuration
        let vbr = "\(AppConfig.Encoding.videoBitrate / 1000)k"
        let abr = "\(AppConfig.Encoding.audioBitrate / 1000)k"

        var inputs: [String] = []
        for part in parts { inputs += ["-i", part.path] }

        var filterParts: [String] = []

        // Normalise every input to a common timebase (fps=30) and sample rate (48 kHz)
        // before xfade/acrossfade — the filters require matching specs across all inputs.
        // Intro/outro come from AVFoundation (1/600 tb, 48 kHz); middles come from
        // FFmpeg libx264 (1/15360 tb, 96 kHz); fps + aresample unify them.
        for i in 0..<parts.count {
            filterParts.append("[\(i):v]fps=fps=30[vn\(i)]")
            filterParts.append("[\(i):a]aresample=48000[an\(i)]")
        }

        var prevV = "[vn0]"
        var prevA = "[an0]"
        // offset(i) = sum(durations[0..<i]) - i * X  (cumulative chained-output timeline)
        var cumulativeDur = durations[0]

        for i in 1..<parts.count {
            let offset  = max(0, cumulativeDur - X)
            let isLast  = (i == parts.count - 1)
            let vOut    = isLast ? "[vchain]" : "[v\(i)]"
            let aOut    = isLast ? "[achain]" : "[a\(i)]"
            filterParts.append("\(prevV)[vn\(i)]xfade=transition=fade:duration=\(X):offset=\(String(format: "%.3f", offset))\(vOut)")
            filterParts.append("\(prevA)[an\(i)]acrossfade=d=\(X)\(aOut)")
            prevV = vOut
            prevA = aOut
            cumulativeDur += durations[i] - X
        }

        filterParts.append("[vchain]null[vout]")
        filterParts.append("[achain]anull[aout]")

        let filter = filterParts.joined(separator: ";")
        print("[ConcatStep] xfade join: \(parts.count) parts, X=\(X)s → \(outputURL.lastPathComponent)")
        try await bridge.execute(arguments: inputs + [
            "-filter_complex", filter,
            "-map", "[vout]", "-map", "[aout]",
            "-c:v", "libx264", "-b:v", vbr,
            "-c:a", "aac", "-b:a", abr,
            "-movflags", "+faststart",
            "-y", outputURL.path,
        ])
    }
}
