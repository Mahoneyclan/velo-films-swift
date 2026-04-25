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

    var flattenJSONL: URL    { workingDir.appending(path: "flatten.jsonl") }
    var extractJSONL: URL   { workingDir.appending(path: "extract.jsonl") }
    var enrichedJSONL: URL  { workingDir.appending(path: "enriched.jsonl") }
    var selectJSONL: URL    { workingDir.appending(path: "select.jsonl") }
    var segmentsJSON: URL    { workingDir.appending(path: "segments.json") }
    var finalConcatList: URL { workingDir.appending(path: "final_concat_list.txt") }
    var finalReelURL: URL    { folderURL.appending(path: "\(name).mp4") }
}

extension Project {
    func createOutputDirectories() throws {
        try ProjectFileManager.createDirectoryStructure(for: self)
    }
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
            flattenExists:   fm.fileExists(atPath: project.flattenJSONL.path),
            extractExists:   fm.fileExists(atPath: project.extractJSONL.path),
            enrichedExists:  fm.fileExists(atPath: project.enrichedJSONL.path),
            selectExists:    fm.fileExists(atPath: project.selectJSONL.path),
            finalReelExists: fm.fileExists(atPath: project.finalReelURL.path)
        )
    }
}

/// Observable list of projects — passed via the SwiftUI environment.
@Observable
final class ProjectStore {
    var projects: [Project] = []
    var selected: Project?
    var lastPipelineUpdate: Date = .now

    init() { load() }

    func add(_ project: Project) {
        projects.append(project)
        save()
    }

    func remove(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        if selected?.id == project.id { selected = nil }
        save()
    }

    // MARK: - Persistence

    private static let udKey = "projectStoreV1"

    private func save() {
        let records: [[String: String]] = projects.map { project in
            ["name": project.name, "id": project.id.uuidString, "path": project.folderURL.path]
        }
        UserDefaults.standard.set(records, forKey: Self.udKey)
    }

    private func load() {
        guard let records = UserDefaults.standard.array(forKey: Self.udKey) as? [[String: String]] else { return }
        projects = records.compactMap { record in
            guard let name = record["name"],
                  let idStr = record["id"],
                  let id = UUID(uuidString: idStr),
                  let path = record["path"] else { return nil }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return Project(id: id, name: name, folderURL: url)
        }
    }
}
