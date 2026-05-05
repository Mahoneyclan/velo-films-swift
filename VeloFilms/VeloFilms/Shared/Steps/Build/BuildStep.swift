import Foundation

/// Orchestrates the build step: pre-render assets then composite clips.
/// Mirrors build.py: minimaps → elevation strips → gauges → clip render → segment concat.
struct BuildStep: PipelineStep {
    let name = "build"
    let jsonlReader: JSONLReader
    let yoloModelURL: URL

    init(yoloModelURL: URL, jsonlReader: JSONLReader = JSONLReader()) {
        self.jsonlReader = jsonlReader
        self.yoloModelURL = yoloModelURL
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        try project.createOutputDirectories()
        await reporter.report(current: 0, total: 6, message: "Loading select.jsonl...")

        let selectRows:  [SelectRow]  = try jsonlReader.read(from: project.selectJSONL)
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

        let recommendedIds = Set(recommended.map { $0.base.momentId })
        let allMoments     = PartnerMatcher.group(selectRows.map(\.base))
        let moments        = allMoments
            .filter { recommendedIds.contains($0.momentId) }
            .sorted { ($0.primary?.absTimeEpoch ?? 0) < ($1.primary?.absTimeEpoch ?? 0) }
        let total          = moments.count

        clearDirectory(project.minimapsDir)
        clearDirectory(project.elevationDir)
        clearClips(in: project.clipsDir)
        try? FileManager.default.removeItem(at: project.finalReelURL)

        await reporter.report(current: 0, total: total, message: "Fetching map tiles...")
        let baseSnapshot = await MinimapRenderer.makeBaseSnapshot(gpxPoints: gpxPoints)

        var minimapPaths: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            await reporter.report(current: i, total: total, message: "Minimap \(i+1)/\(total)...")
            let outURL = project.minimapsDir.appending(
                path: String(format: "minimap_%04d.png", i+1))
            try MinimapRenderer.render(base: baseSnapshot, gpxPoints: gpxPoints,
                                       currentEpoch: primary.absTimeEpoch, outputURL: outURL)
            minimapPaths[i+1] = outURL
        }

