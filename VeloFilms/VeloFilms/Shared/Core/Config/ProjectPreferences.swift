// ProjectPreferences.swift
// Per-ride settings saved in each project folder, and helpers on Project to read and write them.

import Foundation

/// Per-project overrides stored as preferences.json in the project folder.
/// Holds the settings that vary ride to ride (per-project fields of `persistent_config.py` in the original Python app).
struct ProjectPreferences: Codable {
    /// Music track filename (e.g. "track01.mp3"). Empty string = pick randomly.
    var selectedMusicTrack: String = ""

    /// Override global highlight target duration. nil = use GlobalSettings.highlightTargetMinutes.
    /// Saved and shown in Project Preferences, but clip selection currently uses the global setting only.
    var highlightTargetMinutes: Double? = nil

    /// Free-text notes about this ride.
    var notes: String = ""
}

extension Project {
    /// Location of this project's `preferences.json`.
    var preferencesURL: URL {
        folderURL.appending(path: "preferences.json")
    }

    /// Reads `preferences.json`.
    /// - Returns: The saved preferences, or defaults if the file is missing or unreadable.
    func loadPreferences() -> ProjectPreferences {
        guard let data = try? Data(contentsOf: preferencesURL),
              let prefs = try? JSONDecoder().decode(ProjectPreferences.self, from: data)
        else { return ProjectPreferences() }
        return prefs
    }

    /// Writes `preferences.json` atomically. Failures are ignored (the previous file is kept).
    /// - Parameter prefs: The preferences to save.
    func savePreferences(_ prefs: ProjectPreferences) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        try? data.write(to: preferencesURL, options: .atomic)
    }

    /// Effective highlight target in minutes: the project override if set, otherwise the global setting
    /// (which itself defaults to `AppConfig.highlightTargetDurationM`).
    /// - Returns: Minutes of highlights to aim for.
    func effectiveHighlightTargetMinutes() -> Double {
        loadPreferences().highlightTargetMinutes ?? GlobalSettings.shared.highlightTargetMinutes
    }

    /// Number of clips needed to fill this project's target length, rounded down. Not currently used.
    /// - Returns: The clip count, from the target length divided by the clip length.
    func effectiveTargetClips() -> Int {
        Int((effectiveHighlightTargetMinutes() * 60) / AppConfig.clipOutLenS)
    }
}
