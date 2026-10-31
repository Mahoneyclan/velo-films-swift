// EnrichRow.swift
// Row model for enriched.jsonl, written by EnrichStep and read by SelectStep and the manual selection screen.

import Foundation

/// One row in `enriched.jsonl`: an `ExtractRow` plus YOLO detections, action, GPS telemetry and scores.
/// JSON keys match `enrich.py` in the original Python app; they are permanent.
struct EnrichRow: Codable {
    // From ExtractRow (same meaning as there)
    /// Unique row ID (see `ExtractRow.index`).
    var index: String
    /// Camera raw value.
    var camera: String
    /// 1-based clip number.
    var clipNum: Int
    /// Frame index in the clip.
    var frameNumber: Int
    /// Absolute path to the source clip.
    var videoPath: String
    /// Grid time in Unix seconds, shared by both cameras.
    var absTimeEpoch: Double
    /// Grid time as ISO 8601.
    var absTimeIso: String
    /// Seconds since the first GPX point.
    var sessionTsS: Double
    /// Corrected clip start, Unix seconds.
    var clipStartEpoch: Double
    /// Clip start as ISO 8601.
    var adjustedStartTime: String
    /// Clip duration in seconds.
    var durationS: Double
    /// Always `"video"`.
    var source: String
    /// Clip frame rate.
    var fps: Double

    // YOLO detections
    /// Highest (confidence × class weight) among the frame's detections, 0–1. A person counts with the
    /// pedestrian weight unless a bicycle is also in the frame.
    var detectScore: Double
    /// Number of objects detected above the confidence thresholds.
    var numDetections: Int
    /// Combined area of the cycling-related boxes (person, bicycle) as a fraction of the frame, 0–1.
    var bboxArea: Double
    /// Comma-separated class names of the detections, e.g. `"person,bicycle"`.
    var detectedClasses: String
    /// `true` when at least one object was detected.
    var objectDetected: Bool

    // Action
    /// Action score, 0–1: how much objects grew or shrank in view during the clip (`ClipWindowScorer`). Set only
    /// for the camera refined in Enrich's second pass; 0 elsewhere. Stored under the permanent key `scene_boost`,
    /// from when this field held a scene-change score.
    var actionScore: Double

    // GPS (may be absent if no GPX match within tolerance)
    /// Time of the matched GPX point.
    var gpxEpoch: Double?
    /// Matched GPX time as ISO 8601.
    var gpxTimeUtc: String?
    /// Latitude in degrees.
    var lat: Double?
    /// Longitude in degrees.
    var lon: Double?
    /// Elevation in metres.
    var elevation: Double?
    /// Heart rate in bpm.
    var hrBpm: Double?
    /// Cadence in rpm.
    var cadenceRpm: Double?
    /// Speed in km/h.
    var speedKmh: Double?
    /// Gradient in percent; negative is downhill.
    var gradientPct: Double?

    // Scores
    /// Weighted sum of the component scores (`ScoreCalculator.composite`).
    var scoreComposite: Double
    /// Composite × camera weight (`ScoreCalculator.weighted`).
    var scoreWeighted: Double
    /// Strava segment score for this time (`AppConfig.StravaBoost`), 0 if none.
    var segmentBoost: Double
    /// `absTimeEpoch` rounded to whole seconds. Rows from both cameras at the same grid point share it, which
    /// is how front and rear footage are paired.
    var momentId: Int
    /// Seconds the clip start was moved towards the action (negative is earlier), the same for both cameras of a
    /// moment. `nil` in files analysed before clip refinement existed, meaning no shift.
    var clipShiftS: Double? = nil

    /// The moment's time after the shift: the clip, map marker and gauges start `clipPreRollS` before it.
    var clipAnchorEpoch: Double { absTimeEpoch + (clipShiftS ?? 0) }

    /// JSON key names (snake_case). Permanent: existing files use them.
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
        case actionScore      = "scene_boost"
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
        case clipShiftS       = "clip_shift_s"
    }
}
