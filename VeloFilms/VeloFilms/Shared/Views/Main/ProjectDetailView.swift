import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @Environment(ProjectStore.self) private var store
    @State private var executor = PipelineExecutor()
    @State private var showManualSelection = false
    @State private var showProjectPreferences = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showProjectPreferences = true
                } label: {
                    Label("Project Preferences", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showManualSelection) {
            ManualSelectionView(project: project)
        }
        .sheet(isPresented: $showProjectPreferences) {
            ProjectPreferencesView(project: project)
        }
        .onAppear {
            registerSteps()
        }
        .onChange(of: executor.isRunning) {
            if !executor.isRunning { store.lastPipelineUpdate = .now }
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
