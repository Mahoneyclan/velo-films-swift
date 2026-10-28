// FlattenStep.swift
// Pipeline step 1: turns the ride GPX into one telemetry point per second (flatten.jsonl).

import Foundation

/// Parses the GPX file and writes flatten.jsonl.
/// Steps: locate GPX → parse → resample to 1 Hz → write JSONL (same as `flatten.py` in the original Python app, not in this repo).
struct FlattenStep: PipelineStep {
    /// Step name used in logs.
    let name = "flatten"
    /// Writer for the output file (injectable for testing).
    let jsonlWriter: JSONLWriter
    private static let isoFmt = ISO8601DateFormatter()

    /// Creates the step.
    /// - Parameter jsonlWriter: Output writer; defaults to a standard `JSONLWriter`.
    init(jsonlWriter: JSONLWriter = JSONLWriter()) {
        self.jsonlWriter = jsonlWriter
    }

    /// Reads the GPX, applies the user's GPX time offset and writes `flatten.jsonl`.
    /// - Throws: `PipelineError.missingInput` if no GPX is found or it has no usable points; XML or file errors.
    /// - Parameters:
    ///   - project: The ride project to process.
    ///   - reporter: Receives progress updates for the pipeline screen.
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
            let iso = Self.isoFmt.string(from: dt)
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

    // MARK: - GPX location logic (same search order as flatten.py in the original Python app, not in this repo)

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
