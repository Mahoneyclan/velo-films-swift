import Foundation
import AVFoundation

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
    // Default implementations use AVFoundation directly; override if needed.
    func probeDuration(url: URL) async throws -> Double? {
        let asset = AVURLAsset(url: url)
        let dur = try? await asset.load(.duration)
        return dur.map { $0.seconds }
    }

    func probeFPS(url: URL) async throws -> Double? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        return try? await Double(track.load(.nominalFrameRate))
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
