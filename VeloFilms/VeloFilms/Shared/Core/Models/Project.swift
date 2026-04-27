import Foundation
import Observation

/// A single ride project — maps to {PROJECTS_ROOT}/{rideFolder}/ on disk.
struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String           // ride folder name, e.g. "2025-04-20-Wahgunyah"
    var folderURL: URL         // project working directory (working/, clips/, frames/ etc.)
    var sourceVideoURL: URL?   // folder containing raw MP4s — set at project creation

    init(id: UUID = UUID(), name: String, folderURL: URL, sourceVideoURL: URL? = nil) {
        self.id = id
        self.name = name
        self.folderURL = folderURL
        self.sourceVideoURL = sourceVideoURL
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

    var gpxFile: URL         { workingDir.appending(path: "ride.gpx") }

    var flattenJSONL: URL    { workingDir.appending(path: "flatten.jsonl") }
    var extractJSONL: URL   { workingDir.appending(path: "extract.jsonl") }
    var enrichedJSONL: URL  { workingDir.appending(path: "enriched.jsonl") }
    var selectJSONL: URL    { workingDir.appending(path: "select.jsonl") }
    var segmentsJSON: URL    { workingDir.appending(path: "segments.json") }
    var finalConcatList: URL { workingDir.appending(path: "final_concat_list.txt") }
    var finalReelURL: URL    { folderURL.appending(path: "\(name).mp4") }

    /// Source clips directory: inputBaseDir/{name}/
    func sourceVideosDir(inputBase: URL) -> URL { inputBase.appending(path: name) }
}

extension Project {
    func createOutputDirectories() throws {
        try ProjectFileManager.createDirectoryStructure(for: self)
    }
}

/// Tracks which pipeline artifacts and prerequisites exist for a project.
struct ProjectArtifacts {
    // Prerequisites
    let gpxExists: Bool
    let sourceVideoCount: Int

    // Analysis phase outputs
    let flattenExists: Bool
    let extractExists: Bool
    let enrichedExists: Bool
    let selectExists: Bool

    // Build phase output
    let finalReelExists: Bool

    var hasVideos: Bool { sourceVideoCount > 0 }
    var analysisReady: Bool { gpxExists && hasVideos }

    static func check(_ project: Project, inputBase: URL? = GlobalSettings.shared.inputBaseDir) -> ProjectArtifacts {
        let fm = FileManager.default
        var videoCount = 0
        let srcDir: URL? = project.sourceVideoURL
            ?? inputBase.map { project.sourceVideosDir(inputBase: $0) }
        if let srcDir {
            let contents = (try? fm.contentsOfDirectory(at: srcDir,
                                                         includingPropertiesForKeys: nil,
                                                         options: .skipsHiddenFiles)) ?? []
            videoCount = contents.filter { $0.pathExtension.uppercased() == "MP4" }.count
        }
        return ProjectArtifacts(
            gpxExists:       fm.fileExists(atPath: project.gpxFile.path),
            sourceVideoCount: videoCount,
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
            var r = ["name": project.name, "id": project.id.uuidString, "path": project.folderURL.path]
            if let src = project.sourceVideoURL { r["sourcePath"] = src.path }
            return r
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
            let sourceURL = record["sourcePath"].map { URL(fileURLWithPath: $0) }
            return Project(id: id, name: name, folderURL: url, sourceVideoURL: sourceURL)
        }
    }
}
