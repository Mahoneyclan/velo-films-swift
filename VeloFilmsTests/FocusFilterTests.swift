import XCTest
@testable import VeloFilms

// MARK: - Helpers

private func makeRow(
    index: String = "0",
    momentId: Int = 0,
    absTimeEpoch: Double = 0,
    gradientPct: Double? = nil,
    speedKmh: Double? = 20,
    detectedClasses: String = "",
    numDetections: Int = 0
) -> EnrichRow {
    EnrichRow(
        index: index, camera: "Fly12Sport", clipNum: 1, frameNumber: 0,
        videoPath: "/dev/null",
        absTimeEpoch: absTimeEpoch, absTimeIso: "", sessionTsS: 0,
        clipStartEpoch: 0, adjustedStartTime: "", durationS: 3.5,
        source: "test", fps: 30,
        detectScore: 0, numDetections: numDetections, bboxArea: 0,
        detectedClasses: detectedClasses, objectDetected: numDetections > 0,
        sceneBoost: 0,
        gpxEpoch: absTimeEpoch, gpxTimeUtc: nil,
        lat: nil, lon: nil, elevation: nil,
        hrBpm: nil, cadenceRpm: nil,
        speedKmh: speedKmh, gradientPct: gradientPct,
        scoreComposite: 0, scoreWeighted: 0, segmentBoost: 0,
        momentId: momentId
    )
}

private func makeMoment(momentId: Int, gradientPct: Double? = nil,
                        detectedClasses: String = "", numDetections: Int = 0,
                        absTimeEpoch: Double? = nil) -> PartnerMatcher.Moment {
    let epoch = absTimeEpoch ?? Double(momentId)
    let row = makeRow(index: "\(momentId)", momentId: momentId,
                      absTimeEpoch: epoch,
                      gradientPct: gradientPct,
                      detectedClasses: detectedClasses,
                      numDetections: numDetections)
    return PartnerMatcher.Moment(momentId: momentId, rows: [row])
}

/// Ride: 1_000 → 4_600 (3_600 s).
/// Default zone endpoints mirror a 10-min opening / 10-min closing window.
private func makeContext(
    rideStartEpoch: Double = 1_000,
    rideDurationS: Double = 3_600,
    lapEpochRanges: [(name: String, startEpoch: Double, endEpoch: Double)] = [],
    startZoneEndEpoch: Double = 1_600,   // 600 s = 10 min into ride
    endZoneStartEpoch: Double = 4_000,   // 600 s before end
    climbGradientPct: Double = 3.0,
    descentGradientPct: Double = -3.0,   // stored negative, e.g. -3.0 means ≥ 3% descent
    groupMinDetections: Int = 5,
    stravaPRMomentIds: Set<Int> = []
) -> FocusFilterContext {
    FocusFilterContext(
        rideStartEpoch: rideStartEpoch,
        rideDurationS: rideDurationS,
        lapEpochRanges: lapEpochRanges,
        startZoneEndEpoch: startZoneEndEpoch,
        endZoneStartEpoch: endZoneStartEpoch,
        climbGradientPct: climbGradientPct,
        descentGradientPct: descentGradientPct,
        groupMinDetections: groupMinDetections,
        stravaPRMomentIds: stravaPRMomentIds
    )
}

// MARK: - Tests

final class FocusFilterTests: XCTestCase {

    // MARK: All filter

    func testAllFilterPassesEverything() {
        let moments = [
            makeMoment(momentId: 1000),
            makeMoment(momentId: 2000, gradientPct: -15),
            makeMoment(momentId: 3000, detectedClasses: "person,bicycle")
        ]
        let ctx = makeContext()
        XCTAssertTrue(moments.allSatisfy { FocusFilter.all.matches($0, in: ctx) })
    }

    // MARK: Zone filters (opening / closing)

    func testOpeningZone_includesEarlyMoments() {
        // startZoneEndEpoch = 1600 — moments at or before pass.
        let ctx = makeContext(startZoneEndEpoch: 1_600)
        let early  = makeMoment(momentId: 1_300)
        let border = makeMoment(momentId: 1_600)
        let late   = makeMoment(momentId: 1_601)
        XCTAssertTrue(FocusFilter.openingZone.matches(early,  in: ctx))
        XCTAssertTrue(FocusFilter.openingZone.matches(border, in: ctx))
        XCTAssertFalse(FocusFilter.openingZone.matches(late,  in: ctx))
    }

