// ContentView.swift
// Root screen: project list in the sidebar, the selected project on the right, and first-run setup.

import SwiftUI

/// The app's root split view. Shows onboarding when the projects or input folder isn't set.
struct ContentView: View {
    @Environment(ProjectStore.self) private var projectStore
    @State private var showOnboarding = false

    private var settings: GlobalSettings { GlobalSettings.shared }
    private var needsSetup: Bool {
        settings.projectsRoot == nil || settings.inputBaseDir == nil
    }

    /// Sidebar list plus the selected project's detail, or an empty-state prompt.
    var body: some View {
        NavigationSplitView {
            ProjectListView()
#if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
#endif
        } detail: {
            if let project = projectStore.selected {
                if project.isFolderAvailable {
                    ProjectDetailView(project: project)
                } else {
                    ContentUnavailableView {
                        Label("Drive not connected", systemImage: "externaldrive.badge.xmark")
                    } description: {
                        Text("Connect the drive holding \(project.name), then select it again.\n\(project.folderURL.path)")
                    }
                }
            } else {
                emptyDetail
            }
        }
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
