import Foundation

/// Central configuration — mirrors config.py.
/// All values are constants matching the Python source. User-overridable
/// settings are in GlobalSettings; these are algorithmic constants that
/// must not change without also updating the pipeline logic.
enum AppConfig {
    // MARK: - Compositor path
    static let useAVCompositor: Bool = false   // true = custom AVVideoCompositing; false = AVAssetReader+Writer

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
    static let requireGpsForSelection: Bool = false
    static let startZoneDurationM: Double = 20.0
    static let endZoneDurationM: Double = 20.0
    static let maxStartZoneClips: Int = 4
    static let maxEndZoneClips: Int = 4

    // MARK: - YOLO
    static let yoloImageSize: Int = 640
    static var yoloMinConfidence: Float { Float(GlobalSettings.shared.yoloMinConfidence) }
    static let yoloBatchSizeMac: Int = 8
    static let yoloBatchSizeiPad: Int = 4
    static let yoloDetectClasses: Set<Int> = [0, 1, 2, 11]

    enum YOLOClass: Int, CaseIterable {
        case person = 0, bicycle = 1, car = 2, stopSign = 11
    }

    // MARK: - Scoring weights — reads from GlobalSettings so user can tune them
    enum ScoreWeights {
        static var detectScore: Double  { GlobalSettings.shared.scoreWeightDetect }
        static var sceneBoost: Double   { GlobalSettings.shared.scoreWeightScene }
        static var speedKmh: Double     { GlobalSettings.shared.scoreWeightSpeed }
        static var gradient: Double     { GlobalSettings.shared.scoreWeightGradient }
        static var bboxArea: Double     { GlobalSettings.shared.scoreWeightBboxArea }
        static var segmentBoost: Double { GlobalSettings.shared.scoreWeightSegment }
        static var dualCamera: Double   { GlobalSettings.shared.scoreWeightDualCamera }
    }

    // MARK: - Candidate pool size multiplier
    static var candidateFraction: Double { GlobalSettings.shared.candidateFraction }

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

        // Layout (all at 1920×1080):
        //   [Map 390][gap 8][Gauges 972][gap 8][PiP ~550]  ← y=615–1005 (390px)
        //   [Elev 390]      [open video]       [PiP cont]  ← y=1005–1080 (75px)
        // PiP spans full 465px (map+elev) flush to bottom; open video is below gauges only.
        static let mapW: Int = 390
        static let mapGap: Int = 8
        static let elevStripH: Int = 75
        static let mapPipBottom: Int = 75      // y-from-bottom for map and gauges

        // PiP spans map height + elev height so it fills the right column to the bottom edge
        static let pipH: Int = 465             // mapH(390) + elevH(75)

        // Overlay positions
        static let mapX: Int = 0              // map anchors bottom-left
        static let mapY: String = "H-h-75"   // FFmpeg: above elev strip
        static let gaugeX: Int = 398          // mapW(390) + mapGap(8)
        static let gaugeY: String = "H-h-75"
        static let pipX: Int = 1370           // gaugeX(398) + gaugeCompositeW(972)
        static let pipY: String = "H-h"       // flush bottom — pip covers elev row too
        static let elevX: Int = 0            // below map, same left edge
        static let elevY: String = "H-h"
        static let elevW: Int = 390           // map width only
        static let elevH: Int = 75

        // HUD padding
        static let paddingX: Int = 398        // gaugeX
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
        // macOS: libx264 software encoder (matches segment output from earlier steps).
        // iOS: VideoToolbox hardware encoder (Native FFmpegKit build has no libx264).
        #if os(macOS)
        static let videoCodec = "libx264"
        #else
        static let videoCodec = "h264_videotoolbox"
        #endif
    }

    // MARK: - FFmpeg loudnorm
    static let loudnormTarget: String = "-16"
    static let loudnormTP: String = "-1.5"
    static let loudnormLRA: String = "11"

    // MARK: - Audio
    static let musicVolume: Double = 0.7
    static let rawAudioVolume: Double = 0.3

    // MARK: - Concat
    static let concatXfadeDuration: Double = 0.5

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
