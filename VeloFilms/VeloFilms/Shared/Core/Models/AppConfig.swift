// AppConfig.swift
// Pipeline constants and pass-throughs to user settings. Read by every pipeline step and renderer.

import Foundation

/// Central configuration for the pipeline and renderers.
///
/// `static let` values are fixed algorithm constants that must not change without also updating the pipeline
/// logic. `static var` values are pass-throughs to `GlobalSettings`, so callers have one place to read from
/// whether a value is fixed or user-adjustable. Ported from `config.py` in the original Python app.
/// Several constants are not currently referenced (marked "Not currently used").
enum AppConfig {
    // MARK: - Compositor path
    /// Choice of iOS render path: `true` = custom AVVideoCompositing, `false` = AVAssetReader+Writer.
    /// Not currently used.
    static let useAVCompositor: Bool = false

    // MARK: - Sampling grid
    /// Default seconds between sample points on the ride timeline (user can override in Settings).
    static let extractIntervalSeconds: Double = 5.0
    /// Seconds kept before each selected moment (user setting).
    static var clipPreRollS: Double { GlobalSettings.shared.clipPreRollS }
    /// Length of each output clip in seconds (user setting).
    static var clipOutLenS: Double  { GlobalSettings.shared.clipOutLenS }
    /// Default minimum seconds between selected clips (user can override). 30 s keeps neighbouring clips from
    /// showing the same stretch of road; long rides space clips further apart (see `selectionSpacingFraction`).
    static let minGapBetweenClips: Double = 30.0
    /// Extra minutes of sampling grid added before and after the footage.
    static let gpxGridExtensionM: Double = 5.0

    // MARK: - Highlight target
    /// Default reel length in minutes; the user overrides it in GlobalSettings.
    static let highlightTargetDurationM: Double = 5.0
    /// Number of clips needed to fill the global target length, rounded down.
    static var targetClips: Int { Int((GlobalSettings.shared.highlightTargetMinutes * 60) / clipOutLenS) }

    // MARK: - Clip refinement (Enrich pass 2, `ClipRefiner`)
    /// Shortlist size as a multiple of the clips wanted. 1.5 leaves Select room to choose while keeping the
    /// extra frame reads to about 15% of the first pass at default settings.
    static let refineShortlistFactor: Double = 1.5
    /// Largest shift, in seconds, of a clip's start towards the action. Two seconds stays clear of the next
    /// 5-second grid point's own clip.
    static let clipMaxShiftS: Double = 2.0
    /// Most frames read per shortlisted moment. Nine gives one frame a second at the default 3.5 s clip
    /// (−2 s … +5 s); longer clips space the frames further apart, so the cost doesn't grow with clip length.
    static let refineMaxFrames: Int = 9
    /// Change in weighted box area (fraction of the frame) that YOLO jitter causes in a steady scene; changes
    /// up to this size don't count as action. On four of the owner's rides (2026-10-31), half of all changes
    /// between neighbouring samples on group rides were below 0.03–0.05.
    static let actionNoiseArea: Double = 0.05
    /// Change in weighted box area beyond the noise that scores full action: a rider growing from nothing to
    /// about a third of the frame. On the same rides about 5% of changes reached that.
    static let actionFullScaleArea: Double = 0.25

    // MARK: - Selection
    /// When `true`, moments without GPS would be excluded from selection. Not currently used.
    static let requireGpsForSelection: Bool = false
    /// Below this speed (km/h) a moment counts as stopped (café, lights) and isn't picked.
    static let movingSpeedKmh: Double = 2.0
    /// Gap between picks as a fraction of the average spacing the ride allows. Half the average leaves room
    /// for the best moments to sit closer together than an even grid while keeping picks spread out.
    static let selectionSpacingFraction: Double = 0.5
    /// Clips per stretch of riding footage that must contribute its best moment. Three keeps the longest
    /// ride without a pick to about 3 average spacings while leaving two thirds of picks to pure score.
    static let clipsPerStretch: Int = 3
    /// Seconds at each end of the ride from which the reel always takes one moment, so it opens at the start
    /// and closes at the finish. Five minutes covers the roll-out and the final approach without reaching
    /// mid-ride.
    static let rideEdgeWindowS: Double = 300

