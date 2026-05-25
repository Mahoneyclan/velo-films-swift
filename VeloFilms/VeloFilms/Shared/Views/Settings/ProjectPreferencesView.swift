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
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task {
            prefs = project.loadPreferences()
            availableTracks = discoverTracks()
        }
    }

    private func discoverTracks() -> [String] {
        let extensions = ["mp3", "m4a", "aac", "wav"]
        var names: [String] = []

        // Bundled tracks in the music/ subfolder (folder reference)
        for ext in extensions {
            names += (Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "music") ?? [])
                .map { $0.lastPathComponent }
        }

        // Fallback: Xcode may flatten subdirectory into bundle root
        if names.isEmpty {
            let splash = Set(["intro", "outro"])
            for ext in extensions {
                names += (Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [])
                    .filter { !splash.contains($0.deletingPathExtension().lastPathComponent) }
                    .map { $0.lastPathComponent }
            }
        }

        return Array(Set(names)).sorted()
    }
}
