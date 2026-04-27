import Foundation

/// Assembles each clip's HUD overlay via FFmpegBridge filter_complex.
/// Mirrors clip_renderer.py. All filter strings are ported verbatim from the Python source.
struct ClipCompositor {
    let bridge: any FFmpegBridge
    let outputDir: URL

    /// Render a single clip with PiP, map, elevation, and gauge overlays.
    ///
    /// - Parameters:
    ///   - mainRow: The primary (recommended) select row.
    ///   - pipRow: Optional PiP (partner camera) row.
    ///   - minimapPath: Pre-rendered 390×390 minimap PNG.
    ///   - elevationPath: Pre-rendered 948×75 elevation strip PNG.
    ///   - gaugePath: Pre-rendered 972×194 gauge PNG or ProRes .mov.
    ///   - clipIndex: 1-based index for output filename.
    func renderClip(mainRow: SelectRow,
                    pipRow: SelectRow?,
                    minimapPath: URL,
                    elevationPath: URL,
                    gaugePath: URL,
                    clipIndex: Int) async throws -> URL {

        let outputURL = outputDir.appending(path: String(format: "clip_%04d.mp4", clipIndex))

        let mainVideoURL = URL(fileURLWithPath: mainRow.videoPath)
        let tStartMain = max(0.0, mainRow.absTimeEpoch - mainRow.clipStartEpoch - AppConfig.clipPreRollS)
        let duration = AppConfig.clipOutLenS

        var inputs: [String] = [
            "-ss", String(tStartMain), "-t", String(duration), "-i", mainVideoURL.path
        ]

        var filterComplex: String
        var mapArg: String

        if let pip = pipRow {
            let tStartPip = max(0.0, pip.absTimeEpoch - pip.clipStartEpoch - AppConfig.clipPreRollS)
            let pipVideoURL = URL(fileURLWithPath: pip.videoPath)
            inputs += ["-ss", String(tStartPip), "-t", String(duration), "-i", pipVideoURL.path]
            // Input indices: 0=main, 1=pip, 2=minimap, 3=elev, 4=gauge
            inputs += ["-i", minimapPath.path, "-i", elevationPath.path, "-i", gaugePath.path]
            filterComplex = Self.filterComplexWithPiP(mapInputIdx: 2, elevInputIdx: 3, gaugeInputIdx: 4)
        } else {
            // No PiP — still lay map/elev/gauge on main
            inputs += ["-i", minimapPath.path, "-i", elevationPath.path, "-i", gaugePath.path]
            filterComplex = Self.filterComplexNoPiP(mapInputIdx: 1, elevInputIdx: 2, gaugeInputIdx: 3)
        }

        let enc = AppConfig.Encoding.self
        let args: [String] = inputs + [
            "-filter_complex", filterComplex,
            "-map", "[vhud]", "-map", "0:a",
            "-c:v", enc.codec,
            "-b:v", enc.bitrate, "-maxrate", enc.maxrate, "-bufsize", enc.bufsize,
            "-c:a", "aac", "-b:a", "192k",
            "-movflags", "+faststart",
            "-y", outputURL.path
        ]

        _ = try await bridge.execute(arguments: args)
        return outputURL
    }

    // MARK: - Filter complex strings (verbatim from clip_renderer.py)

    /// With PiP: main=input 0, pip=input 1, map=N, elev=N+1, gauge=N+2
    static func filterComplexWithPiP(mapInputIdx: Int, elevInputIdx: Int, gaugeInputIdx: Int) -> String {
        let m = mapInputIdx, e = elevInputIdx, g = gaugeInputIdx
        let H = AppConfig.HUD.self
        return """
        [0:v]scale=\(H.outputW):\(H.outputH):force_original_aspect_ratio=decrease,\
        pad=\(H.outputW):\(H.outputH):(ow-iw)/2:(oh-ih)/2[vmain];\
        [vmain][1:v]scale=-1:\(H.pipH)[pip];\
        [vmain][pip]overlay=\(H.pipX):H-h-\(H.mapPipBottom)[v1];\
        [v1][\(m):v]overlay=\(H.mapX):H-h-\(H.mapPipBottom)[vmap];\
        [vmap][\(e):v]overlay=\(H.elevX):H-h[velev];\
        [velev][\(g):v]overlay=\(H.gaugeX):H-h-\(H.mapPipBottom)[vhud];\
        [0:a]loudnorm=I=\(AppConfig.loudnormTarget):TP=\(AppConfig.loudnormTP):LRA=\(AppConfig.loudnormLRA)[anorm]
        """
    }

    static func filterComplexNoPiP(mapInputIdx: Int, elevInputIdx: Int, gaugeInputIdx: Int) -> String {
        let m = mapInputIdx, e = elevInputIdx, g = gaugeInputIdx
        let H = AppConfig.HUD.self
        return """
        [0:v]scale=\(H.outputW):\(H.outputH):force_original_aspect_ratio=decrease,\
        pad=\(H.outputW):\(H.outputH):(ow-iw)/2:(oh-ih)/2[vmain];\
        [vmain][\(m):v]overlay=\(H.mapX):H-h-\(H.mapPipBottom)[vmap];\
        [vmap][\(e):v]overlay=\(H.elevX):H-h[velev];\
        [velev][\(g):v]overlay=\(H.gaugeX):H-h-\(H.mapPipBottom)[vhud];\
        [0:a]loudnorm=I=\(AppConfig.loudnormTarget):TP=\(AppConfig.loudnormTP):LRA=\(AppConfig.loudnormLRA)[anorm]
        """
    }

    /// Segment music mix filter_complex — mirrors segment_concatenator.py.
    static let musicMixFilter: String = {
        let rv = AppConfig.rawAudioVolume
        let mv = AppConfig.musicVolume
        let t = AppConfig.loudnormTarget
        let tp = AppConfig.loudnormTP
        let lra = AppConfig.loudnormLRA
        return "[0:a]loudnorm=I=\(t):TP=\(tp):LRA=\(lra),volume=\(rv)[raw];"
             + "[1:a]loudnorm=I=\(t):TP=\(tp):LRA=\(lra),volume=\(mv)[music];"
             + "[raw][music]amix=inputs=2:duration=first:dropout_transition=0[out]"
    }()
}