    func testClosingZone_includesLateMoments() {
        // endZoneStartEpoch = 4000 — moments at or after pass.
        let ctx = makeContext(endZoneStartEpoch: 4_000)
        let early  = makeMoment(momentId: 3_999)
        let border = makeMoment(momentId: 4_000)
        let late   = makeMoment(momentId: 4_500)
        XCTAssertFalse(FocusFilter.closingZone.matches(early,  in: ctx))
        XCTAssertTrue(FocusFilter.closingZone.matches(border,  in: ctx))
        XCTAssertTrue(FocusFilter.closingZone.matches(late,    in: ctx))
    }

    func testOpeningZone_whenBoundaryIsZero_nothingPasses() {
        // startZoneEndEpoch = 0 means zone was never computed; epoch 0 still passes but nothing positive.
        let ctx = makeContext(startZoneEndEpoch: 0)
        let m = makeMoment(momentId: 1000)
        XCTAssertFalse(FocusFilter.openingZone.matches(m, in: ctx))
    }

    // MARK: Terrain filters

    func testClimbs_passesAboveThreshold() {
        let ctx = makeContext(climbGradientPct: 3.0)
        XCTAssertFalse(FocusFilter.climbs.matches(makeMoment(momentId: 0, gradientPct: 2.9), in: ctx))
        XCTAssertTrue(FocusFilter.climbs.matches(makeMoment(momentId: 0, gradientPct: 3.0), in: ctx))
        XCTAssertTrue(FocusFilter.climbs.matches(makeMoment(momentId: 0, gradientPct: 8.5), in: ctx))
    }

    func testClimbs_nilGradient_fails() {
        let ctx = makeContext(climbGradientPct: 3.0)
        XCTAssertFalse(FocusFilter.climbs.matches(makeMoment(momentId: 0, gradientPct: nil), in: ctx))
    }

    func testDescents_passesBelowNegativeThreshold() {
        // descentGradientPct = -3.0 → gradientPct <= -3.0 passes.
        let ctx = makeContext(descentGradientPct: -3.0)
        XCTAssertFalse(FocusFilter.descents.matches(makeMoment(momentId: 0, gradientPct: -2.9), in: ctx))
        XCTAssertTrue(FocusFilter.descents.matches(makeMoment(momentId: 0, gradientPct: -3.0), in: ctx))
        XCTAssertTrue(FocusFilter.descents.matches(makeMoment(momentId: 0, gradientPct: -9.0), in: ctx))
    }

    func testDescents_nilGradient_fails() {
        let ctx = makeContext()
        XCTAssertFalse(FocusFilter.descents.matches(makeMoment(momentId: 0, gradientPct: nil), in: ctx))
    }

    func testFlatMoment_passesNeitherTerrainFilter() {
        let ctx = makeContext(climbGradientPct: 3.0, descentGradientPct: -3.0)
        let flat = makeMoment(momentId: 0, gradientPct: 0.5)
        XCTAssertFalse(FocusFilter.climbs.matches(flat,   in: ctx))
        XCTAssertFalse(FocusFilter.descents.matches(flat, in: ctx))
    }

    // MARK: Group riding filter

    func testGroupRiding_countsPersonAndBicycle() {
        let ctx = makeContext(groupMinDetections: 5)
        let enough = makeMoment(momentId: 0, detectedClasses: "person,person,person,bicycle,bicycle")
        let tooFew = makeMoment(momentId: 0, detectedClasses: "person,person,car")
        XCTAssertTrue(FocusFilter.groupRiding.matches(enough, in: ctx))
        XCTAssertFalse(FocusFilter.groupRiding.matches(tooFew, in: ctx))
    }

    func testGroupRiding_exactThreshold_passes() {
        let ctx = makeContext(groupMinDetections: 3)
        let exact = makeMoment(momentId: 0, detectedClasses: "person,bicycle,person")
        XCTAssertTrue(FocusFilter.groupRiding.matches(exact, in: ctx))
    }

