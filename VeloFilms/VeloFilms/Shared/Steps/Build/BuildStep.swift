import Foundation
import AVFoundation

/// Orchestrates the build step: pre-render assets then composite clips.
/// Mirrors build.py: minimaps → elevation strips → gauges → clip render.
/// Segment concat and music mixing are handled by ConcatStep.
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

        await reporter.report(current: 0, total: total, message: "Rendering clips...")
        let bridge     = makeBridge()
        let compositor = ClipCompositor(bridge: bridge, outputDir: project.clipsDir)

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
                minimapPath:   minimap,
                elevationPath: elev,
                gaugeDir:      gaugeDir,
                clipIndex:     i + 1
            )
            try? FileManager.default.removeItem(at: gaugeDir)
        }

        await reporter.report(current: total, total: total, message: "Build complete")
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
