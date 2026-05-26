import Foundation
import AVFoundation
import CoreGraphics
import CoreImage

/// Assembles each clip's HUD overlay.
/// macOS: FFmpegBridge filter_complex + loudnorm (mirrors clip_renderer.py).
/// iOS:   AVAssetImageGenerator frame extraction + CIImage compositing + AVAssetWriter.
struct ClipCompositor: Sendable {
#if os(macOS)
    let bridge: any FFmpegBridge
#endif
    let outputDir: URL

    @discardableResult
    func renderClip(
        mainRow:       EnrichRow,
        pipRow:        EnrichRow?,
        minimapPath:   URL,
        elevationPath: URL,
        gaugeDir:      URL,
        clipIndex:     Int
    ) async throws -> URL {
        let outputURL = outputDir.appending(path: String(format: "clip_%04d.mp4", clipIndex))

#if os(macOS)
        let tStartMain = max(0.0, mainRow.absTimeEpoch - mainRow.clipStartEpoch - AppConfig.clipPreRollS)
        let duration   = AppConfig.clipOutLenS

        // -framerate 1 must appear before -i when using an image sequence
        var inputs: [String] = [
            "-ss", String(tStartMain), "-t", String(duration), "-i", mainRow.videoPath,
        ]

        let filterComplex: String
        if let pip = pipRow {
            let tStartPip = max(0.0, pip.absTimeEpoch - pip.clipStartEpoch - AppConfig.clipPreRollS)
            inputs += ["-ss", String(tStartPip), "-t", String(duration), "-i", pip.videoPath]
            // map=2, elev=3, gauge=4
            inputs += ["-i", minimapPath.path,
                       "-i", elevationPath.path,
                       "-framerate", "1", "-i", gaugeDir.appending(path: "gauge_%04d.png").path]
            filterComplex = Self.filterComplexWithPiP(mapIdx: 2, elevIdx: 3, gaugeIdx: 4)
        } else {
            // map=1, elev=2, gauge=3
            inputs += ["-i", minimapPath.path,
                       "-i", elevationPath.path,
                       "-framerate", "1", "-i", gaugeDir.appending(path: "gauge_%04d.png").path]
            filterComplex = Self.filterComplexNoPiP(mapIdx: 1, elevIdx: 2, gaugeIdx: 3)
        }

        let args: [String] = inputs + [
            "-filter_complex", filterComplex,
            "-map", "[vhud]", "-map", "[anorm]",
            "-c:v", AppConfig.Encoding.videoCodec,
            "-b:v", "\(AppConfig.Encoding.videoBitrate / 1000)k",
            "-c:a", "aac", "-b:a", "\(AppConfig.Encoding.audioBitrate / 1000)k",
            "-movflags", "+faststart",
            "-y", outputURL.path,
        ]

        try await bridge.execute(arguments: args)

#else
        // iOS: AVAssetImageGenerator decodes frames in-process via VTDecompressionSession.
        // AVAssetReader (both direct and composition-wrapped) routes through mediaserverd XPC
        // which is sandboxed from security-scoped external drive URLs. AVAssetImageGenerator
        // uses a different code path — confirmed working in the Extract step.
        let fps      = 30
        let duration = AppConfig.clipOutLenS
        let ts       = CMTimeScale(600)
        let W        = AppConfig.HUD.outputW
        let H        = AppConfig.HUD.outputH

        let tStartMain = max(0.0, mainRow.absTimeEpoch - mainRow.clipStartEpoch - AppConfig.clipPreRollS)
        let segRange   = CMTimeRange(
            start:    CMTimeMakeWithSeconds(tStartMain, preferredTimescale: ts),
            duration: CMTimeMakeWithSeconds(duration,   preferredTimescale: ts))

        let mainGen = Self.makeGenerator(
            for: Self.reanchorSourceURL(mainRow.videoPath),
            sourceRange: segRange, maxSize: CGSize(width: W, height: H), fps: fps)

        var pipGen: AVAssetImageGenerator? = nil
        if let pip = pipRow {
            let tStartPip   = max(0.0, pip.absTimeEpoch - pip.clipStartEpoch - AppConfig.clipPreRollS)
            let pipSegRange = CMTimeRange(
                start:    CMTimeMakeWithSeconds(tStartPip, preferredTimescale: ts),
                duration: CMTimeMakeWithSeconds(duration,  preferredTimescale: ts))
            pipGen = Self.makeGenerator(
                for: Self.reanchorSourceURL(pip.videoPath),
                sourceRange: pipSegRange,
                maxSize: CGSize(width: AppConfig.HUD.pipH * 2, height: AppConfig.HUD.pipH),
                fps: fps)
        }

        // Load static overlay images
        guard let minimapCG = IntroBuilder.loadCGImage(from: minimapPath),
              let elevCG    = IntroBuilder.loadCGImage(from: elevationPath) else {
            throw PipelineError.renderFailed("ClipCompositor: could not load overlay PNGs")
        }
        let numGaugeFrames = Int(ceil(AppConfig.clipOutLenS)) + 1
        var gaugeImages: [CGImage] = []
        for i in 1...numGaugeFrames {
            let url = gaugeDir.appending(path: String(format: "gauge_%04d.png", i))
            if let cg = IntroBuilder.loadCGImage(from: url) { gaugeImages.append(cg) }
        }
        guard !gaugeImages.isEmpty else {
            throw PipelineError.renderFailed(
                "ClipCompositor: no gauge frames in \(gaugeDir.lastPathComponent)")
        }
        let minimapCI = CIImage(cgImage: minimapCG)
            .transformed(by: CGAffineTransform(translationX: CGFloat(AppConfig.HUD.mapX),
                                                y: CGFloat(AppConfig.HUD.mapPipBottom)))
        let elevCI = CIImage(cgImage: elevCG)
            .transformed(by: CGAffineTransform(translationX: CGFloat(AppConfig.HUD.elevX), y: 0))
        let gaugeCIs: [CIImage] = gaugeImages.map { cg in
            CIImage(cgImage: cg).transformed(by: CGAffineTransform(
                translationX: CGFloat(AppConfig.HUD.gaugeX),
                y: CGFloat(AppConfig.HUD.mapPipBottom)))
        }

        // Write video to iosTmp so exportInProcess (AVAssetReader) can access it.
        // AVAssetReader routes through mediaserverd which can't open external-drive URLs.
        let iosTmp    = FileManager.default.temporaryDirectory
        let tmpVidURL = iosTmp.appending(path: String(format: "clip_vid_%04d.mp4", clipIndex))
        try? FileManager.default.removeItem(at: tmpVidURL)
        let writer = try AVAssetWriter(outputURL: tmpVidURL, fileType: .mp4)
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
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerVideo,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: W,
                kCVPixelBufferHeightKey as String: H,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
        )
        writer.add(writerVideo)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        defer { if writer.status == .writing { writer.cancelWriting() } }

