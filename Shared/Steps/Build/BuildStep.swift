import Foundation

/// Orchestrates the build step: pre-render assets then composite clips via FFmpeg.
/// Mirrors build.py: minimaps → elevation strips → gauges → clip render → segment concat.
struct BuildStep: PipelineStep {
    let name = "build"
    let bridge: any FFmpegBridge
    let csvReader: CSVReader
    let yoloModelURL: URL

    init(bridge: any FFmpegBridge, yoloModelURL: URL, csvReader: CSVReader = CSVReader()) {
        self.bridge = bridge
        self.csvReader = csvReader
        self.yoloModelURL = yoloModelURL
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 0, total: 6, message: "Loading select.csv...")

        let selectRows: [SelectRow] = try csvReader.read(from: project.selectCSV)
        let flattenRows: [FlattenRow] = try csvReader.read(from: project.flattenCSV)
        let recommended = selectRows.filter { $0.recommended }

        guard !recommended.isEmpty else {
            throw PipelineError.missingInput("No recommended clips in select.csv — run select step first")
        }

        let gpxPoints = flattenRows.map {
            GPXPoint(epoch: $0.gpxEpoch, lat: $0.lat, lon: $0.lon,
                     elevation: $0.elevation, hr: $0.hrBpm, cadence: $0.cadenceRpm,
                     speedKmh: $0.speedKmh, gradientPct: $0.gradientPct)
        }

        // Group recommended by moment
        let moments = PartnerMatcher.group(selectRows.filter { $0.recommended })

        await reporter.report(current: 1, total: 6, message: "Pre-rendering minimaps...")
        var minimapPaths: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            let outURL = project.minimapsDir.appending(path: String(format: "minimap_%04d.png", i+1))
            try await MinimapRenderer.render(gpxPoints: gpxPoints,
                                            currentEpoch: primary.absTimeEpoch,
                                            outputURL: outURL)
            minimapPaths[i+1] = outURL
        }

        await reporter.report(current: 2, total: 6, message: "Pre-rendering elevation strips...")
        var elevPaths: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            let outURL = project.elevationDir.appending(path: String(format: "elev_%04d.png", i+1))
            try ElevationRenderer.render(flattenRows: flattenRows,
                                        currentEpoch: primary.absTimeEpoch,
                                        outputURL: outURL)
            elevPaths[i+1] = outURL
        }

        await reporter.report(current: 3, total: 6, message: "Pre-rendering gauge strips...")
        var gaugePaths: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            let outURL = project.gaugesDir.appending(path: String(format: "gauge_%04d.png", i+1))
            let telem = GaugeRenderer.GaugeTelemetry(
                elevM: primary.elevation,
                gradientPct: primary.gradientPct,
                speedKmh: primary.speedKmh,
                hrBpm: primary.hrBpm,
                cadenceRpm: primary.cadenceRpm
            )
            try GaugeRenderer.renderStrip(telemetry: telem, outputURL: outURL)
            gaugePaths[i+1] = outURL
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
            let mainSelectRow = recommended.first { $0.index == primary.index }!
            let pipSelectRow  = moment.secondary.flatMap { sec in
                recommended.first { $0.index == sec.index }
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
        try await buildSegments(clipURLs: clipURLs, project: project)

        await reporter.report(current: 6, total: 6, message: "Build complete")
    }

    // MARK: - Segment concatenation with music

    private func buildSegments(clipURLs: [URL], project: Project) async throws {
        let perSegment = AppConfig.highlightsPerSegment  // 8
        let chunks = stride(from: 0, to: clipURLs.count, by: perSegment).map {
            Array(clipURLs[$0..<min($0 + perSegment, clipURLs.count)])
        }

        for (segIdx, chunk) in chunks.enumerated() {
            let segURL = project.clipsDir.appending(
                path: String(format: "_middle_%02d.mp4", segIdx + 1)
            )
            try await concatenateWithXfade(clips: chunk, outputURL: segURL,
                                           segmentIndex: segIdx,
                                           totalSegments: chunks.count)
        }
    }

    /// Concatenate clips with xfade transitions.
    /// Mirrors segment_concatenator.py: 0.2s crossfade, 0.3s fade in/out on first/last.
    private func concatenateWithXfade(clips: [URL], outputURL: URL,
                                       segmentIndex: Int, totalSegments: Int) async throws {
        guard !clips.isEmpty else { return }
        guard clips.count > 1 else {
            // Single clip — just copy
            _ = try await bridge.execute(arguments: [
                "-i", clips[0].path, "-c", "copy", "-y", outputURL.path
            ])
            return
        }

        // Build filter_complex with xfade chain
        var args: [String] = []
        for clip in clips { args += ["-i", clip.path] }

        let duration = AppConfig.clipOutLenS
        let xfade    = AppConfig.xfadeDuration  // 0.2s

        var filter = ""
        // Label inputs
        for i in 0..<clips.count { filter += "[\(i):v][\(i):a]" }
        // Xfade chain
        var prevV = "[0:v]"
        var prevA = "[0:a]"
        for i in 1..<clips.count {
            let offset = (duration - xfade) * Double(i) - xfade * Double(i - 1)
            let outV = i == clips.count - 1 ? "[vout]" : "[v\(i)]"
            let outA = i == clips.count - 1 ? "[aout]" : "[a\(i)]"
            filter += "\(prevV)[\(i):v]xfade=transition=fade:duration=\(xfade):offset=\(offset)\(outV);"
            filter += "\(prevA)[\(i):a]acrossfade=d=\(xfade)\(outA);"
            prevV = "[v\(i)]"; prevA = "[a\(i)]"
        }

        let enc = AppConfig.Encoding.self
        args += [
            "-filter_complex", filter,
            "-map", "[vout]", "-map", "[aout]",
            "-c:v", enc.codec, "-b:v", enc.bitrate,
            "-c:a", "aac", "-b:a", "192k",
            "-y", outputURL.path
        ]
        _ = try await bridge.execute(arguments: args)
    }
}
