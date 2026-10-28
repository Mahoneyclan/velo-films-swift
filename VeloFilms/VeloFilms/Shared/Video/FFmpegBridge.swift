// FFmpegBridge.swift (macOS rendering)
// Runs the Homebrew-installed `ffmpeg` command-line tool for clip rendering and joining on macOS.

import Foundation

/// Abstracts FFmpeg execution. `ClipCompositor` takes one as a parameter, so it could be given a fake runner
/// in tests; `ConcatStep` creates its own with `makeBridge()`.
/// macOS only: shells out to the ffmpeg installed via Homebrew. iPadOS has no implementation; it renders with
/// AVFoundation instead (ClipCompositor, VideoEncoder).
protocol FFmpegBridge: Sendable {
    /// Execute FFmpeg with the given arguments (not including the leading "ffmpeg" itself).
    /// - Parameter arguments: FFmpeg arguments, one per element (no shell quoting needed).
    /// - Throws: `PipelineError.ffmpegFailed` with FFmpeg's error output on a non-zero exit.
    func execute(arguments: [String]) async throws
}

// MARK: - macOS

#if os(macOS)
/// Runs `ffmpeg` as a child process.
///
/// Security: arguments are passed as an array (no shell), so file names can't inject commands. `ffmpeg` is found
/// through PATH with the Homebrew folders first, and is not otherwise verified (acceptable for the owner's
/// personal Mac build).
struct FFmpegMacBridge: FFmpegBridge {
    /// Runs ffmpeg and waits for it to exit, collecting its error output.
    /// - Parameter arguments: Arguments after the program name.
    /// - Throws: `PipelineError.ffmpegFailed` with the exit code and full stderr on failure; an error if the
    ///   process can't be started (e.g. ffmpeg not installed).
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
            // and be Sendable; drainQueue serialises all access.
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
/// The FFmpeg runner used by the macOS pipeline.
/// - Returns: A bridge that runs the Homebrew `ffmpeg`.
func makeBridge() -> any FFmpegBridge {
    FFmpegMacBridge()
}
#endif
