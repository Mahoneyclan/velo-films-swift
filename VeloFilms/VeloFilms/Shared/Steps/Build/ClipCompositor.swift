import Foundation

/// Assembles each clip's HUD overlay via FFmpegBridge filter_complex.
/// Mirrors clip_renderer.py. Filter strings ported verbatim from the Python source.
struct ClipCompositor: Sendable {
    let bridge: any FFmpegBridge
    let outputDir: URL

    /// Render a single clip with PiP, map, elevation, and gauge overlays.
    ///
    /// - Parameters:
    ///   - mainRow: Primary (recommended) enriched row.
    ///   - pipRow: Optional partner-camera row for PiP overlay.
    ///   - minimapPath: Pre-rendered minimap PNG.
    ///   - elevationPath: Pre-rendered elevation strip PNG.
    ///   - gaugeDir: Directory of per-second gauge PNGs (gauge_0001.png, …).
    ///   - clipIndex: 1-based index used for the output filename.
    func renderClip(
        mainRow:       EnrichRow,
        pipRow:        EnrichRow?,
        minimapPath:   URL,
        elevationPath: URL,
        gaugeDir:      URL,
        clipIndex:     Int
    ) async throws -> URL {
        let outputURL = outputDir.appending(path: String(format: "clip_%04d.mp4", clipIndex))

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
            "-c:v", "libx264",
            "-b:v", "\(AppConfig.Encoding.videoBitrate / 1000)k",
            "-c:a", "aac", "-b:a", "\(AppConfig.Encoding.audioBitrate / 1000)k",
            "-movflags", "+faststart",
            "-y", outputURL.path,
        ]

        try await bridge.execute(arguments: args)
        return outputURL
    }

    // MARK: - Filter complex strings (mirrored from clip_renderer.py)

    private static func filterComplexWithPiP(mapIdx: Int, elevIdx: Int, gaugeIdx: Int) -> String {
        let H = AppConfig.HUD.self
        let t = AppConfig.loudnormTarget, tp = AppConfig.loudnormTP, lra = AppConfig.loudnormLRA
        return
            "[0:v]scale=\(H.outputW):\(H.outputH):force_original_aspect_ratio=decrease," +
            "pad=\(H.outputW):\(H.outputH):(ow-iw)/2:(oh-ih)/2[vmain];" +
            "[1:v]scale=-1:\(H.pipH)[pipsc];" +
            "[vmain][pipsc]overlay=\(H.pipX):H-h-\(H.mapPipBottom)[v1];" +
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