        var elevPaths: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            await reporter.report(current: i, total: total, message: "Elevation \(i+1)/\(total)...")
            let outURL = project.elevationDir.appending(
                path: String(format: "elev_%04d.png", i+1))
            try ElevationRenderer.render(flattenRows: flattenRows,
                                         currentEpoch: primary.absTimeEpoch, outputURL: outURL)
            elevPaths[i+1] = outURL
        }

        await reporter.report(current: 0, total: total, message: "Pre-rendering gauge strips...")
        var gaugeDirs: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            gaugeDirs[i+1] = try GaugeRenderer.writeFramesToDisk(
                flattenRows: flattenRows, clipEpoch: primary.absTimeEpoch, clipIndex: i + 1)
        }

        await reporter.report(current: 4, total: 6, message: "Rendering clips...")
        let bridge    = makeBridge()
        let compositor = ClipCompositor(bridge: bridge, outputDir: project.clipsDir)
        var clipURLs: [URL] = []

        for (i, moment) in moments.enumerated() {
            guard let primary  = moment.primary,
                  let minimap  = minimapPaths[i+1],
                  let elev     = elevPaths[i+1],
                  let gaugeDir = gaugeDirs[i+1] else { continue }

            await reporter.report(current: i, total: moments.count,
                                  message: "Rendering clip \(i+1) of \(moments.count)…")

            let clipURL = try await compositor.renderClip(
                mainRow:       primary,
                pipRow:        moment.secondary,
                minimapPath:   minimap,
                elevationPath: elev,
                gaugeDir:      gaugeDir,
                clipIndex:     i + 1
            )
            try? FileManager.default.removeItem(at: gaugeDir)
            clipURLs.append(clipURL)
        }

        await reporter.report(current: 5, total: 6, message: "Building segments...")
        let prefs = project.loadPreferences()
        try await buildSegments(clipURLs: clipURLs, project: project, preferences: prefs, bridge: bridge)

        await reporter.report(current: 6, total: 6, message: "Build complete")
    }

    // MARK: - Segment concatenation

    private func buildSegments(clipURLs: [URL], project: Project,
                                preferences: ProjectPreferences,
                                bridge: any FFmpegBridge) async throws {
        let perSegment = AppConfig.highlightsPerSegment
        let chunks = stride(from: 0, to: clipURLs.count, by: perSegment).map {
            Array(clipURLs[$0..<min($0 + perSegment, clipURLs.count)])
        }

        let musicTrack  = findMusicTrack(preferred: preferences.selectedMusicTrack)
        var musicOffset = 0.0

        for (segIdx, chunk) in chunks.enumerated() {
            let segURL  = project.clipsDir.appending(path: String(format: "_middle_%02d.mp4", segIdx + 1))
            let isFirst = segIdx == 0
            let isLast  = segIdx == chunks.count - 1
            let segDur  = segmentDuration(clipCount: chunk.count)

            if let music = musicTrack {
                let rawURL = project.clipsDir.appending(path: String(format: "_raw_%02d.mp4", segIdx + 1))
                try await concatenateWithXfade(clips: chunk, outputURL: rawURL,
                                               isFirst: isFirst, isLast: isLast, bridge: bridge)
                try await mixMusic(videoURL: rawURL, musicURL: music,
                                   musicOffset: musicOffset, outputURL: segURL, bridge: bridge)
                try? FileManager.default.removeItem(at: rawURL)
            } else {
                try await concatenateWithXfade(clips: chunk, outputURL: segURL,
                                               isFirst: isFirst, isLast: isLast, bridge: bridge)
            }
            musicOffset += segDur
        }
    }

    private func segmentDuration(clipCount: Int) -> Double {
        let d = AppConfig.clipOutLenS, x = AppConfig.xfadeDuration
        return Double(clipCount) * d - Double(max(0, clipCount - 1)) * x
    }

    // MARK: - FFmpeg xfade concat

    /// Concatenate clips with crossfade transitions and optional fade in/out.
    /// Mirrors segment_concatenator.py: xfade+acrossfade chain, 0.3s fade in/out on first/last.
    private func concatenateWithXfade(clips: [URL], outputURL: URL,
                                       isFirst: Bool, isLast: Bool,
                                       bridge: any FFmpegBridge) async throws {
        guard !clips.isEmpty else { return }

        let D       = AppConfig.clipOutLenS
        let X       = AppConfig.xfadeDuration
        let fade    = AppConfig.fadeInOutDuration
        let vbr     = "\(AppConfig.Encoding.videoBitrate / 1000)k"
        let abr     = "\(AppConfig.Encoding.audioBitrate / 1000)k"

        // Single clip: copy, or re-encode only if fades are needed
        if clips.count == 1 {
            if !isFirst && !isLast {
                try await bridge.execute(arguments: [
                    "-i", clips[0].path, "-c", "copy", "-y", outputURL.path,
                ])
            } else {
                let totalDur = D
                var vf = ""
                var af = ""
                if isFirst {
                    vf += "fade=t=in:st=0:d=\(fade),"
                    af += "afade=t=in:st=0:d=\(fade),"
                }
                if isLast {
                    vf += "fade=t=out:st=\(totalDur - fade):d=\(fade),"
                    af += "afade=t=out:st=\(totalDur - fade):d=\(fade),"
                }
                // trim trailing commas
                vf = String(vf.dropLast()); af = String(af.dropLast())
                try await bridge.execute(arguments: [
                    "-i", clips[0].path,
                    "-vf", vf, "-af", af,
                    "-c:v", AppConfig.Encoding.videoCodec, "-b:v", vbr,
                    "-c:a", "aac", "-b:a", abr,
                    "-y", outputURL.path,
                ])
            }
            return
        }

        // Multiple clips: build xfade + acrossfade filter chain
        var inputs: [String] = []
        for clip in clips { inputs += ["-i", clip.path] }

        var filterParts: [String] = []
        var prevV = "[0:v]"
        var prevA = "[0:a]"
        for i in 1..<clips.count {
            // Offset for xfade i (measured in cumulative output timeline): (D-X)*i
            let offset = (D - X) * Double(i)
            let isLast_ = (i == clips.count - 1)
            let vOut = isLast_ ? "[vchain]" : "[v\(i)]"
            let aOut = isLast_ ? "[achain]" : "[a\(i)]"
            filterParts.append("\(prevV)[\(i):v]xfade=transition=fade:duration=\(X):offset=\(offset)\(vOut)")
            filterParts.append("\(prevA)[\(i):a]acrossfade=d=\(X)\(aOut)")
            prevV = vOut; prevA = aOut
        }

        // Append fade in/out on the final chained stream
        let totalDur = segmentDuration(clipCount: clips.count)
        var vfPost = ""
        var afPost = ""
        if isFirst {
            vfPost += "fade=t=in:st=0:d=\(fade),"
            afPost += "afade=t=in:st=0:d=\(fade),"
        }
        if isLast {
            vfPost += "fade=t=out:st=\(totalDur - fade):d=\(fade),"
            afPost += "afade=t=out:st=\(totalDur - fade):d=\(fade),"
        }
        if !vfPost.isEmpty {
            vfPost = String(vfPost.dropLast())   // trim trailing comma
            afPost = String(afPost.dropLast())
            filterParts.append("[vchain]\(vfPost)[vout]")
            filterParts.append("[achain]\(afPost)[aout]")
        } else {
            filterParts.append("[vchain]null[vout]")
            filterParts.append("[achain]anull[aout]")
        }

        let filter = filterParts.joined(separator: ";")
        print("[BuildStep] xfade concat: \(clips.count) clips, X=\(X)s → \(outputURL.lastPathComponent)")
        try await bridge.execute(arguments: inputs + [
            "-filter_complex", filter,
            "-map", "[vout]", "-map", "[aout]",
            "-c:v", AppConfig.Encoding.videoCodec, "-b:v", vbr,
            "-c:a", "aac", "-b:a", abr,
            "-movflags", "+faststart",
            "-y", outputURL.path,
        ])
    }

    // MARK: - Music mixing

    /// Mix background music under the segment audio using FFmpeg amix.
    /// Uses -stream_loop to handle music shorter than the segment.
    /// Video is stream-copied (no re-encode).
    private func mixMusic(videoURL: URL, musicURL: URL,
                           musicOffset: Double, outputURL: URL,
                           bridge: any FFmpegBridge) async throws {
        let rv = GlobalSettings.shared.rawAudioVolume
        let mv = GlobalSettings.shared.musicVolume
        let abr = "\(AppConfig.Encoding.audioBitrate / 1000)k"

        let filter =
            "[0:a]volume=\(rv)[raw];" +
            "[1:a]volume=\(mv)[music];" +
            "[raw][music]amix=inputs=2:duration=first:dropout_transition=0[aout]"

        try await bridge.execute(arguments: [
            "-i", videoURL.path,
            "-stream_loop", "-1", "-ss", String(musicOffset), "-i", musicURL.path,
            "-filter_complex", filter,
            "-map", "0:v",
            "-map", "[aout]",
            "-c:v", "copy",
            "-c:a", "aac", "-b:a", abr,
            "-movflags", "+faststart",
            "-y", outputURL.path,
        ])
    }

    // MARK: - Music lookup

    private func findMusicTrack(preferred: String = "") -> URL? {
        // 1. User-selected file from Settings (highest priority)
        if let url = GlobalSettings.shared.musicURL,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        // 2. Bundled tracks — try music/ subfolder first, fall back to bundle root
        let extensions = ["mp3", "m4a", "aac", "wav"]
        var candidates: [URL] = []
        for ext in extensions {
            candidates += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "music") ?? []
        }
        if candidates.isEmpty {
            // Xcode may flatten the subfolder; check root, excluding splash assets
            let splash = Set(["intro", "outro"])
            for ext in extensions {
                let rootURLs = (Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [])
                    .filter { !splash.contains($0.deletingPathExtension().lastPathComponent) }
                candidates += rootURLs
            }
        }

        print("[BuildStep] findMusicTrack: \(candidates.count) bundled candidates, preferred='\(preferred)'")

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

    private func clearClips(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for f in files {
            guard f.hasSuffix(".mp4") || f.hasSuffix(".mov") else { continue }
            try? fm.removeItem(at: dir.appending(path: f))
        }
    }
}
