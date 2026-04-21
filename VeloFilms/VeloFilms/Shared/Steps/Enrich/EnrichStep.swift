import Foundation
import CoreGraphics

/// Runs YOLO detection, scene scoring, GPS enrichment, and composite scoring.
/// Writes enriched.csv. Mirrors enrich.py.
struct EnrichStep: PipelineStep {
    let name = "enrich"
    let csvWriter: CSVWriter
    let csvReader: CSVReader
    let yoloModelURL: URL

    init(yoloModelURL: URL,
         csvWriter: CSVWriter = CSVWriter(),
         csvReader: CSVReader = CSVReader()) {
        self.yoloModelURL = yoloModelURL
        self.csvWriter = csvWriter
        self.csvReader = csvReader
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 0, total: 100, message: "Loading CSV files...")

        let extractRows: [ExtractRow] = try csvReader.read(from: project.extractCSV)
        let flattenRows: [FlattenRow] = try csvReader.read(from: project.flattenCSV)

        guard !extractRows.isEmpty else {
            throw PipelineError.missingInput("extract.csv is empty")
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
        for (i, row) in sorted.enumerated() {
            if i % 50 == 0 {
                await reporter.report(current: i, total: total,
                                      message: "Enriching frame \(i)/\(total)...")
            }

            // Extract frame
            let secIntoClip = row.absTimeEpoch - row.clipStartEpoch - AppConfig.clipPreRollS
            let frame = await FrameSampler.extractFrame(
                videoURL: URL(fileURLWithPath: row.videoPath),
                atSecond: max(0, secIntoClip)
            )

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

        await reporter.report(current: total, total: total,
                              message: "Writing enriched.csv (\(enrichedRows.count) rows)...")
        try csvWriter.write(rows: enrichedRows, to: project.enrichedCSV)
    }
}
