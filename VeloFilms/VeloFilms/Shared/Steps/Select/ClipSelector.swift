import Foundation

/// Selects the best moments for the highlight reel.
/// Mirrors select.py: candidate pool → gap filter → zone enforcement → PR auto-include.
struct ClipSelector {

    struct Config {
        var targetClips: Int          = AppConfig.targetClips
        var candidateFraction: Double = AppConfig.candidateFraction
        var minGap: Double            = AppConfig.minGapBetweenClips
        var maxStartClips: Int        = AppConfig.maxStartZoneClips
        var maxEndClips: Int          = AppConfig.maxEndZoneClips
        var startZoneDuration: Double = AppConfig.startZoneDurationM * 60
        var endZoneDuration: Double   = AppConfig.endZoneDurationM * 60
    }

    static func select(moments: [PartnerMatcher.Moment], config: Config = Config()) -> [PartnerMatcher.Moment] {
        guard !moments.isEmpty else { return [] }

        let rideStart  = Double(moments.first!.momentId)
        let rideEnd    = Double(moments.last!.momentId)
        _ = rideEnd - rideStart
        let startZoneEnd  = rideStart + config.startZoneDuration
        let endZoneStart  = rideEnd   - config.endZoneDuration

        // 1. Candidate pool: top-K per clip, globally trimmed
        let numClips   = Set(moments.compactMap { $0.primary?.clipNum }).count
        let poolSize   = Int((Double(config.targetClips) * config.candidateFraction).rounded(.up))
        let kPerClip   = max(1, Int(ceil(Double(poolSize) / Double(max(1, numClips)))))

        var byClip: [Int: [PartnerMatcher.Moment]] = [:]
        for m in moments {
            let clip = m.primary?.clipNum ?? 0
            byClip[clip, default: []].append(m)
        }
        var candidates: [PartnerMatcher.Moment] = []
        for (_, clipMoments) in byClip {
            let top = clipMoments.sorted { $0.bestScore > $1.bestScore }.prefix(kPerClip)
            candidates.append(contentsOf: top)
        }
        if candidates.count > poolSize {
            candidates = Array(candidates.sorted { $0.bestScore > $1.bestScore }.prefix(poolSize))
        }

        // 2. Gap filter
        var selected: [PartnerMatcher.Moment] = []
        var usedWindows: Set<Int> = []

        let sortedByScore = candidates.sorted { $0.bestScore > $1.bestScore }
        for moment in sortedByScore {
            let t = Double(moment.momentId)
            let sceneBoost = moment.primary?.sceneBoost ?? 0
            let effectiveGap = sceneBoost >= AppConfig.sceneHighThreshold
                ? config.minGap * AppConfig.sceneHighGapMultiplier
                : config.minGap
            let windowIdx = Int(t / effectiveGap)
            let blocked = (windowIdx-1...windowIdx+1).contains(where: { usedWindows.contains($0) })
            if blocked { continue }
            selected.append(moment)
            usedWindows.insert(windowIdx)
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
            mids = applyGapFilter(Array(midCandidates.prefix(needed * 3)),
                                  minGap: config.minGap, limit: needed)
            selected = (starts + mids + ends).sorted { $0.momentId < $1.momentId }
        }

        return selected
    }

    // MARK: - Gap filter helper (standalone, for zone re-fill)

    private static func applyGapFilter(_ moments: [PartnerMatcher.Moment],
                                       minGap: Double, limit: Int) -> [PartnerMatcher.Moment] {
        var result: [PartnerMatcher.Moment] = []
        var usedWindows: Set<Int> = []
        for m in moments.sorted(by: { $0.bestScore > $1.bestScore }) {
            let w = Int(Double(m.momentId) / minGap)
            guard !(w-1...w+1).contains(where: { usedWindows.contains($0) }) else { continue }
            result.append(m)
            usedWindows.insert(w)
            if result.count >= limit { break }
        }
        return result
    }
}
