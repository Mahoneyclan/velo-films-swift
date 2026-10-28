// FilePickerBridge.swift (iPadOS only)
// SwiftUI wrappers around the system folder picker.

import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
/// iPad folder picker (wraps `UIDocumentPickerViewController`) with pick and cancel callbacks.
///
/// Presented as a sheet from GlobalSettingsView and OnboardingView. The picked URL's security-scoped access is
/// started here and never stopped, so the app keeps access for the session. The picker does not save a
/// bookmark itself: assigning the URL to a `GlobalSettings` folder property does that.
struct FolderPickerView: View {
    /// Called with the chosen folder.
    let onPicked: (URL) -> Void
    /// Called when the user cancels.
    let onCancel: () -> Void

    /// The system picker, full screen.
    var body: some View {
        _FolderPickerRepresentable(onPicked: onPicked, onCancel: onCancel)
            .ignoresSafeArea()
    }
}

private struct _FolderPickerRepresentable: UIViewControllerRepresentable {
    var onPicked: (URL) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPicked: (URL) -> Void
        var onCancel: () -> Void
        init(onPicked: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked; self.onCancel = onCancel
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            onPicked(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
#endif

#if os(iOS)
/// Older folder picker with a pick callback only. Not currently used; `FolderPickerView` replaced it.
/// It creates a bookmark but discards it, and stops folder access when the callback returns.
struct DrivePickerView: UIViewControllerRepresentable {
    /// Called with the chosen folder.
    var onPicked: (URL) -> Void

    /// Creates the delegate that receives the picker's result.
    /// - Returns: A coordinator holding the `onPicked` callback.
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    /// Creates a single-folder picker.
    /// - Parameter context: SwiftUI context supplying the coordinator.
    /// - Returns: A folder picker (folders only, one at a time).
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    /// Nothing to update; the picker has no changing state.
    /// - Parameters:
    ///   - uiViewController: The picker.
    ///   - context: SwiftUI context.
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    /// Picker delegate that forwards the chosen folder.
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        /// Called with the chosen folder.
        var onPicked: (URL) -> Void
        /// Creates the delegate.
        /// - Parameter onPicked: Called with the folder the user chose.
        init(onPicked: @escaping (URL) -> Void) { self.onPicked = onPicked }

        /// Forwards the first picked folder.
        /// - Parameters:
        ///   - controller: The picker.
        ///   - urls: The chosen folders; only the first is used.
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            // Persist bookmark so we can re-resolve on future launches.
            if let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
                onPicked(url)
                _ = bookmark  // Discarded: nothing stores it.
            }
        }
    }
}
#endif
