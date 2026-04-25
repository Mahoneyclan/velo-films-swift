import Foundation
import AVFoundation
import ImageIO

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

    /// Returns the corrected UTC creation epoch for a Cycliq MP4 file.
    ///
    /// AVFoundation does not expose mvhd.creation_time for NOVATEK mp42 files,
    /// so we read it directly from the binary. The Cycliq UTC bug means the
    /// stored value is local time mislabelled as UTC — we correct for that.
    static func creationTime(for url: URL, camera: AppConfig.CameraName) -> Double? {
        guard let raw = readMVHDCreationTime(url: url) else { return nil }
        return applyCycliqUTCFix(rawDate: raw, camera: camera)
    }

    /// Reads creation_time from the mvhd box by scanning the last 4 MB of the file.
    /// NOVATEK mp42 files place moov at the end; mvhd is always the first child of moov.
    private static func readMVHDCreationTime(url: URL) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return nil }

        let scanSize = UInt64(4 * 1024 * 1024)
        let offset   = fileSize > scanSize ? fileSize - scanSize : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let tail = try? handle.readToEnd() else { return nil }

        // Find last occurrence of 'mvhd' — avoids false positives in video data
        let magic = Data([0x6D, 0x76, 0x68, 0x64]) // "mvhd"
        guard let range = tail.range(of: magic, options: .backwards) else { return nil }

        let pos = range.lowerBound  // index of 'm' in 'mvhd'
        // Layout after magic: version(1) flags(3) creation_time(4 or 8)
        let versionIdx = pos + 4
        guard versionIdx + 1 <= tail.endIndex else { return nil }
        let version = tail[versionIdx]

        let macToUnix: Int64 = 2_082_844_800
        let ctIdx = versionIdx + 4  // skip version(1) + flags(3)

        if version == 0 {
            guard ctIdx + 4 <= tail.endIndex else { return nil }
            let ct = readU32BE(tail, at: ctIdx)
            return Date(timeIntervalSince1970: Double(Int64(ct) - macToUnix))
        } else {
            guard ctIdx + 8 <= tail.endIndex else { return nil }
            let ct = readU64BE(tail, at: ctIdx)
            return Date(timeIntervalSince1970: Double(Int64(bitPattern: ct) - macToUnix))
        }
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

    static func makeGenerator(for videoURL: URL) -> AVAssetImageGenerator {
        let asset = AVURLAsset(url: videoURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)
        return gen
    }

    /// Extract one frame using a pre-built generator, with an 8-second timeout.
    /// On timeout, cancels the generator so the next call doesn't also hang.
    static func extractFrame(using generator: AVAssetImageGenerator,
                             atSecond second: Double) async -> CGImage? {
        let time = CMTime(seconds: max(0, second), preferredTimescale: 600)
        return await withTaskGroup(of: CGImage?.self) { group in
            group.addTask {
                guard let (img, _) = try? await generator.image(at: time) else { return nil }
                return img
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                generator.cancelAllCGImageGeneration()
                return nil
            }
            for await result in group {
                group.cancelAll()
                return result
            }
            return nil
        }
    }

    /// Convenience overload — creates its own generator (used from BuildStep / SplashStep).
    static func extractFrame(videoURL: URL, atSecond second: Double) async -> CGImage? {
        let gen = makeGenerator(for: videoURL)
        defer { gen.cancelAllCGImageGeneration() }
        return await extractFrame(using: gen, atSecond: second)
    }

    /// Extract multiple frames at specified second offsets (one generator, one asset load).
    static func extractFrames(videoURL: URL, atSeconds seconds: [Double]) async -> [(Double, CGImage?)] {
        let gen = makeGenerator(for: videoURL)
        defer { gen.cancelAllCGImageGeneration() }
        var results: [(Double, CGImage?)] = seconds.map { ($0, nil) }
        for (i, second) in seconds.enumerated() {
            results[i].1 = await extractFrame(using: gen, atSecond: second)
        }
        return results
    }

    // MARK: - Thumbnail persistence

    static func saveJPEG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    // MARK: - Helpers

    private static func readU32BE(_ data: Data, at i: Data.Index) -> UInt32 {
        UInt32(data[i]) << 24 | UInt32(data[i+1]) << 16 |
        UInt32(data[i+2]) << 8  | UInt32(data[i+3])
    }

    private static func readU64BE(_ data: Data, at i: Data.Index) -> UInt64 {
        UInt64(data[i])   << 56 | UInt64(data[i+1]) << 48 |
        UInt64(data[i+2]) << 40 | UInt64(data[i+3]) << 32 |
        UInt64(data[i+4]) << 24 | UInt64(data[i+5]) << 16 |
        UInt64(data[i+6]) << 8  | UInt64(data[i+7])
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: string) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: string)
    }
}