        let ciCtx: CIContext = {
            if let dev = MTLCreateSystemDefaultDevice() {
                return CIContext(mtlDevice: dev,
                                  options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
            }
            return CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        }()
        let outBounds = CGRect(x: 0, y: 0, width: CGFloat(W), height: CGFloat(H))
        let frameDur  = CMTime(value: CMTimeValue(ts / CMTimeScale(fps)), timescale: ts)
        let pbAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey  as String: W,
            kCVPixelBufferHeightKey as String: H,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]

        let frameCount = Int(duration * Double(fps))
        var framesWritten = 0
        for i in 0..<frameCount {
            let t = CMTimeMakeWithSeconds(Double(i) / Double(fps), preferredTimescale: ts)

            guard let mainCG = (try? await mainGen.image(at: t))?.image else { continue }
            var comp = Self.scaleAndPadCI(CIImage(cgImage: mainCG),
                                           toWidth: CGFloat(W), height: CGFloat(H))

            if let pg = pipGen,
               let pipCG = (try? await pg.image(at: t))?.image {
                let pipH  = CGFloat(AppConfig.HUD.pipH)
                let src   = CIImage(cgImage: pipCG)
                let scale = pipH / src.extent.height
                comp = src
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .transformed(by: CGAffineTransform(
                        translationX: CGFloat(AppConfig.HUD.pipX), y: 0))
                    .composited(over: comp)
            }

            comp = minimapCI.composited(over: comp)
            comp = elevCI.composited(over: comp)
            comp = gaugeCIs[min(i / fps, gaugeCIs.count - 1)].composited(over: comp)

            var pb: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, W, H, kCVPixelFormatType_32BGRA,
                                       pbAttrs as CFDictionary, &pb) == kCVReturnSuccess,
                  let pixelBuffer = pb else { continue }
            ciCtx.render(comp, to: pixelBuffer, bounds: outBounds,
                          colorSpace: CGColorSpaceCreateDeviceRGB())

