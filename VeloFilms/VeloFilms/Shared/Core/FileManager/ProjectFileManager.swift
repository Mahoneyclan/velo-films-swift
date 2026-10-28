// ProjectFileManager.swift
// Folder layout and file discovery for a ride project.

import Foundation

/// Creates the project folder structure and finds input files on disk.
/// All paths are derived from `Project.folderURL`. Ported from `io_paths.py` in the original Python app.
enum ProjectFileManager {
    /// Creates the project folder and its working subfolders if they don't exist.
    /// - Parameter project: The project whose folders to create.
    /// - Throws: File system errors, e.g. when the drive is not mounted or read-only.
    static func createDirectoryStructure(for project: Project) throws {
        let dirs: [URL] = [
            project.folderURL,
            project.workingDir,
            project.clipsDir,
            project.framesDir,
            project.minimapsDir,
            project.elevationDir,
            project.splashAssetsDir,
        ]
        for dir in dirs {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Whether a folder is a Velo Films project: it holds a `working/` folder (created with every project and
    /// where the pipeline writes its files). Used by "Open Existing Project" to reject raw-clip folders.
    /// - Parameter url: The folder the user picked.
    /// - Returns: `true` if `url/working` exists and is a folder.
    static func isProjectFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.appending(path: "working").path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Lists every subfolder of `root` as a project, newest name first. Not currently used.
    /// - Parameter root: The projects root folder.
    /// - Returns: One `Project` per subfolder.
    /// - Throws: File system errors reading `root`.
    static func discoverProjects(in root: URL) throws -> [Project] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .map { url in
                Project(name: url.lastPathComponent, folderURL: url)
            }
            .sorted { $0.name > $1.name }
    }

    /// Lists the `.MP4` clips directly inside `sourceDir` (not subfolders), sorted by file name, which is
    /// recording order for Cycliq cameras.
    /// - Parameter sourceDir: `{inputBaseDir}/{rideFolderName}` or a folder the user picked.
    /// - Returns: Clip URLs in name order.
    /// - Throws: File system errors reading the folder.
    static func findVideoFiles(in sourceDir: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: sourceDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { $0.pathExtension.uppercased() == "MP4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Returns the first `.gpx` file found directly inside `dir`, or `nil` if there is none or the folder
    /// can't be read. If several exist, which one is "first" is not defined.
    /// - Parameter dir: Folder to search (not recursive).
    /// - Returns: A `.gpx` file, or `nil`.
    static func findGPXFile(in dir: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return contents.first { $0.pathExtension.lowercased() == "gpx" }
    }
}
