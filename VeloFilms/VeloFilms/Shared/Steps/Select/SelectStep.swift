import Foundation

/// Runs clip selection and writes select.csv.
/// Mirrors select.py: groups by moment_id → score → gap filter → zone enforcement.
struct SelectStep: PipelineStep {
    let name = "select"
    let csvWriter: CSVWriter
    let csvReader: CSVReader

    init(csvWriter: CSVWriter = CSVWriter(), csvReader: CSVReader = CSVReader()) {
        self.csvWriter = csvWriter
        self.csvReader = csvReader
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 0, total: 3, message: "Loading enriched.csv...")

        let enrichedRows: [EnrichRow] = try csvReader.read(from: project.enrichedCSV)
        guard !enrichedRows.isEmpty else {
            throw PipelineError.missingInput("enriched.csv is empty — run enrich step first")
        }

        await reporter.report(current: 1, total: 3, message: "Selecting best moments...")

        let moments    = PartnerMatcher.group(enrichedRows)
        let selected   = ClipSelector.select(moments: moments)
        let selectedIds = Set(selected.map { $0.momentId })

        // Build select.csv rows — one row per EnrichRow, with recommended flag
        var selectRows: [SelectRow] = []
        for row in enrichedRows {
            let moment  = moments.first { $0.momentId == row.momentId }
            let isRec   = selectedIds.contains(row.momentId) && moment?.primary?.index == row.index
            let isPaired = moment?.secondary != nil
            let isPR    = (row.segmentBoost >= AppConfig.StravaBoost.rank1)

            selectRows.append(SelectRow(
                index: row.index, camera: row.camera,
                clipNum: row.clipNum, frameNumber: row.frameNumber,
                videoPath: row.videoPath,
                absTimeEpoch: row.absTimeEpoch, absTimeIso: row.absTimeIso,
                sessionTsS: row.sessionTsS, clipStartEpoch: row.clipStartEpoch,
                adjustedStartTime: row.adjustedStartTime, durationS: row.durationS,
                source: row.source, fps: row.fps,
                detectScore: row.detectScore, numDetections: row.numDetections,
                bboxArea: row.bboxArea, detectedClasses: row.detectedClasses,
                objectDetected: row.objectDetected,
                sceneBoost: row.sceneBoost,
                gpxEpoch: row.gpxEpoch, gpxTimeUtc: row.gpxTimeUtc,
                lat: row.lat, lon: row.lon, elevation: row.elevation,
                hrBpm: row.hrBpm, cadenceRpm: row.cadenceRpm,
                speedKmh: row.speedKmh, gradientPct: row.gradientPct,
                scoreComposite: row.scoreComposite, scoreWeighted: row.scoreWeighted,
                segmentBoost: row.segmentBoost, momentId: row.momentId,
                recommended: isRec,
                stravaPR: isPR,
                isSingleCamera: moment?.isSingleCamera ?? true,
                paired: isPaired,
                segmentName: nil, segmentDistance: nil, segmentGrade: nil
            ))
        }

        await reporter.report(current: 2, total: 3, message: "Writing select.csv...")
        try csvWriter.write(rows: selectRows, to: project.selectCSV)

        let recCount = selectRows.filter { $0.recommended }.count
        await reporter.report(current: 3, total: 3,
                              message: "Selected \(recCount) clips (target: \(AppConfig.targetClips))")
    }
}
