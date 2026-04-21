import Foundation

/// Builds intro and outro splash segments.
/// Mirrors splash.py: IntroBuilder + OutroBuilder.
/// Phase 4 implementation — this stub wires up the step; full rendering in IntroBuilder/OutroBuilder.
struct SplashStep: PipelineStep {
    let name = "splash"
    let bridge: any FFmpegBridge
    let csvReader: CSVReader

    init(bridge: any FFmpegBridge, csvReader: CSVReader = CSVReader()) {
        self.bridge = bridge
        self.csvReader = csvReader
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        await reporter.report(current: 0, total: 4, message: "Loading select.csv...")

        let selectRows: [SelectRow] = try csvReader.read(from: project.selectCSV)
        let flattenRows: [FlattenRow] = try csvReader.read(from: project.flattenCSV)

        await reporter.report(current: 1, total: 4, message: "Building intro...")
        try await IntroBuilder.build(project: project, selectRows: selectRows,
                                     flattenRows: flattenRows, bridge: bridge)

        await reporter.report(current: 2, total: 4, message: "Building outro...")
        try await OutroBuilder.build(project: project, selectRows: selectRows,
                                     bridge: bridge)

        await reporter.report(current: 4, total: 4, message: "Splash complete")
    }
}
