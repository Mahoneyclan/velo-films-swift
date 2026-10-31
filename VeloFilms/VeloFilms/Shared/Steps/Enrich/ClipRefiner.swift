// ClipRefiner.swift
// Enrich pass 2: scores each shortlisted moment on its whole clip and slides the clip towards the action.

import Foundation
import AVFoundation
import CoreGraphics

/// Looks closely at the moments most likely to make the reel.
///
/// Pass 1 scores every grid point from one frame. This pass shortlists `AppConfig.refineShortlistFactor` times
/// the clips wanted (using the same rules as Select, so the start, finish and every stretch of the ride are
/// included), reads up to `AppConfig.refineMaxFrames` frames around each shortlisted moment from its leading
/// camera, and lets `ClipWindowScorer` choose the clip start and the clip's detection and action scores. Frames
/// pass 1 already read are reused. The other camera keeps its pass 1 score but moves by the same shift, so the
/// picture-in-picture stays in sync.
enum ClipRefiner {

    /// What pass 1 found in a row's frame, kept so this pass doesn't read it again.
    struct FirstPassFrame {
        /// The row's `detectScore`.
        var detectScore: Double
        /// The frame's weighted box area (`YOLODetector.detect`).
        var presence: Double
    }

    /// One frame read in this pass, with what YOLO found.
    private struct ReadFrame {
        var image: CGImage
        var detections: [YOLODetection]
        var bboxArea: Double
    }

    /// Refines the shortlisted moments in `rows`.
    /// - Parameters:
    ///   - rows: Every pass 1 row, both cameras.
    ///   - firstPass: Pass 1 results by row `index`.
    ///   - project: Supplies the video folder and `frames/`.
    ///   - yolo: The detector pass 1 used.
    ///   - gps: Re-averages speed and gradient over a shifted clip.
    ///   - reporter: Receives progress.
    /// - Returns: `rows` in the same order, with shortlisted moments rescored, shifted (`clipShiftS`) and their
    ///   thumbnails replaced by the clip's strongest frame. A moment whose frames can't be read keeps its
    ///   pass 1 values.
    static func refine(rows: [EnrichRow], firstPass: [String: FirstPassFrame], project: Project,
                       yolo: YOLODetector, gps: GPSEnricher, reporter: ProgressReporter) async -> [EnrichRow] {
        var out = rows
        let position = Dictionary(rows.enumerated().map { ($0.element.index, $0.offset) },
                                  uniquingKeysWith: { a, _ in a })
        let reusable = reusableFrames(rows: rows, firstPass: firstPass)
        // Sorted by video so one frame generator serves every moment in the same file.
        let moments = shortlist(rows).sorted {
            ($0.primary?.videoPath ?? "", $0.momentId) < ($1.primary?.videoPath ?? "", $1.momentId)
        }

        var generator: (path: String, gen: AVAssetImageGenerator)?
        for (i, moment) in moments.enumerated() {
            if i % 10 == 0 {
                await reporter.report(current: i, total: moments.count,
                                      message: "Step 2 of 2 · Looking closely at the best moments \(i)/\(moments.count)...")
            }
            guard let lead = moment.primary else { continue }
            if generator?.path != lead.videoPath {
                generator?.gen.cancelAllCGImageGeneration()
                generator = (lead.videoPath,
                             FrameSampler.makeGenerator(for: project.videoURL(forStoredPath: lead.videoPath)))
            }
            guard let gen = generator?.gen else { continue }
            await refine(moment: moment, lead: lead, generator: gen, reusable: reusable[lead.videoPath] ?? [],
                         rows: &out, position: position, project: project, yolo: yolo, gps: gps)
        }
        generator?.gen.cancelAllCGImageGeneration()
        return out
    }

    /// The moments Select would pick if it wanted `AppConfig.refineShortlistFactor` times as many clips.
    /// - Parameter rows: Every pass 1 row.
    /// - Returns: The shortlisted moments.
    static func shortlist(_ rows: [EnrichRow]) -> [PartnerMatcher.Moment] {
        var config = ClipSelector.Config()
        config.targetClips = Int((Double(config.targetClips) * AppConfig.refineShortlistFactor).rounded(.up))
        return ClipSelector.select(moments: PartnerMatcher.group(rows), config: config)
    }

    // MARK: - One moment

    /// Reads the lead camera's frames around `moment`, scores the clip and writes the results into `rows`.
    private static func refine(moment: PartnerMatcher.Moment, lead: EnrichRow, generator: AVAssetImageGenerator,
                               reusable: [(second: Double, row: String, frame: FirstPassFrame)],
                               rows: inout [EnrichRow], position: [String: Int], project: Project,
                               yolo: YOLODetector, gps: GPSEnricher) async {
        let clipLength = AppConfig.clipOutLenS
        let start = defaultStart(lead)
        var frames: [ClipWindowScorer.Frame] = []
        var read: [Double: ReadFrame] = [:]
        var reusedRow: [Double: String] = [:]
        for offset in ClipWindowScorer.sampleOffsets(clipLength: clipLength, maxShift: AppConfig.clipMaxShiftS) {
            let second = start + offset
            guard second >= 0, second <= lead.durationS else { continue }
            // The generator accepts frames within ±0.5 s, so a pass 1 frame that close is the same frame.
            if let hit = reusable.first(where: { abs($0.second - second) <= 0.5 }) {
                frames.append(.init(offset: offset, detectScore: hit.frame.detectScore, presence: hit.frame.presence))
                reusedRow[offset] = hit.row
            } else if let image = await FrameSampler.extractFrame(using: generator, atSecond: second),
                      let result = try? yolo.detect(image: image) {
                frames.append(.init(offset: offset, detectScore: result.detectScore, presence: result.presence))
                read[offset] = ReadFrame(image: image, detections: result.detections, bboxArea: result.bboxArea)
            }
        }
        let w = AppConfig.ScoreWeights.self
        guard let best = ClipWindowScorer.best(frames: frames, clipLength: clipLength,
                                               shiftRange: shiftRange(moment), detectWeight: w.detectScore,
                                               actionWeight: w.action),
              let leadPos = position[lead.index] else { return }

        rows[leadPos].detectScore = best.detectScore
        rows[leadPos].actionScore = best.actionScore
        setThumbnail(of: &rows[leadPos], offset: best.thumbnailOffset, read: read, reusedRow: reusedRow,
                     rows: rows, position: position, project: project)
        for row in moment.rows {
            guard let pos = position[row.index] else { continue }
            rows[pos].clipShiftS = best.shift
            if best.shift != 0 { reaverageGPS(&rows[pos], gps: gps) }
            rescore(&rows[pos])
        }
        if best.shift != 0, let pip = moment.secondary {
            await savePiPThumbnail(pip, at: defaultStart(pip) + best.thumbnailOffset, project: project)
        }
    }

