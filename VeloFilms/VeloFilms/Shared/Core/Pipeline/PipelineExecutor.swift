// PipelineExecutor.swift
// Runs pipeline steps in order, skipping finished prerequisites, and publishes status to the project screen.

import Foundation
import Observation
import os

/// Runs pipeline steps sequentially, enforces dependencies, handles cancellation.
/// Progress is reported via `ProgressReporter`. Same role as `pipeline_executor.py` in the original Python app.
///
/// Main-actor isolated: its properties drive the UI.
@Observable
@MainActor
final class PipelineExecutor {
    /// The step running now, if any.
    var runningStep: StepName?
    /// Steps finished during this executor's lifetime (not read from disk).
    var completedSteps: Set<StepName> = []
    /// The step that failed in the last run, if any.
    var failedStep: StepName?
    /// The error from the last failed run.
    var lastError: Error?
    /// Latest progress from the running step.
    var currentProgress: ProgressEvent?
    /// `true` while a run is in progress. A new run is ignored until it ends.
    var isRunning: Bool = false

    private var task: Task<Void, Error>?
    private let log = Logger(subsystem: "com.velofilms", category: "PipelineExecutor")
    /// Registered step implementations.
    var steps: [StepName: any PipelineStep] = [:]

    /// Registers the implementation for a step, replacing any earlier one.
    /// - Parameters:
    ///   - step: The implementation to run.
    ///   - name: The pipeline step it implements.
    func register(_ step: any PipelineStep, for name: StepName) {
        steps[name] = step
    }

    /// Runs `stepName`, first running any prerequisite steps whose output is missing. Returns immediately.
    ///
    /// `stepName` itself always runs, even if its output exists. On failure the error is stored in `lastError`
    /// and appended to `pipeline.log` in the project folder.
    /// - Parameters:
    ///   - stepName: The step to run.
    ///   - project: The project to run it on.
    func run(_ stepName: StepName, project: Project) {
        guard !isRunning else { return }
        failedStep = nil
        lastError = nil

        // An unreadable project folder looks like one whose steps never ran, which would start the analysis over
        // from the GPX. Re-open folder access (a drive plugged in after launch) and stop with a plain message if
        // the files still can't be read.
        GlobalSettings.shared.restoreFolderAccess()
        if let problem = Self.projectFolderProblem(project) {
            failedStep = stepName
            lastError = problem
            return
        }
        isRunning = true

        // Snapshot chain + step impls on MainActor now, then run them in a detached task.
        // Note: the project's default isolation is MainActor, so the step implementations are main-actor
        // isolated too. Their synchronous work runs on the main thread; only their awaits release it.
        let chain      = dependencyChain(for: stepName, project: project)
        let stepImpls  = steps   // [StepName: any PipelineStep] captured by value

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                for name in chain {
                    guard let step = stepImpls[name] else {
                        throw PipelineError.stepNotRegistered(name.rawValue)
                    }
                    try Task.checkCancellation()

                    await MainActor.run { self.runningStep = name }
                    self.log.info("Starting step: \(name.rawValue)")

                    let reporter = ProgressReporter()
                    let monitorTask = Task { @MainActor [weak self] in
                        guard let self else { return }
                        for await event in reporter.stream {
                            self.currentProgress = event
                        }
                    }

                    try await step.run(project: project, reporter: reporter)
                    await reporter.finish()
                    monitorTask.cancel()

                    await MainActor.run {
                        self.completedSteps.insert(name)
                        self.runningStep = nil
                        self.currentProgress = nil
                    }
                    self.log.info("Completed step: \(name.rawValue)")
                }
            } catch is CancellationError {
                self.log.info("Pipeline cancelled")
            } catch {
                self.log.error("Step failed: \(error.localizedDescription)")
                let stepName = await MainActor.run { self.runningStep?.rawValue ?? "?" }
                Self.appendToLog("Step failed (\(stepName)): \(error)", projectFolder: project.folderURL)
                await MainActor.run {
                    self.failedStep = self.runningStep
                    self.lastError = error
                    self.runningStep = nil
                }
            }
            await MainActor.run { self.isRunning = false }
        }
    }

    private nonisolated static func appendToLog(_ message: String, projectFolder: URL) {
        let url = projectFolder.appending(path: "pipeline.log")
        guard let data = "[\(Date())] \(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Checks that the project's `working/` folder can be read.
    /// - Parameter project: The project about to run.
    /// - Returns: `PipelineError.projectFolderUnreadable` when it can't be listed (drive not connected, or no
    ///   permission on iPad), otherwise `nil`.
    static func projectFolderProblem(_ project: Project) -> PipelineError? {
        let listed = try? FileManager.default.contentsOfDirectory(at: project.workingDir, includingPropertiesForKeys: nil)
        return listed == nil ? .projectFolderUnreadable(project.folderURL.path(percentEncoded: false)) : nil
    }

    /// Cancels the current run. Steps stop at their next cancellation check.
    func cancel() {
        task?.cancel()
    }

    private func dependencyChain(for target: StepName, project: Project) -> [StepName] {
        var chain: [StepName] = []
        func visit(_ name: StepName, forceRun: Bool) {
            for dep in name.dependencies { visit(dep, forceRun: false) }
            if (forceRun || !name.isComplete(for: project)) && !chain.contains(name) {
                chain.append(name)
            }
        }
        visit(target, forceRun: true)
        return chain
    }
}

/// Errors raised by pipeline steps.
enum PipelineError: LocalizedError {
    case stepNotRegistered(String)
    case missingInput(String)
    case renderFailed(String)
    case ffmpegFailed(Int32, String)
    /// The project's files can't be read; the associated value is the project folder's path.
    case projectFolderUnreadable(String)

    /// Plain message shown on the project screen. Technical text is kept out of it and offered separately
    /// through `technicalDetails`; the full error is also written to `pipeline.log`.
    var errorDescription: String? {
        switch self {
        case .stepNotRegistered(let name): return "Step '\(name)' is not available in this version of the app."
        case .missingInput(let detail):    return "Missing input: \(detail)"
        case .renderFailed:                return "The video couldn't be rendered. See Details, or try running the step again."
        case .ffmpegFailed:                return "FFmpeg couldn't render the video. See Details, or check that FFmpeg is installed (brew install ffmpeg)."
        case .projectFolderUnreadable:     return "Can't read this ride's files. Check the drive is connected, then try again. If it is, close and reopen the app."
        }
    }

    /// Technical text for the Details disclosure, or `nil` when the message says it all.
    /// For `ffmpegFailed` this is the exit code and the last 40 lines of FFmpeg's output, where the cause is.
    var technicalDetails: String? {
        switch self {
        case .stepNotRegistered, .missingInput: return nil
        case .projectFolderUnreadable(let folder): return "Project folder: \(folder)"
        case .renderFailed(let detail):         return detail
        case .ffmpegFailed(let code, let stderr):
            let tail = stderr.split(separator: "\n", omittingEmptySubsequences: false).suffix(40)
            return "FFmpeg exit code \(code)\n" + tail.joined(separator: "\n")
        }
    }
}
