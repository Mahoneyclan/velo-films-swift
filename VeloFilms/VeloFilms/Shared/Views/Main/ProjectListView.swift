import SwiftUI

struct ProjectListView: View {
    @Environment(ProjectStore.self) private var store
    @State private var showImport = false
    @State private var showSettings = false

    var body: some View {
        @Bindable var store = store
        List(store.projects, selection: $store.selected) { project in
            ProjectRow(project: project, lastUpdate: store.lastPipelineUpdate)
                .tag(project)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.remove(project)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        store.remove(project)
                    } label: {
                        Label("Remove from list", systemImage: "trash")
                    }
                }
        }
        .navigationTitle("Velo Films")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showImport = true } label: { Image(systemName: "plus") }
            }
#if os(iOS)
            // macOS gets Settings via Velo Films → Settings… (⌘,); show button on iPad only
            ToolbarItem(placement: .navigation) {
                Button { showSettings = true } label: {
                    Image(systemName: "gear")
                }
            }
#endif
        }
        .sheet(isPresented: $showImport) {
            ImportView()
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                GlobalSettingsView()
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
        .overlay {
            if store.projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "film.stack",
                    description: Text("Tap + to add a ride project")
                )
            }
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let lastUpdate: Date   // passed from parent to force re-render after pipeline steps
    var artifacts: ProjectArtifacts { ProjectArtifacts.check(project) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.headline)
                Text(statusLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if artifacts.finalReelExists {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusLabel: String {
        let a = artifacts
        if a.finalReelExists   { return "Complete" }
        if a.selectExists      { return "Ready to build" }
        if a.enrichedExists    { return "Enriched" }
        if a.extractExists     { return "Extracted" }
        if a.flattenExists     { return "GPX parsed" }
        return "Not started"
    }
}
