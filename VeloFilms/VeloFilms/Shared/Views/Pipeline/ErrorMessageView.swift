// ErrorMessageView.swift
// Shows a pipeline error on the project and pipeline screens: a plain message, plus a collapsed Details
// section with the technical text when there is any.

import SwiftUI

/// A red error message with an optional "Details" disclosure for technical output (e.g. FFmpeg's log).
///
/// Keeps raw tool output off the main screen while still letting the user copy it for troubleshooting.
struct ErrorMessageView: View {
    /// The error to show. `PipelineError.technicalDetails` supplies the Details text.
    let error: Error

    /// The message, and the Details section when the error has technical text.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            if let details = (error as? PipelineError)?.technicalDetails {
                DisclosureGroup("Details") {
                    ScrollView {
                        Text(details)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    Text("The full error is saved in pipeline.log in the project folder.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
    }
}
