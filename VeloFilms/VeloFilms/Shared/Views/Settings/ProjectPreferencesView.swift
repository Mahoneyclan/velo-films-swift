// ProjectPreferencesView.swift
// Per-project settings sheet, saved to the project's preferences.json.

import SwiftUI

/// Per-project settings sheet — music track, highlight target override, notes.
struct ProjectPreferencesView: View {
    /// The project whose preferences are edited.
    let project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var prefs = ProjectPreferences()
    @State private var availableTracks: [String] = []

    /// Music track, highlight length override and notes.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: Music
                    GroupBox("Music") {
                        VStack(alignment: .leading, spacing: 12) {
                            if availableTracks.isEmpty {
                                Text("No music yet. Choose a music folder or add songs in Settings → Audio.")
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
                                Text("Random picks a different track each build. Ignored when Settings → Audio → Single Track Override is set.")
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
        MusicLibrary.allTracks().map(\.lastPathComponent)
    }
}