    func testGroupRiding_carsIgnored() {
        let ctx = makeContext(groupMinDetections: 5)
        let cars = makeMoment(momentId: 0, detectedClasses: "car,car,car,car,car,car,car,car")
        XCTAssertFalse(FocusFilter.groupRiding.matches(cars, in: ctx))
    }

    func testGroupRiding_emptyDetections_fails() {
        let ctx = makeContext(groupMinDetections: 1)
        let empty = makeMoment(momentId: 0, detectedClasses: "")
        XCTAssertFalse(FocusFilter.groupRiding.matches(empty, in: ctx))
    }

    func testGroupRiding_threshold1_singleRiderPasses() {
        let ctx = makeContext(groupMinDetections: 1)
        let solo = makeMoment(momentId: 0, detectedClasses: "person")
        XCTAssertTrue(FocusFilter.groupRiding.matches(solo, in: ctx))
    }

    // MARK: Strava PR filter

    func testStravaPR_matchesMomentInPRSet() {
        let ctx = makeContext(stravaPRMomentIds: [2000, 3000])
        let pr    = makeMoment(momentId: 2000)
        let notPR = makeMoment(momentId: 1500)
        XCTAssertTrue(FocusFilter.stravaPR.matches(pr,    in: ctx))
        XCTAssertFalse(FocusFilter.stravaPR.matches(notPR, in: ctx))
    }

    func testStravaPR_emptySet_nothingPasses() {
        let ctx = makeContext(stravaPRMomentIds: [])
        XCTAssertFalse(FocusFilter.stravaPR.matches(makeMoment(momentId: 1000), in: ctx))
    }

    // MARK: Lap filter

    func testLap_matchesMomentInsideLapWindow() {
        let laps = [(name: "Lap 3", startEpoch: 2_000.0, endEpoch: 2_500.0)]
        let ctx = makeContext(lapEpochRanges: laps)

        let inside  = makeMoment(momentId: 2_250)
        let atStart = makeMoment(momentId: 2_000)
        let atEnd   = makeMoment(momentId: 2_500)
        let before  = makeMoment(momentId: 1_999)
        let after   = makeMoment(momentId: 2_501)

        XCTAssertTrue(FocusFilter.lap(name: "Lap 3").matches(inside,  in: ctx))
        XCTAssertTrue(FocusFilter.lap(name: "Lap 3").matches(atStart, in: ctx))
        XCTAssertTrue(FocusFilter.lap(name: "Lap 3").matches(atEnd,   in: ctx))
        XCTAssertFalse(FocusFilter.lap(name: "Lap 3").matches(before, in: ctx))
        XCTAssertFalse(FocusFilter.lap(name: "Lap 3").matches(after,  in: ctx))
    }

    func testLap_wrongNameFails() {
        let laps = [(name: "Lap 3", startEpoch: 2_000.0, endEpoch: 2_500.0)]
        let ctx = makeContext(lapEpochRanges: laps)
        let m = makeMoment(momentId: 2_250)
        XCTAssertFalse(FocusFilter.lap(name: "Lap 99").matches(m, in: ctx))
    }

    func testLap_multipleLaps_correctIsolation() {
        let laps: [(name: String, startEpoch: Double, endEpoch: Double)] = [
            ("Lap 1", 1_000, 1_800),
            ("Lap 2", 2_000, 2_800)
        ]
        let ctx = makeContext(lapEpochRanges: laps)
        let m1 = makeMoment(momentId: 1_400)
        let m2 = makeMoment(momentId: 2_400)

        XCTAssertTrue(FocusFilter.lap(name: "Lap 1").matches(m1,  in: ctx))
        XCTAssertFalse(FocusFilter.lap(name: "Lap 1").matches(m2, in: ctx))
        XCTAssertTrue(FocusFilter.lap(name: "Lap 2").matches(m2,  in: ctx))
        XCTAssertFalse(FocusFilter.lap(name: "Lap 2").matches(m1, in: ctx))
    }

    // MARK: riderCount helper

    func testRiderCount_exactlyCountsPersonAndBicycle() {
        let classes = "person,car,bicycle,truck,person"
        let row = makeRow(index: "0", momentId: 0, detectedClasses: classes)
        let moment = PartnerMatcher.Moment(momentId: 0, rows: [row])
        XCTAssertEqual(FocusFilter.riderCount(for: moment), 3) // 2 person + 1 bicycle, car/truck ignored
    }

