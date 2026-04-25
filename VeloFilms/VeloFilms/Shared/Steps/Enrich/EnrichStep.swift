import Foundation
import AVFoundation
import CoreGraphics

/// Runs YOLO detection, scene scoring, GPS enrichment, and composite scoring.
/// Writes enriched.jsonl. Mirrors enrich.py.
struct EnrichStep: PipelineStep {
    let name = "enrich"
    let jsonlWriter: JSONLWriter
    let jsonlReader: JSONLReader
    let yoloModelURL: URL

    init(yoloModelURL: URL,
         jsonlWriter: JSONLWriter = JSONLWriter(),
         jsonlReader: JSONLReader = JSONLReader()) {
        self.yoloModelURL = yoloModelURL
        self.jsonlWriter = jsonlWriter
        self.jsonlReader = jsonlReader
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        try project.createOutputDirectories()
        await reporter.report(current: 0, total: 100, message: "Loading CSV files...")

        let extractRows: [ExtractRow] = try jsonlReader.read(from: project.extractJSONL)
        let flattenRows: [FlattenRow] = try jsonlReader.read(from: project.flattenJSONL)

        guard !extractRows.isEmpty else {
            throw PipelineError.missingInput("extract.jsonl is empty")
        }

        let gpsEnricher = GPSEnricher(flattenRows: flattenRows)
        let sceneDetector = SceneDetector()
        let yolo = YOLODetector(modelURL: yoloModelURL)
        let segmentMatcher = SegmentMatcher(segmentsURL: project.segmentsJSON)

        // Sort by camera + timestamp for scene continuity (mirrors enrich.py)
        let sorted = extractRows.sorted {
            if $0.camera != $1.camera { return $0.camera < $1.camera }
            return $0.absTimeEpoch < $1.absTimeEpoch
        }

        var enrichedRows: [EnrichRow] = []
        enrichedRows.reserveCapacity(sorted.count)

        let total = sorted.count
        var globalIdx = 0

        // Batch by video file — one AVAssetImageGenerator per clip, not per frame.
        // This loads the moov box once per 2.2 GB file instead of once per frame.
        var clipStart = 0
        while clipStart < sorted.count {
            let clipPath = sorted[clipStart].videoPath
            var clipEnd = clipStart + 1
            while clipEnd < sorted.count && sorted[clipEnd].videoPath == clipPath { clipEnd += 1 }

            let generator = FrameSampler.makeGenerator(for: URL(fileURLWithPath: clipPath))

            for rowIdx in clipStart..<clipEnd {
                let row = sorted[rowIdx]

                if globalIdx % 50 == 0 {
                    await reporter.report(current: globalIdx, total: total,
                                          message: "Enriching frame \(globalIdx)/\(total)...")
                }
                globalIdx += 1

                // Extract frame
                let secIntoClip = row.absTimeEpoch - row.clipStartEpoch - AppConfig.clipPreRollS
                let frame = await FrameSampler.extractFrame(using: generator,
                                                           atSecond: max(0, secIntoClip))
                // Save thumbnail for ManualSelectionView
                if let frame {
                    let thumbURL = project.framesDir.appending(path: "\(row.index).jpg")
                    FrameSampler.saveJPEG(frame, to: thumbURL)
                }

            // YOLO detection
            var detectScore = 0.0
            var numDetections = 0
            var bboxArea = 0.0
            var detectedClasses = ""
            if let frame, let result = try? yolo.detect(image: frame) {
                detectScore    = result.detectScore
                numDetections  = result.detections.count
                bboxArea       = result.bboxArea
                detectedClasses = result.detections.map { $0.className }.joined(separator: ",")
            }

            // Scene detection
            let sceneBoost = frame.map { sceneDetector.score(frame: $0, camera: row.camera) } ?? 0.0

            // GPS enrichment
            let gps = gpsEnricher.enrich(epoch: row.absTimeEpoch)

            // Segment boost
            let segBoost = segmentMatcher.boost(epoch: row.absTimeEpoch)

            // Scoring
            let camera = AppConfig.CameraName(rawValue: row.camera) ?? .fly12Sport
            let composite = ScoreCalculator.composite(ScoreCalculator.Input(
                detectScore: detectScore,
                sceneBoost: sceneBoost,
                speedKmh: gps?.speedKmh ?? 0,
                gradientPct: gps?.gradientPct ?? 0,
                bboxArea: bboxArea,
                segmentBoost: segBoost,
                camera: camera
            ))
            let weighted = ScoreCalculator.weighted(composite, camera: camera)

            let momentId = Int(row.absTimeEpoch.rounded())

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
                    gpxEpoch: gps?.epoch, gpxTimeUtc: gps.map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0.epoch)) },
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
