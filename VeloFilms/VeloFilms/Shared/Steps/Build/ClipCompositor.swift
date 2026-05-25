import Foundation
import AVFoundation
import CoreGraphics

/// Assembles each clip's HUD overlay.
/// macOS: FFmpegBridge filter_complex + loudnorm (mirrors clip_renderer.py).
/// iOS:   AVMutableComposition + ClipVideoCompositor (Metal GPU compositing, no FFmpeg).
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
        // iOS: AVMutableComposition + ClipVideoCompositor (Metal GPU compositing, no FFmpeg)
        let ts         = CMTimeScale(600)
        let tStartMain = max(0.0, mainRow.absTimeEpoch - mainRow.clipStartEpoch - AppConfig.clipPreRollS)
        let duration   = AppConfig.clipOutLenS
        let startCM    = CMTimeMakeWithSeconds(tStartMain, preferredTimescale: ts)
        let durCM      = CMTimeMakeWithSeconds(duration,   preferredTimescale: ts)
        let srcRange   = CMTimeRange(start: startCM, duration: durCM)

        guard let minimapCG = IntroBuilder.loadCGImage(from: minimapPath),
              let elevCG    = IntroBuilder.loadCGImage(from: elevationPath) else {
            throw PipelineError.renderFailed("ClipCompositor: could not load overlay PNGs")
        }

        // Load gauge frames from the pre-rendered PNG sequence
        let numFrames = Int(ceil(AppConfig.clipOutLenS)) + 1
        var gaugeImages: [CGImage] = []
        for i in 1...numFrames {
            let url = gaugeDir.appending(path: String(format: "gauge_%04d.png", i))
            if let cg = IntroBuilder.loadCGImage(from: url) { gaugeImages.append(cg) }
        }
        guard !gaugeImages.isEmpty else {
            throw PipelineError.renderFailed(
                "ClipCompositor: no gauge frames in \(gaugeDir.lastPathComponent)")
        }

        let composition = AVMutableComposition()
        let mainAsset   = AVURLAsset(url: URL(fileURLWithPath: mainRow.videoPath))

        guard let mainVSrc = try await mainAsset.loadTracks(withMediaType: .video).first else {
            throw PipelineError.renderFailed("ClipCompositor: no video track in main clip")
        }
        guard let mainTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw PipelineError.renderFailed("ClipCompositor: failed to add main video track")
        }
        try mainTrack.insertTimeRange(srcRange, of: mainVSrc, at: .zero)

        var pipTrackID: CMPersistentTrackID? = nil
        if let pip = pipRow {
            let tStartPip = max(0.0, pip.absTimeEpoch - pip.clipStartEpoch - AppConfig.clipPreRollS)
            let pipStart  = CMTimeMakeWithSeconds(tStartPip, preferredTimescale: ts)
            let pipRange  = CMTimeRange(start: pipStart, duration: durCM)
            let pipAsset  = AVURLAsset(url: URL(fileURLWithPath: pip.videoPath))
            if let pipVSrc = try? await pipAsset.loadTracks(withMediaType: .video).first,
               let pipTrack = composition.addMutableTrack(
                   withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try? pipTrack.insertTimeRange(pipRange, of: pipVSrc, at: .zero)
                pipTrackID = pipTrack.trackID
            }
        }

        // Camera audio at raw volume (no loudnorm available on iOS)
        var audioParams: [AVMutableAudioMixInputParameters] = []
        if let mainASrc = try? await mainAsset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioTrack.insertTimeRange(srcRange, of: mainASrc, at: .zero)
            let params = AVMutableAudioMixInputParameters(track: audioTrack)
            params.setVolume(Float(GlobalSettings.shared.rawAudioVolume), at: .zero)
            audioParams.append(params)
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParams

        let instrRange  = CMTimeRange(start: .zero, duration: durCM)
        let instruction = ClipCompositionInstruction(
            timeRange:    instrRange,
            mainTrackID:  mainTrack.trackID,
            pipTrackID:   pipTrackID,
            minimapImage: minimapCG,
            elevImage:    elevCG,
            gaugeImages:  gaugeImages
        )

        var compCfg = AVVideoComposition.Configuration(
            frameDuration: CMTime(value: 1, timescale: 30),
            instructions: [instruction],
            renderSize: CGSize(width: AppConfig.HUD.outputW, height: AppConfig.HUD.outputH)
        )
        compCfg.customVideoCompositorClass = ClipVideoCompositor.self
        let videoComp = AVVideoComposition(configuration: compCfg)

        try await VideoEncoder.exportInProcess(composition: composition,
                                              videoComposition: videoComp,
                                              audioMix: audioMix,
                                              to: outputURL)
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
