// BuildStep.swift
// Pipeline step 5: renders the map, elevation and gauge overlays and then each highlight clip.

import Foundation
import AVFoundation

/// Orchestrates the build step: pre-render overlays, then composite each clip.
/// Order: map base snapshot → minimaps → elevation strips → gauge frames → clip render
/// (same as `build.py` in the original Python app).
/// Segment concat and music mixing are handled by ConcatStep.
struct BuildStep: PipelineStep {
    /// Step name used in logs.
    let name = "build"
    /// Input reader (injectable for testing).
    let jsonlReader: JSONLReader
    /// YOLO model location. Stored but not used by this step.
    let yoloModelURL: URL

    /// Creates the step.
    /// - Parameters:
    ///   - yoloModelURL: The bundled YOLO model.
    ///   - jsonlReader: Reads `select.jsonl` and `flatten.jsonl`.
    init(yoloModelURL: URL, jsonlReader: JSONLReader = JSONLReader()) {
        self.jsonlReader = jsonlReader
        self.yoloModelURL = yoloModelURL
    }

    /// Renders `clips/clip_NNNN.mp4` for every recommended moment, in time order.
    ///
    /// Side effects: first deletes earlier minimaps, elevation strips, rendered clips (`.mp4`/`.mov` in `clips/`,
    /// including the intro and outro) and the final reel.
    /// - Throws: `PipelineError.missingInput` if nothing is recommended; render, FFmpeg or file errors.
    /// - Parameters:
    ///   - project: The ride project to process.
    ///   - reporter: Receives progress updates for the pipeline screen.
    func run(project: Project, reporter: ProgressReporter) async throws {
        try project.createOutputDirectories()
        await reporter.report(current: 0, total: 1, message: "Loading select.jsonl...")

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

        try Self.checkVideosReachable(moments.compactMap(\.primary), in: project)

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
                                       currentEpoch: primary.clipAnchorEpoch, outputURL: outURL)
            minimapPaths[i+1] = outURL
        }

        var elevPaths: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            await reporter.report(current: i, total: total, message: "Elevation \(i+1)/\(total)...")
            let outURL = project.elevationDir.appending(
                path: String(format: "elev_%04d.png", i+1))
            try ElevationRenderer.render(flattenRows: flattenRows,
                                         currentEpoch: primary.clipAnchorEpoch, outputURL: outURL)
            elevPaths[i+1] = outURL
        }

        await reporter.report(current: 0, total: total, message: "Pre-rendering gauge strips...")
        var gaugeDirs: [Int: URL] = [:]
        for (i, moment) in moments.enumerated() {
            guard let primary = moment.primary else { continue }
            gaugeDirs[i+1] = try GaugeRenderer.writeFramesToDisk(
                flattenRows: flattenRows, clipEpoch: primary.clipAnchorEpoch, clipIndex: i + 1)
        }

        await reporter.report(current: 0, total: total, message: "Rendering clips...")
#if os(macOS)
        let compositor = ClipCompositor(bridge: makeBridge(), outputDir: project.clipsDir)
#else
        let compositor = ClipCompositor(outputDir: project.clipsDir)
#endif

        for (i, moment) in moments.enumerated() {
            guard let primary  = moment.primary,
                  let minimap  = minimapPaths[i+1],
                  let elev     = elevPaths[i+1],
                  let gaugeDir = gaugeDirs[i+1] else { continue }

            await reporter.report(current: i, total: total,
                                  message: "Rendering clip \(i+1) of \(total)…")

            try await compositor.renderClip(
                mainRow:       primary,
                pipRow:        moment.secondary,
                videoURL:      { project.videoURL(forStoredPath: $0.videoPath) },
                minimapPath:   minimap,
                elevationPath: elev,
                gaugeDir:      gaugeDir,
                clipIndex:     i + 1
            )
            try? FileManager.default.removeItem(at: gaugeDir)
        }

        await reporter.report(current: total, total: total, message: "Build complete")
    }

    // MARK: - Checks

    /// Stops the build before anything is deleted or rendered when a clip's camera video can't be found on this
    /// device, e.g. the drive isn't connected or its raw videos were archived.
    /// - Parameters:
    ///   - rows: The camera row of every clip in the reel.
    ///   - project: The project, which knows its video folder on this device.
    ///   - inputBase: The Input Videos folder (injectable for tests).
    /// - Throws: `PipelineError.missingInput` naming the first missing video and the folder searched.
    static func checkVideosReachable(_ rows: [EnrichRow], in project: Project,
                                     inputBase: URL? = GlobalSettings.shared.inputBaseDir) throws {
        let fm = FileManager.default
        for row in rows {
            let url = project.videoURL(forStoredPath: row.videoPath, inputBase: inputBase)
            if !fm.fileExists(atPath: url.path(percentEncoded: false)) {
                throw PipelineError.missingInput(
                    "Can't find the camera video \(url.lastPathComponent) in "
                    + "\(url.deletingLastPathComponent().path(percentEncoded: false)). Connect the drive with "
                    + "this ride's raw videos, or check the Input Videos folder in Settings.")
            }
        }
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
