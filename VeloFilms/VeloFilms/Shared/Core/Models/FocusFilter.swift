import Foundation

/// View-level focus mode applied on top of AI clip selection in ManualSelectionView.
/// Filters the visible list of moments without modifying AI scores, selection, or any pipeline step.
enum FocusFilter: Hashable {
    case all
    case firstNMinutes
    case lastNMinutes
    case climbs
    case descents
    case groupRiding
    case segment(name: String)

    var label: String {
        switch self {
        case .all:            return "All Clips"
        case .firstNMinutes:  return "First N min"
        case .lastNMinutes:   return "Last N min"
        case .climbs:         return "Climbs"
        case .descents:       return "Descents"
        case .groupRiding:    return "Group Riding"
        case .segment(let n): return n
        }
    }

    var icon: String {
        switch self {
        case .all:            return "square.grid.2x2"
        case .firstNMinutes:  return "clock"
        case .lastNMinutes:   return "clock.badge.checkmark"
        case .climbs:         return "arrow.up.right"
        case .descents:       return "arrow.down.right"
        case .groupRiding:    return "person.3"
        case .segment:        return "location"
        }
    }
}

// MARK: - Filtering context

/// Immutable snapshot of all values needed to evaluate a FocusFilter.
/// Passed to `matches(_:in:)` to avoid accessing singletons in the hot path — also makes testing trivial.
struct FocusFilterContext {
    let rideStartEpoch: Double
    let rideDurationS: Double
    let segmentEpochRanges: [(name: String, startEpoch: Double, endEpoch: Double)]
    let firstNMinutes: Double
    let lastNMinutes: Double
    let climbGradientPct: Double
    let descentGradientPct: Double
    let groupMinDetections: Int

    static func build(
        moments: [PartnerMatcher.Moment],
        segmentEpochRanges: [(name: String, startEpoch: Double, endEpoch: Double)],
        firstNMinutes: Double,
        lastNMinutes: Double,
        climbGradientPct: Double,
        descentGradientPct: Double,
        groupMinDetections: Int
    ) -> FocusFilterContext {
        let start = Double(moments.first?.momentId ?? 0)
        let end   = Double(moments.last?.momentId ?? 0)
        return FocusFilterContext(
            rideStartEpoch:     start,
            rideDurationS:      Swift.max(0.0, end - start),
            segmentEpochRanges: segmentEpochRanges,
            firstNMinutes:      firstNMinutes,
            lastNMinutes:       lastNMinutes,
            climbGradientPct:   climbGradientPct,
            descentGradientPct: descentGradientPct,
            groupMinDetections: groupMinDetections
        )
    }
}

// MARK: - Matching logic

extension FocusFilter {
    /// Returns true if this moment passes the filter given the provided context.
    func matches(_ moment: PartnerMatcher.Moment, in ctx: FocusFilterContext) -> Bool {
        let t       = Double(moment.momentId)
        let elapsed = t - ctx.rideStartEpoch

        switch self {
        case .all:
            return true

        case .firstNMinutes:
            return elapsed <= ctx.firstNMinutes * 60

        case .lastNMinutes:
            return elapsed >= max(0.0, ctx.rideDurationS - ctx.lastNMinutes * 60)

        case .climbs:
            return (moment.primary?.gradientPct ?? 0) >= ctx.climbGradientPct

        case .descents:
            // descentGradientPct is stored as a negative value (e.g. -4.0); direct comparison works
            return (moment.primary?.gradientPct ?? 0) <= ctx.descentGradientPct

        case .groupRiding:
            return Self.riderCount(for: moment) >= ctx.groupMinDetections

        case .segment(let name):
            return ctx.segmentEpochRanges.contains {
                $0.name == name && t >= $0.startEpoch && t <= $0.endEpoch
            }
        }
    }

    /// Counts person + bicycle detections for group-riding determination.
    /// `detectedClasses` is comma-joined with one entry per detection (not unique),
    /// matching how EnrichStep builds it: detections.map { $0.className }.joined(separator: ",").
    static func riderCount(for moment: PartnerMatcher.Moment) -> Int {
        guard let row = moment.primary ?? moment.rows.first else { return 0 }
        let riderClasses: Set<String> = ["person", "bicycle"]
        return row.detectedClasses
            .split(separator: ",")
            .filter { riderClasses.contains(String($0).trimmingCharacters(in: CharacterSet.whitespaces).lowercased()) }
            .count
    }
}
