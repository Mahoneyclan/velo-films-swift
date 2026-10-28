// FocusFilter.swift
// Moment filters for the Fine Tune screen (climbs, descents, group riding, Strava PRs) and their matching rules.

import Foundation

/// A view-level filter on the Fine Tune screen. It narrows which moments are shown without changing scores,
/// selection or any pipeline step.
enum FocusFilter: Hashable {
    /// Every moment.
    case all
    /// Moments at or above the climb gradient threshold.
    case climbs
    /// Moments at or below the (negative) descent gradient threshold.
    case descents
    /// Moments with at least the minimum number of riders in view.
    case groupRiding
    /// Moments inside a Strava segment PR.
    case stravaPR
}

// MARK: - Filtering context

/// The thresholds and PR moments needed to evaluate a `FocusFilter`, captured once so matching never reads
/// settings in a loop.
struct FocusFilterContext {
    /// Climb threshold in percent.
    let climbGradientPct: Double
    /// Descent threshold in percent, stored as a negative number (e.g. -4.0).
    let descentGradientPct: Double
    /// Minimum rider count for the Group Riding filter.
    let groupMinDetections: Int
    /// momentIds of clips where `SelectRow.stravaPR` is `true`.
    let stravaPRMomentIds: Set<Int>
}

// MARK: - Matching logic

extension FocusFilter {
    /// Whether `moment` passes this filter.
    /// - Parameters:
    ///   - moment: A grid point with the rows from one or both cameras.
    ///   - ctx: Thresholds captured when the screen loaded.
    /// - Returns: `true` if the moment should be shown. Gradient filters use the primary camera's row and treat a
    ///   missing gradient as 0.
    func matches(_ moment: PartnerMatcher.Moment, in ctx: FocusFilterContext) -> Bool {
        switch self {
        case .all:
            return true
        case .climbs:
            return (moment.primary?.gradientPct ?? 0) >= ctx.climbGradientPct
        case .descents:
            return (moment.primary?.gradientPct ?? 0) <= ctx.descentGradientPct
        case .groupRiding:
            return Self.riderCount(for: moment) >= ctx.groupMinDetections
        case .stravaPR:
            return ctx.stravaPRMomentIds.contains(moment.momentId)
        }
    }

    /// Counts riders in a moment — defined as max(person detections, bicycle detections)
    /// per camera row, then max across rows.
    ///
    /// Using max(persons, bicycles) rather than summing both avoids double-counting:
    /// a cyclist detected as both "person" and "bicycle" is one rider, not two.
    /// Taking the per-row max (not sum) avoids double-counting the same group
    /// viewed from two camera angles.
    /// - Parameter moment: A moment with one or two camera rows.
    /// - Returns: The estimated number of riders in view, 0 if nothing was detected.
    static func riderCount(for moment: PartnerMatcher.Moment) -> Int {
        return moment.rows.map { row in
            let classes = row.detectedClasses
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let persons  = classes.filter { $0 == "person" }.count
            let bicycles = classes.filter { $0 == "bicycle" }.count
            return max(persons, bicycles)
        }.max() ?? 0
    }
}
