// VideoEncoder.swift
// AVFoundation helpers: turn a still image into a video, and export compositions to MP4.

import Foundation
import AVFoundation
import CoreGraphics
import CoreImage

/// Shared AVFoundation-based encoding and export utilities.
/// Used on both platforms for the intro and outro, and on iPadOS for clips too. macOS still renders clips and
/// joins the reel with FFmpeg (ClipCompositor, ConcatStep).
enum VideoEncoder {

    // MARK: - Still image → video

    /// Encodes a single image as an H.264 video of the given length (the same frame repeated).
    /// The image is scaled and letterboxed to 1920×1080 if needed.
    /// - Parameters:
    ///   - image: The still.
    ///   - duration: Length in seconds.
    ///   - fps: Frame rate.
    ///   - outputURL: Destination `.mp4` (replaced).
    /// - Throws: `PipelineError.renderFailed` or AVAssetWriter errors.
    static func encodeStill(
        image: CGImage,
        duration: Double,
        fps: Int = 30,
        outputURL: URL
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let W = AppConfig.HUD.outputW
        let H = AppConfig.HUD.outputH

        let scaled = try scaleAndPad(image: image, toWidth: W, height: H)
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

    /// Exports a composition to an `.mp4` file at 1920×1080 using AVAssetExportSession.
    /// - Parameters:
    ///   - composition: The tracks to export.
    ///   - videoComposition: Optional compositing instructions.
    ///   - audioMix: Optional volume settings.
    ///   - outputURL: Destination file (replaced).
    /// - Throws: `PipelineError.renderFailed` if the session can't be created, or the export error.
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

        session.videoComposition = videoComposition
        session.audioMix         = audioMix
        session.shouldOptimizeForNetworkUse = true

        try await session.export(to: outputURL, as: .mp4)
    }

    // MARK: - Scale / pad helper (letterbox to exact W×H)

    /// Scales `image` to fit W×H without cropping and centres it on black.
    /// - Returns: A W×H image.
    /// - Throws: `PipelineError.renderFailed` if drawing fails.
    /// - Parameters:
    ///   - image: The source image.
    ///   - W: Output width in pixels.
    ///   - H: Output height in pixels.
    static func scaleAndPad(image: CGImage, toWidth W: Int, height H: Int) throws -> CGImage {
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        let scale = min(CGFloat(W) / srcW, CGFloat(H) / srcH)
        let dstW  = srcW * scale
        let dstH  = srcH * scale
        let offX  = (CGFloat(W) - dstW) / 2
        let offY  = (CGFloat(H) - dstH) / 2

        guard let ctx = CGContext(
            data: nil, width: W, height: H,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PipelineError.renderFailed("VideoEncoder: CGContext creation failed")
        }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.draw(image, in: CGRect(x: offX, y: offY, width: dstW, height: dstH))
        guard let result = ctx.makeImage() else {
            throw PipelineError.renderFailed("VideoEncoder: CGImage creation failed")
        }
        return result
    }

    // MARK: - Pixel buffer

    /// Copies an image into a new 32-bit BGRA pixel buffer for AVAssetWriter.
    /// - Returns: The pixel buffer.
    /// - Throws: `PipelineError.renderFailed` if the buffer or context can't be created.
    /// - Parameters:
    ///   - image: The source image, drawn to fill the buffer.
    ///   - width: Buffer width in pixels.
    ///   - height: Buffer height in pixels.
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