    // MARK: - Helpers

    /// Seconds into the row's video where its unshifted clip starts.
    private static func defaultStart(_ row: EnrichRow) -> Double {
        row.absTimeEpoch - row.clipStartEpoch - AppConfig.clipPreRollS
    }

    /// Shifts that keep every camera's clip inside its video file, within `AppConfig.clipMaxShiftS`.
    /// No shift at all is allowed when the clip can't fit either way (a very short file).
    private static func shiftRange(_ moment: PartnerMatcher.Moment) -> ClosedRange<Double> {
        var lo = -AppConfig.clipMaxShiftS, hi = AppConfig.clipMaxShiftS
        for row in moment.rows {
            let start = defaultStart(row)
            lo = max(lo, -start)
            hi = min(hi, row.durationS - AppConfig.clipOutLenS - start)
        }
        return lo <= hi ? lo...hi : 0...0
    }

    /// Pass 1 frames by video file, with the second into the file each was read at.
    private static func reusableFrames(rows: [EnrichRow], firstPass: [String: FirstPassFrame])
        -> [String: [(second: Double, row: String, frame: FirstPassFrame)]] {
        var out: [String: [(second: Double, row: String, frame: FirstPassFrame)]] = [:]
        for row in rows {
            guard let frame = firstPass[row.index] else { continue }
            out[row.videoPath, default: []].append((max(0, defaultStart(row)), row.index, frame))
        }
        return out
    }

    /// Makes the clip's strongest frame the row's thumbnail and detection summary (what Fine Tune shows).
    private static func setThumbnail(of row: inout EnrichRow, offset: Double, read: [Double: ReadFrame],
                                     reusedRow: [Double: String], rows: [EnrichRow], position: [String: Int],
                                     project: Project) {
        let target = thumbnailURL(row.index, project: project)
        if let frame = read[offset] {
            FrameSampler.saveJPEG(frame.image, to: target)
            row.numDetections   = frame.detections.count
            row.bboxArea        = frame.bboxArea
            row.detectedClasses = frame.detections.map(\.className).joined(separator: ",")
            row.objectDetected  = !frame.detections.isEmpty
        } else if let source = reusedRow[offset], source != row.index, let pos = position[source] {
            let from = rows[pos]
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: thumbnailURL(source, project: project), to: target)
            row.numDetections   = from.numDetections
            row.bboxArea        = from.bboxArea
            row.detectedClasses = from.detectedClasses
            row.objectDetected  = from.objectDetected
        }
    }

    /// Replaces the other camera's thumbnail with its frame at the shifted time, so Fine Tune shows both cameras
    /// at the same instant. No detection is run: that camera keeps its pass 1 scores.
    private static func savePiPThumbnail(_ row: EnrichRow, at second: Double, project: Project) async {
        let url = project.videoURL(forStoredPath: row.videoPath)
        guard let image = await FrameSampler.extractFrame(videoURL: url, atSecond: second) else { return }
        FrameSampler.saveJPEG(image, to: thumbnailURL(row.index, project: project))
    }

    /// `frames/<index>.jpg`, the name EnrichStep and the Fine Tune screen use.
    private static func thumbnailURL(_ index: String, project: Project) -> URL {
        project.framesDir.appending(path: "\(index).jpg")
    }

    /// Recomputes speed and gradient over the shifted clip.
    private static func reaverageGPS(_ row: inout EnrichRow, gps: GPSEnricher) {
        let start = row.clipAnchorEpoch - AppConfig.clipPreRollS
        guard let point = gps.enrich(epoch: row.absTimeEpoch, over: start...(start + AppConfig.clipOutLenS)) else {
            return
        }
        row.speedKmh = point.speedKmh
        row.gradientPct = point.gradientPct
    }

    /// Recomputes the composite and weighted scores from the row's current component scores.
    private static func rescore(_ row: inout EnrichRow) {
        guard let camera = AppConfig.CameraName(rawValue: row.camera) else { return }
        row.scoreComposite = ScoreCalculator.composite(ScoreCalculator.Input(
            detectScore:  row.detectScore,
            actionScore:  row.actionScore,
            speedKmh:     row.speedKmh    ?? 0,
            gradientPct:  row.gradientPct ?? 0,
            segmentBoost: row.segmentBoost,
            camera:       camera))
        row.scoreWeighted = ScoreCalculator.weighted(row.scoreComposite, camera: camera)
    }
}
