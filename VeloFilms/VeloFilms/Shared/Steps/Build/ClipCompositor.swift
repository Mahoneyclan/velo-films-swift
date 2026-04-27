import Foundation
import AVFoundation
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Assembles each clip's HUD overlay using AVFoundation custom compositing.
/// Replaces the FFmpeg filter_complex pipeline from clip_renderer.py.
struct ClipCompositor {
    let outputDir: URL

    /// Render a single clip with PiP, map, elevation, and gauge overlays.
    func renderClip(
        mainRow:      EnrichRow,
        pipRow:       EnrichRow?,
        minimapPath:  URL,
        elevationPath: URL,
        gaugeImages:  [CGImage],
        clipIndex:    Int
    ) async throws -> URL {
        let outputURL = outputDir.appending(
            path: String(format: "clip_%04d.mp4", clipIndex))

        // Load overlay images from disk
        guard let minimapImage  = loadCGImage(from: minimapPath),
              let elevImage     = loadCGImage(from: elevationPath) else {
            throw PipelineError.renderFailed("Could not load overlay images for clip \(clipIndex)")
        }

        let ts       = CMTimeScale(600)
        let tStart   = max(0.0, mainRow.absTimeEpoch - mainRow.clipStartEpoch - AppConfig.clipPreRollS)
        let duration = AppConfig.clipOutLenS
        let tStartCM = CMTimeMakeWithSeconds(tStart,    preferredTimescale: ts)
        let durCM    = CMTimeMakeWithSeconds(duration,  preferredTimescale: ts)
        let srcRange = CMTimeRange(start: tStartCM, duration: durCM)

        let composition = AVMutableComposition()

        // Main video track
        let mainAsset = AVURLAsset(url: URL(fileURLWithPath: mainRow.videoPath))
        guard let mainSrcVideo = try await mainAsset.loadTracks(withMediaType: .video).first else {
            throw PipelineError.renderFailed("No video track in \(mainRow.videoPath)")
        }
        let mainTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try mainTrack.insertTimeRange(srcRange, of: mainSrcVideo, at: .zero)

        // Main audio track (optional — not all clips have audio)
        if let mainSrcAudio = try? await mainAsset.loadTracks(withMediaType: .audio).first {
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try? audioTrack.insertTimeRange(srcRange, of: mainSrcAudio, at: .zero)
        }

        // PiP video track
        var pipTrackID: CMPersistentTrackID? = nil
        if let pip = pipRow {
            let pipStart   = max(0.0, pip.absTimeEpoch - pip.clipStartEpoch - AppConfig.clipPreRollS)
            let pipStartCM = CMTimeMakeWithSeconds(pipStart, preferredTimescale: ts)
            let pipRange   = CMTimeRange(start: pipStartCM, duration: durCM)
            let pipAsset   = AVURLAsset(url: URL(fileURLWithPath: pip.videoPath))
            if let pipSrcVideo = try? await pipAsset.loadTracks(withMediaType: .video).first {
                let pipTrack = composition.addMutableTrack(
                    withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
                try? pipTrack.insertTimeRange(pipRange, of: pipSrcVideo, at: .zero)
                pipTrackID = pipTrack.trackID
            }
        }

        // Custom video composition
        let instrRange = CMTimeRange(start: .zero, duration: durCM)
        let instruction = ClipCompositionInstruction(
            timeRange:    instrRange,
            mainTrackID:  mainTrack.trackID,
            pipTrackID:   pipTrackID,
            minimapImage: minimapImage,
            elevImage:    elevImage,
            gaugeImages:  gaugeImages
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = ClipVideoCompositor.self
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize    = CGSize(width:  AppConfig.HUD.outputW,
                                                height: AppConfig.HUD.outputH)
        videoComposition.instructions  = [instruction]

        // Audio mix — apply raw audio volume; loudnorm replaced by fixed gain
        var audioMix: AVAudioMix? = nil
        if let audioTrack = composition.tracks(withMediaType: .audio).first {
            let params = AVMutableAudioMixInputParameters(track: audioTrack)
            params.setVolume(Float(GlobalSettings.shared.rawAudioVolume), at: .zero)
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            audioMix = mix
        }

        try await VideoEncoder.export(
            composition:      composition,
            videoComposition: videoComposition,
            audioMix:         audioMix,
            to:               outputURL
        )
        return outputURL
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
