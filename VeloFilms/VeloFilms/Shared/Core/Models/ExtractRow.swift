import Foundation

/// One row in extract.csv — a sampled frame at a GPX-grid point.
/// Mirrors extract.py output schema exactly.
struct ExtractRow: Codable {
    var index: String           // "{camera}_{clipId}_{sec:06d}"
    var camera: String          // "Fly12Sport" | "Fly6Pro"
    var clipNum: Int
    var frameNumber: Int
    var videoPath: String       // absolute path to source .MP4
    var absTimeEpoch: Double    // authoritative world timestamp — shared across cameras at same grid point
    var absTimeIso: String
    var sessionTsS: Double      // seconds since session start
    var clipStartEpoch: Double
    var adjustedStartTime: String
    var durationS: Double
    var source: String          // "video"
    var fps: Double

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
