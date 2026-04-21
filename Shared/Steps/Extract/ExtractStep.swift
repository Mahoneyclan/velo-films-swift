import Foundation
import AVFoundation

/// Generates extract.csv: one row per (camera, grid-point) pair.
/// Mirrors extract.py: GPX-anchored global 5s grid → per-clip frame rows.
struct ExtractStep: PipelineStep {
    let name = "extract"
    let csvWriter: CSVWriter
    let csvReader: CSVReader

    init(csvWriter: CSVWriter = CSVWriter(), csvReader: CSVReader = CSVReader()) {
        self.csvWriter = csvWriter
        self.csvReader = csvReader
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 0, total: 4, message: "Loading flatten.csv...")

        let flattenRows: [FlattenRow] = try csvReader.read(from: project.flattenCSV)
        guard !flattenRows.isEmpty else {
            throw PipelineError.missingInput("flatten.csv is empty — run flatten step first")
        }

        let gpxStart = flattenRows.first!.gpxEpoch
        let gpxEnd   = flattenRows.last!.gpxEpoch
        let extension_ = AppConfig.gpxGridExtensionM * 60
        let gridStart  = gpxStart - extension_
        let gridEnd    = gpxEnd   + extension_
        let interval   = AppConfig.extractIntervalSeconds

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

            let asset = AVAsset(url: videoURL)
            guard let durationS = try? await asset.load(.duration).seconds,
                  durationS > 0 else { continue }
            let fps = try? await FrameSampler.fps(for: asset)

            // Fix Cycliq UTC bug: reinterpret creation_time using camera's known timezone
            guard let creationTimeUTC = try? await FrameSampler.creationTime(for: asset, camera: camera) else { continue }

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
                let index    = "\(camera.rawValue)_\(clipId)_\(Int(secIntoClip):06d)"

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

        await reporter.report(current: 4, total: 4, message: "Writing extract.csv (\(rows.count) rows)...")
        try csvWriter.write(rows: rows, to: project.extractCSV)
    }
}
