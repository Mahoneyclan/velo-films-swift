// VideoCompositor.swift (used for iPadOS clip rendering)
// Custom AVFoundation compositor that draws the main video, picture-in-picture and HUD overlays for each frame.

import Foundation
import AVFoundation
import CoreGraphics
import CoreImage
import Metal

// MARK: - Custom instruction

/// Carries per-clip overlay data into the compositor.
/// AVFoundation passes this through the instruction chain to startRequest(_:).
final class ClipCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {

    /// Time range this instruction covers.
    let timeRange:             CMTimeRange
    /// Required by the protocol; post-processing is allowed.
    let enablePostProcessing:  Bool = true
    /// `false`: overlays don't animate between frames, except the gauge image swap.
    let containsTweening:      Bool = false
    /// No passthrough; every frame is composited.
    let passthroughTrackID:    CMPersistentTrackID = kCMPersistentTrackID_Invalid

    /// Track of the full-screen camera.
    let mainTrackID:   CMPersistentTrackID
    /// Track of the picture-in-picture camera, if any.
    let pipTrackID:    CMPersistentTrackID?
    /// Map overlay.
    let minimapImage:  CGImage
    /// Elevation strip overlay.
    let elevImage:     CGImage
    /// Gauge strip images, one per second of the clip.
    let gaugeImages:   [CGImage]

    /// The tracks AVFoundation must decode for this instruction.
    var requiredSourceTrackIDs: [NSValue]? {
        var ids: [NSValue] = [NSNumber(value: mainTrackID)]
        if let pip = pipTrackID { ids.append(NSNumber(value: pip)) }
        return ids
    }

    /// Creates an instruction for one clip.
    /// - Parameters:
    ///   - timeRange: The span of the composition this instruction covers.
    ///   - mainTrackID: Track of the main camera.
    ///   - pipTrackID: Track of the picture-in-picture camera, or `nil` for one camera.
    ///   - minimapImage: Map overlay.
    ///   - elevImage: Elevation strip overlay.
    ///   - gaugeImages: One gauge image per second of the clip.
    init(timeRange: CMTimeRange,
         mainTrackID: CMPersistentTrackID,
         pipTrackID:  CMPersistentTrackID?,
         minimapImage: CGImage,
         elevImage:    CGImage,
         gaugeImages:  [CGImage]) {
        self.timeRange    = timeRange
        self.mainTrackID  = mainTrackID
        self.pipTrackID   = pipTrackID
        self.minimapImage = minimapImage
        self.elevImage    = elevImage
        self.gaugeImages  = gaugeImages
    }
}

// MARK: - Compositor

/// Custom AVVideoCompositing used by ClipCompositor.
/// Per frame: scale/pad main video → composite PiP → overlay minimap, elevation, gauge.
///
/// Coordinate system: CIImage origin is bottom-left.
/// FFmpeg "H-h-75" (top-left origin) → y=75 in CIImage coordinates.
///
/// AVFoundation calls this on its own background queues. The project's default main-actor isolation also
/// applies to this class, and the lazily created `ciContext` is not synchronised.
final class ClipVideoCompositor: NSObject, AVVideoCompositing {

