import Foundation
import AVFoundation

/// Generates extract.jsonl: one row per (camera, grid-point) pair.
/// Mirrors extract.py: GPX-anchored global 5s grid → per-clip frame rows.
struct ExtractStep: PipelineStep {
    let name = "extract"
    let jsonlWriter: JSONLWriter
    let jsonlReader: JSONLReader

    init(jsonlWriter: JSONLWriter = JSONLWriter(), jsonlReader: JSONLReader = JSONLReader()) {
        self.jsonlWriter = jsonlWriter
        self.jsonlReader = jsonlReader
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 0, total: 4, message: "Loading flatten.jsonl...")

        let flattenRows: [FlattenRow] = try jsonlReader.read(from: project.flattenJSONL)
        guard !flattenRows.isEmpty else {
            throw PipelineError.missingInput("flatten.jsonl is empty — run flatten step first")
        }

        let gpxStart = flattenRows.first!.gpxEpoch
        let gpxEnd   = flattenRows.last!.gpxEpoch
        let extension_ = AppConfig.gpxGridExtensionM * 60
        let gridStart  = gpxStart - extension_
        let gridEnd    = gpxEnd   + extension_
        let interval   = GlobalSettings.shared.effectiveExtractInterval

        await reporter.report(current: 1, total: 4, message: "Discovering video files...")

        guard let inputBase = GlobalSettings.shared.inputBaseDir else {
            throw PipelineError.missingInput("Input base directory not set in Settings")
        }
        let sourceDir = inputBase.appending(path: project.name)
        let videoFiles = try ProjectFileManager.findVideoFiles(in: sourceDir)

        guard !videoFiles.isEmpty else {
            throw PipelineError.missingInput("No MP4 files found in \(sourceDir.path)")
        }

        await reporter.report(current: 2, total: 4, message: "Building frame grid from \(videoFiles.count) clips...")

        var rows: [ExtractRow] = []
        for (clipIndex, videoURL) in videoFiles.enumerated() {
            let filename = videoURL.lastPathComponent
            guard let camera = AppConfig.CameraName.from(filename: filename) else { continue }

            let asset = AVURLAsset(url: videoURL)
            guard let durationS = try? await asset.load(.duration).seconds,
                  durationS > 0 else { continue }
            let fps = try? await FrameSampler.fps(for: asset)

            // Fix Cycliq UTC bug: reinterpret creation_time using camera's known timezone
            guard let creationTimeUTC = FrameSampler.creationTime(for: videoURL, camera: camera) else { continue }

            // real recording start = creation_time_utc - duration - known_offset
            let clipStartEpoch = creationTimeUTC - durationS - camera.knownOffset
            let clipEndEpoch   = creationTimeUTC - camera.knownOffset

            // Enumerate grid points that fall within this clip's window
            var t = (gridStart / interval).rounded(.up) * interval
            while t <= gridEnd {
                defer { t += interval }
                guard t >= clipStartEpoch && t <= clipEndEpoch else { continue }

                let secIntoClip = t - clipStartEpoch
                let frameNum = Int((secIntoClip * (fps ?? 59.94)).rounded())
                let clipId   = String(format: "%04d", clipIndex + 1)
                let index    = "\(camera.rawValue)_\(clipId)_\(String(format: "%06d", Int(secIntoClip)))"

                let iso = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: t))
                let adjustedISO = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: clipStartEpoch))

                rows.append(ExtractRow(
                    index: index,
                    camera: camera.rawValue,
                    clipNum: clipIndex + 1,
                    frameNumber: frameNum,
                    videoPath: videoURL.path,
                    absTimeEpoch: t,
                    absTimeIso: iso,
                    sessionTsS: t - gpxStart,
                    clipStartEpoch: clipStartEpoch,
                    adjustedStartTime: adjustedISO,
                    durationS: durationS,
                    source: "video",
                    fps: fps ?? 59.94
                ))
            }

            let progress = clipIndex + 1
            await reporter.report(current: progress, total: videoFiles.count + 1,
                                  message: "Processed \(filename)")
        }

        guard !rows.isEmpty else {
            throw PipelineError.missingInput(
                "Extract produced 0 rows from \(videoFiles.count) clips — " +
                "check that creation_time metadata is readable and camera timezones are correct"
            )
        }

        await reporter.report(current: 4, total: 4, message: "Writing extract.jsonl (\(rows.count) rows)...")
        try jsonlWriter.write(rows: rows, to: project.extractJSONL)
    }
}
