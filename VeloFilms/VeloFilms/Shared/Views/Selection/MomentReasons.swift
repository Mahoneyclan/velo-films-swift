// MomentReasons.swift
// Builds the short "Why this moment" lines on the Fine Tune screen (Strava PR, riders in view, gradient, speed).

import Foundation

/// One line explaining why a moment is worth including.
struct MomentReason: Equatable, Identifiable {
    /// What the line is about; also chooses its icon.
    enum Kind: Equatable {
        /// A Strava PR on the segment named in the text.
        case stravaPR
        /// A Strava segment without a PR.
        case segment
        /// Other riders in view.
        case riders
        /// Climbing at or above the climb threshold.
        case climb
        /// Descending at or below the descent threshold.
        case descent
        /// Speed at the moment.
        case speed
    }

    /// What the line is about.
    let kind: Kind
    /// The text shown, e.g. "Climbing 8.3%".
    let text: String
    /// Stable identity for SwiftUI lists; one line per kind.
    var id: Kind { kind }
}

/// Explains moments in plain words, using the same thresholds as the Climbs, Descents and Group filters.
enum MomentReasons {

    /// The reasons for `moment`, most notable first.
    /// - Parameters:
    ///   - moment: The moment.
    ///   - row: The camera row being shown (its speed and gradient are used).
    ///   - segmentName: Strava segment at this moment, if any.
    ///   - isPR: `true` if the moment is inside a Strava PR.
    ///   - ctx: Climb and descent thresholds.
    /// - Returns: Up to five lines; empty if nothing stands out and no speed is known.
    static func reasons(for moment: PartnerMatcher.Moment, row: EnrichRow, segmentName: String?, isPR: Bool,
                        ctx: FocusFilterContext) -> [MomentReason] {
        var out: [MomentReason] = []
        if let name = segmentName, !name.isEmpty {
            out.append(isPR ? MomentReason(kind: .stravaPR, text: "Strava PR · \(name)")
                            : MomentReason(kind: .segment, text: "Segment · \(name)"))
        } else if isPR {
            out.append(MomentReason(kind: .stravaPR, text: "Strava PR"))
        }

        let riders = FocusFilter.riderCount(for: moment)
        if riders >= 2 {
            out.append(MomentReason(kind: .riders, text: "\(riders) riders in view"))
        } else if riders == 1 {
            out.append(MomentReason(kind: .riders, text: "1 rider in view"))
        }

        if let g = row.gradientPct {
            if g >= ctx.climbGradientPct {
                out.append(MomentReason(kind: .climb, text: "Climbing " + percent(g)))
            } else if g <= ctx.descentGradientPct {
                out.append(MomentReason(kind: .descent, text: "Descending " + percent(-g)))
            }
        }
        if let speed = row.speedKmh {
            out.append(MomentReason(kind: .speed, text: "\(Int(speed.rounded())) km/h"))
        }
        return out
    }

    /// One decimal place, e.g. "8.3%".
    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}
