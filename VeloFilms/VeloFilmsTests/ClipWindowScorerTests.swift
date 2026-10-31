// ClipWindowScorerTests.swift
// Tests for whole-clip scoring: choosing the clip start, staying inside the video, ignoring one stray frame,
// scoring objects that come closer, frame spacing for other clip lengths, and speed averaged over the clip.

import Testing
@testable import VeloFilms

@MainActor
struct ClipWindowScorerTests {

    private typealias Frame = ClipWindowScorer.Frame

    /// Frames one second apart from −2 s to +5 s, the default sampling.
    private func frames(detect: (Double) -> Double = { _ in 0.2 },
                        presence: (Double) -> Double = { _ in 0.1 }) -> [Frame] {
        stride(from: -2.0, through: 5.0, by: 1).map { Frame(offset: $0, detectScore: detect($0), presence: presence($0)) }
    }

    private func best(_ frames: [Frame], range: ClosedRange<Double> = -2...2) -> ClipWindowScorer.Result? {
        ClipWindowScorer.best(frames: frames, clipLength: 3.5, shiftRange: range, detectWeight: 0.3, actionWeight: 0.2)
    }

    @Test func steadySceneKeepsTheClipWhereItIs() throws {
        let result = try #require(best(frames()))
        #expect(result.shift == 0)
        #expect(result.actionScore == 0)
    }

    @Test func clipSlidesToTheAction() throws {
        // A rider in view only from 3 s to 5 s: the clip should move later to include it.
        let result = try #require(best(frames(detect: { $0 >= 3 ? 0.9 : 0.1 })))
        #expect(result.shift > 0)
        #expect(result.thumbnailOffset >= 3)
    }

    @Test func clipNeverLeavesTheAllowedRange() throws {
        // The action is late, but the video ends: no shift beyond +0.5 s is allowed.
        let result = try #require(best(frames(detect: { $0 >= 4 ? 0.9 : 0.1 }), range: -2...0.5))
        #expect(result.shift <= 0.5)
    }

    @Test func oneStrayFrameDoesNotCarryTheClip() throws {
        let stray = try #require(ClipWindowScorer.score(
            frames: frames(detect: { $0 == 1 ? 0.9 : 0 }), shift: 0, clipLength: 3.5))
        let steady = try #require(ClipWindowScorer.score(
            frames: frames(detect: { _ in 0.6 }), shift: 0, clipLength: 3.5))
        #expect(stray.detectScore < steady.detectScore)
    }

    @Test(arguments: [
        // (presence at clip start, presence at clip end, expect action?)
        (0.0, 0.30, true),    // rider or car comes up close
        (0.30, 0.0, true),    // rider pulls away
        (0.30, 0.33, false),  // steady group ride: YOLO jitter only
    ])
    func actionScoresObjectsComingCloserOrPullingAway(from: Double, to: Double, expectAction: Bool) throws {
        let result = try #require(ClipWindowScorer.score(
            frames: frames(presence: { $0 <= 0 ? from : to }), shift: 0, clipLength: 3.5))
        #expect((result.actionScore > 0) == expectAction)
    }

    @Test func noFramesInsideTheClipGivesNoResult() {
        #expect(best([Frame(offset: 9, detectScore: 1, presence: 1)]) == nil)
    }

    @Test(arguments: [(3.5, 8), (10.0, 9)])
    func frameCountStaysBoundedForAnyClipLength(clipLength: Double, expected: Int) {
        let offsets = ClipWindowScorer.sampleOffsets(clipLength: clipLength, maxShift: 2)
        #expect(offsets.count == expected)
        #expect(offsets.first == -2)
        #expect((offsets.last ?? 0) <= clipLength + 2)
    }

    @Test func speedAndGradientAreAveragedOverTheClip() throws {
        let flatten = (0..<10).map { i in
            FlattenRow(gpxEpoch: Double(i), gpxTimeUtc: "", lat: 0, lon: 0, elevation: 0, hrBpm: nil, cadenceRpm: nil,
                       speedKmh: Double(i * 10), gradientPct: Double(i))
        }
        let point = try #require(GPSEnricher(flattenRows: flatten).enrich(epoch: 2, over: 2...4))
        #expect(point.speedKmh == 30)
        #expect(point.gradientPct == 3)
        #expect(point.epoch == 2)
    }
}
