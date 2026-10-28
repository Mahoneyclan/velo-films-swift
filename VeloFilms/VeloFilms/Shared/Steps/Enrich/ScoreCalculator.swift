// ScoreCalculator.swift
// The scoring formula for one grid point.

import Foundation

/// Computes composite and weighted scores for a frame.
/// Same formula as `score_calculator.py` in the original Python app; the weights are user settings read through
/// `AppConfig.ScoreWeights`.
enum ScoreCalculator {

    /// The measurements for one frame.
    struct Input {
        /// YOLO detection score, 0–1.
        var detectScore: Double
        /// Scene-change score, 0–1.
        var sceneBoost: Double
        /// Speed in km/h.
        var speedKmh: Double
        /// Gradient in percent.
        var gradientPct: Double
        /// Strava segment score, 0–1.
        var segmentBoost: Double
        /// The camera; not used by `composite`.
        var camera: AppConfig.CameraName
    }

    /// Weighted sum of the five component scores.
    ///
    /// Speed and gradient are normalised to 0–1 (`AppConfig.speedNormDivisor`, `gradNormDivisor`). Gradient
    /// counts only when moving (≥ 1 km/h), so GPS elevation noise while stopped doesn't score. Climbs and
    /// descents score the same. The weights aren't normalised, so the maximum equals their sum.
    /// - Parameter input: The frame's measurements.
    /// - Returns: The composite score.
    static func composite(_ input: Input) -> Double {
        let speedNorm = min(1.0, input.speedKmh / AppConfig.speedNormDivisor)
        let moving    = input.speedKmh >= 1.0
        let gradNorm  = moving ? min(1.0, abs(input.gradientPct) / AppConfig.gradNormDivisor) : 0.0

        let w = AppConfig.ScoreWeights.self
        return input.detectScore  * w.detectScore
             + input.sceneBoost   * w.sceneBoost
             + speedNorm          * w.speedKmh
             + gradNorm           * w.gradient
             + input.segmentBoost * w.segmentBoost
    }

    /// The composite multiplied by the camera's weight (currently 1.0 for both cameras).
    /// - Parameters:
    ///   - composite: From `composite(_:)`.
    ///   - camera: The camera that filmed the frame.
    /// - Returns: The weighted score.
    static func weighted(_ composite: Double, camera: AppConfig.CameraName) -> Double {
        composite * camera.weight
    }
}
