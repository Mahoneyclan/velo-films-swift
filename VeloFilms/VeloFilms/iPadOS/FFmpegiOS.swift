#if os(iOS)
import ffmpegkit

/// iPadOS implementation of FFmpegBridge — delegates to FFmpegKit.
///
/// Added as Swift Package: https://github.com/arthenica/ffmpeg-kit
/// Product: ffmpeg-kit-https (iOS target only)
///
/// FFmpegKit.executeAsync takes a single command string; its tokenizer respects
/// single-quoted tokens, so arguments containing spaces (filter_complex, drawtext
/// strings, file paths with spaces) are wrapped in single quotes before joining.
struct FFmpegKitBridge: FFmpegBridge {

    func execute(arguments: [String]) async throws -> String {
        let command = arguments.map(shellEscape).joined(separator: " ")
        return try await withCheckedThrowingContinuation { continuation in
            FFmpegKit.executeAsync(command) { session in
                guard let session else {
                    continuation.resume(throwing: PipelineError.ffmpegFailed(-1, "nil session"))
                    return
                }
                let log = session.getAllLogsAsString() ?? ""
                let rc  = session.getReturnCode()
                if ReturnCode.isSuccess(rc) {
                    continuation.resume(returning: log)
                } else {
                    let code = Int32(rc?.getValue() ?? -1)
                    continuation.resume(throwing: PipelineError.ffmpegFailed(code, log))
                }
            }
        }
    }

    /// Wraps arguments that contain shell metacharacters in single quotes so
    /// FFmpegKit's tokenizer treats them as a single token. Embedded single
    /// quotes are escaped using the standard '\'' substitution.
    private func shellEscape(_ arg: String) -> String {
        let safe = CharacterSet.alphanumerics.union(.init(charactersIn: "._/-+=:@,"))
        guard !arg.unicodeScalars.allSatisfy({ safe.contains($0) }) else { return arg }
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
#endif