            while !writerVideo.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            adaptor.append(pixelBuffer,
                            withPresentationTime: CMTimeMultiply(frameDur, multiplier: Int32(i)))
            framesWritten += 1
        }

        guard framesWritten > 0 else {
            let mapped = Self.reanchorSourceURL(mainRow.videoPath).path(percentEncoded: false)
            throw PipelineError.renderFailed(
                "ClipCompositor: zero frames decoded — check source URL mapping. " +
                "Mapped path: \(mapped)")
        }

        writerVideo.markAsFinished()
        await writer.finishWriting()
        if let err = writer.error { throw err }
        guard writer.status == .completed else {
            throw PipelineError.renderFailed("ClipCompositor: writer status \(writer.status.rawValue)")
        }

        // Cycliq raw audio is not used in iOS output — ConcatStep builds the middle via
        // AVAssetImageGenerator (video-only) then mixes backing music separately.
        // Attempting to pass Cycliq audio through AVAssetReaderAudioMixOutput triggers
        // AudioFormatDescription err=-12710 (malformed AudioSpecificConfig in esds box)
        // which causes reader.startReading() to fail even when format desc creation succeeds.
        // Produce a video-only clip; ConcatStep adds music in its own pass.
        let durCM = CMTimeMakeWithSeconds(duration, preferredTimescale: ts)
        let comp  = AVMutableComposition()
        if let vt = comp.addMutableTrack(withMediaType: .video,
                                          preferredTrackID: kCMPersistentTrackID_Invalid) {
            vt.segments = [AVCompositionTrackSegment(
                url: tmpVidURL, trackID: 1,
                sourceTimeRange: CMTimeRange(start: .zero, duration: durCM),
                targetTimeRange: CMTimeRange(start: .zero, duration: durCM))]
        }

        try? FileManager.default.removeItem(at: outputURL)
        try await VideoEncoder.exportInProcess(composition: comp, to: outputURL)
        try? FileManager.default.removeItem(at: tmpVidURL)
