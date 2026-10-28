// ImportView.swift
// "Add Project" sheet: create a project from a folder of raw clips, copy clips from the camera first, or open a
// project made earlier (on this or another device).

import SwiftUI
import UniformTypeIdentifiers

/// Lets the user pick a raw-video folder (creating a project for it), open the camera copy screen, or open an
/// existing project folder.
struct ImportView: View {
    /// What the folder picker is choosing.
    private enum FolderPurpose {
        /// A folder of raw clips; a new project is created for it.
        case rawVideos
        /// A project folder made earlier; it is added to the list as it is.
        case existingProject
    }

    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showCopyVideos = false
    @State private var showFolderPicker = false
    @State private var folderPurpose = FolderPurpose.rawVideos
    @State private var errorTitle = "Failed to Create Project"
    @State private var errorMessage: String?

    /// The three options and the platform folder picker.
    var body: some View {
        NavigationStack {
            List {
                Section("New project") {
                    Button { pickFolder(for: .rawVideos) } label: {
                        Label("Select raw video folder…", systemImage: "film.stack")
                    }
                    Button { showCopyVideos = true } label: {
                        Label("Copy from Camera (Cycliq)", systemImage: "sdcard")
                    }
                }
                Section {
                    Button { pickFolder(for: .existingProject) } label: {
                        Label("Open existing project…", systemImage: "folder")
                    }
                } footer: {
                    Text("Choose a ride's project folder, the one holding its working, clips and frames folders.")
                }
            }
            .navigationTitle("Add Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCopyVideos) { CopyVideosView { dismiss() } }
#if os(iOS)
            // iOS folder picker — presented as a system sheet over this view
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    // Start security-scoped access and leave it open for the session —
                    // the pipeline needs to read from this folder when it runs.
                    _ = url.startAccessingSecurityScopedResource()
                    handlePicked(url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
#endif
        }
        .frame(minWidth: 360, minHeight: 300)
        .alert(errorTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func pickFolder(for purpose: FolderPurpose) {
        folderPurpose = purpose
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = purpose == .existingProject ? "Open Project" : "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            handlePicked(url)
        }
#else
        showFolderPicker = true
#endif
    }

    private func handlePicked(_ url: URL) {
        switch folderPurpose {
        case .rawVideos:       addProject(at: url)
        case .existingProject: openProject(at: url)
        }
    }

    /// Adds a project folder made earlier, or selects it if it's already in the list.
    private func openProject(at url: URL) {
        guard ProjectFileManager.isProjectFolder(url) else {
            errorTitle = "Not a Velo Films Project"
            errorMessage = "“\(url.lastPathComponent)” has no working folder. Choose the ride's project folder, "
                + "not the folder of raw clips. To start a new project from clips, use Select raw video folder."
            return
        }
        store.open(folderURL: url)
        dismiss()
    }

    private func addProject(at sourceURL: URL) {
        let name = sourceURL.lastPathComponent
        let folderURL: URL
        if let root = GlobalSettings.shared.projectsRoot {
            folderURL = root.appending(path: name)
        } else {
            folderURL = sourceURL
        }
        let project = Project(name: name, folderURL: folderURL, sourceVideoURL: sourceURL)
        do {
            try ProjectFileManager.createDirectoryStructure(for: project)
        } catch {
            errorTitle = "Failed to Create Project"
            errorMessage = error.localizedDescription
            return
        }
        store.add(project)
        dismiss()
    }
}
