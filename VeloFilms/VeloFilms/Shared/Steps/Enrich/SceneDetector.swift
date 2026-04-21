import Foundation
import CoreGraphics
import Accelerate

/// Per-camera scene change detector.
/// Mirrors scene_detector.py: maintains a circular buffer of the last
/// SCENE_COMPARISON_WINDOW_S frames per camera; scores by mean absolute
/// difference of grayscale 64×64 thumbnails.
final class SceneDetector {
    private let windowSize: Int  // number of frames in comparison window
    private var cameras: [String: CameraBuffer] = [:]

    init(windowSeconds: Double = AppConfig.sceneComparisonWindowS, fps: Double = 1.0) {
        windowSize = max(1, Int(windowSeconds / fps))
    }

    /// Feed a frame and get a scene-change score in [0, 1].
    /// Higher = more scene change from the oldest buffered frame.
    func score(frame: CGImage, camera: String) -> Double {
        if cameras[camera] == nil {
            cameras[camera] = CameraBuffer(capacity: windowSize)
        }
        let thumb = thumbnail(frame)
        let result: Double
        if let oldest = cameras[camera]!.oldest {
            result = meanAbsDiff(oldest, thumb)
        } else {
            result = 0
        }
        cameras[camera]!.push(thumb)
        return result
    }

    // MARK: - Thumbnail (64×64 grayscale)

    private func thumbnail(_ image: CGImage) -> [Float] {
        let size = 64
        let ctx = CGContext(data: nil, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: size,
                            space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = ctx.data else { return Array(repeating: 0, count: size * size) }
        let bytes = data.bindMemory(to: UInt8.self, capacity: size * size)
        return (0..<size*size).map { Float(bytes[$0]) }
    }

    private func meanAbsDiff(_ a: [Float], _ b: [Float]) -> Double {
        var sum: Float = 0
        vDSP_meanv(zip(a, b).map { abs($0 - $1) }, 1, &sum, vDSP_Length(a.count))
        return Double(sum) / 255.0
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