#endif
        return outputURL
    }

    // MARK: - Filter complex strings (FFmpeg / macOS only)

    private static func filterComplexWithPiP(mapIdx: Int, elevIdx: Int, gaugeIdx: Int) -> String {
        let H = AppConfig.HUD.self
        let t = AppConfig.loudnormTarget, tp = AppConfig.loudnormTP, lra = AppConfig.loudnormLRA
        return
            "[0:v]scale=\(H.outputW):\(H.outputH):force_original_aspect_ratio=decrease," +
            "pad=\(H.outputW):\(H.outputH):(ow-iw)/2:(oh-ih)/2[vmain];" +
            "[1:v]scale=-1:\(H.pipH)[pipsc];" +
            "[vmain][pipsc]overlay=\(H.pipX):\(H.pipY)[v1];" +
            "[v1][\(mapIdx):v]overlay=\(H.mapX):H-h-\(H.mapPipBottom)[vmap];" +
            "[vmap][\(elevIdx):v]overlay=\(H.elevX):H-h[velev];" +
            "[velev][\(gaugeIdx):v]overlay=\(H.gaugeX):H-h-\(H.mapPipBottom)[vhud];" +
            "[0:a]loudnorm=I=\(t):TP=\(tp):LRA=\(lra)[anorm]"
    }

    private static func filterComplexNoPiP(mapIdx: Int, elevIdx: Int, gaugeIdx: Int) -> String {
        let H = AppConfig.HUD.self
        let t = AppConfig.loudnormTarget, tp = AppConfig.loudnormTP, lra = AppConfig.loudnormLRA
        return
            "[0:v]scale=\(H.outputW):\(H.outputH):force_original_aspect_ratio=decrease," +
            "pad=\(H.outputW):\(H.outputH):(ow-iw)/2:(oh-ih)/2[vmain];" +
            "[vmain][\(mapIdx):v]overlay=\(H.mapX):H-h-\(H.mapPipBottom)[vmap];" +
            "[vmap][\(elevIdx):v]overlay=\(H.elevX):H-h[velev];" +
            "[velev][\(gaugeIdx):v]overlay=\(H.gaugeX):H-h-\(H.mapPipBottom)[vhud];" +
            "[0:a]loudnorm=I=\(t):TP=\(tp):LRA=\(lra)[anorm]"
    }
}

// MARK: - iOS frame-extraction helpers

#if os(iOS)
extension ClipCompositor {

    /// Re-derives a file URL from one of the bookmark-resolved parent URLs stored in
    /// GlobalSettings so the result inherits the parent's active security scope,
    /// which FileHandle requires to open files on an external drive on iOS.
    ///
    /// On iOS, external drives mount at /private/var/mobile/Library/LiveFiles/{UUID}/...
    /// but paths are stored in JSONL as macOS /Volumes/DriveName/... paths. A plain
    /// prefix match fails cross-platform, so we also try anchoring on the parent's
    /// last path component (e.g. "Fly_Raw") found anywhere in the stored path string.
    static func reanchorSourceURL(_ path: String) -> URL {
        let gs = GlobalSettings.shared
        let candidates = [gs.fly12SourceURL, gs.fly6SourceURL, gs.inputBaseDir].compactMap { $0 }
        for parent in candidates {
            let parentPath = parent.path(percentEncoded: false)

            // Exact prefix match — works when macOS source paths are used on macOS.
            if path.hasPrefix(parentPath) {
                let relative = String(path.dropFirst(parentPath.count)).drop(while: { $0 == "/" })
                if !relative.isEmpty {
                    return parent.appending(path: String(relative))
                }
                return parent
            }

            // Cross-platform anchor match — on iOS the drive mounts at a different root
            // than the /Volumes path stored in JSONL. Locate the parent's last component
            // in the stored path and use everything after it as the relative sub-path.
            let anchor = parent.lastPathComponent
            if !anchor.isEmpty {
                let needle = "/\(anchor)/"
                if let r = path.range(of: needle) {
                    let relative = String(path[r.upperBound...])
                    if !relative.isEmpty {
                        return parent.appending(path: relative)
                    }
                }
            }
        }
        return URL(fileURLWithPath: path)
    }

