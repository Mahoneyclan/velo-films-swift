import SwiftUI

/// Per-project settings sheet — music track, highlight target override, notes.
struct ProjectPreferencesView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var prefs = ProjectPreferences()
    @State private var availableTracks: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: Music
                    GroupBox("Music") {
                        VStack(alignment: .leading, spacing: 12) {
                            if availableTracks.isEmpty {
                                Text("No music tracks found in bundle or Shared/Resources/music")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            } else {
                                Picker("Track", selection: $prefs.selectedMusicTrack) {
                                    Text("Random").tag("")
                                    ForEach(availableTracks, id: \.self) { track in
                                        Text(track).tag(track)
                                    }
                                }
                                .pickerStyle(.menu)
                                Text("Random picks a different track each build.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    // MARK: Highlight Duration
                    GroupBox("Highlight Duration") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Override global setting", isOn: Binding(
                                get: { prefs.highlightTargetMinutes != nil },
                                set: { prefs.highlightTargetMinutes = $0
                                    ? (prefs.highlightTargetMinutes ?? GlobalSettings.shared.highlightTargetMinutes)
                                    : nil }
                            ))
                            if prefs.highlightTargetMinutes != nil {
                                HStack {
                                    Text("Duration (min)")
                                    Spacer()
                                    TextField("5.0", value: Binding(
                                        get: { prefs.highlightTargetMinutes ?? GlobalSettings.shared.highlightTargetMinutes },
                                        set: { prefs.highlightTargetMinutes = $0 }
                                    ), format: .number)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
#if os(macOS)
                                    .textFieldStyle(.roundedBorder)
#endif
                                }
                                Text("Global default: \(GlobalSettings.shared.highlightTargetMinutes, specifier: "%.1f") min → \(AppConfig.targetClips) clips")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    // MARK: Notes
                    GroupBox("Notes") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $prefs.notes)
                                .frame(minHeight: 80)
#if os(macOS)
                                .font(.body)
#endif
                            Text("Saved with the project. Not used by the pipeline.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Project Preferences — \(project.name)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        project.savePreferences(prefs)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .task {
            prefs = project.loadPreferences()
            availableTracks = discoverTracks()
        }
    }

    private func discoverTracks() -> [String] {
        let extensions = Set(["mp3", "m4a", "aac", "wav"])
        var names: [String] = []

        if let bundleURL = Bundle.main.resourceURL {
            let musicDir = bundleURL.appending(path: "music")
            if let files = try? FileManager.default.contentsOfDirectory(
                at: musicDir, includingPropertiesForKeys: nil) {
                names += files
                    .filter { extensions.contains($0.pathExtension.lowercased()) }
                    .map { $0.lastPathComponent }
            }
        }
        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                names += urls.map { $0.lastPathComponent }
            }
        }
        let repoMusic = URL(fileURLWithPath: "/Volumes/AData/Github/velo-films-swift/Shared/Resources/music")
        if let files = try? FileManager.default.contentsOfDirectory(
            at: repoMusic, includingPropertiesForKeys: nil) {
            names += files
                .filter { extensions.contains($0.pathExtension.lowercased()) }
                .map { $0.lastPathComponent }
        }

        return Array(Set(names)).sorted()
    }
}
