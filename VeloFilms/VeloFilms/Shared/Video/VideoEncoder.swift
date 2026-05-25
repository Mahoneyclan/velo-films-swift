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

    /// Export an AVMutableComposition to an .mp4 file using AVAssetExportSession.
    /// macOS only — on iOS use exportInProcess() to avoid mediaserverd sandbox restrictions.
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

#if os(iOS)
    // MARK: - In-process export (iOS)

    /// iOS replacement for export(): uses AVAssetReader + AVAssetWriter entirely in-process.
    /// AVAssetExportSession spawns mediaserverd which cannot access security-scoped URLs on
    /// external drives, and its sandbox blocks our Metal compositor (FIGSANDBOX err=-17508).
    /// AVAssetReader + AVAssetWriter run in the app's own process where security-scoped access
    /// is active, so they can both read source clips and write output to the external drive.
    static func exportInProcess(
        composition: AVComposition,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil,
        to outputURL: URL
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        // Reader
        let reader = try AVAssetReader(asset: composition)

        let videoTracks = composition.tracks(withMediaType: .video)
        let readerVideo = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        readerVideo.videoComposition = videoComposition
        reader.add(readerVideo)

        var readerAudio: AVAssetReaderOutput? = nil
        let audioTracks = composition.tracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let ra = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks,
                audioSettings: [
                    AVFormatIDKey:             kAudioFormatLinearPCM,
                    AVSampleRateKey:           44100.0,
                    AVNumberOfChannelsKey:     2,
                    AVLinearPCMBitDepthKey:    16,
                    AVLinearPCMIsNonInterleaved: false,
                    AVLinearPCMIsFloatKey:     false,
                    AVLinearPCMIsBigEndianKey: false,
                ] as [String: Any]
            )
            ra.audioMix = audioMix
            reader.add(ra)
            readerAudio = ra
        }

        // Writer
        let W = AppConfig.HUD.outputW
        let H = AppConfig.HUD.outputH
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let writerVideo = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  W,
            AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: AppConfig.Encoding.videoBitrate,
                AVVideoProfileLevelKey:   AVVideoProfileLevelH264HighAutoLevel,
            ]
        ])
        writerVideo.expectsMediaDataInRealTime = false
        writer.add(writerVideo)

        var writerAudio: AVAssetWriterInput? = nil
        if readerAudio != nil {
            let wa = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey:         kAudioFormatMPEG4AAC,
                AVSampleRateKey:       44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey:   AppConfig.Encoding.audioBitrate,
            ] as [String: Any])
            wa.expectsMediaDataInRealTime = false
            writer.add(wa)
            writerAudio = wa
        }

        guard reader.startReading() else {
            throw reader.error ?? PipelineError.renderFailed("exportInProcess: reader failed to start")
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Pump video and audio concurrently — both run in-process with security-scoped access
        try await withThrowingTaskGroup(of: Void.self) { group in
            let rv = readerVideo
            let wv = writerVideo
            group.addTask { try await VideoEncoder.pumpOutput(rv, to: wv) }
            let ra = readerAudio
            let wa = writerAudio
            group.addTask { try await VideoEncoder.pumpOutput(ra, to: wa) }
            try await group.waitForAll()
        }

        if reader.status == .failed {
            throw reader.error ?? PipelineError.renderFailed("exportInProcess: reader error")
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }

        if let err = writer.error { throw err }
        guard writer.status == .completed else {
            throw PipelineError.renderFailed("exportInProcess: writer status \(writer.status.rawValue)")
        }
    }

    /// Pumps one AVAssetReaderOutput → AVAssetWriterInput until the source is exhausted.
    private static func pumpOutput(
        _ output: AVAssetReaderOutput?,
        to input: AVAssetWriterInput?
    ) async throws {
        guard let output, let input else { return }
        while let buf = output.copyNextSampleBuffer() {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            input.append(buf)
        }
        input.markAsFinished()
    }
#endif

    // MARK: - Scale / pad helper (letterbox to exact W×H)

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
