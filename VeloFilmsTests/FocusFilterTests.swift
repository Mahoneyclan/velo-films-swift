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

private func makeContext(
    rideStartEpoch: Double = 1_000,
    rideDurationS: Double = 3600,
    segments: [(name: String, startEpoch: Double, endEpoch: Double)] = [],
    firstNMinutes: Double = 10,
    lastNMinutes: Double = 10,
    climbGradientPct: Double = 3.0,
    descentGradientPct: Double = 3.0,
    groupMinDetections: Int = 5
) -> FocusFilterContext {
    FocusFilterContext(
        rideStartEpoch: rideStartEpoch,
        rideDurationS: rideDurationS,
        segmentEpochRanges: segments,
        firstNMinutes: firstNMinutes,
        lastNMinutes: lastNMinutes,
        climbGradientPct: climbGradientPct,
        descentGradientPct: descentGradientPct,
        groupMinDetections: groupMinDetections
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

    // MARK: Time-based filters

    func testFirstNMinutes_includesEarlyMoments() {
        // Ride starts at epoch 1000. First 10 min = epochs 1000–1600.
        let ctx = makeContext(rideStartEpoch: 1000, rideDurationS: 3600, firstNMinutes: 10)
        let early  = makeMoment(momentId: 1300)   // 300s = 5 min into ride ✓
        let border = makeMoment(momentId: 1600)   // 600s = exactly 10 min ✓
        let late   = makeMoment(momentId: 1601)   // just over 10 min ✗
        XCTAssertTrue(FocusFilter.firstNMinutes.matches(early,  in: ctx))
        XCTAssertTrue(FocusFilter.firstNMinutes.matches(border, in: ctx))
        XCTAssertFalse(FocusFilter.firstNMinutes.matches(late,  in: ctx))
    }

    func testLastNMinutes_includesLateMoments() {
        // Ride: 1000 → 4600 (3600s). Last 10 min = epochs ≥ 4000.
        let ctx = makeContext(rideStartEpoch: 1000, rideDurationS: 3600, lastNMinutes: 10)
        let early  = makeMoment(momentId: 3999)  // just before last 10 min ✗
        let border = makeMoment(momentId: 4000)  // exactly at boundary ✓
        let veryLate = makeMoment(momentId: 4500) // deep in last 10 min ✓
        XCTAssertFalse(FocusFilter.lastNMinutes.matches(early,    in: ctx))
        XCTAssertTrue(FocusFilter.lastNMinutes.matches(border,   in: ctx))
        XCTAssertTrue(FocusFilter.lastNMinutes.matches(veryLate, in: ctx))
    }

    func testLastNMinutes_shortRide_returnsEverything() {
        // Ride is 5 min total; last 10 min → threshold clamps to 0 → all pass.
        let ctx = makeContext(rideStartEpoch: 0, rideDurationS: 300, lastNMinutes: 10)
        let m = makeMoment(momentId: 0)
        XCTAssertTrue(FocusFilter.lastNMinutes.matches(m, in: ctx))
    }

    // MARK: Terrain filters

    func testClimbs_passesAboveThreshold() {
        let ctx = makeContext(climbGradientPct: 3.0)
        XCTAssertFalse(FocusFilter.climbs.matches(makeMoment(momentId: 0, gradientPct: 2.9), in: ctx))
        XCTAssertTrue(FocusFilter.climbs.matches(makeMoment(momentId: 0, gradientPct: 3.0), in: ctx))
        XCTAssertTrue(FocusFilter.climbs.matches(makeMoment(momentId: 0, gradientPct: 8.5), in: ctx))
    }

    func testClimbs_nilGradient_fails() {
        // Missing GPS data should not pass terrain filter
        let ctx = makeContext(climbGradientPct: 3.0)
        XCTAssertFalse(FocusFilter.climbs.matches(makeMoment(momentId: 0, gradientPct: nil), in: ctx))
    }

    func testDescents_passesBelowNegativeThreshold() {
        let ctx = makeContext(descentGradientPct: 3.0)
        XCTAssertFalse(FocusFilter.descents.matches(makeMoment(momentId: 0, gradientPct: -2.9), in: ctx))
        XCTAssertTrue(FocusFilter.descents.matches(makeMoment(momentId: 0, gradientPct: -3.0), in: ctx))
        XCTAssertTrue(FocusFilter.descents.matches(makeMoment(momentId: 0, gradientPct: -9.0), in: ctx))
    }

    func testDescents_nilGradient_fails() {
        let ctx = makeContext()
        XCTAssertFalse(FocusFilter.descents.matches(makeMoment(momentId: 0, gradientPct: nil), in: ctx))
    }

    func testFlatMoment_passesNeitherTerrainFilter() {
        let ctx = makeContext(climbGradientPct: 3.0, descentGradientPct: 3.0)
        let flat = makeMoment(momentId: 0, gradientPct: 0.5)
        XCTAssertFalse(FocusFilter.climbs.matches(flat,  in: ctx))
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
        // 10 cars should not count as group riding
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

    // MARK: Segment filter

    func testSegmentFilter_matchesMomentInSegmentWindow() {
        let seg = (name: "Zipp Hill", startEpoch: 2000.0, endEpoch: 2120.0)
        let ctx = makeContext(rideStartEpoch: 1000, segments: [seg])

        let inside  = makeMoment(momentId: 2060)   // inside segment ✓
        let before  = makeMoment(momentId: 1999)   // just before ✗
        let after   = makeMoment(momentId: 2121)   // just after ✗
        let atStart = makeMoment(momentId: 2000)   // at boundary ✓

        XCTAssertTrue(FocusFilter.segment(name: "Zipp Hill").matches(inside,  in: ctx))
        XCTAssertTrue(FocusFilter.segment(name: "Zipp Hill").matches(atStart, in: ctx))
        XCTAssertFalse(FocusFilter.segment(name: "Zipp Hill").matches(before, in: ctx))
        XCTAssertFalse(FocusFilter.segment(name: "Zipp Hill").matches(after,  in: ctx))
    }

    func testSegmentFilter_wrongNameFails() {
        let seg = (name: "Zipp Hill", startEpoch: 2000.0, endEpoch: 2120.0)
        let ctx = makeContext(segments: [seg])
        let m = makeMoment(momentId: 2060)
        XCTAssertFalse(FocusFilter.segment(name: "Other Climb").matches(m, in: ctx))
    }

    func testSegmentFilter_noSegments_fails() {
        let ctx = makeContext(segments: [])
        let m = makeMoment(momentId: 2060)
        XCTAssertFalse(FocusFilter.segment(name: "Anything").matches(m, in: ctx))
    }

    func testSegmentFilter_multipleSegments_correctIsolation() {
        let segs: [(name: String, startEpoch: Double, endEpoch: Double)] = [
            ("Zipp Hill", 2000, 2120),
            ("Main Street Sprint", 3000, 3060)
        ]
        let ctx = makeContext(segments: segs)
        let mHill   = makeMoment(momentId: 2060)
        let mSprint = makeMoment(momentId: 3030)

        XCTAssertTrue(FocusFilter.segment(name: "Zipp Hill").matches(mHill,   in: ctx))
        XCTAssertFalse(FocusFilter.segment(name: "Zipp Hill").matches(mSprint, in: ctx))
        XCTAssertTrue(FocusFilter.segment(name: "Main Street Sprint").matches(mSprint, in: ctx))
        XCTAssertFalse(FocusFilter.segment(name: "Main Street Sprint").matches(mHill,  in: ctx))
    }

    // MARK: Combined filters (focus + class)
    // The view chains: focus filter → class filter. Both must pass.

    func testRiderCount_exactlyCountsPersonAndBicycle() {
        let classes = "person,car,bicycle,truck,person"
        let row = makeRow(index: "0", momentId: 0, detectedClasses: classes)
        let moment = PartnerMatcher.Moment(momentId: 0, rows: [row])
        XCTAssertEqual(FocusFilter.riderCount(for: moment), 3) // 2 person + 1 bicycle
    }

    func testFocusFilterContextBuild_computesRideBounds() {
        let moments = [
            makeMoment(momentId: 1000),
            makeMoment(momentId: 2000),
            makeMoment(momentId: 4600)
        ]
        let ctx = FocusFilterContext.build(
            moments: moments, segmentEpochRanges: [],
            firstNMinutes: 10, lastNMinutes: 10,
            climbGradientPct: 3, descentGradientPct: 3, groupMinDetections: 5
        )
        XCTAssertEqual(ctx.rideStartEpoch, 1000)
        XCTAssertEqual(ctx.rideDurationS,  3600)
    }

    func testFocusFilterContext_emptyMoments_nocrash() {
        let ctx = FocusFilterContext.build(
            moments: [], segmentEpochRanges: [],
            firstNMinutes: 10, lastNMinutes: 10,
            climbGradientPct: 3, descentGradientPct: 3, groupMinDetections: 5
        )
        XCTAssertEqual(ctx.rideStartEpoch, 0)
        XCTAssertEqual(ctx.rideDurationS,  0)
    }

    // MARK: AI selection unchanged

    func testAISelectionNotAffectedByFocusFilter() {
        // Create a pool of moments and verify ClipSelector output is identical
        // regardless of whether focus filter is conceptually applied at view level.
        let rows: [EnrichRow] = (0..<20).map { i in
            makeRow(index: "\(i)", momentId: 1000 + i * 10,
                    absTimeEpoch: Double(1000 + i * 10),
                    gradientPct: Double(i % 3) * 2.0)
        }
        let moments = PartnerMatcher.group(rows)
        let config  = ClipSelector.Config(targetClips: 5, minGap: 5)

        // Run selection twice — should produce identical results
        let selected1 = ClipSelector.select(moments: moments, config: config)
        let selected2 = ClipSelector.select(moments: moments, config: config)

        XCTAssertEqual(selected1.map(\.momentId), selected2.map(\.momentId),
                       "AI selection must be deterministic and not influenced by view-level filtering")

        // Focus filter output does not mutate the moments array
        let ctx    = makeContext(rideStartEpoch: 1000, rideDurationS: 200)
        let filtered = moments.filter { FocusFilter.climbs.matches($0, in: ctx) }
        let selectedAfterFilter = ClipSelector.select(moments: moments, config: config)
        XCTAssertEqual(selected1.map(\.momentId), selectedAfterFilter.map(\.momentId),
                       "ClipSelector receives the same moments regardless of focus filter state")
        _ = filtered // silence unused warning
    }

    // MARK: Edge cases

    func testAllFilters_emptyMoments_nocrash() {
        let ctx = makeContext()
        let allFilters: [FocusFilter] = [
            .all, .firstNMinutes, .lastNMinutes, .climbs, .descents,
            .groupRiding, .segment(name: "X")
        ]
        for filter in allFilters {
            let result = [PartnerMatcher.Moment]().filter { filter.matches($0, in: ctx) }
            XCTAssertTrue(result.isEmpty, "\(filter) should return empty for empty input")
        }
    }

    func testFirstNMinutes_veryShortRide_allPass() {
        // 30-second ride, first-10-min filter → all moments pass
        let ctx = makeContext(rideStartEpoch: 0, rideDurationS: 30, firstNMinutes: 10)
        let m1 = makeMoment(momentId: 0)
        let m2 = makeMoment(momentId: 25)
        XCTAssertTrue(FocusFilter.firstNMinutes.matches(m1, in: ctx))
        XCTAssertTrue(FocusFilter.firstNMinutes.matches(m2, in: ctx))
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
            firstNMinutes: 10, lastNMinutes: 10,
            climbGradientPct: 3.0, descentGradientPct: 3.0, groupMinDetections: 3
        )

        let filters: [FocusFilter] = [.firstNMinutes, .lastNMinutes, .climbs, .descents, .groupRiding]
        measure {
            for filter in filters {
                _ = moments.filter { filter.matches($0, in: ctx) }
            }
        }
        // Expected: well under 50ms for all 5 filters on 2160 moments
    }
}
