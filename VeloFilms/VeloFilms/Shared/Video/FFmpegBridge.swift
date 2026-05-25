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
            // Class wrapper lets both closures capture a reference (not a mutable var),
            // satisfying Swift 6 concurrency rules; drainQueue serialises all access.
            final class StderrAccumulator: @unchecked Sendable { var chunks: [Data] = [] }
            let drainQueue = DispatchQueue(label: "ffmpeg.stderr.drain")
            let stderrAcc  = StderrAccumulator()
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                drainQueue.async { stderrAcc.chunks.append(chunk) }
            }

            process.terminationHandler = { proc in
                errPipe.fileHandleForReading.readabilityHandler = nil
                // Final synchronous drain of any bytes written before handler was cleared.
                let tail = errPipe.fileHandleForReading.readDataToEndOfFile()
                let combined: Data = drainQueue.sync {
                    if !tail.isEmpty { stderrAcc.chunks.append(tail) }
                    return stderrAcc.chunks.reduce(Data(), +)
                }
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let stderr = String(data: combined, encoding: .utf8) ?? ""
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

// MARK: - Factory

#if os(macOS)
func makeBridge() -> any FFmpegBridge {
    FFmpegMacBridge()
}
#endif
