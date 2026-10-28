// Fixtures.swift
// Builders for the rows the selection and Fine Tune tests need, with sensible defaults so each test states only
// what matters to it.

import Foundation
@testable import VeloFilms

/// Builds test rows.
enum Fixtures {
    /// Front camera name as recorded in the data.
    static let front = AppConfig.CameraName.fly12Sport.rawValue
    /// Rear camera name as recorded in the data.
    static let rear = AppConfig.CameraName.fly6Pro.rawValue

    /// An enriched row for one camera frame at `t` seconds.
    static func enrich(t: Int, camera: String = front, score: Double = 0.5, speed: Double? = 25,
                       gradient: Double? = 0, classes: String = "", clip: Int = 1) -> EnrichRow {
        EnrichRow(
            index: "\(camera)_\(clip)_\(t)", camera: camera, clipNum: clip, frameNumber: 0,
            videoPath: "/dev/null",
            absTimeEpoch: Double(t), absTimeIso: "", sessionTsS: 0,
            clipStartEpoch: 0, adjustedStartTime: "", durationS: 3.5,
            source: "test", fps: 30,
            detectScore: 0, numDetections: 0, bboxArea: 0,
            detectedClasses: classes, objectDetected: !classes.isEmpty,
            sceneBoost: 0,
            gpxEpoch: Double(t), gpxTimeUtc: nil,
            lat: nil, lon: nil, elevation: nil,
            hrBpm: nil, cadenceRpm: nil,
            speedKmh: speed, gradientPct: gradient,
            scoreComposite: score, scoreWeighted: score, segmentBoost: 0,
            momentId: t)
    }

    /// A moment filmed by the front camera only.
    static func moment(t: Int, score: Double = 0.5, speed: Double? = 25, gradient: Double? = 0,
                       classes: String = "", clip: Int = 1) -> PartnerMatcher.Moment {
        PartnerMatcher.Moment(momentId: t, rows: [enrich(t: t, score: score, speed: speed, gradient: gradient,
                                                         classes: classes, clip: clip)])
    }

    /// A select row (front and rear frames are separate rows).
    static func select(t: Int, camera: String = front, score: Double = 0.5, recommended: Bool = false,
                       pr: Bool = false, segment: String? = nil, override: Bool? = nil,
                       gradient: Double? = 0, classes: String = "") -> SelectRow {
        SelectRow(base: enrich(t: t, camera: camera, score: score, gradient: gradient, classes: classes),
                  recommended: recommended, stravaPR: pr, isSingleCamera: false, paired: true,
                  segmentName: segment, manualOverride: override)
    }

    /// Thresholds as the app's defaults would give them.
    static func context(prs: Set<Int> = []) -> FocusFilterContext {
        FocusFilterContext(climbGradientPct: 4, descentGradientPct: -4, groupMinDetections: 3,
                           stravaPRMomentIds: prs)
    }
}
