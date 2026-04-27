import Foundation
import AVFoundation
import CoreGraphics
import CoreImage
import Metal
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders a single clip using AVAssetReader + AVAssetWriter.
/// Reads decoded frames from source video(s), composites HUD overlays with CIImage,
/// and writes H.264 output — no custom AVVideoCompositing involved.
struct ClipCompositor {
    let outputDir: URL

    func renderClip(
        mainRow:       EnrichRow,
        pipRow:        EnrichRow?,
        minimapPath:   URL,
        elevationPath: URL,
        gaugeImages:   [CGImage],
        clipIndex:     Int
    ) async throws -> URL {
        let outputURL = outputDir.appending(
            path: String(format: "clip_%04d.mp4", clipIndex))
        try? FileManager.default.removeItem(at: outputURL)

        guard let minimapImage = loadCGImage(from: minimapPath),
              let elevImage    = loadCGImage(from: elevationPath) else {
            throw PipelineError.renderFailed(
                "Could not load overlay images for clip \(clipIndex)")
        }

        let ts       = CMTimeScale(600)
        let tStart   = max(0.0, mainRow.absTimeEpoch - mainRow.clipStartEpoch
                                - AppConfig.clipPreRollS)
        let duration = AppConfig.clipOutLenS

        let mainAsset  = AVURLAsset(url: URL(fileURLWithPath: mainRow.videoPath))
        let fileDur    = try await mainAsset.load(.duration)

        // Clamp range so we never seek past EOF
        let tStartCM     = CMTimeMakeWithSeconds(tStart,    preferredTimescale: ts)
        let durCM        = CMTimeMakeWithSeconds(duration,  preferredTimescale: ts)
        let clampedStart = CMTimeMinimum(tStartCM, CMTimeMaximum(.zero, fileDur - durCM))
        let clampedDur   = CMTimeMinimum(durCM, fileDur - clampedStart)
        let srcRange     = CMTimeRange(start: clampedStart, duration: clampedDur)

        guard let mainVideoTrack =
            try await mainAsset.loadTracks(withMediaType: .video).first else {
            throw PipelineError.renderFailed("No video track in \(mainRow.videoPath)")
        }

        let W = AppConfig.HUD.outputW, H = AppConfig.HUD.outputH

        // Metal-backed CIContext (falls back to CPU if Metal unavailable)
        let ciCtx: CIContext = {
            if let dev = MTLCreateSystemDefaultDevice() {
                return CIContext(mtlDevice: dev,
                                options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
            }
            return CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        }()

        // MARK: - AVAssetWriter

        let videoSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  W,
            AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: AppConfig.Encoding.videoBitrate,
            ],
        ]
        let writer     = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video,
                                            outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: W,
                kCVPixelBufferHeightKey as String: H,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ]
        )
        writer.add(videoInput)

        // Audio passthrough input (nil settings = copy compressed AAC from source)
        var audioInput: AVAssetWriterInput? = nil
        if (try? await mainAsset.loadTracks(withMediaType: .audio).first) != nil {
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            ai.expectsMediaDataInRealTime = false
            writer.add(ai)
            audioInput = ai
        }

        writer.startWriting()
        // startSession(atSourceTime:) maps clampedStart → 0 in the output file
        writer.startSession(atSourceTime: clampedStart)

        // MARK: - PiP reader (optional, runs in lockstep with main)

        var pipReader: AVAssetReader? = nil
        var pipOutput: AVAssetReaderTrackOutput? = nil

        if let pip = pipRow {
            let pipStart  = max(0.0, pip.absTimeEpoch - pip.clipStartEpoch
                                    - AppConfig.clipPreRollS)
            let pipAsset  = AVURLAsset(url: URL(fileURLWithPath: pip.videoPath))
            let pipFileDur = (try? await pipAsset.load(.duration)) ?? clampedDur
            let pipStartCM = CMTimeMakeWithSeconds(pipStart, preferredTimescale: ts)
            let pipCS      = CMTimeMinimum(pipStartCM,
                                           CMTimeMaximum(.zero, pipFileDur - clampedDur))
            let pipRange   = CMTimeRange(start: pipCS, duration: clampedDur)

            if let pipTrack = try? await pipAsset.loadTracks(withMediaType: .video).first,
               let pr = try? AVAssetReader(asset: pipAsset) {
                let po = AVAssetReaderTrackOutput(track: pipTrack, outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                ])
                po.alwaysCopiesSampleData = false
                pr.add(po); pr.timeRange = pipRange; pr.startReading()
                pipReader = pr; pipOutput = po
            }
        }

        // MARK: - Phase 1: Video decode → composite → encode

        let mainReader  = try AVAssetReader(asset: mainAsset)
        let videoOutput = AVAssetReaderTrackOutput(track: mainVideoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        videoOutput.alwaysCopiesSampleData = false
        mainReader.add(videoOutput)
        mainReader.timeRange = srcRange

        guard mainReader.startReading() else {
            throw PipelineError.renderFailed(
                "AVAssetReader (video) failed to start for clip \(clipIndex): "
                + (mainReader.error?.localizedDescription ?? "unknown"))
        }

        while mainReader.status == .reading {
            guard videoInput.isReadyForMoreMediaData else { await Task.yield(); continue }
            guard let mainSample = videoOutput.copyNextSampleBuffer() else { break }
            guard let mainBuf    = CMSampleBufferGetImageBuffer(mainSample) else { continue }

            let pts     = CMSampleBufferGetPresentationTimeStamp(mainSample)
            let elapsed = max(0.0, (pts - clampedStart).seconds)
            let gaugeIdx = min(Int(elapsed), gaugeImages.count - 1)

            // Advance PiP reader one frame (lockstep — no PTS matching needed for 3.5s)
            var pipBuf: CVPixelBuffer? = nil
            if let pr = pipReader, let po = pipOutput, pr.status == .reading,
               let pipSample = po.copyNextSampleBuffer() {
                pipBuf = CMSampleBufferGetImageBuffer(pipSample)
            }

            guard let out = compositeFrame(
                main: mainBuf, pip: pipBuf,
                minimap: minimapImage, elev: elevImage,
                gauge: gaugeImages[gaugeIdx],
                width: W, height: H,
                pool: adaptor.pixelBufferPool,
                context: ciCtx
            ) else { continue }

            adaptor.append(out, withPresentationTime: pts)
        }

        videoInput.markAsFinished()

        if let err = mainReader.error {
            throw PipelineError.renderFailed(
                "Video reader error for clip \(clipIndex): \(err.localizedDescription)")
        }

        // MARK: - Phase 2: Audio passthrough

        if let ai = audioInput,
           let audioTrack = try? await mainAsset.loadTracks(withMediaType: .audio).first {
            let audioReader = try AVAssetReader(asset: mainAsset)
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack,
                                                        outputSettings: nil) // compressed passthrough
            audioOutput.alwaysCopiesSampleData = false
            audioReader.add(audioOutput)
            audioReader.timeRange = srcRange

            if audioReader.startReading() {
                while audioReader.status == .reading {
                    guard ai.isReadyForMoreMediaData else { await Task.yield(); continue }
                    guard let sample = audioOutput.copyNextSampleBuffer() else { break }
                    ai.append(sample)
                }
            }
        }
        audioInput?.markAsFinished()

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw PipelineError.renderFailed(
                "AVAssetWriter failed for clip \(clipIndex): "
                + (writer.error?.localizedDescription ?? "status \(writer.status.rawValue)"))
        }

        return outputURL
    }

    // MARK: - CIImage compositing

    private func compositeFrame(
        main: CVPixelBuffer, pip: CVPixelBuffer?,
        minimap: CGImage, elev: CGImage, gauge: CGImage,
        width: Int, height: Int,
        pool: CVPixelBufferPool?,
        context: CIContext
    ) -> CVPixelBuffer? {
        let W = CGFloat(width), H = CGFloat(height)

        var c = scaleAndPad(CIImage(cvPixelBuffer: main), toWidth: W, height: H)

        // PiP — partner camera, scaled to pipH, placed at (pipX, mapPipBottom)
        if let pipBuf = pip {
            let pipH  = CGFloat(AppConfig.HUD.pipH)
            let src   = CIImage(cvPixelBuffer: pipBuf)
            if src.extent.height > 0 {
            let scale = pipH / src.extent.height
            var p = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            p = p.transformed(by: CGAffineTransform(
                translationX: CGFloat(AppConfig.HUD.pipX),
                y:            CGFloat(AppConfig.HUD.mapPipBottom)))
            c = p.composited(over: c)
            }
        }

        // Minimap — 390×390 at (mapX, mapPipBottom)
        c = CIImage(cgImage: minimap)
            .transformed(by: CGAffineTransform(
                translationX: CGFloat(AppConfig.HUD.mapX),
                y:            CGFloat(AppConfig.HUD.mapPipBottom)))
            .composited(over: c)

        // Elevation strip — 948×75 at bottom (y=0)
        c = CIImage(cgImage: elev)
            .transformed(by: CGAffineTransform(
                translationX: CGFloat(AppConfig.HUD.elevX), y: 0))
            .composited(over: c)

        // Gauge strip — 972×194 at (gaugeX, mapPipBottom)
        c = CIImage(cgImage: gauge)
            .transformed(by: CGAffineTransform(
                translationX: CGFloat(AppConfig.HUD.gaugeX),
                y:            CGFloat(AppConfig.HUD.mapPipBottom)))
            .composited(over: c)

        // Allocate output buffer from pool (avoids per-frame malloc)
        var outBuf: CVPixelBuffer?
        if let pool = pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuf)
        } else {
            CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                kCVPixelFormatType_32BGRA,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                                &outBuf)
        }
        guard let out = outBuf else { return nil }

        context.render(c, to: out,
                       bounds: CGRect(x: 0, y: 0, width: W, height: H),
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        return out
    }

    private func scaleAndPad(_ image: CIImage, toWidth W: CGFloat, height H: CGFloat) -> CIImage {
        let src = image.extent
        guard src.width > 0, src.height > 0 else { return image }
        let scale = min(W / src.width, H / src.height)
        let offX  = (W - src.width  * scale) / 2
        let offY  = (H - src.height * scale) / 2
        let bg    = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: W, height: H))
        return image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offX, y: offY))
            .composited(over: bg)
    }

    // MARK: - Image loading

    private func loadCGImage(from url: URL) -> CGImage? {
#if os(macOS)
        guard let img = NSImage(contentsOf: url) else { return nil }
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
#else
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        return img.cgImage
#endif
    }
}
