import Foundation
import CoreGraphics

/// Builds _outro.mp4: frame collage + animated "Velo Films" text → fade to black.
/// Mirrors outro_builder.py.
enum OutroBuilder {

    static func build(project: Project,
                      selectRows: [SelectRow],
                      flattenRows: [FlattenRow],
                      bridge: any FFmpegBridge) async throws {
        let outputURL = project.clipsDir.appending(path: "_outro.mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let assetsDir = project.splashAssetsDir
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let W = AppConfig.HUD.outputW, H = AppConfig.HUD.outputH
        let bannerH = AppConfig.bannerHeight
        let enc = AppConfig.Encoding.self

        // Build outro collage PNG from recommended frames
        let collagePNG = assetsDir.appending(path: "outro_collage.png")
        let frames = IntroBuilder.collectFrames(from: project.framesDir, selectRows: selectRows, max: 24)
        let stats = IntroBuilder.computeRideStats(flattenRows: flattenRows)
        try IntroBuilder.renderCollage(frames: frames, outputURL: collagePNG,
                                       width: W, height: H, bannerHeight: bannerH,
                                       stats: stats, project: project)

        let outroDuration = 3.7
        let titleAppear  = 1.0
        let titleFadeIn  = 0.5
        let fadeOutStart = 3.0
        let fadeOutD     = 0.7

        let alphaExpr =
            "if(lt(t,\(titleAppear)),0," +
            "if(lt(t,\(titleAppear + titleFadeIn))," +
            "(t-\(titleAppear))/\(titleFadeIn),1))"

        let titleFontSize = 160 * W / 2560
        let drawtext =
            "drawtext=text='Velo Films':" +
            "x=(w-text_w)/2:y=(h-text_h)/2:" +
            "fontsize=\(titleFontSize):fontcolor=white:" +
            "bordercolor=black@0.45:borderw=6:" +
            "shadowcolor=black@0.7:shadowx=4:shadowy=4:" +
            "alpha='\(alphaExpr)'"

        let vf = "scale=\(W):\(H):force_original_aspect_ratio=decrease," +
                 "pad=\(W):\(H):(ow-iw)/2:(oh-ih)/2," +
                 "\(drawtext)," +
                 "fade=t=out:st=\(fadeOutStart):d=\(fadeOutD)"

        // Collage clip with animated text overlay
        let collageClip = assetsDir.appending(path: "outro_collage.mp4")
        _ = try await bridge.execute(arguments: [
            "-loop", "1", "-framerate", "30",
            "-i", collagePNG.path,
            "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
            "-t", String(format: "%.2f", outroDuration),
            "-vf", vf,
            "-map", "0:v", "-map", "1:a",
            "-c:v", enc.codec, "-b:v", enc.bitrate, "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "128k", "-shortest",
            "-y", collageClip.path
        ])

        // Black screen clip — r=30 must match collage so xfade timebases align
        let blackClip = assetsDir.appending(path: "outro_black.mp4")
        _ = try await bridge.execute(arguments: [
            "-f", "lavfi", "-i", "color=c=black:s=\(W)x\(H):r=30:d=2",
            "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
            "-t", "2", "-c:v", enc.codec, "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "128k", "-shortest",
            "-y", blackClip.path
        ])

        // Concat collage → black with xfade → raw silent outro
        let rawURL = assetsDir.appending(path: "outro_raw.mp4")
        try? FileManager.default.removeItem(at: rawURL)

        _ = try await bridge.execute(arguments: [
            "-i", collageClip.path,
            "-i", blackClip.path,
            "-filter_complex",
            "[0:v][1:v]xfade=transition=fade:duration=\(fadeOutD):offset=\(outroDuration - fadeOutD)[vout];" +
            "[0:a][1:a]acrossfade=d=\(fadeOutD)[aout]",
            "-map", "[vout]", "-map", "[aout]",
            "-c:v", enc.codec, "-b:v", enc.bitrate,
            "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "128k",
            "-y", rawURL.path
        ])

        // Mix in outro.mp3 if available; otherwise just rename
        let totalDur = outroDuration + 2.0 - fadeOutD  // 5.0s
        if let musicURL = IntroBuilder.findResourceAudio(named: "outro") {
            _ = try await bridge.execute(arguments: [
                "-i", rawURL.path,
                "-stream_loop", "-1", "-i", musicURL.path,
                "-map", "0:v", "-map", "1:a",
                "-af", "loudnorm=I=-16:TP=-1.5:LRA=11,volume=0.85",
                "-c:v", "copy",
                "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "128k",
                "-t", String(format: "%.3f", totalDur),
                "-y", outputURL.path
            ])
            try? FileManager.default.removeItem(at: rawURL)
        } else {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.moveItem(at: rawURL, to: outputURL)
        }
    }
}
