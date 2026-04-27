import Foundation
import AVFoundation
import CoreGraphics
import CoreImage

/// Shared AVFoundation-based encoding and export utilities.
/// Replaces FFmpegBridge for all render operations.
enum VideoEncoder {

    // MARK: - Still image → video

    /// Encodes a single CGImage as a looped H.264 video.
    /// The image is scaled and letterboxed to 1920×1080 if needed.
    static func encodeStill(
        image: CGImage,
        duration: Double,
        fps: Int = 30,
        outputURL: URL
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let W = AppConfig.HUD.outputW
        let H = AppConfig.HUD.outputH

        let scaled = scaleAndPad(image: image, toWidth: W, height: H)
        let pixelBuffer = try makePixelBuffer(from: scaled, width: W, height: H)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  W,
            AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:  8_000_000,
                AVVideoProfileLevelKey:    AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: W,
                kCVPixelBufferHeightKey as String: H,
            ]
        )

        writer.add(videoInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let ts: CMTimeScale = 600
        let frameDur = CMTime(value: CMTimeValue(ts / CMTimeScale(fps)), timescale: ts)
        let frameCount = Int(duration * Double(fps))

        for i in 0..<frameCount {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let pts = CMTimeMultiply(frameDur, multiplier: Int32(i))
            adaptor.append(pixelBuffer, withPresentationTime: pts)
        }

        videoInput.markAsFinished()
        await writer.finishWriting()

        if let err = writer.error { throw err }
        guard writer.status == .completed else {
            throw PipelineError.renderFailed("encodeStill: writer status \(writer.status.rawValue)")
        }
    }

    // MARK: - Composition export

    /// Export an AVMutableComposition to an .mp4 file using AVAssetExportSession.
    static func export(
        composition: AVComposition,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil,
        to outputURL: URL
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPreset1920x1080
        ) else {
            throw PipelineError.renderFailed("AVAssetExportSession could not be created")
        }

        session.outputURL        = outputURL
        session.outputFileType   = .mp4
        session.videoComposition = videoComposition
        session.audioMix         = audioMix
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        if let err = session.error { throw err }
        guard session.status == .completed else {
            throw PipelineError.renderFailed("Export ended with status \(session.status.rawValue)")
        }
    }

    // MARK: - Scale / pad helper (letterbox to exact W×H)

    static func scaleAndPad(image: CGImage, toWidth W: Int, height H: Int) -> CGImage {
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        let scale = min(CGFloat(W) / srcW, CGFloat(H) / srcH)
        let dstW  = srcW * scale
        let dstH  = srcH * scale
        let offX  = (CGFloat(W) - dstW) / 2
        let offY  = (CGFloat(H) - dstH) / 2

        let ctx = CGContext(
            data: nil, width: W, height: H,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(.black)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.draw(image, in: CGRect(x: offX, y: offY, width: dstW, height: dstH))
        return ctx.makeImage()!
    }

    // MARK: - Pixel buffer

    static func makePixelBuffer(from image: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true,
             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pb else {
            throw PipelineError.renderFailed("CVPixelBuffer create failed: \(status)")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let ctx = CGContext(
            data:             CVPixelBufferGetBaseAddress(pixelBuffer),
            width:            width,
            height:           height,
            bitsPerComponent: 8,
            bytesPerRow:      CVPixelBufferGetBytesPerRow(pixelBuffer),
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGImageAlphaInfo.premultipliedFirst.rawValue |
                              CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw PipelineError.renderFailed("CGContext creation failed for pixel buffer")
        }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
