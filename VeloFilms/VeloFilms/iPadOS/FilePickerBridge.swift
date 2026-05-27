import SwiftUI
import UniformTypeIdentifiers

/// Wraps UIDocumentPickerViewController for iPadOS drive root selection.
/// The resolved URL is persisted as a security-scoped bookmark so the app
/// can re-access it on every subsequent launch without user interaction.
/// SwiftUI folder-picker sheet with both pick and cancel callbacks.
/// Presented via .sheet(isPresented:) or .sheet(item:) in GlobalSettingsView / OnboardingView.
#if os(iOS)
struct FolderPickerView: View {
    let onPicked: (URL) -> Void
    let onCancel: () -> Void

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
