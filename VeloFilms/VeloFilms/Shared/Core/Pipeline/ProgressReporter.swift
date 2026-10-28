// ProgressReporter.swift
// Progress events from pipeline steps to the UI.

import Foundation

/// A single progress event emitted by a pipeline step.
struct ProgressEvent: Sendable {
    /// Units done so far.
    var current: Int
    /// Total units for this step.
    var total: Int
    /// Plain-language status line, e.g. "Building frame grid from 42 clips...".
    var message: String
    /// Progress from 0 to 1 (0 when `total` is 0).
    var fraction: Double { total > 0 ? min(1.0, Double(current) / Double(total)) : 0 }
}

/// Actor that wraps an AsyncStream continuation and lets pipeline steps report progress
/// without knowing anything about the UI. Same role as `progress_reporter.py` in the original Python app.
actor ProgressReporter {
    private var continuation: AsyncStream<ProgressEvent>.Continuation?

    /// Events in the order reported. Ends when `finish()` is called.
    nonisolated let stream: AsyncStream<ProgressEvent>

    /// Creates a reporter with an open stream.
    init() {
        // AsyncStream calls its build closure synchronously, so `cont` is set before it is read.
        var cont: AsyncStream<ProgressEvent>.Continuation!
        stream = AsyncStream { cont = $0 }
        continuation = cont
    }

    /// Sends one progress event. Ignored after `finish()`.
    /// - Parameters:
    ///   - current: Units done so far.
    ///   - total: Total units for this step.
    ///   - message: Status text shown on the pipeline screen.
    func report(current: Int, total: Int, message: String) {
        continuation?.yield(ProgressEvent(current: current, total: total, message: message))
    }

    /// Ends the stream. Safe to call more than once.
    func finish() {
        continuation?.finish()
        continuation = nil
    }
}
