// SplashStep.swift
// Pipeline step 6: builds the intro and outro sequences.

import Foundation

/// Builds the intro (`clips/_intro.mp4`) and outro segments via IntroBuilder and OutroBuilder.
/// Same structure as `splash.py` in the original Python app.
struct SplashStep: PipelineStep {
    /// Step name used in logs.
    let name = "splash"
    /// Input reader (injectable for testing).
    let jsonlReader: JSONLReader

    /// Creates the step with a standard reader by default.
    /// - Parameter jsonlReader: Reads `select.jsonl` and `flatten.jsonl`.
    init(jsonlReader: JSONLReader = JSONLReader()) {
        self.jsonlReader = jsonlReader
    }

    /// Builds the intro, then the outro.
    /// - Throws: File errors reading `select.jsonl`/`flatten.jsonl`, or render errors.
    /// - Parameters:
    ///   - project: The ride project to process.
    ///   - reporter: Receives progress updates for the pipeline screen.
    func run(project: Project, reporter: ProgressReporter) async throws {
        try project.createOutputDirectories()
        await reporter.report(current: 0, total: 4, message: "Loading select.jsonl...")

        let selectRows:  [SelectRow]  = try jsonlReader.read(from: project.selectJSONL)
        let flattenRows: [FlattenRow] = try jsonlReader.read(from: project.flattenJSONL)

        await reporter.report(current: 1, total: 4, message: "Building intro...")
        try await IntroBuilder.build(project: project,
                                     selectRows: selectRows,
                                     flattenRows: flattenRows)

        await reporter.report(current: 2, total: 4, message: "Building outro...")
        try await OutroBuilder.build(project: project,
                                     selectRows: selectRows,
                                     flattenRows: flattenRows)

        await reporter.report(current: 4, total: 4, message: "Splash complete")
    }
}
