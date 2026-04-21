import SwiftUI

/// Shows pipeline step buttons + live progress. Mirrors main_window.py button states.
struct PipelineView: View {
    let project: Project
    var executor: PipelineExecutor
    @State private var artifacts: ProjectArtifacts

    init(project: Project, executor: PipelineExecutor) {
        self.project = project
        self.executor = executor
        self._artifacts = State(initialValue: ProjectArtifacts.check(project))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pipeline").font(.headline)

            ForEach(StepName.allCases, id: \.self) { step in
                StepStatusView(
                    step: step,
                    project: project,
                    executor: executor,
                    artifacts: artifacts
                )
            }

            if let progress = executor.currentProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fraction)
                    Text(progress.message).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            if let error = executor.lastError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .onAppear { artifacts = ProjectArtifacts.check(project) }
    }
}

struct StepStatusView: View {
    let step: StepName
    let project: Project
    var executor: PipelineExecutor
    let artifacts: ProjectArtifacts

    var isRunning: Bool { executor.runningStep == step }
    var isComplete: Bool { step.isComplete(for: project) }
    var isFailed: Bool { executor.failedStep == step }
    var canRun: Bool { !executor.isRunning && dependenciesMet }

    var body: some View {
        HStack {
            statusIcon
            Text(step.rawValue.capitalized).frame(maxWidth: .infinity, alignment: .leading)
            if canRun && !isComplete {
                Button("Run") { executor.run(step, project: project) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isRunning {
            ProgressView().controlSize(.small).frame(width: 16, height: 16)
        } else if isFailed {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else if isComplete {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    private var dependenciesMet: Bool {
        step.dependencies.allSatisfy { $0.isComplete(for: project) }
    }
}
