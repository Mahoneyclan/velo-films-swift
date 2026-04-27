import Foundation
import AVFoundation
import os

/// Joins _intro + _middle_01…N + _outro into {rideName}.mp4 using AVMutableComposition.
/// Replaces the FFmpeg -f concat stream-copy approach.
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
                              message: "Joining \(parts.count) segments...")

        let composition  = AVMutableComposition()
        let vTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let aTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!

        var insertTime = CMTime.zero

        for url in parts {
            let asset = AVURLAsset(url: url)
            let dur   = try await asset.load(.duration)

            if let src = try? await asset.loadTracks(withMediaType: .video).first {
                let range = CMTimeRange(start: .zero, duration: dur)
                try? vTrack.insertTimeRange(range, of: src, at: insertTime)
            }
            if let src = try? await asset.loadTracks(withMediaType: .audio).first {
                let range = CMTimeRange(start: .zero, duration: dur)
                try? aTrack.insertTimeRange(range, of: src, at: insertTime)
            }

            insertTime = insertTime + dur
        }

        try? FileManager.default.removeItem(at: project.finalReelURL)
        try await VideoEncoder.export(composition: composition, to: project.finalReelURL)

        let sizeMB = (try? FileManager.default
            .attributesOfItem(atPath: project.finalReelURL.path)[.size] as? Int)
            .map { Double($0) / 1_048_576 } ?? 0

        await reporter.report(current: 3, total: 3,
                              message: String(format: "Done — %.0f MB: %@",
                                             sizeMB, project.finalReelURL.lastPathComponent))
    }
}
