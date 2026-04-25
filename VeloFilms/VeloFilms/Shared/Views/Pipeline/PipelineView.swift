import SwiftUI

struct PipelineView: View {
    let project: Project
    var executor: PipelineExecutor
    @State private var completedSteps: Set<StepName> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pipeline").font(.headline)
                Spacer()
                if !executor.isRunning {
                    Button("Run All") { runAll() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(executor.isRunning)
                } else {
                    Button("Cancel", role: .destructive) { executor.cancel() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.bottom, 10)

            ForEach(StepName.allCases, id: \.self) { step in
                StepRow(step: step,
                        project: project,
                        executor: executor,
                        completedSteps: completedSteps,
                        onRun: { executor.run(step, project: project) })
                    .padding(.vertical, 6)
                if step != StepName.allCases.last {
                    Divider()
                }
            }

            if let progress = executor.currentProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fraction)
                    Text(progress.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 10)
            }

            if let error = executor.lastError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.top, 6)
            }
        }
        .onAppear { refreshCompletedSteps() }
        .onChange(of: executor.isRunning) { refreshCompletedSteps() }
        .onChange(of: executor.completedSteps) { refreshCompletedSteps() }
    }

    private func refreshCompletedSteps() {
        completedSteps = Set(StepName.allCases.filter { $0.isComplete(for: project) })
    }

    private func runAll() {
        executor.run(.concat, project: project)
    }
}

private struct StepRow: View {
    let step: StepName
    let project: Project
    var executor: PipelineExecutor
    let completedSteps: Set<StepName>
    let onRun: () -> Void

    private var isRunning: Bool { executor.runningStep == step }
    private var isFailed:  Bool { executor.failedStep == step }
    private var isComplete: Bool { completedSteps.contains(step) }
    private var isLocked: Bool { !step.dependencies.allSatisfy { completedSteps.contains($0) } }

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.rawValue.capitalized)
                    .foregroundStyle(isLocked ? .secondary : .primary)
                if isLocked && !isComplete {
                    Text("Waiting for \(step.dependencies.map(\.rawValue).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isRunning {
                Text("Running…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if executor.isRunning {
                // another step is running — show nothing
            } else if isComplete {
                Button("Re-run") { onRun() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.secondary)
            } else if !isLocked {
                Button("Run") { onRun() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isRunning {
            ProgressView().controlSize(.small)
        } else if isFailed {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else if isComplete {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if isLocked {
            Image(systemName: "lock.circle").foregroundStyle(.tertiary)
        } else {
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }
}
