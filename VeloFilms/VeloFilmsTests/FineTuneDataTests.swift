// FineTuneDataTests.swift
// Tests for what the Fine Tune screen loads: the moments to review, Strava laps and the elevation profile.

import Foundation
import Testing
@testable import VeloFilms

@MainActor
struct FineTuneDataTests {

    // MARK: - Moments to review

    @Test func poolKeepsPicksAndTheirNeighbours() {
        let moments = (0..<100).map { Fixtures.moment(t: $0 * 5, score: 0.1) }
        let pool = FineTuneData.reviewPool(moments, recommendedIds: [250], target: 1).map(\.momentId)
        #expect(pool.contains(245) && pool.contains(250) && pool.contains(255))
    }

    @Test func poolKeepsBestMomentOfEveryFile() {
        // Clip 2 only has low scores, so the top-N alone would skip it.
        let clip1 = (0..<50).map { Fixtures.moment(t: $0 * 5, score: 0.9, clip: 1) }
        let clip2 = (50..<100).map { Fixtures.moment(t: $0 * 5, score: $0 == 70 ? 0.2 : 0.1, clip: 2) }
        let pool = FineTuneData.reviewPool(clip1 + clip2, recommendedIds: [], target: 5).map(\.momentId)
        #expect(pool.contains(350))
    }

    @Test func poolIsInTimeOrder() {
        let moments = [Fixtures.moment(t: 30, score: 0.9), Fixtures.moment(t: 10, score: 0.1),
                       Fixtures.moment(t: 20, score: 0.5)]
        let pool = FineTuneData.reviewPool(moments, recommendedIds: [], target: 5).map(\.momentId)
        #expect(pool == [10, 20, 30])
    }

    // MARK: - Laps

    @Test func parsesLapsWithAndWithoutFractions() {
        let json = """
        [{"name":"Lap 1","start_date":"2026-10-13T19:20:55Z","elapsed_time":600},
         {"name":"Lap 2","start_date":"2026-10-13T19:30:55.500Z","elapsed_time":600}]
        """
        let laps = FineTuneData.parseLaps(Data(json.utf8))
        #expect(laps.map(\.name) == ["Lap 1", "Lap 2"])
        #expect(laps[1].startEpoch - laps[0].startEpoch == 600.5)
    }

    @Test func badLapFileGivesNoLaps() {
        #expect(FineTuneData.parseLaps(Data("not json".utf8)).isEmpty)
    }

    @Test func lapOffsetIsWholeHours() {
        // Ride clock is 10 h ahead (local time stored as UTC) plus 40 s before the first lap.
        let laps = [RideLap(name: "Lap 1", startEpoch: 1_000_000)]
        #expect(FineTuneData.lapOffset(rideStartEpoch: 1_000_000 + 36_000 - 40, laps: laps) == 36_000)
    }

    @Test func noLapsNoOffset() {
        #expect(FineTuneData.lapOffset(rideStartEpoch: 1_000, laps: []) == 0)
    }

    // MARK: - Elevation

    private func point(_ t: Double, _ elevation: Double) -> FlattenRow {
        FlattenRow(gpxEpoch: t, gpxTimeUtc: "", lat: 0, lon: 0, elevation: elevation,
                   hrBpm: nil, cadenceRpm: nil, speedKmh: 20, gradientPct: 0)
    }

    @Test func profileIsScaledZeroToOne() {
        let track = [point(0, 10), point(50, 60), point(100, 35)]
        let profile = FineTuneData.elevationProfile(track, from: 0, to: 100, samples: 3)
        #expect(profile == [0, 1, 0.5])
    }

    @Test func flatRideIsAllZero() {
        let profile = FineTuneData.elevationProfile([point(0, 5), point(100, 5)], from: 0, to: 100, samples: 4)
        #expect(profile == [0, 0, 0, 0])
    }

    @Test func noTrackNoProfile() {
        #expect(FineTuneData.elevationProfile([], from: 0, to: 100, samples: 10).isEmpty)
    }
}
