// SceneDetector.swift
// Scores how much the view has changed, per camera, by comparing small greyscale thumbnails.

import Foundation
import CoreGraphics
import Accelerate

/// Per-camera scene change detector.
///
/// Keeps a circular buffer of the last `windowSize` frames per camera and scores each new frame by the mean
/// absolute difference of 64×64 greyscale thumbnails against the oldest buffered frame. `windowSize` is
/// `windowSeconds / fps` frames; with the defaults (15 s, fps 1) that is 15 frames, which at the default 5-second
/// sampling interval means frames 75 seconds apart. Ported from `scene_detector.py` in the original Python app.
///
/// Stateful and not thread-safe: feed frames for each camera in time order from one task.
final class SceneDetector {
    private let windowSize: Int  // number of frames in comparison window
    private var cameras: [String: CameraBuffer] = [:]
    private static let graySpace = CGColorSpaceCreateDeviceGray()

    /// Creates a detector.
    /// - Parameters:
    ///   - windowSeconds: Comparison window length.
    ///   - fps: Frames per second the caller feeds; the window holds `windowSeconds / fps` frames (at least 1).
    init(windowSeconds: Double = AppConfig.sceneComparisonWindowS, fps: Double = 1.0) {
        windowSize = max(1, Int(windowSeconds / fps))
    }

    /// Feeds a frame and returns a scene-change score in [0, 1].
    /// Higher means more change from the oldest buffered frame. Returns 0 until the camera's buffer is full.
    /// - Parameters:
    ///   - frame: The new frame.
    ///   - camera: Camera name; each camera has its own buffer.
    /// - Returns: The score.
    func score(frame: CGImage, camera: String) -> Double {
        if cameras[camera] == nil {
            cameras[camera] = CameraBuffer(capacity: windowSize)
        }
        let thumb = thumbnail(frame)
        // Safe: the entry is created just above if missing.
        var buf = cameras[camera]!
        let result = buf.oldest.map { meanAbsDiff($0, thumb) } ?? 0.0
        buf.push(thumb)
        cameras[camera] = buf
        return result
    }

    // MARK: - Thumbnail (64×64 grayscale)

    private func thumbnail(_ image: CGImage) -> [Float] {
        let size = 64
        guard let ctx = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size,
                                  space: Self.graySpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return Array(repeating: 0, count: size * size)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = ctx.data else { return Array(repeating: 0, count: size * size) }
        let bytes = data.bindMemory(to: UInt8.self, capacity: size * size)
        return (0..<size*size).map { Float(bytes[$0]) }
    }

    private func meanAbsDiff(_ a: [Float], _ b: [Float]) -> Double {
        let diffs = zip(a, b).map { abs($0 - $1) }
        var mean: Float = 0
        vDSP_meanv(diffs, 1, &mean, vDSP_Length(diffs.count))
        return Double(mean) / 255.0
    }
}

// MARK: - Circular buffer

private struct CameraBuffer {
    private var buffer: [[Float]]
    private var head = 0
    private var count = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        buffer = []
        buffer.reserveCapacity(capacity)
    }

    mutating func push(_ item: [Float]) {
        if buffer.count < capacity {
            buffer.append(item)
        } else {
            buffer[head] = item
        }
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }

    /// The oldest frame in the buffer (for comparison with current).
    var oldest: [Float]? {
        guard count == capacity else { return nil }
        return buffer[head]
    }
}
