import Foundation
import AVFoundation
import CoreGraphics
import QuartzCore

/// Builds _outro.mp4: frame collage + animated "Velo Films" text → fade to black.
/// Mirrors outro_builder.py. drawtext replaced with CATextLayer via AVVideoCompositionCoreAnimationTool.
enum OutroBuilder {

    static func build(project: Project,
                      selectRows: [SelectRow],
                      flattenRows: [FlattenRow]) async throws {
        let outputURL = project.clipsDir.appending(path: "_outro.mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let assetsDir = project.splashAssetsDir
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let W = AppConfig.HUD.outputW, H = AppConfig.HUD.outputH
        let bannerH = AppConfig.bannerHeight

        let collagePNG = assetsDir.appending(path: "outro_collage.png")
        let frames = IntroBuilder.collectFrames(from: project.framesDir,
                                                selectRows: selectRows, max: 24)
        let stats  = IntroBuilder.computeRideStats(flattenRows: flattenRows)
        try IntroBuilder.renderCollage(frames: frames, outputURL: collagePNG,
                                       width: W, height: H, bannerHeight: bannerH,
                                       stats: stats, project: project)

        guard let collageCG = IntroBuilder.loadCGImage(from: collagePNG) else {
            throw PipelineError.renderFailed("OutroBuilder: could not load collage PNG")
        }

        let outroDuration = 3.7
        let titleAppear   = 1.0
        let titleFadeIn   = 0.5
        let fadeOutStart  = 3.0
        let fadeOutDur    = 0.7

        // 1. Encode collage still (no text yet — text added via CoreAnimation)
        let collageRaw = assetsDir.appending(path: "outro_collage_raw.mp4")
        try await VideoEncoder.encodeStill(image: collageCG, duration: outroDuration,
                                           outputURL: collageRaw)

        // 2. Add animated "Velo Films" text overlay using AVVideoCompositionCoreAnimationTool
        let collageClip = assetsDir.appending(path: "outro_collage.mp4")
        try await addTextOverlay(
            videoURL:     collageRaw,
            outputURL:    collageClip,
            text:         "Velo Films",
            fontSize:     CGFloat(160 * W / 2560),
            width: W, height: H,
            titleAppear:  titleAppear,
            titleFadeIn:  titleFadeIn,
            fadeOutStart: fadeOutStart,
            fadeOutDur:   fadeOutDur,
            totalDur:     outroDuration
        )
        try? FileManager.default.removeItem(at: collageRaw)

        // 3. Build a black clip (solid black CGImage encoded as still)
        let blackDur  = 2.0
        let blackClip = assetsDir.appending(path: "outro_black.mp4")
        let blackImg  = makeBlackImage(width: W, height: H)
        try await VideoEncoder.encodeStill(image: blackImg, duration: blackDur,
                                           outputURL: blackClip)

        // 4. Cross-dissolve collage → black
        let rawURL = assetsDir.appending(path: "outro_raw.mp4")
        try await IntroBuilder.crossDissolveChain(
            clips:    [collageClip, blackClip],
            clipDur:  outroDuration,   // first clip duration
            xfadeDur: fadeOutDur,
            outputURL: rawURL
        )

        // 5. Add music or keep silent
        let totalDur = outroDuration + blackDur - fadeOutDur
        if let musicURL = IntroBuilder.findResourceAudio(named: "outro") {
            try await IntroBuilder.mixAudio(videoURL: rawURL, musicURL: musicURL,
                                            duration: totalDur, musicVolume: 0.85,
                                            outputURL: outputURL)
            try? FileManager.default.removeItem(at: rawURL)
        } else {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.moveItem(at: rawURL, to: outputURL)
        }
    }

    // MARK: - Text overlay via AVVideoCompositionCoreAnimationTool

    private static func addTextOverlay(
        videoURL:    URL,
        outputURL:   URL,
        text:        String,
        fontSize:    CGFloat,
        width: Int, height: Int,
        titleAppear:  Double,
        titleFadeIn:  Double,
        fadeOutStart: Double,
        fadeOutDur:   Double,
        totalDur:     Double
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let ts    = CMTimeScale(600)
        let durCM = CMTimeMakeWithSeconds(totalDur, preferredTimescale: ts)

        let asset       = AVURLAsset(url: videoURL)
        let composition = AVMutableComposition()

        guard let srcVideo = try? await asset.loadTracks(withMediaType: .video).first else {
            throw PipelineError.renderFailed("OutroBuilder: no video track in collage clip")
        }
        let vTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try vTrack.insertTimeRange(CMTimeRange(start: .zero, duration: durCM), of: srcVideo, at: .zero)

        // CoreAnimation layer tree
        let W = CGFloat(width), H = CGFloat(height)

        // Video layer — AVVideoCompositionCoreAnimationTool renders into this
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(x: 0, y: 0, width: W, height: H)

        // Text layer with animated opacity
        let textLayer        = CATextLayer()
        textLayer.string     = text
        textLayer.fontSize   = fontSize
        textLayer.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        textLayer.alignmentMode   = .center
        textLayer.frame      = CGRect(x: 0, y: H / 2 - fontSize, width: W, height: fontSize * 2)
        textLayer.opacity    = 0

        // Shadow
        textLayer.shadowColor   = CGColor(red: 0, green: 0, blue: 0, alpha: 0.7)
        textLayer.shadowOffset  = CGSize(width: 4, height: -4)
        textLayer.shadowRadius  = 3
        textLayer.shadowOpacity = 1

        // Fade in: opacity 0→1 from titleAppear to titleAppear+titleFadeIn
        let fadeIn           = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue     = 0.0
        fadeIn.toValue       = 1.0
        fadeIn.beginTime     = AVCoreAnimationBeginTimeAtZero + titleAppear
        fadeIn.duration      = titleFadeIn
        fadeIn.fillMode      = .forwards
        fadeIn.isRemovedOnCompletion = false
        textLayer.add(fadeIn, forKey: "fadeIn")

        let parentLayer     = CALayer()
        parentLayer.frame   = CGRect(x: 0, y: 0, width: W, height: H)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(textLayer)

        // Fade out entire frame: fade out of the parent via video composition instruction
        // (handled by crossDissolveChain xfade to black, so no additional fade needed here)

        let videoComp = AVMutableVideoComposition()
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)
        videoComp.renderSize    = CGSize(width: W, height: H)
        videoComp.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let instr    = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: durCM)
        instr.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)]
        videoComp.instructions = [instr]

        try await VideoEncoder.export(composition: composition,
                                      videoComposition: videoComp,
                                      to: outputURL)
    }

    // MARK: - Black frame

    private static func makeBlackImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }
}
