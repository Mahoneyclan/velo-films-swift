// Project.swift
// The ride project model, its on-disk paths, a check of which pipeline outputs exist, and the saved project list.

import Foundation
import Observation

/// A single ride project, stored on disk at `{projectsRoot}/{rideFolder}/`.
struct Project: Identifiable, Codable, Hashable {
    /// Stable identifier, saved with the project list.
    let id: UUID
    /// Ride folder name, e.g. `"2025-04-20-Wahgunyah"`. Also used for the final reel's file name.
    var name: String
    /// The project folder, which holds `working/`, `clips/`, `frames/` and the other output folders.
    var folderURL: URL
    /// Folder of raw camera MP4s chosen when the project was created; `nil` means `{inputBaseDir}/{name}`.
    var sourceVideoURL: URL?

    /// Creates a project. A new random `id` is used unless one is supplied (e.g. when loading).
    /// - Parameters:
    ///   - id: Stable identifier saved in the project list.
    ///   - name: Project (ride) name, also the folder name.
    ///   - folderURL: The project folder on the external drive.
    ///   - sourceVideoURL: Folder holding the raw clips, or `nil` for `{inputBase}/{name}/`.
    init(id: UUID = UUID(), name: String, folderURL: URL, sourceVideoURL: URL? = nil) {
        self.id = id
        self.name = name
        self.folderURL = folderURL
        self.sourceVideoURL = sourceVideoURL
    }
}

/// Paths derived from `folderURL`. File names are permanent: existing projects on disk use them.
/// Same layout as `io_paths.py` in the original Python app.
extension Project {
    /// Folder for intermediate pipeline files (`working/`).
    var workingDir: URL      { folderURL.appending(path: "working") }
    /// Rendered highlight clips.
    var clipsDir: URL        { folderURL.appending(path: "clips") }
    /// Extracted still frames.
    var framesDir: URL       { folderURL.appending(path: "frames") }
    /// Rendered map overlays.
    var minimapsDir: URL     { folderURL.appending(path: "minimaps") }
    /// Rendered elevation-strip overlays.
    var elevationDir: URL    { folderURL.appending(path: "elevation") }
    /// Intro and outro assets.
    var splashAssetsDir: URL { folderURL.appending(path: "splash_assets") }

    /// The ride's GPX track (`working/ride.gpx`).
    var gpxFile: URL         { workingDir.appending(path: "ride.gpx") }

    /// Output of the Flatten step.
    var flattenJSONL: URL    { workingDir.appending(path: "flatten.jsonl") }
    /// Output of the Extract step.
    var extractJSONL: URL   { workingDir.appending(path: "extract.jsonl") }
    /// Output of the Enrich step.
    var enrichedJSONL: URL  { workingDir.appending(path: "enriched.jsonl") }
    /// Output of the Select step, also edited by manual selection.
    var selectJSONL: URL    { workingDir.appending(path: "select.jsonl") }
    /// Strava segment efforts.
    var segmentsJSON: URL    { workingDir.appending(path: "segments.json") }
    /// Strava laps.
    var lapsJSON: URL        { workingDir.appending(path: "laps.json") }
    /// Strava activity description.
    var descriptionTXT: URL  { workingDir.appending(path: "description.txt") }
    /// FFmpeg concat list path. Not currently used.
    var finalConcatList: URL { workingDir.appending(path: "final_concat_list.txt") }
    /// The finished highlight reel, `{name}.mp4` in the project folder.
    var finalReelURL: URL    { folderURL.appending(path: "\(name).mp4") }

    /// The default source clip folder, `{inputBase}/{name}/`, used when `sourceVideoURL` is `nil`.
    /// - Parameter inputBase: The Input Videos folder from Settings.
    /// - Returns: `inputBase` plus the project name.
    func sourceVideosDir(inputBase: URL) -> URL { inputBase.appending(path: name) }
}

extension Project {
    /// `true` if the project folder can be reached now; `false` when its drive isn't connected.
    /// - Note: Synchronous file system check; cheap, but don't call it in a tight loop.
    var isFolderAvailable: Bool { FileManager.default.fileExists(atPath: folderURL.path) }

    /// This project's camera-video folder on this device: the folder chosen when the project was created, else the
    /// Input Videos folder from Settings plus the project name (e.g. `Fly_Raw/[Name]`).
    /// - Parameter inputBase: The Input Videos folder (injectable for tests).
    /// - Returns: The folder, or `nil` when neither is set.
    func videoFolder(inputBase: URL? = GlobalSettings.shared.inputBaseDir) -> URL? {
        sourceVideoURL ?? inputBase.map { sourceVideosDir(inputBase: $0) }
    }

    /// Where a clip named in the project's files is on this device.
    ///
    /// The stored `video_path` is a full path on whichever device analysed the ride (`/Volumes/AData/…` on the Mac,
    /// `/private/var/mobile/…` on iPad), and the same drive appears at a different path on the other device. Only
    /// its file name is used, looked up in `videoFolder(inputBase:)`.
    /// - Parameters:
    ///   - path: `video_path` from a project file.
    ///   - inputBase: The Input Videos folder (injectable for tests).
    /// - Returns: The clip's URL in this device's video folder, or `path` unchanged when no folder is set.
    func videoURL(forStoredPath path: String, inputBase: URL? = GlobalSettings.shared.inputBaseDir) -> URL {
        let stored = URL(fileURLWithPath: path)
        guard let folder = videoFolder(inputBase: inputBase) else { return stored }
        return folder.appending(path: stored.lastPathComponent)
    }

