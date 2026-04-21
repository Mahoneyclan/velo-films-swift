import Foundation

/// One row in select.csv — enrich row + selection metadata.
/// Mirrors select.py output schema exactly.
struct SelectRow: Codable {
    // From EnrichRow (flattened for direct CSV round-trip)
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
    var detectScore: Double
    var numDetections: Int
    var bboxArea: Double
    var detectedClasses: String
    var objectDetected: Bool
    var sceneBoost: Double
    var gpxEpoch: Double?
    var gpxTimeUtc: String?
    var lat: Double?
    var lon: Double?
    var elevation: Double?
    var hrBpm: Double?
    var cadenceRpm: Double?
    var speedKmh: Double?
    var gradientPct: Double?
    var scoreComposite: Double
    var scoreWeighted: Double
    var segmentBoost: Double
    var momentId: Int

    // Selection output
    var recommended: Bool
    var stravaPR: Bool
    var isSingleCamera: Bool
    var paired: Bool            // has a partner camera row for this moment
    var segmentName: String?
    var segmentDistance: Double?
    var segmentGrade: Double?

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
        case recommended
        case stravaPR         = "strava_pr"
        case isSingleCamera   = "is_single_camera"
        case paired
        case segmentName      = "segment_name"
        case segmentDistance  = "segment_distance"
        case segmentGrade     = "segment_grade"
    }
}