    // MARK: - YOLO
    /// Square input size, in pixels, that the YOLO model expects.
    static let yoloImageSize: Int = 640
    /// Frames per YOLO batch on Mac. Not currently used.
    static let yoloBatchSizeMac: Int = 8
    /// Frames per YOLO batch on iPad. Not currently used.
    static let yoloBatchSizeiPad: Int = 4
    /// COCO class IDs the app counts (see `YOLOClass`). Not currently used.
    static let yoloDetectClasses: Set<Int> = [0, 1, 2, 3, 5, 7]

    /// The COCO class IDs the app cares about, by name.
    enum YOLOClass: Int, CaseIterable {
        case person = 0, bicycle = 1, car = 2, motorcycle = 3
        case bus = 5, truck = 7
    }

    // MARK: - Scoring weights — reads from GlobalSettings so user can tune them
    /// Score weights from user settings (see `GlobalSettings` for meanings).
    enum ScoreWeights {
        /// Weight of the detection score.
        static var detectScore: Double  { GlobalSettings.shared.scoreWeightDetect }
        /// Weight of the action score (objects moving in view during the clip).
        static var action: Double       { GlobalSettings.shared.scoreWeightAction }
        /// Weight of speed.
        static var speedKmh: Double     { GlobalSettings.shared.scoreWeightSpeed }
        /// Weight of gradient.
        static var gradient: Double     { GlobalSettings.shared.scoreWeightGradient }
        /// Weight of Strava segment efforts.
        static var segmentBoost: Double { GlobalSettings.shared.scoreWeightSegment }
        /// Bonus for moments filmed by both cameras.
        static var dualCamera: Double   { GlobalSettings.shared.scoreWeightDualCamera }
    }

    // MARK: - Score normalisation denominators
    /// Speed (km/h) that scores 1.0; faster speeds are capped at 1.0.
    static let speedNormDivisor: Double = 60.0
    /// Gradient (%, up or down) that scores 1.0; steeper is capped at 1.0.
    static let gradNormDivisor: Double = 8.0

    // MARK: - Camera
    /// The supported Cycliq cameras. Raw values match the clip filename prefix and are stored in CSV/JSONL
    /// files, so they are permanent.
    enum CameraName: String, CaseIterable, Codable {
        case fly12Sport = "Fly12Sport"
        case fly6Pro    = "Fly6Pro"

        /// Per-camera multiplier for the weighted score. Both cameras are currently weighted equally.
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
        /// Reads from GlobalSettings ("Time Sync" tab in Settings) so the user can dial it in.
        var knownOffset: Double {
            switch self {
            case .fly12Sport: return GlobalSettings.shared.fly12SportOffset
            case .fly6Pro:    return GlobalSettings.shared.fly6ProOffset
            }
        }

        /// Identifies the camera from a clip's filename prefix.
        /// - Parameter filename: The clip's file name, e.g. `"Fly12Sport_0042.MP4"`.
        /// - Returns: The camera, or `nil` for an unrecognised file.
        static func from(filename: String) -> CameraName? {
            if filename.hasPrefix("Fly12Sport") || filename.hasPrefix("Fly12S") { return .fly12Sport }
            if filename.hasPrefix("Fly6Pro") || filename.hasPrefix("Fly6")     { return .fly6Pro }
            return nil
        }
    }

    // MARK: - GPX
    /// Default GPX time offset in seconds (user setting overrides).
    static let gpxTimeOffsetS: Double = 0.0
    /// Maximum seconds between a sample time and the nearest GPX point for the point to be used.
    static let gpxTolerance: Double = 1.0

