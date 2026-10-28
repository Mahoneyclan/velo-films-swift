// MusicLibrary.swift
// Finds backing-music tracks: the royalty-free tracks built into the app plus the user's own tracks in
// "My Music". Used by ConcatStep (playlist), ProjectPreferencesView (track picker) and Settings → Audio.

import Foundation

/// The backing-music library: built-in tracks (Mac only), the user's chosen music folder (`MusicFolder`) and the
/// tracks added to the app ("My Music").
///
/// Every build (Mac, iPhone, iPad) bundles the royalty-free tracks. The app is shared privately with friends
/// via TestFlight, not sold; those licences don't cover shipping the files inside an App Store app, so they
/// must be removed again before any public release (see docs/APP_STORE.md, L2).
/// Tracks are identified by file name (`ProjectPreferences.selectedMusicTrack` stores it), so a track
/// keeps working when it moves between the bundle and My Music.
enum MusicLibrary {
    /// Audio file extensions the library accepts.
    static let audioExtensions = ["mp3", "m4a", "aac", "wav"]

    /// Bundled audio used by the intro and outro, never as backing music.
    private static let splashNames: Set<String> = ["intro", "outro"]

    /// The My Music folder.
    ///
    /// macOS: `~/Music/Velo Films/`, so tracks can be dropped in with Finder (the Mac build is unsandboxed).
    /// iPadOS: `Application Support/Music/` inside the app, filled with `addTrack(from:)`.
    /// `nil` only if the system can't name the folder.
    static var userFolderURL: URL? {
#if os(macOS)
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Velo Films", isDirectory: true)
#else
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Music", isDirectory: true)
#endif
    }

    /// Royalty-free tracks built into the app.
    ///
    /// Xcode's synced folder copies `Resources/music/` files into the bundle root, so the root is searched
    /// too, skipping the intro and outro music.
    /// - Returns: The built-in tracks, sorted by file name.
    static func bundledTracks() -> [URL] {
        var urls: [URL] = []
        for ext in audioExtensions {
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "music") ?? []
        }
        if urls.isEmpty {
            for ext in audioExtensions {
                urls += (Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [])
                    .filter { !splashNames.contains($0.deletingPathExtension().lastPathComponent) }
            }
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Tracks in My Music, sorted by file name. Empty if the folder doesn't exist yet.
    /// - Returns: The user's tracks.
    static func userTracks() -> [URL] {
        guard let folder = userFolderURL,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [] }
        return files
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Every track (built-in, music folder, My Music), sorted by file name. When names clash, My Music wins over
    /// the music folder, which wins over built-in tracks.
    /// - Returns: Built-in and user tracks, one per file name.
    static func allTracks() -> [URL] {
        var byName: [String: URL] = [:]
        for url in bundledTracks() { byName[url.lastPathComponent] = url }
        for url in MusicFolder.tracks() { byName[url.lastPathComponent] = url }
        for url in userTracks() { byName[url.lastPathComponent] = url }
        return byName.values.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Copies an audio file into My Music, creating the folder if needed and replacing a file of the same name.
    /// - Parameter source: The file to copy. Security-scoped access is started and stopped here, so URLs
    ///   from a file picker can be passed directly.
    /// - Returns: The copy's location.
    /// - Throws: `MusicLibraryError.unsupportedType` for non-audio files, `.noFolder` if My Music can't be
    ///   located, or file-copy errors.
    @discardableResult
    static func addTrack(from source: URL) throws -> URL {
        guard audioExtensions.contains(source.pathExtension.lowercased()) else {
            throw MusicLibraryError.unsupportedType(source.lastPathComponent)
        }
        guard let folder = try ensureUserFolder() else { throw MusicLibraryError.noFolder }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        // Picking a file that is already in My Music is a no-op; copying it onto itself would delete it.
        if source.standardizedFileURL.resolvingSymlinksInPath()
            == destination.standardizedFileURL.resolvingSymlinksInPath() {
            return destination
        }
        // Copy to a temporary file first, so a failed copy never removes the existing track.
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
        try fm.copyItem(at: source, to: temp)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: destination)
        }
        return destination
    }

    /// Removes a track from My Music. Built-in tracks can't be removed.
    ///
    /// macOS moves the file to the Trash, because the folder may hold the user's only copy.
    /// iPadOS deletes the app's copy (the original stays wherever it was added from).
    /// - Parameter url: A URL returned by `userTracks()`.
    /// - Throws: `MusicLibraryError.notInMyMusic` if the file isn't in My Music; file errors.
    static func removeTrack(_ url: URL) throws {
        guard let folder = userFolderURL,
              url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else {
            throw MusicLibraryError.notInMyMusic
        }
#if os(macOS)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
#else
        try FileManager.default.removeItem(at: url)
#endif
    }

    /// Creates My Music if it doesn't exist yet.
    /// - Returns: The folder, or `nil` if it can't be located.
    /// - Throws: Directory-creation errors.
    @discardableResult
    static func ensureUserFolder() throws -> URL? {
        guard let folder = userFolderURL else { return nil }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

/// Errors from adding or removing My Music tracks, worded for display.
enum MusicLibraryError: LocalizedError {
    /// The chosen file isn't an MP3, M4A, AAC or WAV file.
    case unsupportedType(String)
    /// The system couldn't locate the My Music folder.
    case noFolder
    /// A removal was asked for a file outside My Music.
    case notInMyMusic

    /// Plain-language message for an alert.
    var errorDescription: String? {
        switch self {
        case .unsupportedType(let name): "\(name) isn't a supported audio file. Use MP3, M4A, AAC or WAV."
        case .noFolder: "The folder for added songs couldn't be found."
        case .notInMyMusic: "Only songs you added in the app can be removed."
        }
    }
}
