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
#if os(iOS)
        // AVAssetExportSession spawns mediaserverd which cannot access security-scoped external
        // drive URLs and its sandbox blocks our Metal compositor. Use the in-process path instead.
        try await exportInProcess(composition: composition,
                                   videoComposition: videoComposition,
                                   audioMix: audioMix,
                                   to: outputURL)
#else
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
#endif
    }

#if os(iOS)
    // MARK: - In-process export (iOS)

    /// iOS audio-mix + video-passthrough export — the only AVAssetReader use on iOS.
    ///
    /// iOS constraints established through testing:
    ///   1. External-drive files: AVAssetReader routes through mediaserverd XPC which cannot
    ///      access security-scoped URLs. Pass only iosTmp or bundle files to this function.
    ///   2. AVAssetReaderVideoCompositionOutput: engages the Fig video compositor
    ///      (FigApplicationStateMonitor err=-19431) regardless of composition complexity.
    ///      NEVER pass a non-nil videoComposition here; do all video compositing upstream
    ///      via AVAssetImageGenerator before calling this function.
    ///   3. AVAssetReaderTrackOutput with decode outputSettings (e.g. BGRA): mediaserverd
    ///      cannot create a VTDecompressionSession in the current app state ("Cannot Open").
    ///      Use outputSettings:nil (compressed passthrough) — no decode required.
    ///
    /// This function handles ONLY: video compressed passthrough + optional audio mix.
    /// All video compositing must happen outside via AVAssetImageGenerator frame loops.
    static func exportInProcess(
        composition: AVComposition,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil,
        to outputURL: URL
    ) async throws {
        // videoComposition must be nil on iOS — all compositing goes through AVAssetImageGenerator.
        // Callers that need video compositing should produce a composited video file first and
        // then call this function for audio mixing only (videoComposition: nil).
        guard videoComposition == nil else {
            throw PipelineError.renderFailed(
                "exportInProcess: non-nil videoComposition on iOS triggers Fig compositor " +
                "(FigApplicationStateMonitor err=-19431). Do video compositing via " +
                "AVAssetImageGenerator upstream and call this with videoComposition: nil.")
        }

        try? FileManager.default.removeItem(at: outputURL)

        // Reader
        let reader = try AVAssetReader(asset: composition)

        let videoTracks = composition.tracks(withMediaType: .video)
        guard let firstVideoTrack = videoTracks.first else {
            throw PipelineError.renderFailed("exportInProcess: no video tracks in composition")
        }
        // outputSettings: nil → compressed passthrough (no decode, no VTDecompressionSession).
        // Avoids mediaserverd VT decoder which fails in the current iOS app state.
        let readerVideo = AVAssetReaderTrackOutput(track: firstVideoTrack, outputSettings: nil)
        readerVideo.alwaysCopiesSampleData = false
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
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // outputSettings: nil → passthrough mode. MP4 container requires a sourceFormatHint
        // so the writer knows the incoming compressed format before the first sample arrives.
        // Use async load because AVCompositionTrack.formatDescriptions is not populated
        // synchronously when the backing file was just written (e.g. iosTmp clips).
        let videoFormatHint = (try? await firstVideoTrack.load(.formatDescriptions))?.first
        guard let videoFormatHint else {
            throw PipelineError.renderFailed(
                "exportInProcess: could not load video format description for passthrough")
        }
        let writerVideo = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                             sourceFormatHint: videoFormatHint)
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
            let errDetail = reader.error.map { " (\($0.localizedDescription))" } ?? ""
            throw reader.error ?? PipelineError.renderFailed("exportInProcess: reader failed to start\(errDetail)")
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard writer.status == .writing else {
            throw PipelineError.renderFailed("exportInProcess: writer failed to start: \(writer.error?.localizedDescription ?? "unknown")")
        }
        // Ensure writer is cancelled on any throw path before finishWriting is reached.
        // Deallocating an AVAssetWriter in .writing state raises NSFileHandleOperationException.
        defer { if writer.status == .writing { writer.cancelWriting() } }

        // Pump video and audio concurrently — both run in-process with security-scoped access
        try await withThrowingTaskGroup(of: Void.self) { group in
            let rv = readerVideo
            let wv = writerVideo
            let w  = writer
            group.addTask { try await VideoEncoder.pumpOutput(rv, to: wv, writer: w) }
            let ra = readerAudio
            let wa = writerAudio
            group.addTask { try await VideoEncoder.pumpOutput(ra, to: wa, writer: w) }
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
    /// writer is checked before each append — appending to a failed writer raises NSException.
    private static func pumpOutput(
        _ output: AVAssetReaderOutput?,
        to input: AVAssetWriterInput?,
        writer: AVAssetWriter
    ) async throws {
        guard let output, let input else { return }
        while let buf = output.copyNextSampleBuffer() {
            guard writer.status == .writing else { break }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard writer.status == .writing else { break }
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

