import Foundation

/// Central configuration — mirrors config.py.
/// All values are constants matching the Python source. User-overridable
/// settings are in GlobalSettings; these are algorithmic constants that
/// must not change without also updating the pipeline logic.
enum AppConfig {
    // MARK: - Sampling grid
    static let extractIntervalSeconds: Double = 5.0
    static let clipPreRollS: Double = 0.5
    static let clipOutLenS: Double = 3.5
    static let minGapBetweenClips: Double = 10.0
    static let gpxGridExtensionM: Double = 5.0

    // MARK: - Highlight target
    static let highlightTargetDurationM: Double = 5.0   // default; user override in GlobalSettings
    static var targetClips: Int { Int((GlobalSettings.shared.highlightTargetMinutes * 60) / clipOutLenS) }

    // MARK: - Scene detection
    static let sceneHighThreshold: Double = 0.50
    static let sceneHighGapMultiplier: Double = 0.5
    static let sceneComparisonWindowS: Double = 15.0

    // MARK: - Selection
    static let candidateFraction: Double = 2.5
    static let requireGpsForSelection: Bool = false
    static let startZoneDurationM: Double = 20.0
    static let endZoneDurationM: Double = 20.0
    static let maxStartZoneClips: Int = 4
    static let maxEndZoneClips: Int = 4

    // MARK: - YOLO
    static let yoloImageSize: Int = 640
    static let yoloMinConfidence: Float = 0.10
    static let yoloBatchSizeMac: Int = 8
    static let yoloBatchSizeiPad: Int = 4
    static let yoloDetectClasses: Set<Int> = [0, 1, 2, 3, 5, 7, 9, 11]

    enum YOLOClass: Int, CaseIterable {
        case person = 0, bicycle = 1, car = 2, motorcycle = 3
        case bus = 5, truck = 7, trafficLight = 9, stopSign = 11
    }

    // MARK: - Scoring weights (must sum to 1.0)
    enum ScoreWeights {
        static let detectScore: Double = 0.30
        static let sceneBoost: Double  = 0.10
        static let speedKmh: Double    = 0.20
        static let gradient: Double    = 0.20
        static let bboxArea: Double    = 0.05
        static let segmentBoost: Double = 0.05
        static let dualCamera: Double  = 0.10
    }

    // MARK: - Score normalisation denominators
    static let speedNormDivisor: Double = 60.0
    static let gradNormDivisor: Double = 8.0
    static let bboxNormDivisor: Double = 400_000.0

    // MARK: - Camera
    enum CameraName: String, CaseIterable, Codable {
        case fly12Sport = "Fly12Sport"
        case fly6Pro    = "Fly6Pro"

        var weight: Double { 1.0 }

        /// UTC offset string for timezone correction (Cycliq UTC bug).
        /// Cameras record local time but tag it with 'Z' — reinterpret with this offset.
        /// Reads from GlobalSettings so the user can adjust per camera in Settings.
        var timezoneIdentifier: String {
            switch self {
            case .fly12Sport: return GlobalSettings.shared.fly12SportTimezone
            case .fly6Pro:    return GlobalSettings.shared.fly6ProTimezone
            }
        }

        /// Manual sync offset (seconds) applied on top of duration-derived start time.
        /// Reads from GlobalSettings (Camera Calibration) so the user can dial it in.
        var knownOffset: Double {
            switch self {
            case .fly12Sport: return GlobalSettings.shared.fly12SportOffset
            case .fly6Pro:    return GlobalSettings.shared.fly6ProOffset
            }
        }

        static func from(filename: String) -> CameraName? {
            if filename.hasPrefix("Fly12Sport") || filename.hasPrefix("Fly12S") { return .fly12Sport }
            if filename.hasPrefix("Fly6Pro") || filename.hasPrefix("Fly6")     { return .fly6Pro }
            return nil
        }
    }

    // MARK: - GPX
    static let gpxTimeOffsetS: Double = 0.0
    static let gpxTolerance: Double = 1.0

    // MARK: - HUD geometry (all sizes in pixels at 1920×1080 output)
    enum HUD {
        static let outputW: Int = 1920
        static let outputH: Int = 1080

        // Gauge strip — 5 equal cells, each 194×194px
        static let gaugeCompositeW: Int = 972
        static let gaugeCompositeH: Int = 194
        static let gaugeCellSize: Int = 194   // each cell is square
        static let gaugeOrder: [String] = ["elev", "gradient", "speed", "hr", "cadence"]
        static let enabledGauges: [String] = ["speed", "cadence", "hr", "elev", "gradient"]

        // PiP / Map strip (bottom bar)
        static let pipH: Int = 390
        static let mapW: Int = 390
        static let mapGap: Int = 8
        static let elevStripH: Int = 75
        static let mapPipBottom: Int = 75

        // Overlay positions (x, y from top-left of 1920×1080 frame)
        static let gaugeX: Int = 0
        static let gaugeY: String = "H-h-75"     // FFmpeg expression
        static let mapX: Int = 972
        static let mapY: String = "H-h-75"
        static let pipX: Int = 1370
        static let pipY: String = "H-h-75"
        static let elevX: Int = 972
        static let elevY: String = "H-h"
        static let elevW: Int = 948              // outputW - gaugeCompositeW
        static let elevH: Int = 75

        // HUD padding (x flush-left, y = elevStripH)
        static let paddingX: Int = 0
        static let paddingY: Int = 75
    }

    // MARK: - Map
    enum Map {
        static let routeColor: (Int, Int, Int) = (40, 180, 60)
        static let routeWidth: Int = 6
        static let splashRouteWidth: Int = 24
        static let markerColor: (Int, Int, Int) = (230, 175, 0)
        static let markerRadius: Int = 18
        static let paddingPct: Double = 0.25
        static let zoomPip: Int = 15
        static let zoomSplash: Int = 12
        static let splashSize: (Int, Int) = (2560, 1440)
    }

    // MARK: - Video encoding
    enum Encoding {
        static let videoBitrate: Int = 8_000_000   // 8 Mbps H.264
        static let audioBitrate: Int = 192_000     // 192 kbps AAC
    }

    // MARK: - Audio
    static let musicVolume: Double = 0.7
    static let rawAudioVolume: Double = 0.3

    // MARK: - Segment concat
    static let highlightsPerSegment: Int = 8   // Int(30.0 / clipOutLenS)
    static let xfadeDuration: Double = 0.2
    static let fadeInOutDuration: Double = 0.3

    // MARK: - Splash
    static let bannerHeight: Int = 165         // 220 * 1080 / 1440

    // MARK: - Gauge arc drawing (PIL clockwise from 3-o'clock → CoreGraphics conversion needed)
    enum GaugeArc {
        static let arcStartDeg: Double = 150    // PIL angle
        static let arcEndDeg: Double   = 390    // PIL angle
        static let arcSpan: Double     = 240
        static let green: (Int, Int, Int, Int)  = (0, 230, 77, 255)
        static let dim:   (Int, Int, Int, Int)  = (0, 55, 22, 255)
        static let bg:    (Int, Int, Int, Int)  = (0, 0, 0, 100)
        static let white: (Int, Int, Int, Int)  = (255, 255, 255, 255)
    }

    // MARK: - Strava PR boosts
    enum StravaBoost {
        static let rank1: Double   = 1.0
        static let rank2_3: Double = 0.7
        static let any: Double     = 0.3
    }
}
