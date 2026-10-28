// ProjectListView.swift
// Sidebar list of ride projects, with Add Project and Settings buttons.

import SwiftUI

/// The project sidebar. "Delete" (swipe) and "Remove from list" (context menu) both only remove the project
/// from the list, without asking; its folder on disk is kept.
struct ProjectListView: View {
    @Environment(ProjectStore.self) private var store
    @State private var showImport = false
    @State private var showSettings = false

    /// The list, its toolbar and the Add Project and Settings sheets.
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
                ContentUnavailableView {
                    Label("No Projects Yet", systemImage: "film.stack")
                } description: {
                    Text("Insert your Cycliq SD card, then tap **+** → Copy from Camera to create your first ride project. Made one before? Tap **+** → Open existing project.")
                } actions: {
                    Button("Add Project") { showImport = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let lastUpdate: Date   // passed from parent to force re-render after pipeline steps
    var artifacts: ProjectArtifacts { ProjectArtifacts.check(project) }

    var body: some View {
        let available = project.isFolderAvailable
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.headline)
                Text(available ? statusLabel : "Drive not connected").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !available {
                Image(systemName: "externaldrive.badge.xmark").foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else if artifacts.finalReelExists {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
        .opacity(available ? 1 : 0.6)
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