    // MARK: - HUD geometry (all sizes in pixels at 1920×1080 output)
    /// Layout of the on-video overlays, in pixels at 1920×1080. String positions are FFmpeg overlay expressions.
    /// Some layout values are not currently used (`gaugeOrder`, `enabledGauges`, `mapGap`, `elevStripH`, `mapY`,
    /// `gaugeY`, `elevY`, `paddingX`, `paddingY`).
    enum HUD {
        /// Output frame width.
        static let outputW: Int = 1920
        /// Output frame height.
        static let outputH: Int = 1080

        // Gauge strip — 5 equal cells, each 194×194px
        /// Width of the gauge strip.
        static let gaugeCompositeW: Int = 972
        /// Height of the gauge strip.
        static let gaugeCompositeH: Int = 194
        /// Side of each square gauge cell.
        static let gaugeCellSize: Int = 194   // each cell is square
        /// Gauge order, left to right. Not currently used.
        static let gaugeOrder: [String] = ["elev", "gradient", "speed", "hr", "cadence"]
        /// Gauges to draw. Not currently used.
        static let enabledGauges: [String] = ["speed", "cadence", "hr", "elev", "gradient"]

        // Layout (all at 1920×1080):
        //   [Map 390][gap 8][Gauges 972][gap 8][PiP ~550]  ← y=615–1005 (390px)
        //   [Elev 390]      [open video]       [PiP cont]  ← y=1005–1080 (75px)
        // PiP spans full 465px (map+elev) flush to bottom; open video is below gauges only.
        /// Map overlay width (it is square).
        static let mapW: Int = 390
        /// Gap between map and gauges. Not currently used.
        static let mapGap: Int = 8
        /// Elevation strip height. Not currently used.
        static let elevStripH: Int = 75
        /// Distance from the bottom edge to the map and gauges (room for the elevation strip).
        static let mapPipBottom: Int = 75      // y-from-bottom for map and gauges

        // PiP spans map height + elev height so it fills the right column to the bottom edge
        /// Picture-in-picture height.
        static let pipH: Int = 465             // mapH(390) + elevH(75)

        // Overlay positions
        /// Map overlay x position: flush with the left edge.
        static let mapX: Int = 0              // map anchors bottom-left
        /// Map y position (FFmpeg expression). Not currently used.
        static let mapY: String = "H-h-75"   // FFmpeg: above elev strip
        /// Gauge strip x position.
        static let gaugeX: Int = 398          // mapW(390) + mapGap(8)
        /// Gauge strip y position (FFmpeg expression). Not currently used.
        static let gaugeY: String = "H-h-75"
        /// Picture-in-picture x position.
        static let pipX: Int = 1370           // gaugeX(398) + gaugeCompositeW(972)
        /// Picture-in-picture y position (FFmpeg expression).
        static let pipY: String = "H-h"       // flush bottom — pip covers elev row too
        /// Elevation strip x position.
        static let elevX: Int = 0            // below map, same left edge
        /// Elevation strip y position (FFmpeg expression). Not currently used.
        static let elevY: String = "H-h"
        /// Elevation strip width.
        static let elevW: Int = 390           // map width only
        /// Elevation strip height.
        static let elevH: Int = 75

        // HUD padding
        /// Horizontal HUD padding. Not currently used.
        static let paddingX: Int = 398        // gaugeX
        /// Vertical HUD padding. Not currently used.
        static let paddingY: Int = 75
    }

    // MARK: - Map
    /// Map overlay styling. `zoomPip`, `zoomSplash` and `splashSize` are not currently used.
    enum Map {
        /// Route line colour (RGB).
        static let routeColor: (Int, Int, Int) = (40, 180, 60)
        /// Route line width on the video map, in pixels.
        static let routeWidth: Int = 6
        /// Route line width on the intro map, in pixels.
        static let splashRouteWidth: Int = 24
        /// Rider position marker colour (RGB).
        static let markerColor: (Int, Int, Int) = (230, 175, 0)
        /// Rider position marker **diameter**, in pixels (MinimapRenderer halves it). The name is kept so
        /// existing call sites don't change.
        static let markerRadius: Int = 18
        /// Margin around the route when framing the map, as a fraction of the route size.
        static let paddingPct: Double = 0.25
        /// Map zoom level for the video map. Not currently used.
        static let zoomPip: Int = 15
        /// Map zoom level for the intro map. Not currently used.
        static let zoomSplash: Int = 12
        /// Intro image size. Not currently used.
        static let splashSize: (Int, Int) = (2560, 1440)
    }

