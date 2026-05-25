import Foundation
import Observation
import os

/// Runs pipeline steps sequentially, enforces dependencies, handles cancellation.
/// Mirrors pipeline_executor.py. Progress is reported via AsyncStream.
@Observable
@MainActor
final class PipelineExecutor {
    var runningStep: StepName?
    var completedSteps: Set<StepName> = []
    var failedStep: StepName?
    var lastError: Error?
    var currentProgress: ProgressEvent?
    var isRunning: Bool = false

    private var task: Task<Void, Error>?
    private let log = Logger(subsystem: "com.velofilms", category: "PipelineExecutor")
    var steps: [StepName: any PipelineStep] = [:]

    func register(_ step: any PipelineStep, for name: StepName) {
        steps[name] = step
    }

    func run(_ stepName: StepName, project: Project) {
        guard !isRunning else { return }
        isRunning = true
        failedStep = nil
        lastError = nil

        // Snapshot chain + step impls on MainActor now, then detach so heavy
        // encode/decode work runs on the cooperative thread pool — Task.sleep and
        // copyNextSampleBuffer never block the UI thread.
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
                await MainActor.run {
                    Self.appendToLog("Step failed (\(self.runningStep?.rawValue ?? "?")): \(error)")
                    self.failedStep = self.runningStep
                    self.lastError = error
                    self.runningStep = nil
                }
            }
            await MainActor.run { self.isRunning = false }
        }
    }

    private nonisolated static func appendToLog(_ message: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let url = docs?.appending(path: "pipeline.log"),
              let data = "[\(Date())] \(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

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

enum PipelineError: LocalizedError {
    case stepNotRegistered(String)
    case missingInput(String)
    case renderFailed(String)
    case ffmpegFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .stepNotRegistered(let name):         return "Step '\(name)' is not registered"
        case .missingInput(let detail):            return "Missing input: \(detail)"
        case .renderFailed(let detail):            return "Render failed: \(detail)"
        case .ffmpegFailed(let code, let stderr):  return "FFmpeg exited \(code): \(stderr)"
        }
    }
}
