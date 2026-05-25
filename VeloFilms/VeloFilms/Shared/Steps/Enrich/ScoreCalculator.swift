import Foundation

/// Computes composite and weighted scores for a frame.
/// Mirrors score_calculator.py exactly — weight constants from AppConfig.ScoreWeights.
enum ScoreCalculator {

    struct Input {
        var detectScore: Double
        var sceneBoost: Double
        var speedKmh: Double
        var gradientPct: Double
        var segmentBoost: Double
        var camera: AppConfig.CameraName
    }

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

    /// composite × camera weight.
    static func weighted(_ composite: Double, camera: AppConfig.CameraName) -> Double {
        composite * camera.weight
    }
}
