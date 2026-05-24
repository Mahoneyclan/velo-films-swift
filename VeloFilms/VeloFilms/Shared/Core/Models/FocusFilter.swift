import Foundation

/// View-level focus mode applied on top of AI clip selection in ManualSelectionView.
/// Filters the visible list of moments without modifying AI scores, selection, or any pipeline step.
enum FocusFilter: Hashable {
    case all
    case openingZone
    case closingZone
    case climbs
    case descents
    case groupRiding
    case stravaPR
    case lap(name: String)

    var label: String {
        switch self {
        case .all:          return "All Clips"
        case .openingZone:  return "Opening"
        case .closingZone:  return "Closing"
        case .climbs:       return "Climbs"
        case .descents:     return "Descents"
        case .groupRiding:  return "Group Riding"
        case .stravaPR:     return "Strava PRs"
        case .lap(let n):   return n
        }
    }

    var icon: String {
        switch self {
        case .all:          return "square.grid.2x2"
        case .openingZone:  return "play.circle"
        case .closingZone:  return "stop.circle"
        case .climbs:       return "arrow.up.right"
        case .descents:     return "arrow.down.right"
        case .groupRiding:  return "person.3"
        case .stravaPR:     return "trophy"
        case .lap:          return "flag.checkered"
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
    /// Wall-clock epoch where the opening zone ends (from moving-time boundary in SelectStep).
    let startZoneEndEpoch: Double
    /// Wall-clock epoch where the closing zone begins (from moving-time boundary in SelectStep).
    let endZoneStartEpoch: Double
    let climbGradientPct: Double
    let descentGradientPct: Double   // stored as negative (e.g. -4.0)
    let groupMinDetections: Int
    /// momentIds of clips where SelectRow.stravaPR == true.
    let stravaPRMomentIds: Set<Int>
}

// MARK: - Matching logic

extension FocusFilter {
    func matches(_ moment: PartnerMatcher.Moment, in ctx: FocusFilterContext) -> Bool {
        let t = Double(moment.momentId)

        switch self {
        case .all:
            return true

        case .openingZone:
            return t <= ctx.startZoneEndEpoch

        case .closingZone:
            return t >= ctx.endZoneStartEpoch

        case .climbs:
            return (moment.primary?.gradientPct ?? 0) >= ctx.climbGradientPct

        case .descents:
            // descentGradientPct stored as negative (e.g. -4.0)
            return (moment.primary?.gradientPct ?? 0) <= ctx.descentGradientPct

        case .groupRiding:
            return Self.riderCount(for: moment) >= ctx.groupMinDetections

        case .stravaPR:
            return ctx.stravaPRMomentIds.contains(moment.momentId)

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
