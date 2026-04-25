#if os(macOS)
import Foundation

/// macOS implementation of FFmpegBridge.
/// Execs ffmpeg directly (no shell) so arguments are passed verbatim — no quoting issues.
struct FFmpegMacBridge: FFmpegBridge {

    /// Resolved ffmpeg path, checked once at startup.
    private static let ffmpegPath: String = {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",   // Apple Silicon Homebrew
            "/usr/local/bin/ffmpeg",       // Intel Homebrew
            "/usr/bin/ffmpeg",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/opt/homebrew/bin/ffmpeg"
    }()

    func execute(arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.ffmpegPath)
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let combined = (String(data: outData, encoding: .utf8) ?? "")
                             + (String(data: errData, encoding: .utf8) ?? "")

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: combined)
                } else {
                    continuation.resume(throwing: PipelineError.ffmpegFailed(
                        proc.terminationStatus, combined
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
