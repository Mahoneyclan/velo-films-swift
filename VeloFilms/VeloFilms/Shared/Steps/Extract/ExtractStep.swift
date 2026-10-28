// ExtractStep.swift
// Pipeline step 2: builds the sampling grid and matches each grid point to the camera clip that covers it.

import Foundation
import AVFoundation

/// Generates `extract.jsonl`: one row per (camera, grid point) pair.
///
/// The grid is anchored to the GPX timeline (extended by `AppConfig.gpxGridExtensionM` either side) and spaced by
/// the sampling interval (default 5 s, user-adjustable). Each clip's real start is its file creation time
/// (corrected for the camera clock) minus its duration minus the manual offset. No pixels are read here.
/// Same approach as `extract.py` in the original Python app.
struct ExtractStep: PipelineStep {
    /// Step name used in logs.
    let name = "extract"
    /// Output writer (injectable for testing).
    let jsonlWriter: JSONLWriter
    /// Input reader (injectable for testing).
    let jsonlReader: JSONLReader
    private static let isoFmt = ISO8601DateFormatter()

    /// Creates the step with standard reader and writer by default.
    /// - Parameters:
    ///   - jsonlWriter: Writes `extract.jsonl`.
    ///   - jsonlReader: Reads `flatten.jsonl`.
    init(jsonlWriter: JSONLWriter = JSONLWriter(), jsonlReader: JSONLReader = JSONLReader()) {
        self.jsonlWriter = jsonlWriter
        self.jsonlReader = jsonlReader
    }

    /// Reads `flatten.jsonl`, scans the source clips and writes `extract.jsonl`.
    /// - Throws: `PipelineError.missingInput` if flatten output, source folder or clips are missing, or if no clip
    ///   overlaps the GPX time window (the message explains the likely clock setting to change); file errors.
    /// - Note: Clips whose camera can't be identified from the file name, or whose duration or creation time can't be
    ///   read, are skipped.
    /// - Parameters:
    ///   - project: The ride project to process.
    ///   - reporter: Receives progress updates for the pipeline screen.
    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 0, total: 4, message: "Loading flatten.jsonl...")

        let flattenRows: [FlattenRow] = try jsonlReader.read(from: project.flattenJSONL)
        guard !flattenRows.isEmpty else {
            throw PipelineError.missingInput("flatten.jsonl is empty — run flatten step first")
        }

        let gpxStart = flattenRows[0].gpxEpoch
        let gpxEnd   = flattenRows[flattenRows.count - 1].gpxEpoch
        let extension_ = AppConfig.gpxGridExtensionM * 60
        let gridStart  = gpxStart - extension_
        let gridEnd    = gpxEnd   + extension_
        let interval   = GlobalSettings.shared.effectiveExtractInterval

        await reporter.report(current: 1, total: 4, message: "Discovering video files...")

        let sourceDir: URL
        if let explicit = project.sourceVideoURL {
            sourceDir = explicit
        } else if let base = GlobalSettings.shared.inputBaseDir {
            sourceDir = project.sourceVideosDir(inputBase: base)
        } else {
            throw PipelineError.missingInput("No video source set — select a raw video folder when creating the project, or set Input Base Dir in Settings")
        }
        let videoFiles = try ProjectFileManager.findVideoFiles(in: sourceDir)

        guard !videoFiles.isEmpty else {
            throw PipelineError.missingInput("No MP4 files found in \(sourceDir.path)")
        }

        await reporter.report(current: 2, total: 4, message: "Building frame grid from \(videoFiles.count) clips...")

        let isLocalWrongZ = GlobalSettings.shared.cameraCreationTimeIsLocalWrongZ

        var rows: [ExtractRow] = []
        for (clipIndex, videoURL) in videoFiles.enumerated() {
            let filename = videoURL.lastPathComponent
            guard let camera = AppConfig.CameraName.from(filename: filename) else { continue }

            let asset = AVURLAsset(url: videoURL)
            guard let durationS = try? await asset.load(.duration).seconds,
                  durationS > 0 else { continue }
            let fps = try? await FrameSampler.fps(for: asset)

            guard let creationTimeUTC = FrameSampler.creationTime(for: videoURL, camera: camera,
                                                                   isLocalWrongZ: isLocalWrongZ) else { continue }

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

                let iso = Self.isoFmt.string(from: Date(timeIntervalSince1970: t))
                let adjustedISO = Self.isoFmt.string(from: Date(timeIntervalSince1970: clipStartEpoch))

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
            // Build a diagnostic to help the user fix the problem
            let gpxFmt = DateFormatter()
            gpxFmt.dateFormat = "yyyy-MM-dd HH:mm"
            gpxFmt.timeZone = TimeZone(secondsFromGMT: 0)
            let gpxWindowStr = "\(gpxFmt.string(from: Date(timeIntervalSince1970: gpxStart))) – " +
                               "\(gpxFmt.string(from: Date(timeIntervalSince1970: gpxEnd))) UTC"

            var diagLines = ["Extract produced 0 rows from \(videoFiles.count) clips."]
            diagLines.append("GPX window: \(gpxWindowStr)")

            // Sample the first clip — show both raw and corrected times so the user can
            // tell whether the offset is right, too large, or should be zero.
            if let firstURL = videoFiles.first,
               let cam = AppConfig.CameraName.from(filename: firstURL.lastPathComponent) {
                if let rawDate = FrameSampler.rawCreationTime(for: firstURL) {
                    let rawStr = gpxFmt.string(from: rawDate)
                    diagLines.append("First clip raw mvhd time: \(rawStr) UTC (as stored in file)")
                    if isLocalWrongZ {
                        let corrected    = FrameSampler.applyCycliqUTCFix(rawDate: rawDate, camera: cam)
                        let correctedStr = gpxFmt.string(from: Date(timeIntervalSince1970: corrected))
                        diagLines.append("First clip corrected time: \(correctedStr) UTC (subtracted \(cam.timezoneIdentifier) offset)")
                        diagLines.append("→ If the raw time above is within the GPX window, the camera stores genuine UTC.")
                        diagLines.append("  Disable 'Camera stores local time (Cycliq UTC bug)' in Settings → Time Sync.")
                    } else {
                        diagLines.append("→ Raw time is used as-is (GPS-synced UTC mode). If this is wrong,")
                        diagLines.append("  enable 'Camera stores local time (Cycliq UTC bug)' and set the correct timezone.")
                    }
                } else {
                    diagLines.append("First clip: could not read creation_time from binary — file may be corrupt or unsupported container")
                }
            }

            diagLines.append("Fix: Settings → Time Sync → toggle 'Camera stores local time (Cycliq UTC bug)'.")
            throw PipelineError.missingInput(diagLines.joined(separator: "\n"))
        }

        await reporter.report(current: 4, total: 4, message: "Writing extract.jsonl (\(rows.count) rows)...")
        try jsonlWriter.write(rows: rows, to: project.extractJSONL)
    }
}
