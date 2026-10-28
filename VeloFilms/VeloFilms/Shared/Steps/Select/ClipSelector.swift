// ClipSelector.swift
// The clip selection algorithm: ride-wide coverage, spacing that scales with the ride, start and finish picks.

import Foundation

/// Selects the best moments for the highlight reel.
///
/// Steps: (1) ignore moments while stopped; (2) set the gap between picks to half the average spacing the ride
/// allows, never below the user's minimum; (3) split the riding footage into equal stretches and take the best
/// moment from each, so the whole ride is represented; (4) fill the remaining places best-first, keeping the gap;
/// (5) make sure one moment comes from the first and one from the last few minutes, so the reel opens at the
/// start and ends at the finish.
/// Replaces the shortlist and opening/closing caps of `select.py` in the original Python app, which left picks
/// bunched together (up to 64% under 30 s apart) and skipped up to 40 minutes of riding.
struct ClipSelector {

    /// Selection limits. Defaults come from settings.
    struct Config {
        /// Clips wanted (global target length ÷ clip length).
        var targetClips: Int   = AppConfig.targetClips
        /// The user's minimum seconds between picks; long rides space picks further apart than this.
        var minGap: Double     = GlobalSettings.shared.minGapBetweenClips
        /// Seconds at each end of the ride that must contribute one moment (0 turns this off).
        var edgeWindow: Double = AppConfig.rideEdgeWindowS
    }

    /// Picks the moments for the reel.
    /// - Parameters:
    ///   - moments: All moments (as `PartnerMatcher.group` returns them).
    ///   - config: Limits.
    /// - Returns: Up to `config.targetClips` moments, in no guaranteed order (callers use only the ids).
    static func select(moments: [PartnerMatcher.Moment], config: Config = Config()) -> [PartnerMatcher.Moment] {
        guard config.targetClips > 0 else { return [] }
        let riding = ridingMoments(moments)
        guard let first = riding.first, let last = riding.last else { return [] }

        let gap = spacing(for: riding, config: config)
        let coverage = bestPerStretch(riding, gap: gap, targetClips: config.targetClips)
        var selected = coverage
        fillBestFirst(&selected, from: riding, gap: gap, limit: config.targetClips)

        if config.edgeWindow > 0 {
            // Coverage picks are never swapped out: they are often the lowest-scoring, and losing one
            // reopens a long stretch with no pick.
            var keep = Set(coverage.map(\.momentId))
            let rideStart = Double(first.momentId), rideEnd = Double(last.momentId)
            selected = ensurePick(in: rideStart...(rideStart + config.edgeWindow), selected: selected,
                                  moments: riding, gap: gap, targetClips: config.targetClips, keep: keep)
            let startPick = selected.filter { Double($0.momentId) <= rideStart + config.edgeWindow }
            keep.formUnion(startPick.map(\.momentId))
            selected = ensurePick(in: (rideEnd - config.edgeWindow)...rideEnd, selected: selected,
                                  moments: riding, gap: gap, targetClips: config.targetClips, keep: keep)
        }
        return selected
    }

    // MARK: - Riding footage and spacing

    /// Moments filmed while moving, in time order. Moments with no speed (no GPS match) count as moving, and if
    /// nothing is moving at all every moment is used, so a ride without GPS still gets a reel.
    /// - Parameter moments: All moments.
    /// - Returns: The moments to choose from, sorted by time.
    static func ridingMoments(_ moments: [PartnerMatcher.Moment]) -> [PartnerMatcher.Moment] {
        let sorted = moments.sorted { $0.momentId < $1.momentId }
        let moving = sorted.filter { m in
            let speeds = m.rows.compactMap(\.speedKmh)
            return speeds.isEmpty || (speeds.max() ?? 0) >= AppConfig.movingSpeedKmh
        }
        return moving.isEmpty ? sorted : moving
    }

    /// Seconds required between picks: `AppConfig.selectionSpacingFraction` of the average spacing the riding
    /// footage allows for the target, never below the user's `config.minGap`.
    /// - Parameters:
    ///   - riding: Riding moments in time order.
    ///   - config: Supplies `targetClips` and `minGap`.
    /// - Returns: The gap in seconds.
    static func spacing(for riding: [PartnerMatcher.Moment], config: Config) -> Double {
        let times = riding.map { Double($0.momentId) }
        let steps = zip(times, times.dropFirst()).map { $1 - $0 }.sorted()
        // Median sample spacing, so camera gaps between files don't inflate the footage length.
        let step = steps.isEmpty ? AppConfig.extractIntervalSeconds : steps[steps.count / 2]
        let footage = Double(riding.count) * step
        let average = footage / Double(max(1, config.targetClips))
        return max(config.minGap, average * AppConfig.selectionSpacingFraction)
    }