    /// Creates the project folder and its output subfolders.
    /// - Throws: File system errors, e.g. when the drive is not mounted.
    func createOutputDirectories() throws {
        try ProjectFileManager.createDirectoryStructure(for: self)
    }
}

/// A snapshot of which inputs and pipeline outputs exist for a project. Drives the status rows and button
/// states on the project screen.
struct ProjectArtifacts {
    // Prerequisites
    /// `true` if `working/ride.gpx` exists. Only this name counts here, although Flatten also finds other
    /// `.gpx` names (see FlattenStep).
    let gpxExists: Bool
    /// Number of `.MP4` files in the source folder.
    let sourceVideoCount: Int

    // Analysis phase outputs
    /// `true` if `working/flatten.jsonl` exists (the step has run at least once; it may be out of date).
    let flattenExists: Bool
    /// `true` if `working/extract.jsonl` exists (the step has run at least once; it may be out of date).
    let extractExists: Bool
    /// `true` if `working/enriched.jsonl` exists (the step has run at least once; it may be out of date).
    let enrichedExists: Bool
    /// `true` if `working/select.jsonl` exists (the step has run at least once; it may be out of date).
    let selectExists: Bool

    // Build phase output
    /// `true` if the finished reel exists.
    let finalReelExists: Bool

    /// `true` if there is at least one source clip.
    var hasVideos: Bool { sourceVideoCount > 0 }
    /// `true` when the analysis steps can run: a GPX and at least one clip.
    var analysisReady: Bool { gpxExists && hasVideos }

    /// Checks the disk for each input and output.
    /// - Parameters:
    ///   - project: The project to check.
    ///   - inputBase: Base folder for source clips when the project has no explicit source folder.
    /// - Returns: The snapshot. An unreadable source folder counts as zero clips.
    /// - Note: Synchronous file system access; call it when the screen appears or after a step finishes.
    static func check(_ project: Project, inputBase: URL? = GlobalSettings.shared.inputBaseDir) -> ProjectArtifacts {
        let fm = FileManager.default
        var videoCount = 0
        if let srcDir = project.videoFolder(inputBase: inputBase) {
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

/// The saved list of projects, passed through the SwiftUI environment.
///
/// Saved in UserDefaults under `projectStoreV1` (permanent key) as name, ID and paths only; project data stays
/// in the project folders.
@Observable
final class ProjectStore {
    /// All known projects, in the order they were added.
    var projects: [Project] = []
    /// The project open in the detail view, if any.
    var selected: Project?
    /// Time of the last pipeline step change; views observe it to refresh.
    var lastPipelineUpdate: Date = .now

    /// Loads the saved project list.
    init() { load() }

    /// Adds a project and saves the list.
    /// - Parameter project: The project to add.
    func add(_ project: Project) {
        projects.append(project)
        save()
    }

    /// Adds an existing project folder to the list, or finds it if it's already there, and selects it.
    /// - Parameter folderURL: A folder that `ProjectFileManager.isProjectFolder` accepts.
    /// - Returns: The project now selected.
    @discardableResult
    func open(folderURL: URL) -> Project {
        if let existing = Self.project(at: folderURL, in: projects) {
            selected = existing
            return existing
        }
        let project = Project(name: folderURL.lastPathComponent, folderURL: folderURL)
        add(project)
        selected = project
        return project
    }

    /// The project whose folder is `folderURL`, comparing standardized paths (so a trailing slash or `..`
    /// doesn't create a duplicate).
    /// - Parameters:
    ///   - folderURL: The folder to look for.
    ///   - projects: The list to search.
    /// - Returns: The matching project, or `nil`.
    static func project(at folderURL: URL, in projects: [Project]) -> Project? {
        let target = comparablePath(folderURL)
        return projects.first { comparablePath($0.folderURL) == target }
    }

    /// `url`'s path with `..`/`.` resolved and no trailing slash (folder URLs from pickers end in "/").
    private static func comparablePath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// Removes a project from the list (its folder is not deleted) and saves the list.
    /// - Parameter project: The project to remove (matched by `id`).
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
        // Use bookmark-resolved roots so derived URLs inherit the TCC/powerbox access grant.
        let root    = GlobalSettings.shared.projectsRoot
        let srcBase = GlobalSettings.shared.inputBaseDir
        projects = records.compactMap { record in
            guard let name = record["name"],
                  let idStr = record["id"],
                  let id = UUID(uuidString: idStr),
                  let path = record["path"] else { return nil }
            // Projects whose drive isn't connected are kept; the list shows them as "Drive not connected"
            // (`Project.isFolderAvailable`).
            let url       = Self.reanchor(path: path, under: root)
            let sourceURL = record["sourcePath"].map { Self.reanchor(path: $0, under: srcBase) }
            return Project(id: id, name: name, folderURL: url, sourceVideoURL: sourceURL)
        }
    }

    /// Re-derives a URL from a bookmark-resolved parent when the path falls inside it,
    /// so the resulting URL inherits the parent's TCC access context.
    private static func reanchor(path: String, under parent: URL?) -> URL {
        if let parent {
            let parentPath = parent.path(percentEncoded: false)
            if path.hasPrefix(parentPath) {
                let relative = String(path.dropFirst(parentPath.count)).drop(while: { $0 == "/" })
                if !relative.isEmpty {
                    return parent.appending(path: String(relative))
                }
                return parent
            }
        }
        return URL(fileURLWithPath: path)
    }
}


