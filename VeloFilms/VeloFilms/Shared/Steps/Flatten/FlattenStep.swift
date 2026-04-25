import Foundation

/// Parses the GPX file and writes flatten.jsonl.
/// Mirrors flatten.py: locate GPX → parse → resample to 1Hz → write CSV.
struct FlattenStep: PipelineStep {
    let name = "flatten"
    let jsonlWriter: JSONLWriter

    init(jsonlWriter: JSONLWriter = JSONLWriter()) {
        self.jsonlWriter = jsonlWriter
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        try project.createOutputDirectories()
        await reporter.report(current: 0, total: 3, message: "Locating GPX file...")

        let gpxURL = try locateGPX(for: project)

        await reporter.report(current: 1, total: 3, message: "Parsing \(gpxURL.lastPathComponent)...")
        let points = try GPXParser.parse(url: gpxURL, gpxTimeOffsetS: GlobalSettings.shared.gpxTimeOffsetS)

        guard !points.isEmpty else {
            throw PipelineError.missingInput("GPX file produced no telemetry points")
        }

        await reporter.report(current: 2, total: 3, message: "Writing flatten.jsonl (\(points.count) rows)...")
        let rows = points.map { pt -> FlattenRow in
            let dt = Date(timeIntervalSince1970: pt.epoch)
            let iso = ISO8601DateFormatter().string(from: dt)
            return FlattenRow(
                gpxEpoch: pt.epoch,
                gpxTimeUtc: iso,
                lat: pt.lat, lon: pt.lon,
                elevation: pt.elevation,
                hrBpm: pt.hr,
                cadenceRpm: pt.cadence,
                speedKmh: pt.speedKmh,
                gradientPct: pt.gradientPct
            )
        }

        try jsonlWriter.write(rows: rows, to: project.flattenJSONL)
        await reporter.report(current: 3, total: 3, message: "Flatten complete — \(rows.count) rows")
    }

    // MARK: - GPX location logic (mirrors flatten.py)

    private func locateGPX(for project: Project) throws -> URL {
        // 1. project working dir
        if let url = ProjectFileManager.findGPXFile(in: project.workingDir) { return url }
        // 2. same-name source folder under inputBaseDir
        if let inputBase = GlobalSettings.shared.inputBaseDir {
            let sourceDir = inputBase.appending(path: project.name)
            if let url = ProjectFileManager.findGPXFile(in: sourceDir) { return url }
        }
        // 3. project root
        if let url = ProjectFileManager.findGPXFile(in: project.folderURL) { return url }
        throw PipelineError.missingInput("No .gpx file found for project '\(project.name)'")
    }
}
