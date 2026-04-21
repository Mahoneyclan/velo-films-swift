import Foundation

/// One row in enriched.csv — extract row + YOLO detections + GPS + scores.
/// Mirrors enrich.py output schema exactly.
struct EnrichRow: Codable {
    // From ExtractRow
    var index: String
    var camera: String
    var clipNum: Int
    var frameNumber: Int
    var videoPath: String
    var absTimeEpoch: Double
    var absTimeIso: String
    var sessionTsS: Double
    var clipStartEpoch: Double
    var adjustedStartTime: String
    var durationS: Double
    var source: String
    var fps: Double

    // YOLO detections
    var detectScore: Double
    var numDetections: Int
    var bboxArea: Double
    var detectedClasses: String  // comma-separated class names
    var objectDetected: Bool

    // Scene detection
    var sceneBoost: Double

    // GPS (may be absent if no GPX match within tolerance)
    var gpxEpoch: Double?
    var gpxTimeUtc: String?
    var lat: Double?
    var lon: Double?
    var elevation: Double?
    var hrBpm: Double?
    var cadenceRpm: Double?
    var speedKmh: Double?
    var gradientPct: Double?

    // Scores
    var scoreComposite: Double
    var scoreWeighted: Double
    var segmentBoost: Double
    var momentId: Int            // int(round(absTimeEpoch)) — groups dual-camera pairs

    enum CodingKeys: String, CodingKey {
        case index, camera
        case clipNum          = "clip_num"
        case frameNumber      = "frame_number"
        case videoPath        = "video_path"
        case absTimeEpoch     = "abs_time_epoch"
        case absTimeIso       = "abs_time_iso"
        case sessionTsS       = "session_ts_s"
        case clipStartEpoch   = "clip_start_epoch"
        case adjustedStartTime = "adjusted_start_time"
        case durationS        = "duration_s"
        case source, fps
        case detectScore      = "detect_score"
        case numDetections    = "num_detections"
        case bboxArea         = "bbox_area"
        case detectedClasses  = "detected_classes"
        case objectDetected   = "object_detected"
        case sceneBoost       = "scene_boost"
        case gpxEpoch         = "gpx_epoch"
        case gpxTimeUtc       = "gpx_time_utc"
        case lat, lon, elevation
        case hrBpm            = "hr_bpm"
        case cadenceRpm       = "cadence_rpm"
        case speedKmh         = "speed_kmh"
        case gradientPct      = "gradient_pct"
        case scoreComposite   = "score_composite"
        case scoreWeighted    = "score_weighted"
        case segmentBoost     = "segment_boost"
        case momentId         = "moment_id"
    }
}