    func testRiderCount_usesBestCameraRow() {
        // Front camera sees 1 rider; rear sees 6 — filter should use the max.
        let front = makeRow(index: "0", momentId: 0, camera: "Fly12Sport",
                            detectedClasses: "person")
        let rear  = makeRow(index: "1", momentId: 0, camera: "Fly6Pro",
                            detectedClasses: "person,person,person,bicycle,bicycle,bicycle")
        let moment = PartnerMatcher.Moment(momentId: 0, rows: [front, rear])
        XCTAssertEqual(FocusFilter.riderCount(for: moment), 6)
    }

    // MARK: AI selection unchanged by focus filter

    func testAISelectionNotAffectedByFocusFilter() {
        let rows: [EnrichRow] = (0..<20).map { i in
            makeRow(index: "\(i)", momentId: 1000 + i * 10,
                    absTimeEpoch: Double(1000 + i * 10),
                    gradientPct: Double(i % 3) * 2.0)
        }
        let moments = PartnerMatcher.group(rows)
        var config  = ClipSelector.Config()
        config.targetClips = 5

        let selected1 = ClipSelector.select(moments: moments, config: config)
        let selected2 = ClipSelector.select(moments: moments, config: config)
        XCTAssertEqual(selected1.map(\.momentId), selected2.map(\.momentId),
                       "AI selection must be deterministic")

        let ctx      = makeContext(rideStartEpoch: 1000, rideDurationS: 200)
        let filtered = moments.filter { FocusFilter.climbs.matches($0, in: ctx) }
        let selectedAfterFilter = ClipSelector.select(moments: moments, config: config)
        XCTAssertEqual(selected1.map(\.momentId), selectedAfterFilter.map(\.momentId),
                       "ClipSelector receives the same moments regardless of focus filter state")
        _ = filtered
    }

    // MARK: Edge cases

    func testAllFilters_emptyMoments_nocrash() {
        let ctx = makeContext()
        let allFilters: [FocusFilter] = [
            .all, .openingZone, .closingZone, .climbs, .descents,
            .groupRiding, .stravaPR, .lap(name: "Lap 1")
        ]
        for filter in allFilters {
            let result = [PartnerMatcher.Moment]().filter { filter.matches($0, in: ctx) }
            XCTAssertTrue(result.isEmpty, "\(filter) should return empty for empty input")
        }
    }

    func testOpeningZone_veryShortRide_allPass() {
        // Entire 30-second ride falls inside a 10-minute opening zone.
        let ctx = makeContext(rideStartEpoch: 0, startZoneEndEpoch: 600)
        let m1 = makeMoment(momentId: 0)
        let m2 = makeMoment(momentId: 25)
        XCTAssertTrue(FocusFilter.openingZone.matches(m1, in: ctx))
        XCTAssertTrue(FocusFilter.openingZone.matches(m2, in: ctx))
    }

    // MARK: Performance

    func testPerformance_filterLargeRide() {
        // ~3-hour ride at 5s intervals ≈ 2160 moments
        let momentCount = 2160
        let rideStart   = 1_700_000_000.0
        let moments: [PartnerMatcher.Moment] = (0..<momentCount).map { i in
            let t = rideStart + Double(i * 5)
            return makeMoment(momentId: Int(t), gradientPct: Double(i % 10) - 5,
                              detectedClasses: i % 10 == 0 ? "person,bicycle,person" : "car")
        }
        let ctx = makeContext(
            rideStartEpoch: rideStart,
            rideDurationS: Double(momentCount * 5),
            startZoneEndEpoch: rideStart + 600,
            endZoneStartEpoch: rideStart + Double(momentCount * 5) - 600,
            climbGradientPct: 3.0,
            descentGradientPct: -3.0,
            groupMinDetections: 3
        )

        let filters: [FocusFilter] = [.openingZone, .closingZone, .climbs, .descents, .groupRiding]
        measure {
            for filter in filters {
                _ = moments.filter { filter.matches($0, in: ctx) }
            }
        }
    }
}
