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
    case lap(name: String)

    var label: String {
        switch self {
        case .all:            return "All Clips"
        case .firstNMinutes:  return "First N min"
        case .lastNMinutes:   return "Last N min"
        case .climbs:         return "Climbs"
        case .descents:       return "Descents"
        case .groupRiding:    return "Group Riding"
        case .lap(let n):     return n
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
        case .lap:            return "flag.checkered"
        }
    }
}

// MARK: - Filtering context

/// Immutable snapshot of all values needed to evaluate a FocusFilter.
/// Passed to `matches(_:in:)` to avoid accessing singletons in the hot path.
struct FocusFilterContext {
    let rideStartEpoch: Double
    let rideDurationS: Double
    let lapEpochRanges: [(name: String, startEpoch: Double, endEpoch: Double)]
    let firstNMinutes: Double
    let lastNMinutes: Double
    let climbGradientPct: Double
    let descentGradientPct: Double   // stored as negative (e.g. -4.0)
    let groupMinDetections: Int
}

// MARK: - Matching logic

extension FocusFilter {
    func matches(_ moment: PartnerMatcher.Moment, in ctx: FocusFilterContext) -> Bool {
        let t       = Double(moment.momentId)
        let elapsed = t - ctx.rideStartEpoch

        switch self {
        case .all:
            return true

        case .firstNMinutes:
            return elapsed <= ctx.firstNMinutes * 60

        case .lastNMinutes:
            return elapsed >= Swift.max(0.0, ctx.rideDurationS - ctx.lastNMinutes * 60)

        case .climbs:
            return (moment.primary?.gradientPct ?? 0) >= ctx.climbGradientPct

        case .descents:
            // descentGradientPct stored as negative (e.g. -4.0)
            return (moment.primary?.gradientPct ?? 0) <= ctx.descentGradientPct

        case .groupRiding:
            return Self.riderCount(for: moment) >= ctx.groupMinDetections

        case .lap(let name):
            return ctx.lapEpochRanges.contains {
                $0.name == name && t >= $0.startEpoch && t <= $0.endEpoch
            }
        }
    }

    /// Counts person + bicycle detections for group-riding determination.
    static func riderCount(for moment: PartnerMatcher.Moment) -> Int {
        guard let row = moment.primary ?? moment.rows.first else { return 0 }
        let riderClasses: Set<String> = ["person", "bicycle"]
        return row.detectedClasses
            .split(separator: ",")
            .filter { riderClasses.contains(String($0).trimmingCharacters(in: CharacterSet.whitespaces).lowercased()) }
            .count
    }
}
