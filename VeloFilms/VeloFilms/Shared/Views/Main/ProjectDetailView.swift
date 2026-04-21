import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @State private var executor = PipelineExecutor()
    @State private var showManualSelection = false

    var artifacts: ProjectArtifacts { ProjectArtifacts.check(project) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(project.name).font(.title2.bold())

                Divider()

                PipelineView(project: project, executor: executor)

                if artifacts.selectExists {
                    Button("Manual Clip Selection...") {
                        showManualSelection = true
                    }
                    .buttonStyle(.bordered)
                }

                if artifacts.finalReelExists {
                    HStack {
                        Image(systemName: "film.fill").foregroundStyle(.green)
                        Text("Reel ready: \(project.finalReelURL.lastPathComponent)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reveal") { reveal(project.finalReelURL) }
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
        .navigationTitle(project.name)
        .sheet(isPresented: $showManualSelection) {
            ManualSelectionView(project: project)
        }
        .onAppear {
            registerSteps()
        }
    }

    private func registerSteps() {
        let bridge = makeBridge()
        // Xcode compiles .mlpackage → .mlmodelc in the app bundle
        let modelURL = Bundle.main.url(forResource: "VeloYOLO", withExtension: "mlmodelc")
                    ?? Bundle.main.url(forResource: "VeloYOLO", withExtension: "mlpackage")
                    ?? URL(fileURLWithPath: "/dev/null")
        executor.register(FlattenStep(), for: .flatten)
        executor.register(ExtractStep(), for: .extract)
        executor.register(EnrichStep(yoloModelURL: modelURL), for: .enrich)
        executor.register(SelectStep(), for: .select)
        executor.register(BuildStep(bridge: bridge, yoloModelURL: modelURL), for: .build)
        executor.register(SplashStep(bridge: bridge), for: .splash)
        executor.register(ConcatStep(bridge: bridge), for: .concat)
    }

    private func reveal(_ url: URL) {
#if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
#endif
    }
}
