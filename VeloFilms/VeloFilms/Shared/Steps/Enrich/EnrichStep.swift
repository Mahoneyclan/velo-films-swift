// EnrichStep.swift
// Pipeline step 3: scores every grid point (objects, scene change, speed, gradient, Strava segments).

import Foundation
import AVFoundation
import CoreGraphics

/// Runs YOLO detection, scene scoring, GPS enrichment and composite scoring, and writes `enriched.jsonl`.
/// Also saves a JPEG thumbnail per row in `frames/` for the manual selection screen.
/// Same approach as `enrich.py` in the original Python app (not in this repo).
///
/// The slowest analysis step: one frame decode plus one YOLO run per row.
struct EnrichStep: PipelineStep {
    /// Step name used in logs.
    let name = "enrich"
    /// Output writer (injectable for testing).
    let jsonlWriter: JSONLWriter
    /// Input reader (injectable for testing).
    let jsonlReader: JSONLReader
    /// Compiled YOLO Core ML model.
    let yoloModelURL: URL

    /// Creates the step.
    /// - Parameters:
    ///   - yoloModelURL: The `.mlmodelc` to load on first use.
    ///   - jsonlWriter: Output writer.
    ///   - jsonlReader: Input reader.
    init(yoloModelURL: URL,
         jsonlWriter: JSONLWriter = JSONLWriter(),
         jsonlReader: JSONLReader = JSONLReader()) {
        self.yoloModelURL = yoloModelURL
        self.jsonlWriter = jsonlWriter
        self.jsonlReader = jsonlReader
    }

