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

        let moments = PartnerMatcher.group(enrichedRows)

        // Compute zone boundaries from moving time so long stops don't skew the opening/closing zones.
        let flattenRows: [FlattenRow] = (try? jsonlReader.read(from: project.flattenJSONL)) ?? []
        let (startZoneEnd, endZoneStart) = Self.movingTimeZoneBoundaries(
            flatten: flattenRows,
            startPct: AppConfig.startZonePct,
            endPct: AppConfig.endZonePct
        )
        var config = ClipSelector.Config()
        config.startZoneEndEpoch = startZoneEnd
        config.endZoneStartEpoch = endZoneStart

        let selected = ClipSelector.select(moments: moments, config: config)
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
    /// time have elapsed. Rows with [speedKmh] < 3 km/h are treated as stopped and excluded
    /// from the moving-time accumulation, so long stops don't push zone boundaries into the
    /// dead middle of the ride.
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
        var startEpoch = entries.first!.epoch
        var endEpoch   = entries.last!.epoch
        for entry in entries {
            if entry.cumMoving >= startTarget { startEpoch = entry.epoch; break }
        }
        for entry in entries.reversed() {
            if entry.cumMoving <= endTarget { endEpoch = entry.epoch; break }
        }

        return (startEpoch, endEpoch)
    }
}
