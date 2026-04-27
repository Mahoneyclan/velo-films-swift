import Foundation

/// Runs clip selection and writes select.jsonl.
/// Mirrors select.py: groups by moment_id → score → gap filter → zone enforcement.
struct SelectStep: PipelineStep {
    let name = "select"
    let jsonlWriter: JSONLWriter
    let jsonlReader: JSONLReader

    init(jsonlWriter: JSONLWriter = JSONLWriter(), jsonlReader: JSONLReader = JSONLReader()) {
        self.jsonlWriter = jsonlWriter
        self.jsonlReader = jsonlReader
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 0, total: 3, message: "Loading enriched.jsonl...")

        let enrichedRows: [EnrichRow] = try jsonlReader.read(from: project.enrichedJSONL)
        guard !enrichedRows.isEmpty else {
            throw PipelineError.missingInput("enriched.jsonl is empty — run enrich step first")
        }

        await reporter.report(current: 1, total: 3, message: "Selecting best moments...")

        let moments    = PartnerMatcher.group(enrichedRows)
        let selected   = ClipSelector.select(moments: moments)
        let selectedIds = Set(selected.map { $0.momentId })

        // Build select.jsonl rows — one row per EnrichRow, with recommended flag
        var selectRows: [SelectRow] = []
        for row in enrichedRows {
            let moment  = moments.first { $0.momentId == row.momentId }
            let isRec   = selectedIds.contains(row.momentId) && moment?.primary?.index == row.index
            let isPaired = moment?.secondary != nil
            let isPR    = (row.segmentBoost >= AppConfig.StravaBoost.rank1)

            selectRows.append(SelectRow(
                base: row,
                recommended: isRec,
                stravaPR: isPR,
                isSingleCamera: moment?.isSingleCamera ?? true,
                paired: isPaired
            ))
        }

        await reporter.report(current: 2, total: 3, message: "Writing select.jsonl...")
        try jsonlWriter.write(rows: selectRows, to: project.selectJSONL)

        let recCount = selectRows.filter { $0.recommended }.count
        await reporter.report(current: 3, total: 3,
                              message: "Selected \(recCount) clips (target: \(AppConfig.targetClips))")
    }
}