    /// Scores every row of `extract.jsonl` and writes `enriched.jsonl`.
    /// - Throws: `PipelineError.missingInput` if extract output is empty or names an unknown camera; file errors.
    /// - Note: A frame that can't be decoded, or a YOLO failure, scores 0 for detection and scene change rather
    ///   than failing the step. The segment score uses the same Strava time-zone correction as SelectStep and
    ///   the Fine Tune screen (`SegmentMatcher.stravaOffset`), because Cycliq times are local time stamped as UTC.
    /// - Parameters:
    ///   - project: The ride project to process.
    ///   - reporter: Receives progress updates for the pipeline screen.
    func run(project: Project, reporter: ProgressReporter) async throws {
        try project.createOutputDirectories()
        await reporter.report(current: 0, total: 100, message: "Loading extract.jsonl...")

        let extractRows: [ExtractRow] = try jsonlReader.read(from: project.extractJSONL)
        let flattenRows: [FlattenRow] = try jsonlReader.read(from: project.flattenJSONL)

        guard !extractRows.isEmpty else {
            throw PipelineError.missingInput("extract.jsonl is empty")
        }

        let gpsEnricher    = GPSEnricher(flattenRows: flattenRows)
        let sceneDetector  = SceneDetector()
        let segmentMatcher = SegmentMatcher(segmentsURL: project.segmentsJSON)
        // Strava efforts are true UTC; grid times are camera local time stamped as UTC. Shift by the whole-hour
        // difference before matching, as SelectStep does.
        let rideStartEpoch = extractRows.map(\.absTimeEpoch).min() ?? 0
        let stravaOffset   = segmentMatcher.stravaOffset(rideStartEpoch: rideStartEpoch)
        // Single YOLODetector reused across all frames — MLModel loads once on first detect()
        // call then is reused; NSLock inside loadModel() makes it safe if ever called concurrently.
        let yolo = YOLODetector(modelURL: yoloModelURL)

        // Sort by camera + timestamp for scene continuity (as enrich.py did in the original Python app, not in this repo)
        let sorted = extractRows.sorted {
            if $0.camera != $1.camera { return $0.camera < $1.camera }
            return $0.absTimeEpoch < $1.absTimeEpoch
        }

        var enrichedRows: [EnrichRow] = []
        enrichedRows.reserveCapacity(sorted.count)

        let isoFmt = ISO8601DateFormatter()
        let total  = sorted.count
        var globalIdx = 0

        // Batch by video file — one AVAssetImageGenerator per clip, not per frame.
        // This loads the moov box once per file instead of once per frame.
        var clipStart = 0
        while clipStart < sorted.count {
            let clipPath = sorted[clipStart].videoPath
            var clipEnd  = clipStart + 1
            while clipEnd < sorted.count && sorted[clipEnd].videoPath == clipPath { clipEnd += 1 }

            let generator = FrameSampler.makeGenerator(
                for: ClipCompositor.reanchorSourceURL(clipPath))

            for rowIdx in clipStart..<clipEnd {
                let row = sorted[rowIdx]

                if globalIdx % 50 == 0 {
                    await reporter.report(current: globalIdx, total: total,
                                          message: "Enriching frame \(globalIdx)/\(total)...")
                }
                globalIdx += 1

                let secIntoClip = row.absTimeEpoch - row.clipStartEpoch - AppConfig.clipPreRollS
                let frame = await FrameSampler.extractFrame(using: generator,
                                                            atSecond: max(0, secIntoClip))
                if let frame {
                    let thumbURL = project.framesDir.appending(path: "\(row.index).jpg")
                    FrameSampler.saveJPEG(frame, to: thumbURL)
                }

                var detectScore     = 0.0
                var numDetections   = 0
                var bboxArea        = 0.0
                var detectedClasses = ""
                if let frame, let result = try? yolo.detect(image: frame) {
                    detectScore      = result.detectScore
                    numDetections    = result.detections.count
                    bboxArea         = result.bboxArea
                    detectedClasses  = result.detections.map { $0.className }.joined(separator: ",")
                }

                let sceneBoost = frame.map { sceneDetector.score(frame: $0, camera: row.camera) } ?? 0.0
                let gps        = gpsEnricher.enrich(epoch: row.absTimeEpoch)
                let segBoost   = segmentMatcher.boost(epoch: row.absTimeEpoch - stravaOffset)

                guard let camera = AppConfig.CameraName(rawValue: row.camera) else {
                    throw PipelineError.missingInput("Unrecognized camera name '\(row.camera)'")
                }
                let composite = ScoreCalculator.composite(ScoreCalculator.Input(
                    detectScore:  detectScore,
                    sceneBoost:   sceneBoost,
                    speedKmh:     gps?.speedKmh    ?? 0,
                    gradientPct:  gps?.gradientPct ?? 0,
                    segmentBoost: segBoost,
                    camera:       camera
                ))
                let weighted  = ScoreCalculator.weighted(composite, camera: camera)
                let momentId  = Int(row.absTimeEpoch.rounded())

                enrichedRows.append(EnrichRow(
                    index: row.index, camera: row.camera,
                    clipNum: row.clipNum, frameNumber: row.frameNumber,
                    videoPath: row.videoPath,
                    absTimeEpoch: row.absTimeEpoch, absTimeIso: row.absTimeIso,
                    sessionTsS: row.sessionTsS, clipStartEpoch: row.clipStartEpoch,
                    adjustedStartTime: row.adjustedStartTime, durationS: row.durationS,
                    source: row.source, fps: row.fps,
                    detectScore: detectScore, numDetections: numDetections,
                    bboxArea: bboxArea, detectedClasses: detectedClasses,
                    objectDetected: numDetections > 0,
                    sceneBoost: sceneBoost,
                    gpxEpoch: gps?.epoch, gpxTimeUtc: gps.map { isoFmt.string(from: Date(timeIntervalSince1970: $0.epoch)) },
                    lat: gps?.lat, lon: gps?.lon, elevation: gps?.elevation,
                    hrBpm: gps?.hr, cadenceRpm: gps?.cadence,
                    speedKmh: gps?.speedKmh, gradientPct: gps?.gradientPct,
                    scoreComposite: composite, scoreWeighted: weighted,
                    segmentBoost: segBoost, momentId: momentId
                ))
            }

            generator.cancelAllCGImageGeneration()
            clipStart = clipEnd
        }

        await reporter.report(current: total, total: total,
                              message: "Writing enriched.jsonl (\(enrichedRows.count) rows)...")
        try jsonlWriter.write(rows: enrichedRows, to: project.enrichedJSONL)
    }
}
