import Foundation

/// Orchestrates the build step: pre-render assets then composite clips via FFmpeg.
/// Mirrors build.py: minimaps → elevation strips → gauges → clip render → segment concat.
struct BuildStep: PipelineStep {
    let name = "build"
    let bridge: any FFmpegBridge
    let jsonlReader: JSONLReader
    let yoloModelURL: URL

    init(bridge: any FFmpegBridge, yoloModelURL: URL, jsonlReader: JSONLReader = JSONLReader()) {
        self.bridge = bridge
        self.jsonlReader = jsonlReader
        self.yoloModelURL = yoloModelURL
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        try project.createOutputDirectories()
        await reporter.report(current: 0, total: 6, message: "Loading select.jsonl...")

        let selectRows: [SelectRow] = try jsonlReader.read(from: project.selectJSONL)
        let flattenRows: [FlattenRow] = try jsonlReader.read(from: project.flattenJSONL)
        let recommended = selectRows.filter { $0.recommended }

        guard !recommended.isEmpty else {
            throw PipelineError.missingInput("No recommended clips in select.jsonl — run select step first")
        }

        let gpxPoints = flattenRows.map {
            GPXPoint(epoch: $0.gpxEpoch, lat: $0.lat, lon: $0.lon,
                     elevation: $0.elevation, hr: $0.hrBpm, cadence: $0.cadenceRpm,
                     speedKmh: $0.speedKmh, gradientPct: $0.gradientPct)
        }

        // Group ALL rows so each moment has both camera perspectives available.
        // Then keep only moments where the primary camera was recommended.
        let recommendedIds = Set(recommended.map { $0.momentId })
        let allMoments = PartnerMatcher.group(selectRows.map { $0.asEnrichRow })
        let moments = allMoments.filter { recommendedIds.contains($0.momentId) }

        let total = moments.count

        // Clear all asset directories before regenerating
        clearDirectory(project.minimapsDir)
        clearDirectory(project.elevationDir)
        clearDirectory(project.gaugesDir)
        clearClips(in: project.clipsDir)

        await reporter.report(current: 0, total: total, message: "Fetching map tiles...")
        let baseSnapshot = await MinimapRenderer.makeBaseSnapshot(gpxPoints: gpxPoints)

        var minimapPaths: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            await reporter.report(current: i, total: total,
                                  message: "Minimap \(i+1)/\(total)...")
            let outURL = project.minimapsDir.appending(path: String(format: "minimap_%04d.png", i+1))
            try MinimapRenderer.render(base: baseSnapshot,
                                       gpxPoints: gpxPoints,
                                       currentEpoch: primary.absTimeEpoch,
                                       outputURL: outURL)
            minimapPaths[i+1] = outURL
        }

