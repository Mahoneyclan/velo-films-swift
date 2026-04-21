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

        task = Task { @MainActor in
            do {
                let chain = dependencyChain(for: stepName, project: project)
                for name in chain {
                    guard let step = steps[name] else {
                        throw PipelineError.stepNotRegistered(name.rawValue)
                    }
                    try Task.checkCancellation()

                    self.runningStep = name
                    log.info("Starting step: \(name.rawValue)")

                    let reporter = ProgressReporter()
                    let monitorTask = Task { @MainActor in
                        for await event in reporter.stream {
                            self.currentProgress = event
                        }
                    }

                    try await step.run(project: project, reporter: reporter)
                    await reporter.finish()
                    monitorTask.cancel()

                    self.completedSteps.insert(name)
                    self.runningStep = nil
                    self.currentProgress = nil
                    log.info("Completed step: \(name.rawValue)")
                }
            } catch is CancellationError {
                log.info("Pipeline cancelled")
            } catch {
                log.error("Step failed: \(error.localizedDescription)")
                self.failedStep = self.runningStep
                self.lastError = error
                self.runningStep = nil
            }
            self.isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func dependencyChain(for target: StepName, project: Project) -> [StepName] {
        var chain: [StepName] = []
        func visit(_ name: StepName) {
            for dep in name.dependencies { visit(dep) }
            if !name.isComplete(for: project) && !chain.contains(name) {
                chain.append(name)
            }
        }
        visit(target)
        if !chain.contains(target) && !target.isComplete(for: project) {
            chain.append(target)
        }
        return chain
    }
}

enum PipelineError: LocalizedError {
    case stepNotRegistered(String)
    case missingInput(String)
    case ffmpegFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .stepNotRegistered(let name): return "Step '\(name)' is not registered"
        case .missingInput(let detail):    return "Missing input: \(detail)"
        case .ffmpegFailed(let code, let stderr): return "FFmpeg exited \(code): \(stderr)"
        }
    }
}
