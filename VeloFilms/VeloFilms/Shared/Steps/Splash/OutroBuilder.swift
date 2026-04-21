import Foundation

/// Builds _outro.mp4.
/// Mirrors splash.py OutroBuilder:
///   collage → drawtext animation → logo → black → outro.mp3
///
/// Phase 4 implementation placeholder.
enum OutroBuilder {
    static func build(project: Project,
                      selectRows: [SelectRow],
                      bridge: any FFmpegBridge) async throws {
        let outputURL = project.clipsDir.appending(path: "_outro.mp4")
        guard !FileManager.default.fileExists(atPath: outputURL.path) else { return }

        // TODO: Phase 4 full implementation
        _ = try await bridge.execute(arguments: [
            "-f", "lavfi", "-i", "color=c=black:s=1920x1080:d=3",
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo:d=3",
            "-c:v", "libx264", "-c:a", "aac", "-shortest",
            "-y", outputURL.path
        ])
    }
}