        var elevPaths: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            await reporter.report(current: i, total: total,
                                  message: "Elevation strip \(i+1)/\(total)...")
            let outURL = project.elevationDir.appending(path: String(format: "elev_%04d.png", i+1))
            try ElevationRenderer.render(flattenRows: flattenRows,
                                        currentEpoch: primary.absTimeEpoch,
                                        outputURL: outURL)
            elevPaths[i+1] = outURL
        }

        await reporter.report(current: 0, total: total, message: "Pre-rendering gauge strips...")
        var gaugePaths: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            let movURL = try await GaugeRenderer.renderDynamic(
                flattenRows: flattenRows,
                clipEpoch: primary.absTimeEpoch,
                outputDir: project.gaugesDir,
                clipIndex: i + 1,
                bridge: bridge
            )
            gaugePaths[i+1] = movURL
        }

        await reporter.report(current: 4, total: 6, message: "Rendering clips...")
        let compositor = ClipCompositor(bridge: bridge, outputDir: project.clipsDir)
        var clipURLs: [URL] = []

        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary,
                  let minimap = minimapPaths[i+1],
                  let elev = elevPaths[i+1],
                  let gauge = gaugePaths[i+1] else { continue }

            // Convert EnrichRow → SelectRow equivalents for compositor
            let mainSelectRow = selectRows.first { $0.index == primary.index }!
            let pipSelectRow  = moment.secondary.flatMap { sec in
                selectRows.first { $0.index == sec.index }
            }

            let clipURL = try await compositor.renderClip(
                mainRow: mainSelectRow, pipRow: pipSelectRow,
                minimapPath: minimap, elevationPath: elev, gaugePath: gauge,
                clipIndex: i + 1
            )
            clipURLs.append(clipURL)

            await reporter.report(current: i + 1, total: moments.count + 2,
                                  message: "Rendered clip \(i+1)/\(moments.count)")
        }

        await reporter.report(current: 5, total: 6, message: "Building segments...")
        let prefs = project.loadPreferences()
        try await buildSegments(clipURLs: clipURLs, project: project, preferences: prefs)

        await reporter.report(current: 6, total: 6, message: "Build complete")
    }

    // MARK: - Segment concatenation with music

    private func buildSegments(clipURLs: [URL], project: Project, preferences: ProjectPreferences) async throws {
        let perSegment = AppConfig.highlightsPerSegment
        let chunks = stride(from: 0, to: clipURLs.count, by: perSegment).map {
            Array(clipURLs[$0..<min($0 + perSegment, clipURLs.count)])
        }

        let musicTrack = findMusicTrack(preferred: preferences.selectedMusicTrack)
        var musicOffset = 0.0

        for (segIdx, chunk) in chunks.enumerated() {
            let segURL = project.clipsDir.appending(
                path: String(format: "_middle_%02d.mp4", segIdx + 1)
            )
            let isFirst = segIdx == 0
            let isLast  = segIdx == chunks.count - 1
            let segDuration = segmentDuration(clipCount: chunk.count)

            if let music = musicTrack {
                // Two-pass: xfade concat → music mix
                let rawURL = project.clipsDir.appending(
                    path: String(format: "_raw_%02d.mp4", segIdx + 1))
                try await concatenateWithXfade(clips: chunk, outputURL: rawURL,
                                               isFirst: isFirst, isLast: isLast)
                try await mixMusic(videoURL: rawURL, musicURL: music,
                                   musicOffset: musicOffset, duration: segDuration,
                                   outputURL: segURL)
                try? FileManager.default.removeItem(at: rawURL)
            } else {
                try await concatenateWithXfade(clips: chunk, outputURL: segURL,
                                               isFirst: isFirst, isLast: isLast)
            }
            musicOffset += segDuration
        }
    }

    /// Net duration of N clips joined with xfade transitions.
    private func segmentDuration(clipCount: Int) -> Double {
        let d = AppConfig.clipOutLenS, x = AppConfig.xfadeDuration
        return Double(clipCount) * d - Double(max(0, clipCount - 1)) * x
    }

    /// Concatenate clips with xfade transitions and optional fade-in/out.
    /// Mirrors segment_concatenator.py _build_xfade_filter.
    /// Offset formula: offset[i] = i * (clipDuration - xfade) — matches Python cumulative calculation.
    private func concatenateWithXfade(clips: [URL], outputURL: URL,
                                       isFirst: Bool, isLast: Bool) async throws {
        guard !clips.isEmpty else { return }
        let duration = AppConfig.clipOutLenS
        let xfade    = AppConfig.xfadeDuration
        let fadeDur  = 0.3

        guard clips.count > 1 else {
            // Single clip — apply fade if needed, otherwise copy
            if isFirst || isLast {
                let segDur = duration
                var vf = ""
                if isFirst && isLast { vf = "fade=t=in:st=0:d=\(fadeDur),fade=t=out:st=\(segDur-fadeDur):d=\(fadeDur)" }
                else if isFirst      { vf = "fade=t=in:st=0:d=\(fadeDur)" }
                else                 { vf = "fade=t=out:st=\(segDur-fadeDur):d=\(fadeDur)" }
                let enc = AppConfig.Encoding.self
                _ = try await bridge.execute(arguments: [
                    "-i", clips[0].path, "-vf", vf,
                    "-c:v", enc.codec, "-b:v", enc.bitrate,
                    "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "192k",
                    "-y", outputURL.path
                ])
            } else {
                _ = try await bridge.execute(arguments: [
                    "-i", clips[0].path, "-c", "copy", "-y", outputURL.path
                ])
            }
            return
        }

        var args: [String] = []
        for clip in clips { args += ["-i", clip.path] }

        // Build xfade chain. offset[i] = i * (duration - xfade) — correct per Python.
        var videoFilter = ""
        var audioFilter = ""
        var prevV = "[0:v]", prevA = "[0:a]"
        let totalDur = segmentDuration(clipCount: clips.count)

        for i in 1..<clips.count {
            let offset = Double(i) * (duration - xfade)
            let isLast_ = (i == clips.count - 1)
            let outV = isLast_ ? "[vxfade]" : "[v\(i)]"
            let outA = isLast_ ? "[axfade]" : "[a\(i)]"
            videoFilter += "\(prevV)[\(i):v]xfade=transition=fade:duration=\(xfade):offset=\(String(format:"%.3f",offset))\(outV);"
            audioFilter += "\(prevA)[\(i):a]acrossfade=d=\(xfade):c1=tri:c2=tri\(outA);"
            prevV = outV; prevA = outA
        }

        // Fade in / out on first / last segment
        if isFirst && isLast {
            videoFilter += "[vxfade]fade=t=in:st=0:d=\(fadeDur),fade=t=out:st=\(totalDur-fadeDur):d=\(fadeDur)[vout];"
            audioFilter += "[axfade]afade=t=in:st=0:d=\(fadeDur),afade=t=out:st=\(totalDur-fadeDur):d=\(fadeDur)[aout]"
        } else if isFirst {
            videoFilter += "[vxfade]fade=t=in:st=0:d=\(fadeDur)[vout];"
            audioFilter += "[axfade]afade=t=in:st=0:d=\(fadeDur)[aout]"
        } else if isLast {
            videoFilter += "[vxfade]fade=t=out:st=\(totalDur-fadeDur):d=\(fadeDur)[vout];"
            audioFilter += "[axfade]afade=t=out:st=\(totalDur-fadeDur):d=\(fadeDur)[aout]"
        } else {
            videoFilter += "[vxfade]copy[vout];"
            audioFilter += "[axfade]acopy[aout]"
        }

        let enc = AppConfig.Encoding.self
        args += [
            "-filter_complex", videoFilter + audioFilter,
            "-map", "[vout]", "-map", "[aout]",
            "-c:v", enc.codec, "-b:v", enc.bitrate,
            "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "192k",
            "-y", outputURL.path
        ]
        _ = try await bridge.execute(arguments: args)
    }

    /// Mix background music into a segment video at the correct playback offset.
    private func mixMusic(videoURL: URL, musicURL: URL,
                           musicOffset: Double, duration: Double,
                           outputURL: URL) async throws {
        let rv = GlobalSettings.shared.rawAudioVolume
        let mv = GlobalSettings.shared.musicVolume
        _ = try await bridge.execute(arguments: [
            "-i", videoURL.path,
            "-ss", String(format: "%.3f", musicOffset),
            "-stream_loop", "-1",
            "-i", musicURL.path,
            "-filter_complex",
            "[0:a]loudnorm=I=-16:TP=-1.5:LRA=11,volume=\(rv)[raw];" +
            "[1:a]loudnorm=I=-16:TP=-1.5:LRA=11,volume=\(mv)[music];" +
            "[raw][music]amix=inputs=2:duration=first:dropout_transition=0[out]",
            "-map", "0:v", "-map", "[out]",
            "-c:v", "copy",
            "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "192k",
            "-t", String(format: "%.3f", duration),
            "-y", outputURL.path
        ])
    }

    /// Find a music track. If a preferred track name is set in project preferences,
    /// look for that filename specifically; otherwise pick randomly.
    private func findMusicTrack(preferred: String = "") -> URL? {
        let extensions = ["mp3", "m4a", "aac", "wav"]
        var candidates: [URL] = []

        // Collect all tracks from bundle music dir
        if let bundleURL = Bundle.main.resourceURL {
            let musicDir = bundleURL.appending(path: "music")
            if let files = try? FileManager.default.contentsOfDirectory(
                at: musicDir, includingPropertiesForKeys: nil) {
                candidates += files.filter { extensions.contains($0.pathExtension.lowercased()) }
            }
        }
        // Flat bundle resources
        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                candidates += urls
            }
        }
        // Dev fallback: repo Shared/Resources/music
        let repoMusic = URL(fileURLWithPath: "/Volumes/AData/Github/velo-films-swift/Shared/Resources/music")
        if let files = try? FileManager.default.contentsOfDirectory(
            at: repoMusic, includingPropertiesForKeys: nil) {
            candidates += files.filter { extensions.contains($0.pathExtension.lowercased()) }
        }

        if !preferred.isEmpty,
           let match = candidates.first(where: { $0.lastPathComponent == preferred }) {
            return match
        }
        return candidates.randomElement()
    }

    // MARK: - Directory cleanup

    private func clearDirectory(_ url: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: url.path) else { return }
        for f in files { try? fm.removeItem(at: url.appending(path: f)) }
    }

    /// Remove clip_XXXX.mp4 and _middle_XX.mp4 from clipsDir, preserve _intro/_outro.
    private func clearClips(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for f in files {
            guard f.hasSuffix(".mp4") || f.hasSuffix(".mov") else { continue }
            guard !f.hasPrefix("_intro") && !f.hasPrefix("_outro") else { continue }
            try? fm.removeItem(at: dir.appending(path: f))
        }
    }
}
