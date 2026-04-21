import XCTest
@testable import VeloFilms

final class GPXParserTests: XCTestCase {

    func testHaversineDistance() {
        // Sydney Opera House → Harbour Bridge — ~1.4km
        let dist = haversineM(-33.8568, 151.2153, -33.8523, 151.2108)
        XCTAssertEqual(dist, 670, accuracy: 50, "Haversine should be ~670m")
    }

    func testCycliqUTCFix() {
        // Fly12Sport UTC+10: a raw timestamp of 2025-04-20T08:00:00Z (parsed as UTC)
        // should be corrected to 2025-04-19T22:00:00Z (real UTC, 10 hours behind)
        let rawDate = Date(timeIntervalSince1970: 1_745_136_000)  // 2025-04-20T08:00:00Z
        let corrected = FrameSampler.applyCycliqUTCFix(rawDate: rawDate, camera: .fly12Sport)
        let expected = rawDate.timeIntervalSince1970 - 36_000   // -10h
        XCTAssertEqual(corrected, expected, accuracy: 1)
    }

    func testScoreCalculator() {
        let input = ScoreCalculator.Input(
            detectScore: 0.8,
            sceneBoost: 0.6,
            speedKmh: 30.0,
            gradientPct: 4.0,
            bboxArea: 200_000,
            segmentBoost: 0.7,
            camera: .fly12Sport
        )
        let score = ScoreCalculator.composite(input)
        // 0.8*0.30 + 0.6*0.10 + 0.5*0.20 + 0.5*0.20 + 0.5*0.05 + 0.7*0.05 = 0.24+0.06+0.10+0.10+0.025+0.035 = 0.56
        XCTAssertEqual(score, 0.56, accuracy: 0.01)
    }

    func testTargetClips() {
        XCTAssertEqual(AppConfig.targetClips, 85)
    }

    func testHUDGeometry() {
        XCTAssertEqual(AppConfig.HUD.elevW, AppConfig.HUD.outputW - AppConfig.HUD.gaugeCompositeW)
        XCTAssertEqual(AppConfig.HUD.gaugeCompositeW, AppConfig.HUD.gaugeCellSize * 5)
    }
}
