import Foundation

/// Abstracts FFmpeg execution across platforms.
/// macOS: shells out to /usr/local/bin/ffmpeg
/// iPadOS: delegates to FFmpegKit
///
/// All pipeline steps call only this protocol. Existing filter_complex strings
/// from the Python source port unchanged to both platforms.
protocol FFmpegBridge: Sendable {
    /// Execute FFmpeg with the given arguments (excluding the leading "ffmpeg").
    /// Returns stdout/stderr combined output.
    /// Throws PipelineError.ffmpegFailed on non-zero exit.
    func execute(arguments: [String]) async throws -> String

    /// Probe a video file and return its duration in seconds, or nil if unreadable.
    func probeDuration(url: URL) async throws -> Double?

    /// Probe a video file and return its frame rate, or nil if unreadable.
    func probeFPS(url: URL) async throws -> Double?
}

extension FFmpegBridge {
    func probeDuration(url: URL) async throws -> Double? {
        let output = try await execute(arguments: [
            "-v", "quiet", "-print_format", "json", "-show_entries",
            "format=duration", "-i", url.path
        ])
        // Parse {"format": {"duration": "123.45"}}
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let format = json["format"] as? [String: Any],
           let durStr = format["duration"] as? String,
           let dur = Double(durStr) {
            return dur
        }
        return nil
    }

    func probeFPS(url: URL) async throws -> Double? {
        let output = try await execute(arguments: [
            "-v", "quiet", "-print_format", "json", "-show_entries",
            "stream=r_frame_rate", "-select_streams", "v:0", "-i", url.path
        ])
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let streams = json["streams"] as? [[String: Any]],
           let rateStr = streams.first?["r_frame_rate"] as? String {
            let parts = rateStr.split(separator: "/")
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                return num / den
            }
        }
        return nil
    }
}

/// Build the shared FFmpegBridge instance for the current platform.
func makeBridge() -> any FFmpegBridge {
#if os(macOS)
    return FFmpegMacBridge()
#else
    return FFmpegKitBridge()
#endif
}
