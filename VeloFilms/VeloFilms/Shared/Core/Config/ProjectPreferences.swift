import Foundation

/// Per-project overrides stored as preferences.json in the project folder.
/// Mirrors the per-project fields of persistent_config.py that vary ride-to-ride.
struct ProjectPreferences: Codable {
    /// Music track filename (e.g. "track01.mp3"). Empty string = pick randomly.
    var selectedMusicTrack: String = ""

    /// Override global highlight target duration. nil = use GlobalSettings.highlightTargetMinutes.
    var highlightTargetMinutes: Double? = nil

    /// Free-text notes about this ride.
    var notes: String = ""
}

extension Project {
    var preferencesURL: URL {
        folderURL.appending(path: "preferences.json")
    }

    func loadPreferences() -> ProjectPreferences {
        guard let data = try? Data(contentsOf: preferencesURL),
              let prefs = try? JSONDecoder().decode(ProjectPreferences.self, from: data)
        else { return ProjectPreferences() }
        return prefs
    }

    func savePreferences(_ prefs: ProjectPreferences) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        try? data.write(to: preferencesURL, options: .atomic)
    }

    /// Effective highlight target: project override → global setting → AppConfig default.
    func effectiveHighlightTargetMinutes() -> Double {
        loadPreferences().highlightTargetMinutes ?? GlobalSettings.shared.highlightTargetMinutes
    }

    /// Effective target clip count for this project.
    func effectiveTargetClips() -> Int {
        Int((effectiveHighlightTargetMinutes() * 60) / AppConfig.clipOutLenS)
    }
}
