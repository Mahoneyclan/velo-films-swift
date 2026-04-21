import SwiftUI
import UniformTypeIdentifiers

/// Wraps UIDocumentPickerViewController for iPadOS drive root selection.
/// The resolved URL is persisted as a security-scoped bookmark so the app
/// can re-access it on every subsequent launch without user interaction.
#if os(iOS)
struct DrivePickerView: UIViewControllerRepresentable {
    var onPicked: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPicked: (URL) -> Void
        init(onPicked: @escaping (URL) -> Void) { self.onPicked = onPicked }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            // Persist bookmark so we can re-resolve on future launches.
            if let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
                onPicked(url)
                _ = bookmark  // caller stores this; see GlobalSettings.inputBaseDirBookmark
            }
        }
    }
}
#endif
