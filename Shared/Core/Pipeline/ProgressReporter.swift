import Foundation

/// A single progress event emitted by a pipeline step.
struct ProgressEvent: Sendable {
    var current: Int
    var total: Int
    var message: String
    var fraction: Double { total > 0 ? min(1.0, Double(current) / Double(total)) : 0 }
}

/// Actor that wraps an AsyncStream continuation and lets pipeline steps report progress
/// without knowing anything about the UI. Mirrors progress_reporter.py.
actor ProgressReporter {
    private var continuation: AsyncStream<ProgressEvent>.Continuation?

    nonisolated let stream: AsyncStream<ProgressEvent>

    init() {
        var cont: AsyncStream<ProgressEvent>.Continuation!
        stream = AsyncStream { cont = $0 }
        continuation = cont
    }

    func report(current: Int, total: Int, message: String) {
        continuation?.yield(ProgressEvent(current: current, total: total, message: message))
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}
