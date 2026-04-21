import Foundation
import AVFoundation

/// Extracts frames from video files and reads clip metadata.
/// Mirrors video_utils.py: fix_cycliq_utc_bug, infer_recording_start, frame extraction.
enum FrameSampler {

    // MARK: - Metadata

    /// Returns the FPS of an asset's first video track.
    static func fps(for asset: AVAsset) async throws -> Double {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { return 59.94 }
        let rate = try await track.load(.nominalFrameRate)
        return Double(rate)
    }

    /// Returns the corrected UTC creation epoch, applying the Cycliq UTC bug fix.
    ///
    /// Cycliq cameras store LOCAL time in the file's creation_time metadata field
    /// but mark it with 'Z' (UTC). We reinterpret the raw timestamp using the
    /// camera's known timezone offset to get real UTC.
    static func creationTime(for asset: AVAsset, camera: AppConfig.CameraName) async throws -> Double? {
        let metadata = try await asset.load(.commonMetadata)
        for item in metadata {
            if item.commonKey == .commonKeyCreationDate {
                guard let value = try? await item.load(.value) as? String,
                      let rawDate = parseISO8601(value) else { continue }
                // Cycliq bug: rawDate is actually local time, wrongly tagged as UTC.
                // Shift it back to real UTC using the camera's timezone.
                return applyCycliqUTCFix(rawDate: rawDate, camera: camera)
            }
        }
        return nil
    }

    /// Cycliq UTC bug: creation_time = local_time + 'Z'. Fix by subtracting the
    /// camera's UTC offset to recover the true UTC epoch.
    ///
    /// camera.timezoneIdentifier = "UTC+10" → offset = 36000s
    /// corrected_epoch = raw_epoch - offset
    static func applyCycliqUTCFix(rawDate: Date, camera: AppConfig.CameraName) -> Double {
        // raw_epoch is local time parsed as UTC; subtract the local offset to get true UTC
        let tz = TimeZone(identifier: camera.timezoneIdentifier)
            ?? TimeZone(secondsFromGMT: 0)!
        let offsetSeconds = Double(tz.secondsFromGMT(for: rawDate))
        return rawDate.timeIntervalSince1970 - offsetSeconds
    }

    // MARK: - Frame extraction

    /// Extract a single frame at a given second offset within a video file.
    /// Returns nil if the frame cannot be read.
    static func extractFrame(videoURL: URL, atSecond second: Double) async -> CGImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.1, preferredTimescale: 600)

        let time = CMTime(seconds: max(0, second), preferredTimescale: 600)
        do {
            let (image, _) = try await generator.image(at: time)
            return image
        } catch {
            return nil
        }
    }

    /// Extract multiple frames at specified second offsets.
    static func extractFrames(videoURL: URL, atSeconds seconds: [Double]) async -> [(Double, CGImage?)] {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.1, preferredTimescale: 600)

        let times = seconds.map { CMTime(seconds: max(0, $0), preferredTimescale: 600) }
        var results: [(Double, CGImage?)] = Array(zip(seconds, Array(repeating: nil, count: seconds.count)))

        for (i, time) in times.enumerated() {
            if let (image, _) = try? await generator.image(at: time) {
                results[i] = (seconds[i], image)
            }
        }
        return results
    }

    // MARK: - Helpers

    private static func parseISO8601(_ string: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: string) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: string)
    }
}
