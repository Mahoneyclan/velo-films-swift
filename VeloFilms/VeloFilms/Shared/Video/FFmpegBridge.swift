import Foundation

/// Abstracts FFmpeg execution across platforms.
/// macOS: shells out to the system ffmpeg installed via Homebrew.
/// iPadOS: placeholder (FFmpegKit would go here when/if added).
protocol FFmpegBridge: Sendable {
    /// Execute FFmpeg with the given arguments (not including the leading "ffmpeg" itself).
    /// Throws PipelineError.ffmpegFailed on non-zero exit.
    func execute(arguments: [String]) async throws
}

// MARK: - macOS

#if os(macOS)
struct FFmpegMacBridge: FFmpegBridge {
    func execute(arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let process = Process()
            // Use /usr/bin/env so ffmpeg is resolved via PATH regardless of Homebrew prefix
            // (Apple Silicon: /opt/homebrew/bin, Intel: /usr/local/bin).
            // Explicitly extend PATH because GUI apps don't inherit the user's shell PATH.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["ffmpeg"] + arguments

            var env = ProcessInfo.processInfo.environment
            let extra = "/opt/homebrew/bin:/usr/local/bin:/opt/local/bin"
            env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
            process.environment = env

            let errPipe = Pipe()
            process.standardError = errPipe

            // Drain stderr asynchronously to prevent pipe-full deadlock.
            // FFmpeg writes continuous progress lines to stderr; without draining,
            // the 64KB pipe buffer fills and FFmpeg blocks indefinitely.
            let drainQueue = DispatchQueue(label: "ffmpeg.stderr.drain")
            var stderrChunks: [Data] = []
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                drainQueue.async { stderrChunks.append(chunk) }
            }

            process.terminationHandler = { proc in
                errPipe.fileHandleForReading.readabilityHandler = nil
                // Final synchronous drain of any bytes written before handler was cleared.
                let tail = errPipe.fileHandleForReading.readDataToEndOfFile()
                drainQueue.sync {
                    if !tail.isEmpty { stderrChunks.append(tail) }
                }
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let stderr = String(data: stderrChunks.reduce(Data(), +), encoding: .utf8) ?? ""
                    cont.resume(throwing: PipelineError.ffmpegFailed(proc.terminationStatus, stderr))
                }
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
#endif

// MARK: - iOS (FFmpegKit)
// To enable: add https://github.com/arthenica/ffmpeg-kit via Swift Package Manager
// (product: ffmpeg-kit-ios-min), then replace the body below with:
//
//   import ffmpegkit
//   let cmd = (["-hide_banner"] + arguments).joined(separator: " ")
//   try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
//       FFmpegKit.executeAsync(cmd) { session in
//           guard let session else { cont.resume(throwing: PipelineError.ffmpegFailed(-1, "nil session")); return }
//           if ReturnCode.isSuccess(session.getReturnCode()) { cont.resume() }
//           else {
//               let code = Int32(session.getReturnCode()?.getValue() ?? -1)
//               cont.resume(throwing: PipelineError.ffmpegFailed(code, session.getAllLogsAsString() ?? ""))
//           }
//       }
//   }

#if os(iOS)
struct FFmpegKitBridge: FFmpegBridge {
    func execute(arguments: [String]) async throws {
        throw PipelineError.ffmpegFailed(-1, "FFmpegKit not yet linked — add the Swift Package to the iOS target")
    }
}
#endif

// MARK: - Factory

func makeBridge() -> any FFmpegBridge {
#if os(macOS)
    return FFmpegMacBridge()
#else
    return FFmpegKitBridge()
#endif
}