    // AVFoundation requires a single pixel format value — not an array.
    // IOSurface backing enables Metal compositing without deprecated OpenGL key.
    // [String: any Sendable] matches the protocol's NS_SWIFT_SENDABLE dictionary type under strict concurrency.
    /// Pixel format the compositor accepts from the source tracks (camera 4:2:0 video, IOSurface-backed).
    var sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]

    /// Pixel format of the output frames (32-bit BGRA, IOSurface-backed).
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]

    private lazy var ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device,
                            options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        }
        return CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
    }()

    /// No action needed; the output size is fixed.
    /// - Parameter newRenderContext: The new context (ignored).
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    /// Composites one output frame: main video, PiP, map, elevation strip and the gauge image for the current
    /// second. Finishes the request with an error if the instruction or main frame is missing.
    /// - Parameter request: The frame request from AVFoundation; called on a background queue.
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instr = request.videoCompositionInstruction as? ClipCompositionInstruction else {
            request.finish(with: makeError("Invalid instruction type"))
            return
        }

        guard let mainBuf = request.sourceFrame(byTrackID: instr.mainTrackID) else {
            request.finish(with: makeError("Missing main frame"))
            return
        }

        let W = CGFloat(AppConfig.HUD.outputW)
        let H = CGFloat(AppConfig.HUD.outputH)

        // 1. Main video — scale/pad to output size
        var composite = scaleAndPad(CIImage(cvPixelBuffer: mainBuf), toWidth: W, height: H)

        // 2. PiP — partner camera scaled to pipH, placed at (pipX, mapPipBottom)
        if let pipID = instr.pipTrackID,
           let pipBuf = request.sourceFrame(byTrackID: pipID) {
            let pipH   = CGFloat(AppConfig.HUD.pipH)
            let pipSrc = CIImage(cvPixelBuffer: pipBuf)
            let scale  = pipH / pipSrc.extent.height
            var pip    = pipSrc.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            pip = pip.transformed(by: CGAffineTransform(
                translationX: CGFloat(AppConfig.HUD.pipX),
                y:            0))   // PiP flush to bottom — spans map+elev height
            composite = pip.composited(over: composite)
        }

        // 3. Minimap — 390×390, at (mapX, mapPipBottom)
        let mapCI = CIImage(cgImage: instr.minimapImage)
            .transformed(by: CGAffineTransform(
                translationX: CGFloat(AppConfig.HUD.mapX),
                y:            CGFloat(AppConfig.HUD.mapPipBottom)))
        composite = mapCI.composited(over: composite)

        // 4. Elevation strip — 390×75, flush at bottom (y=0)
        let elevCI = CIImage(cgImage: instr.elevImage)
            .transformed(by: CGAffineTransform(
                translationX: CGFloat(AppConfig.HUD.elevX),
                y:            0))
        composite = elevCI.composited(over: composite)

        // 5. Gauge strip — select frame by elapsed seconds within clip
        let instrStart = instr.timeRange.start.seconds
        let elapsed    = max(0, request.compositionTime.seconds - instrStart)
        let gaugeIdx   = min(Int(elapsed), instr.gaugeImages.count - 1)
        let gaugeCI    = CIImage(cgImage: instr.gaugeImages[gaugeIdx])
            .transformed(by: CGAffineTransform(
                translationX: CGFloat(AppConfig.HUD.gaugeX),
                y:            CGFloat(AppConfig.HUD.mapPipBottom)))
        composite = gaugeCI.composited(over: composite)

        // 6. Render to output pixel buffer
        guard let outBuf = request.renderContext.newPixelBuffer() else {
            request.finish(with: makeError("Could not allocate output pixel buffer"))
            return
        }

        ciContext.render(composite,
                         to: outBuf,
                         bounds: CGRect(x: 0, y: 0, width: W, height: H),
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        request.finish(withComposedVideoFrame: outBuf)
    }

    /// No queued work to cancel; each request finishes synchronously in `startRequest`.
    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Helpers

    private func scaleAndPad(_ image: CIImage, toWidth W: CGFloat, height H: CGFloat) -> CIImage {
        let src   = image.extent
        let scale = min(W / src.width, H / src.height)
        let dstW  = src.width  * scale
        let dstH  = src.height * scale
        let offX  = (W - dstW) / 2
        let offY  = (H - dstH) / 2

        let background = CIImage(color: CIColor.black)
            .cropped(to: CGRect(x: 0, y: 0, width: W, height: H))
        let scaled = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offX, y: offY))
        return scaled.composited(over: background)
    }

    private func makeError(_ msg: String) -> NSError {
        NSError(domain: "ClipVideoCompositor", code: -1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
