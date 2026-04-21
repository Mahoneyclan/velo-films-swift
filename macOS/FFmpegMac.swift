import Foundation

/// macOS implementation of FFmpegBridge — shells out to /usr/local/bin/ffmpeg.
/// Homebrew installs ffmpeg there by default.
struct FFmpegMacBridge: FFmpegBridge {
    private static let ffmpegPath = "/usr/local/bin/ffmpeg"

    func execute(arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.ffmpegPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let combined = (String(data: outData, encoding: .utf8) ?? "")
                         + (String(data: errData, encoding: .utf8) ?? "")

            if process.terminationStatus == 0 {
                continuation.resume(returning: combined)
            } else {
                continuation.resume(throwing: PipelineError.ffmpegFailed(
                    process.terminationStatus, combined
                ))
            }
        }
    }
}
