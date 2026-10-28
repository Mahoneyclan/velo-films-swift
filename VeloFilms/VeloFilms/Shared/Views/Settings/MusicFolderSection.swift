// MusicFolderSection.swift
// Settings → Audio: choose the music folder (iCloud Drive, Dropbox, Google Drive or any folder) whose tracks
// join the backing-music library automatically. See MusicFolder.

import SwiftUI
import UniformTypeIdentifiers

/// Shows the chosen music folder and its tracks, with Choose Folder… and Stop Using.
///
/// The easiest way to add music: pick a folder once, then drop songs into it from any device.
struct MusicFolderSection: View {
    @State private var folder: URL? = MusicFolder.url
    @State private var tracks: [URL] = []
    @State private var showPicker = false
    @State private var errorMessage: String?

    /// The folder row, its track list and the buttons.
    var body: some View {
        GroupBox("Music Folder") {
            VStack(alignment: .leading, spacing: 10) {
                if let folder {
                    Label(folder.lastPathComponent, systemImage: "folder.fill")
                        .font(.headline)
                    if tracks.isEmpty {
                        Text("No songs in this folder yet. Add MP3, M4A, AAC or WAV files to it from any device.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(tracks.count) song\(tracks.count == 1 ? "" : "s") — new songs you add to the folder appear automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(tracks, id: \.self) { url in
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    HStack {
                        Button("Change Folder…") { showPicker = true }
                        Button("Stop Using Folder", role: .destructive) { setFolder(nil) }
                    }
                } else {
                    Text("Pick a folder of songs, for example in iCloud Drive, Dropbox or Google Drive. Every song in it is used as backing music, and songs you add later appear automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Choose Music Folder…") { showPicker = true }
                        .buttonStyle(.borderedProminent)
                }
                Text("Songs in the cloud are downloaded when a reel is built.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .onAppear(perform: reload)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                // Security: access must be active while the bookmark is created; GlobalSettings keeps it.
                _ = url.startAccessingSecurityScopedResource()
                setFolder(url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Music Folder", isPresented: Binding(get: { errorMessage != nil },
                                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func setFolder(_ url: URL?) {
        GlobalSettings.shared.musicFolderURL = url
        folder = url
        reload()
    }

    private func reload() { tracks = MusicFolder.tracks() }
}
