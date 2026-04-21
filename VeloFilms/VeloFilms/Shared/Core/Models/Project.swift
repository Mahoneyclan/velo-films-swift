import Foundation
import Observation

/// A single ride project — maps to {PROJECTS_ROOT}/{rideFolder}/ on disk.
struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String           // ride folder name, e.g. "2025-04-20-Wahgunyah"
    var folderURL: URL         // security-scoped resolved URL

    init(id: UUID = UUID(), name: String, folderURL: URL) {
        self.id = id
        self.name = name
        self.folderURL = folderURL
    }
}

/// Derived path properties — mirrors io_paths.py.
extension Project {
    var workingDir: URL      { folderURL.appending(path: "working") }
    var clipsDir: URL        { folderURL.appending(path: "clips") }
    var framesDir: URL       { folderURL.appending(path: "frames") }
    var minimapsDir: URL     { folderURL.appending(path: "minimaps") }
    var gaugesDir: URL       { folderURL.appending(path: "gauges") }
    var elevationDir: URL    { folderURL.appending(path: "elevation") }
    var trophiesDir: URL     { folderURL.appending(path: "trophies") }
    var splashAssetsDir: URL { folderURL.appending(path: "splash_assets") }
    var logsDir: URL         { folderURL.appending(path: "logs") }

    var flattenCSV: URL      { workingDir.appending(path: "flatten.csv") }
    var extractCSV: URL      { workingDir.appending(path: "extract.csv") }
    var enrichedCSV: URL     { workingDir.appending(path: "enriched.csv") }
    var selectCSV: URL       { workingDir.appending(path: "select.csv") }
    var segmentsJSON: URL    { workingDir.appending(path: "segments.json") }
    var finalConcatList: URL { workingDir.appending(path: "final_concat_list.txt") }
    var finalReelURL: URL    { folderURL.appending(path: "\(name).mp4") }
}

/// Tracks which pipeline artifacts exist for a project (drives button state in UI).
struct ProjectArtifacts {
    let flattenExists: Bool
    let extractExists: Bool
    let enrichedExists: Bool
    let selectExists: Bool
    let finalReelExists: Bool

    static func check(_ project: Project) -> ProjectArtifacts {
        let fm = FileManager.default
        return ProjectArtifacts(
            flattenExists:   fm.fileExists(atPath: project.flattenCSV.path),
            extractExists:   fm.fileExists(atPath: project.extractCSV.path),
            enrichedExists:  fm.fileExists(atPath: project.enrichedCSV.path),
            selectExists:    fm.fileExists(atPath: project.selectCSV.path),
            finalReelExists: fm.fileExists(atPath: project.finalReelURL.path)
        )
    }
}

/// Observable list of projects — passed via the SwiftUI environment.
@Observable
final class ProjectStore {
    var projects: [Project] = []
    var selected: Project?

    func add(_ project: Project) {
        projects.append(project)
    }

    func remove(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        if selected?.id == project.id { selected = nil }
    }
}
