import Foundation

/// Builds intro and outro splash segments.
/// Mirrors splash.py: IntroBuilder + OutroBuilder.
/// Phase 4 implementation — this stub wires up the step; full rendering in IntroBuilder/OutroBuilder.
struct SplashStep: PipelineStep {
    let name = "splash"
    let bridge: any FFmpegBridge
    let jsonlReader: JSONLReader

    init(bridge: any FFmpegBridge, jsonlReader: JSONLReader = JSONLReader()) {
        self.bridge = bridge
        self.jsonlReader = jsonlReader
    }

    func run(project: Project, reporter: ProgressReporter) async throws {
        try project.createOutputDirectories()
        await reporter.report(current: 0, total: 4, message: "Loading select.jsonl...")

        let selectRows: [SelectRow] = try jsonlReader.read(from: project.selectJSONL)
        let flattenRows: [FlattenRow] = try jsonlReader.read(from: project.flattenJSONL)

        await reporter.report(current: 1, total: 4, message: "Building intro...")
        try await IntroBuilder.build(project: project, selectRows: selectRows,
                                     flattenRows: flattenRows, bridge: bridge)

        await reporter.report(current: 2, total: 4, message: "Building outro...")
        try await OutroBuilder.build(project: project, selectRows: selectRows,
                                     flattenRows: flattenRows, bridge: bridge)

        await reporter.report(current: 4, total: 4, message: "Splash complete")
    }
}
