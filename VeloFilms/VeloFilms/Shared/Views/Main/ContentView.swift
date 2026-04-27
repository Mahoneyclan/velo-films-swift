import SwiftUI

struct ContentView: View {
    @Environment(ProjectStore.self) private var projectStore
    @State private var showOnboarding = false

    private var settings: GlobalSettings { GlobalSettings.shared }
    private var needsSetup: Bool {
        settings.projectsRoot == nil || settings.inputBaseDir == nil
    }

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            ProjectListView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let project = projectStore.selected {
                ProjectDetailView(project: project)
            } else {
                emptyDetail
            }
        }
#else
        NavigationStack {
            ProjectListView()
        }
#endif
    }

    private var emptyDetail: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No project selected")
                .font(.title3)
                .foregroundStyle(.secondary)
            if needsSetup {
                Button("Set up folders…") { showOnboarding = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
        .onAppear { if needsSetup { showOnboarding = true } }
    }
}
