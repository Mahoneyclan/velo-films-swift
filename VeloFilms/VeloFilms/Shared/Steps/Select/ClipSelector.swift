import Foundation

/// Selects the best moments for the highlight reel.
/// Mirrors select.py: candidate pool → gap filter → zone enforcement → PR auto-include.
struct ClipSelector {

    struct Config {
        var targetClips: Int          = AppConfig.targetClips
        var candidateFraction: Double = AppConfig.candidateFraction
        var minGap: Double            = GlobalSettings.shared.minGapBetweenClips
        var maxStartClips: Int        = AppConfig.maxStartZoneClips
        var maxEndClips: Int          = AppConfig.maxEndZoneClips
        /// Pre-computed from moving time in SelectStep. Falls back to wall-clock % if 0.
        var startZoneEndEpoch: Double = 0
        var endZoneStartEpoch: Double = 0
    }

    static func select(moments: [PartnerMatcher.Moment], config: Config = Config()) -> [PartnerMatcher.Moment] {
        guard !moments.isEmpty else { return [] }

        let rideStart = Double(moments[0].momentId)
        let rideEnd   = Double(moments[moments.count - 1].momentId)

        // Use moving-time boundaries if provided by SelectStep; fall back to wall-clock %.
        let startZoneEnd: Double
        let endZoneStart: Double
        if config.startZoneEndEpoch > 0 && config.endZoneStartEpoch > 0 {
            startZoneEnd = config.startZoneEndEpoch
            endZoneStart = config.endZoneStartEpoch
        } else {
            let span = rideEnd - rideStart
            startZoneEnd = rideStart + span * AppConfig.startZonePct
            endZoneStart = rideEnd   - span * AppConfig.endZonePct
        }

        // 1. Candidate pool: top-K per clip, globally trimmed.
        // For dual-camera moments, use min(clipNum12, clipNum6) — matches Python's approach.
        // This groups both cameras' coverage of the same time period under one clip number,
        // giving higher K-per-clip and more balanced ride-wide coverage.
        func clipKey(_ m: PartnerMatcher.Moment) -> Int {
            let c12 = m.fly12Row?.clipNum
            let c6  = m.fly6Row?.clipNum
            if let a = c12, let b = c6 { return min(a, b) }
            return c12 ?? c6 ?? 0
        }
        let poolSize   = Int((Double(config.targetClips) * config.candidateFraction).rounded(.up))
        let numClips   = Set(moments.map { clipKey($0) }).count
        let kPerClip   = max(1, Int(ceil(Double(poolSize) / Double(max(1, numClips)))))

        var byClip: [Int: [PartnerMatcher.Moment]] = [:]
        for m in moments {
            byClip[clipKey(m), default: []].append(m)
        }
        var candidates: [PartnerMatcher.Moment] = []
        for (_, clipMoments) in byClip {
            let top = clipMoments.sorted { $0.bestScore > $1.bestScore }.prefix(kPerClip)
            candidates.append(contentsOf: top)
        }
        if candidates.count > poolSize {
            candidates = Array(candidates.sorted { $0.bestScore > $1.bestScore }.prefix(poolSize))
        }

        // 2. Gap filter — compare in actual time, not quantised window indices.
        // Window-index approach breaks when effectiveGap varies per moment (scene boost
        // halves it), because indices from different scales are not comparable.
        var selected: [PartnerMatcher.Moment] = []
        var usedTimes: [Double] = []

        let sortedByScore = candidates.sorted { $0.bestScore > $1.bestScore }
        for moment in sortedByScore {
            let t = Double(moment.momentId)
            let sceneBoost = moment.primary?.sceneBoost ?? 0
            let effectiveGap = sceneBoost >= AppConfig.sceneHighThreshold
                ? config.minGap * AppConfig.sceneGapReductionFactor
                : config.minGap
            if usedTimes.contains(where: { abs(t - $0) < effectiveGap }) { continue }
            selected.append(moment)
            usedTimes.append(t)
            if selected.count >= config.targetClips { break }
        }

        // 3. Zone enforcement — cap start/end zone clips
        let startCount = selected.filter { Double($0.momentId) <= startZoneEnd }.count
        let endCount   = selected.filter { Double($0.momentId) >= endZoneStart }.count

        if startCount > config.maxStartClips || endCount > config.maxEndClips {
            var starts: [PartnerMatcher.Moment] = []
            var mids:   [PartnerMatcher.Moment] = []
            var ends:   [PartnerMatcher.Moment] = []
            for m in selected {
                let t = Double(m.momentId)
                if t <= startZoneEnd       { starts.append(m) }
                else if t >= endZoneStart  { ends.append(m)   }
                else                       { mids.append(m)   }
            }
            starts = Array(starts.prefix(config.maxStartClips))
            ends   = Array(ends.prefix(config.maxEndClips))
            let needed = config.targetClips - starts.count - ends.count
            // Fill remaining slots from mid-ride candidates
            let usedIds = Set((starts + ends).map { $0.momentId })
            let midCandidates = sortedByScore.filter { m in
                let t = Double(m.momentId)
                return t > startZoneEnd && t < endZoneStart && !usedIds.contains(m.momentId)
            }
            let zoneBoundaryTimes = (starts + ends).map { Double($0.momentId) }
            mids = applyGapFilter(Array(midCandidates.prefix(needed * 3)),
                                  minGap: config.minGap, limit: needed,
                                  excludedTimes: zoneBoundaryTimes)
            selected = (starts + mids + ends).sorted { $0.momentId < $1.momentId }
        }

        return selected
    }

    // MARK: - Gap filter helper (standalone, for zone re-fill)

    /// Same actual-time gap logic as the main gap filter.
    /// [excludedTimes] pre-populates used times with zone boundary clip positions so
    /// mid-ride clips respect the gap from the nearest start/end zone clip.
    private static func applyGapFilter(_ moments: [PartnerMatcher.Moment],
                                       minGap: Double, limit: Int,
                                       excludedTimes: [Double] = []) -> [PartnerMatcher.Moment] {
        var result: [PartnerMatcher.Moment] = []
        var usedTimes: [Double] = excludedTimes
        for m in moments.sorted(by: { $0.bestScore > $1.bestScore }) {
            let t = Double(m.momentId)
            if usedTimes.contains(where: { abs(t - $0) < minGap }) { continue }
            result.append(m)
            usedTimes.append(t)
            if result.count >= limit { break }
        }
        return result
    }
}
