import SwiftUI

struct ImportView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showCopyVideos = false

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
        }
        .frame(minWidth: 360, minHeight: 220)
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
#endif
    }

    private func addProject(at sourceURL: URL) {
        let name = sourceURL.lastPathComponent
        let folderURL: URL
        if let root = GlobalSettings.shared.projectsRoot {
            folderURL = root.appending(path: name)
        } else {
            // No projects root set — create working files inside the source folder
            folderURL = sourceURL
        }
        let project = Project(name: name, folderURL: folderURL, sourceVideoURL: sourceURL)
        try? ProjectFileManager.createDirectoryStructure(for: project)
        store.add(project)
        dismiss()
    }
}
