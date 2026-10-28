// SelectStep.swift
// Pipeline step 4: chooses the highlight clips and writes select.jsonl, keeping the user's manual choices.

import Foundation

/// Runs clip selection and writes `select.jsonl` (one row per enriched row, with a `recommended` flag).
/// Steps: group by moment → select (`ClipSelector`) → apply manual overrides → add Strava segment details.
/// Same approach as `select.py` in the original Python app.
struct SelectStep: PipelineStep {
    /// Step name used in logs.
    let name = "select"
    /// Output writer (injectable for testing).
    let jsonlWriter: JSONLWriter
    /// Input reader (injectable for testing).
    let jsonlReader: JSONLReader

    /// Creates the step with standard reader and writer by default.
    /// - Parameters:
    ///   - jsonlWriter: Writes `select.jsonl`.
    ///   - jsonlReader: Reads `enriched.jsonl` and the earlier `select.jsonl`.
    init(jsonlWriter: JSONLWriter = JSONLWriter(), jsonlReader: JSONLReader = JSONLReader()) {
        self.jsonlWriter = jsonlWriter
        self.jsonlReader = jsonlReader
    }

    /// Selects clips and writes `select.jsonl`. Manual choices from an earlier `select.jsonl` are kept.
    /// - Throws: `PipelineError.missingInput` if `enriched.jsonl` is empty; file errors.
    /// - Note: Only the higher-scoring camera's row of a selected moment is marked `recommended`.
    /// - Parameters:
    ///   - project: The ride project to process.
    ///   - reporter: Receives progress updates for the pipeline screen.
    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 0, total: 3, message: "Loading enriched.jsonl...")

        let enrichedRows: [EnrichRow] = try jsonlReader.read(from: project.enrichedJSONL)
        guard !enrichedRows.isEmpty else {
            throw PipelineError.missingInput("enriched.jsonl is empty — run enrich step first")
        }

        await reporter.report(current: 1, total: 3, message: "Selecting best moments...")

        let moments = PartnerMatcher.group(enrichedRows)

        let selected = ClipSelector.select(moments: moments)
        let selectedIds = Set(selected.map { $0.momentId })
        let momentById  = Dictionary(moments.map { ($0.momentId, $0) }, uniquingKeysWith: { a, _ in a })

        // Load existing select.jsonl to preserve manual overrides across re-runs.
        let existingRows: [SelectRow] = (try? jsonlReader.read(from: project.selectJSONL)) ?? []
        let existingByIndex = Dictionary(existingRows.map { ($0.base.index, $0) },
                                         uniquingKeysWith: { a, _ in a })

        // SegmentMatcher — re-query with timezone offset so segment names and PR flags
        // are correct even when abs_time_epoch is local-time-as-UTC (Cycliq wrong-Z).
        let segMatcher = SegmentMatcher(segmentsURL: project.segmentsJSON)
        let rideStartEpoch = enrichedRows.map(\.absTimeEpoch).min() ?? 0
        let stravaOffset = segMatcher.stravaOffset(rideStartEpoch: rideStartEpoch)

        // Build select.jsonl rows — one row per EnrichRow, with recommended flag.
        // Manual overrides (manualOverride != nil) take precedence over AI selection.
        var selectRows: [SelectRow] = []
        for row in enrichedRows {
            let moment      = momentById[row.momentId]
            let aiIsRec     = selectedIds.contains(row.momentId) && moment?.primary?.index == row.index
            let isPaired    = moment?.secondary != nil
            let existing    = existingByIndex[row.index]
            let override    = existing?.manualOverride
            let isRec       = override ?? aiIsRec   // manual wins if set

            // Use offset-corrected epoch so Strava UTC aligns with abs_time_epoch.
            let adjustedEpoch = row.absTimeEpoch - stravaOffset
            let segEffort     = segMatcher.effort(epoch: adjustedEpoch)
            let isPR          = segEffort?.prRank == 1 || row.segmentBoost >= AppConfig.StravaBoost.rank1

            selectRows.append(SelectRow(
                base: row,
                recommended: isRec,
                stravaPR: isPR,
                isSingleCamera: moment?.isSingleCamera ?? true,
                paired: isPaired,
                segmentName: segEffort?.name,
                segmentDistance: segEffort?.distance,
                segmentGrade: segEffort?.averageGrade,
                manualOverride: override
            ))
        }

        await reporter.report(current: 2, total: 3, message: "Writing select.jsonl...")
        try jsonlWriter.write(rows: selectRows, to: project.selectJSONL)

        let recCount = selectRows.filter { $0.recommended }.count
        await reporter.report(current: 3, total: 3,
                              message: "Selected \(recCount) clips (target: \(AppConfig.targetClips))")
    }
}
