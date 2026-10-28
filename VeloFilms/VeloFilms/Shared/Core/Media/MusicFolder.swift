// MusicFolder.swift
// The user's chosen music folder (iCloud Drive, Dropbox, Google Drive or any Files/Finder location): lists its
// tracks and makes local copies of cloud files when a reel is built. Used by MusicLibrary and ConcatStep.

import Foundation
import os

nonisolated private let folderLog = Logger(subsystem: "com.velofilms", category: "MusicFolder")

/// Reads tracks from the folder in `GlobalSettings.musicFolderURL`, in place (nothing is copied into the app).
///
/// Cloud files may not be on the device yet. Listing works without downloading; `playableCopies(of:)` downloads
/// and copies the tracks a reel actually uses, just before rendering.
enum MusicFolder {

    /// The chosen folder, or `nil` if none is set.
    static var url: URL? { GlobalSettings.shared.musicFolderURL }

    /// Audio files directly inside the folder, sorted by file name. Empty if no folder is set or it can't be read.
    ///
    /// iCloud Drive shows files that aren't downloaded yet as hidden `.Name.mp3.icloud` placeholders; they are
    /// listed under their real name (`Name.mp3`), which `playableCopies(of:)` can download.
    /// - Returns: Track locations inside the folder.
    static func tracks() -> [URL] {
        guard let folder = url,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        let realNames = names.map { name -> String in
            guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return name }
            return String(name.dropFirst().dropLast(".icloud".count))
        }
        return Set(realNames)
            .filter { !$0.hasPrefix(".") }
            .map { folder.appendingPathComponent($0) }
            .filter { MusicLibrary.audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Returns local, readable copies of the given tracks, downloading cloud files first.
    ///
    /// Tracks outside the music folder are returned unchanged. Folder tracks are read through `NSFileCoordinator`,
    /// which makes iCloud Drive and other file providers download the file, and copied to a temporary folder so
    /// FFmpeg and AVFoundation read an ordinary local file. A track that can't be fetched (e.g. offline) is
    /// skipped and logged, so the reel still builds with the tracks that are available.
    /// Runs the downloads off the main thread.
    /// - Parameter tracks: Tracks in playlist order.
    /// - Returns: Playable tracks in the same order, minus any that couldn't be fetched.
    static func playableCopies(of tracks: [URL]) async -> [URL] {
        let folder = url
        return await Task.detached(priority: .userInitiated) {
            let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("MusicFolderCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let accessing = folder?.startAccessingSecurityScopedResource() ?? false
            defer { if accessing { folder?.stopAccessingSecurityScopedResource() } }

            var result: [URL] = []
            for track in tracks {
                let inFolder = folder.map { track.deletingLastPathComponent().standardizedFileURL == $0.standardizedFileURL } ?? false
                guard inFolder else { result.append(track); continue }
                if let copy = coordinatedCopy(of: track, into: cacheDir) {
                    result.append(copy)
                } else {
                    folderLog.error("Music track unavailable, skipped: \(track.lastPathComponent, privacy: .private)")
                }
            }
            return result
        }.value
    }

    /// Reads `track` with file coordination (triggering a cloud download) and copies it into `dir`.
    /// - Returns: The copy, or `nil` if the file couldn't be read.
    private nonisolated static func coordinatedCopy(of track: URL, into dir: URL) -> URL? {
        let destination = dir.appendingPathComponent(track.lastPathComponent)
        var copied: URL?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: track, options: [], error: &coordinationError) { readable in
            let fm = FileManager.default
            try? fm.removeItem(at: destination)
            if (try? fm.copyItem(at: readable, to: destination)) != nil { copied = destination }
        }
        return copied
    }
}
