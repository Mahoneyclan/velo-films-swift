import Foundation

/// Creates and validates the project directory structure on disk.
/// Mirrors io_paths.py. All paths are derived from Project.folderURL.
enum ProjectFileManager {
    static func createDirectoryStructure(for project: Project) throws {
        let dirs: [URL] = [
            project.workingDir,
            project.clipsDir,
            project.framesDir,
            project.minimapsDir,
            project.gaugesDir,
            project.elevationDir,
            project.trophiesDir,
            project.splashAssetsDir,
            project.logsDir,
        ]
        for dir in dirs {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Discover project folders in a projects root directory.
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

    /// Find all source video files for a project's source folder.
    /// Source folder is {inputBaseDir}/{rideFolderName} or supplied directly.
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

    /// Find a GPX file in the given directory (returns first match).
    static func findGPXFile(in dir: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return contents.first { $0.pathExtension.lowercased() == "gpx" }
    }
}
