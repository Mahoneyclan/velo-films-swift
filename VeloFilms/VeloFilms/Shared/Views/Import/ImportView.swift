import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showCopyVideos = false
    @State private var showFolderPicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Button { pickFolder() } label: {
                    Label("Select raw video folder…", systemImage: "film.stack")
                }
                Button { showCopyVideos = true } label: {
                    Label("Copy from Camera (Cycliq)", systemImage: "sdcard")
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
                    addProject(at: url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
#endif
        }
        .frame(minWidth: 360, minHeight: 220)
        .alert("Failed to Create Project", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func pickFolder() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            addProject(at: url)
        }
#else
        showFolderPicker = true
#endif
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
            errorMessage = error.localizedDescription
            return
        }
        store.add(project)
        dismiss()
    }
}