    /// Builds an AVAssetImageGenerator for [sourceRange] of [url], wrapped in a composition
    /// so decoding stays in-process (AVAssetReader routes through mediaserverd and fails
    /// for security-scoped external-drive URLs; AVAssetImageGenerator does not).
    /// Composition times start at zero; callers request frames at 0, 1/fps, 2/fps, ...
    static func makeGenerator(
        for url: URL,
        sourceRange: CMTimeRange,
        maxSize: CGSize,
        fps: Int
    ) -> AVAssetImageGenerator {
        let comp = AVMutableComposition()
        if let track = comp.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            track.segments = [AVCompositionTrackSegment(
                url: url, trackID: 1,
                sourceTimeRange: sourceRange,
                targetTimeRange: CMTimeRange(start: .zero, duration: sourceRange.duration)
            )]
        }
        let gen = AVAssetImageGenerator(asset: comp)
        gen.maximumSize = maxSize
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: CMTimeScale(fps))
        gen.requestedTimeToleranceAfter  = CMTime(value: 1, timescale: CMTimeScale(fps))
        return gen
    }

    /// Extracts [fps × duration] frames from [url] starting at [startTime] seconds.
    /// Returns a map of frame-index → CGImage; missing frames are absent from the map.
    ///
    /// Uses AVMutableComposition + AVCompositionTrackSegment so the image generator
    /// already knows the track structure without an XPC metadata round-trip.
    static func batchExtractFrames(
        from url: URL,
        startTime: Double,
        duration: Double,
        fps: Int,
        maxSize: CGSize
    ) async -> [Int: CGImage] {
        let frameCount = Int(duration * Double(fps))
        guard frameCount > 0 else { return [:] }

        let ts    = CMTimeScale(600)
        let durCM = CMTimeMakeWithSeconds(duration,  preferredTimescale: ts)
        let srcCM = CMTimeMakeWithSeconds(startTime, preferredTimescale: ts)

        // Composition maps source range → [0, duration) so generator uses composition
        // track info (no XPC) and we request frames at composition-relative times.
        let comp = AVMutableComposition()
        guard let vt = comp.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return [:]
        }
        vt.segments = [AVCompositionTrackSegment(
            url: url, trackID: 1,
            sourceTimeRange: CMTimeRange(start: srcCM, duration: durCM),
            targetTimeRange: CMTimeRange(start: .zero, duration: durCM)
        )]

        let gen = AVAssetImageGenerator(asset: comp)
        gen.maximumSize                    = maxSize
        gen.requestedTimeToleranceBefore   = CMTime(value: 1, timescale: 60)
        gen.requestedTimeToleranceAfter    = CMTime(value: 1, timescale: 60)
        gen.appliesPreferredTrackTransform = true

        // Frame times in composition coordinates: 0, 1/fps, 2/fps, ...
        let times: [NSValue] = (0..<frameCount).map { i in
            NSValue(time: CMTimeMakeWithSeconds(Double(i) / Double(fps), preferredTimescale: ts))
        }

        // Pre-compute ms-precision keys for O(1) lookup in completion handler
        var indexMap: [Int: Int] = [:]
        for (i, v) in times.enumerated() {
            indexMap[Int(round(v.timeValue.seconds * 1000))] = i
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<[Int: CGImage], Never>) in
            final class State: @unchecked Sendable {
                let lock      = NSLock()
                var result    = [Int: CGImage]()
                var remaining: Int
                init(_ n: Int) { remaining = n }
            }
            let state = State(times.count)

            gen.generateCGImagesAsynchronously(forTimes: times) { reqTime, image, _, _, _ in
                state.lock.lock()
                if let cg = image {
                    let ms = Int(round(reqTime.seconds * 1000))
                    if let idx = indexMap[ms] { state.result[idx] = cg }
                }
                state.remaining -= 1
                let done = state.remaining == 0
                state.lock.unlock()
                if done { cont.resume(returning: state.result) }
            }
        }
    }

    /// Scales and letter-boxes [image] into a [W]×[H] black canvas (CIImage coords: y=0 at bottom).
    static func scaleAndPadCI(_ image: CIImage, toWidth W: CGFloat, height H: CGFloat) -> CIImage {
        let src   = image.extent
        let scale = min(W / src.width, H / src.height)
        let bg    = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: W, height: H))
        return image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: (W - src.width  * scale) / 2,
                y:            (H - src.height * scale) / 2))
            .composited(over: bg)
    }
}
#endif
