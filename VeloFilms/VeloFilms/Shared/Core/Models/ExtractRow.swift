// ExtractRow.swift
// Row model for extract.jsonl, written by ExtractStep and read by EnrichStep.

import Foundation

/// One row in `extract.jsonl`: a point on the sampling grid that falls inside a camera clip, with the frame
/// position in that clip. No pixels are read at this stage.
/// The JSON keys match `extract.py` in the original Python app; they are permanent.
struct ExtractRow: Codable {
    /// Unique row ID: `"{camera}_{clipNumber 4 digits}_{seconds into clip 6 digits}"`.
    var index: String
    /// Camera raw value: `"Fly12Sport"` or `"Fly6Pro"`.
    var camera: String
    /// 1-based position of the clip in the sorted clip list.
    var clipNum: Int
    /// Frame index in the clip at this time (seconds × fps, rounded).
    var frameNumber: Int
    /// Absolute path to the source `.MP4`.
    var videoPath: String
    /// Grid time in Unix seconds. Both cameras share the same value at the same grid point, which is how
    /// front and rear footage are paired.
    var absTimeEpoch: Double
    /// The grid time as an ISO 8601 string.
    var absTimeIso: String
    /// Seconds since the first GPX point.
    var sessionTsS: Double
    /// Corrected recording start of the clip, in Unix seconds.
    var clipStartEpoch: Double
    /// `clipStartEpoch` as an ISO 8601 string.
    var adjustedStartTime: String
    /// Clip duration in seconds.
    var durationS: Double
    /// Always `"video"`; kept for compatibility with the Python schema.
    var source: String
    /// Clip frame rate (59.94 if it couldn't be read).
    var fps: Double

    /// JSON key names (snake_case). Permanent: existing files use them.
    enum CodingKeys: String, CodingKey {
        case index, camera
        case clipNum         = "clip_num"
        case frameNumber     = "frame_number"
        case videoPath       = "video_path"
        case absTimeEpoch    = "abs_time_epoch"
        case absTimeIso      = "abs_time_iso"
        case sessionTsS      = "session_ts_s"
        case clipStartEpoch  = "clip_start_epoch"
        case adjustedStartTime = "adjusted_start_time"
        case durationS       = "duration_s"
        case source, fps
    }
}
