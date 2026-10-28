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

    // MARK: - Moving-time zone boundaries

    /// Returns the wall-clock epoch values where [startPct] and (1−[endPct]) of total moving
    /// time have elapsed. Used by the Fine Tune screen's Opening/Closing filters; selection itself has no zones. Rows with [speedKmh] < 3 km/h are treated as stopped and excluded
    /// from the moving-time accumulation, so long stops don't push zone boundaries into the
    /// dead middle of the ride.
    /// - Parameters:
    ///   - flatten: The 1 Hz track.
    ///   - startPct: Fraction of moving time in the opening zone.
    ///   - endPct: Fraction of moving time in the closing zone.
    /// - Returns: Zone boundary times, or (0, 0) if the track is empty or never moving (callers then fall back
    ///   to a simple percentage of the ride).
    static func movingTimeZoneBoundaries(
        flatten: [FlattenRow],
        startPct: Double,
        endPct: Double
    ) -> (startZoneEnd: Double, endZoneStart: Double) {
        let movingThresholdKmh = 3.0
        let sorted = flatten.sorted { $0.gpxEpoch < $1.gpxEpoch }
        guard !sorted.isEmpty else { return (0, 0) }

        // Accumulate 1 moving-second per row where speed ≥ threshold
        var cumMoving = 0.0
        var entries: [(epoch: Double, cumMoving: Double)] = []
        entries.reserveCapacity(sorted.count)
        for row in sorted {
            if row.speedKmh >= movingThresholdKmh { cumMoving += 1.0 }
            entries.append((row.gpxEpoch, cumMoving))
        }

        let totalMoving = cumMoving
        guard totalMoving > 0 else { return (0, 0) }

        let startTarget = totalMoving * startPct
        let endTarget   = totalMoving * (1.0 - endPct)

        // Find first epoch where cumulative moving time crosses each target
        var startEpoch = entries[0].epoch
        var endEpoch   = entries[entries.count - 1].epoch
        for entry in entries {
            if entry.cumMoving >= startTarget { startEpoch = entry.epoch; break }
        }
        for entry in entries.reversed() {
            if entry.cumMoving <= endTarget { endEpoch = entry.epoch; break }
        }

        return (startEpoch, endEpoch)
    }
}