    // MARK: - Video encoding
    /// Output video and audio encoding settings.
    enum Encoding {
        /// Video bitrate: 8 Mbps H.264.
        static let videoBitrate: Int = 8_000_000   // 8 Mbps H.264
        /// Audio bitrate: 192 kbps AAC.
        static let audioBitrate: Int = 192_000     // 192 kbps AAC
        // macOS: libx264 software encoder (matches segment output from earlier steps).
        // The non-macOS value is never used: FFmpeg runs only on macOS, and iPadOS renders with AVFoundation.
        #if os(macOS)
        /// FFmpeg video encoder name.
        static let videoCodec = "libx264"
        #else
        /// FFmpeg video encoder name.
        static let videoCodec = "h264_videotoolbox"
        #endif
    }

    // MARK: - FFmpeg loudnorm
    /// FFmpeg `loudnorm` target: -16 LUFS integrated loudness (a common target for online video),
    /// -1.5 dBTP true peak, loudness range 11.
    static let loudnormTarget: String = "-16"
    /// True-peak limit, dBTP.
    static let loudnormTP: String = "-1.5"
    /// Loudness range target.
    static let loudnormLRA: String = "11"

    // MARK: - Audio
    /// Default backing-music volume, 0–1.
    static let musicVolume: Double = 0.7
    /// Default camera-audio volume, 0–1.
    static let rawAudioVolume: Double = 0.3

    // MARK: - Concat
    /// Crossfade length between clips, in seconds.
    static let concatXfadeDuration: Double = 0.5
    /// Seconds over which the backing music fades out at the end of the highlights, so it doesn't cut off
    /// hard where the outro (with its own music) begins.
    static let musicFadeOutDuration: Double = 3.0

    // MARK: - Splash
    /// Height of the intro/outro title banner: the original 220 px at 1440p scaled to 1080p.
    static let bannerHeight: Int = 165

    // MARK: - Gauge arc drawing (PIL clockwise from 3-o'clock → CoreGraphics conversion needed)
    /// Gauge arc geometry and colours from the original Python (PIL) renderer. Not currently used:
    /// GaugeRenderer uses its own values.
    enum GaugeArc {
        /// Arc start angle (PIL convention).
        static let arcStartDeg: Double = 150    // PIL angle
        /// Arc end angle (PIL convention).
        static let arcEndDeg: Double   = 390    // PIL angle
        /// Arc sweep in degrees.
        static let arcSpan: Double     = 240
        /// Active arc colour (RGBA).
        static let green: (Int, Int, Int, Int)  = (0, 230, 77, 255)
        /// Inactive arc colour (RGBA).
        static let dim:   (Int, Int, Int, Int)  = (0, 55, 22, 255)
        /// Gauge background (RGBA).
        static let bg:    (Int, Int, Int, Int)  = (0, 0, 0, 100)
        /// Text colour (RGBA).
        static let white: (Int, Int, Int, Int)  = (255, 255, 255, 255)
    }

    // MARK: - Strava PR boosts
    /// Segment score for a Strava segment effort, by personal-record rank.
    enum StravaBoost {
        /// Segment PR (rank 1).
        static let rank1: Double   = 1.0
        /// Second or third best effort.
        static let rank2_3: Double = 0.7
        /// Any other segment effort: nothing. Ordinary efforts cover 70–90% of a typical ride, so a score for
        /// them would rise almost everywhere and not help pick moments.
        static let any: Double     = 0.0
    }
}
