import Foundation
import AVFoundation
import CoreGraphics
import CoreImage
import Metal

// MARK: - Custom instruction

/// Carries per-clip overlay data into the compositor.
/// AVFoundation passes this through the instruction chain to startRequest(_:).
final class ClipCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {

    let timeRange:             CMTimeRange
    let enablePostProcessing:  Bool = true
    let containsTweening:      Bool = false
    let passthroughTrackID:    CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let mainTrackID:   CMPersistentTrackID
    let pipTrackID:    CMPersistentTrackID?
    let minimapImage:  CGImage
    let elevImage:     CGImage
    let gaugeImages:   [CGImage]   // one per second of the clip

    var requiredSourceTrackIDs: [NSValue]? {
        var ids: [NSValue] = [NSNumber(value: mainTrackID)]
        if let pip = pipTrackID { ids.append(NSNumber(value: pip)) }
        return ids
    }

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
final class ClipVideoCompositor: NSObject, AVVideoCompositing {

    // AVFoundation requires a single pixel format value — not an array.
    // IOSurface backing enables Metal compositing without deprecated OpenGL key.
    var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
    ]

    var requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
    ]

    private lazy var ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device,
                            options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        }
        return CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
    }()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

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
            let pipW   = pipSrc.extent.width * scale
            var pip    = pipSrc.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            pip = pip.transformed(by: CGAffineTransform(
                translationX: CGFloat(AppConfig.HUD.pipX),
                y:            CGFloat(AppConfig.HUD.mapPipBottom)))
            composite = pip.composited(over: composite)
        }

        // 3. Minimap — 390×390, at (mapX, mapPipBottom)
        let mapCI = CIImage(cgImage: instr.minimapImage)
            .transformed(by: CGAffineTransform(
                translationX: CGFloat(AppConfig.HUD.mapX),
                y:            CGFloat(AppConfig.HUD.mapPipBottom)))
        composite = mapCI.composited(over: composite)

        // 4. Elevation strip — 948×75, flush at bottom (y=0)
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