    // MARK: - Coverage and fill

    /// Splits the riding footage into equal stretches (one per `AppConfig.clipsPerStretch` clips) and takes the
    /// best moment from each that keeps [gap] from the picks already made.
    /// - Parameters:
    ///   - riding: Riding moments in time order.
    ///   - gap: Seconds required between picks.
    ///   - targetClips: Clips wanted.
    /// - Returns: At most one moment per stretch.
    static func bestPerStretch(_ riding: [PartnerMatcher.Moment], gap: Double,
                               targetClips: Int) -> [PartnerMatcher.Moment] {
        let stretches = min(riding.count,
                            Int((Double(targetClips) / Double(AppConfig.clipsPerStretch)).rounded(.up)))
        guard stretches > 0 else { return [] }
        let size = Double(riding.count) / Double(stretches)
        var picks: [PartnerMatcher.Moment] = []
        for s in 0..<stretches {
            let stretch = riding[Int(Double(s) * size)..<Int(Double(s + 1) * size)]
            let pick = stretch.sorted { $0.bestScore > $1.bestScore }
                .first { keepsGap($0, from: picks, gap: gap) }
            if let pick { picks.append(pick) }
        }
        return picks
    }

    /// Adds the best remaining moments, keeping [gap] from every pick, until [limit] is reached.
    /// - Parameters:
    ///   - selected: Picks so far; extended in place.
    ///   - riding: Moments to choose from.
    ///   - gap: Seconds required between picks.
    ///   - limit: Clips wanted.
    static func fillBestFirst(_ selected: inout [PartnerMatcher.Moment], from riding: [PartnerMatcher.Moment],
                              gap: Double, limit: Int) {
        for m in riding.sorted(by: { $0.bestScore > $1.bestScore }) {
            if selected.count >= limit { return }
            if keepsGap(m, from: selected, gap: gap) { selected.append(m) }
        }
    }

    /// `true` if [moment] is at least [gap] seconds from every moment in [picks] (and isn't one of them).
    private static func keepsGap(_ moment: PartnerMatcher.Moment, from picks: [PartnerMatcher.Moment],
                                 gap: Double) -> Bool {
        let t = Double(moment.momentId)
        return !picks.contains { abs(Double($0.momentId) - t) < gap }
    }

    // MARK: - Start and finish picks

    /// Makes sure at least one selected moment falls inside [window].
    ///
    /// If none does, the best moment in the window that keeps [gap] from the other picks is added. When the reel
    /// is already full, it replaces the lowest-scoring pick outside [keep]. If no moment in the window keeps the
    /// gap, a pick sits just outside the window, so nothing changes.
    /// - Parameters:
    ///   - window: Time range (moment epochs) that needs a pick.
    ///   - selected: Current picks.
    ///   - moments: The source of the new pick.
    ///   - gap: Seconds required between picks.
    ///   - targetClips: Clips wanted.
    ///   - keep: Moment ids that must not be replaced (coverage picks, and the start pick when placing the
    ///     finish pick).
    /// - Returns: The adjusted picks.
    static func ensurePick(in window: ClosedRange<Double>,
                           selected: [PartnerMatcher.Moment],
                           moments: [PartnerMatcher.Moment],
                           gap: Double, targetClips: Int,
                           keep: Set<Int>) -> [PartnerMatcher.Moment] {
        if selected.contains(where: { window.contains(Double($0.momentId)) }) { return selected }

        var result = selected
        if result.count >= targetClips {
            let replaceable = result.enumerated().filter { !keep.contains($0.element.momentId) }
            guard let victim = replaceable.min(by: { $0.element.bestScore < $1.element.bestScore }) else {
                return selected
            }
            result.remove(at: victim.offset)
        }

        let pick = moments
            .filter { window.contains(Double($0.momentId)) }
            .sorted { $0.bestScore > $1.bestScore }
            .first { keepsGap($0, from: result, gap: gap) }
        guard let pick else { return selected }
        result.append(pick)
        return result
    }
}
