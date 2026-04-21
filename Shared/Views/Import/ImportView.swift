import SwiftUI

/// Entry point for adding a new project — pick a ride folder or import from Strava/Garmin.
struct ImportView: View {
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var settings: GlobalSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showStrava = false
    @State private var showGarmin = false

    var body: some View {
        NavigationStack {
            List {
                Section("From Disk") {
                    Button {
                        pickFolder()
                    } label: {
                        Label("Choose ride folder...", systemImage: "folder")
                    }
                }
                Section("Import GPX from") {
                    Button { showStrava = true } label: {
                        Label("Strava", systemImage: "figure.cycling")
                    }
                    Button { showGarmin = true } label: {
                        Label("Garmin Connect", systemImage: "arrow.down.circle")
                    }
                }
            }
            .navigationTitle("Add Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showStrava)  { StravaImportView() }
            .sheet(isPresented: $showGarmin)  { GarminImportView() }
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
#endif
        // iOS: handled via DrivePickerView in Settings (drive root must be set first)
    }

    private func addProject(at url: URL) {
        let project = Project(name: url.lastPathComponent, folderURL: url)
        try? ProjectFileManager.createDirectoryStructure(for: project)
        store.add(project)
        dismiss()
    }
}
