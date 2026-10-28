// ClipSelectorTests.swift
// Tests for clip selection: spacing that scales with the ride, ride-wide coverage, no picks while stopped, and the
// start and finish picks.

import Testing
@testable import VeloFilms

@MainActor
struct ClipSelectorTests {

    /// A ride of `count` moments every 5 s from t = 0, scored by `score`.
    private func ride(_ count: Int, speed: Double? = 25, score: (Int) -> Double = { _ in 0.5 }) -> [PartnerMatcher.Moment] {
        (0..<count).map { i in Fixtures.moment(t: i * 5, score: score(i), speed: speed) }
    }

    private func config(target: Int, minGap: Double = 30, edge: Double = 300) -> ClipSelector.Config {
        var c = ClipSelector.Config()
        c.targetClips = target
        c.minGap = minGap
        c.edgeWindow = edge
        return c
    }

    @Test func noTargetGivesNoPicks() {
        #expect(ClipSelector.select(moments: ride(100), config: config(target: 0)).isEmpty)
    }

    @Test func neverPicksMoreThanTarget() {
        let picks = ClipSelector.select(moments: ride(2000), config: config(target: 20))
        #expect(picks.count == 20)
    }

    @Test func gapScalesWithRideLength() {
        // 2000 moments × 5 s = 10,000 s of riding for 20 clips: average 500 s apart, so the gap is 250 s.
        let gap = ClipSelector.spacing(for: ride(2000), config: config(target: 20))
        #expect(gap == 250)
    }

    @Test func gapNeverBelowUserMinimum() {
        let gap = ClipSelector.spacing(for: ride(100), config: config(target: 50, minGap: 30))
        #expect(gap == 30)
    }

    @Test func picksKeepTheGap() {
        // The best moments all sit together at the start; spacing must still hold.
        let moments = ride(2000) { i in i < 100 ? 1.0 : 0.1 }
        let picks = ClipSelector.select(moments: moments, config: config(target: 20)).map(\.momentId).sorted()
        let gaps = zip(picks, picks.dropFirst()).map { $1 - $0 }
        #expect(gaps.allSatisfy { $0 >= 250 })
    }

    @Test func wholeRideIsCovered() {
        // Without coverage, every pick would come from the high-scoring first tenth of the ride.
        let moments = ride(2000) { i in i < 200 ? 1.0 : 0.1 }
        let picks = ClipSelector.select(moments: moments, config: config(target: 30)).map(\.momentId).sorted()
        let gaps = zip([0] + picks, picks + [9995]).map { $1 - $0 }
        // 30 clips → 10 stretches of 1,000 s each; a stretch never goes without a pick.
        #expect(gaps.max() ?? .max < 2000)
    }

    @Test func stoppedMomentsAreIgnored() {
        var moments = ride(400)
        // A café stop with the best scores of the ride.
        moments += (400..<500).map { i in Fixtures.moment(t: i * 5, score: 1.0, speed: 0) }
        let picks = ClipSelector.select(moments: moments, config: config(target: 10))
        #expect(picks.allSatisfy { $0.momentId < 2000 })
    }

    @Test func rideWithoutGPSStillGetsPicks() {
        let picks = ClipSelector.select(moments: ride(400, speed: nil), config: config(target: 10))
        #expect(picks.count == 10)
    }

    @Test func rideFullyStoppedStillGetsPicks() {
        let picks = ClipSelector.select(moments: ride(400, speed: 0), config: config(target: 10))
        #expect(picks.count == 10)
    }

    @Test func opensAtStartAndEndsAtFinish() {
        // Best moments in the middle of a 10,000 s ride.
        let moments = ride(2000) { i in (900..<1100).contains(i) ? 1.0 : 0.1 }
        let picks = ClipSelector.select(moments: moments, config: config(target: 20)).map(\.momentId)
        #expect(picks.contains { $0 <= 300 })
        #expect(picks.contains { $0 >= 9995 - 300 })
    }

    @Test func edgePickNeverReplacesAProtectedPick() {
        let selected = [Fixtures.moment(t: 5000, score: 0.1), Fixtures.moment(t: 6000, score: 0.9)]
        let pool = [Fixtures.moment(t: 100, score: 0.5)] + selected
        let result = ClipSelector.ensurePick(in: 0...300, selected: selected, moments: pool, gap: 30,
                                             targetClips: 2, keep: [5000])
        #expect(Set(result.map(\.momentId)) == [100, 5000])
    }

    @Test func edgePickLeavesPicksAloneWhenWindowAlreadyCovered() {
        let selected = [Fixtures.moment(t: 200), Fixtures.moment(t: 5000)]
        let result = ClipSelector.ensurePick(in: 0...300, selected: selected, moments: selected, gap: 30,
                                             targetClips: 2, keep: [])
        #expect(result.map(\.momentId) == [200, 5000])
    }
}
