import SwiftUI
import UniformTypeIdentifiers

/// Folder picker for iPadOS external drive selection.
/// Uses UIDocumentPickerViewController in open mode (forOpeningContentTypes:) which returns
/// a direct security-scoped URL without materialising folder contents — required for large
/// folders on external USB drives where .fileImporter import mode fails silently.
/// Presented via .sheet so the picker VC is the root of a modal presentation, not embedded
/// as a child VC (embedding renders blank on iOS).
#if os(iOS)
struct FolderPickerView: UIViewControllerRepresentable {
    var onPicked: (URL) -> Void
    var onCancel: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {
        context.coordinator.onPicked = onPicked
        context.coordinator.onCancel = onCancel
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPicked: (URL) -> Void
        var onCancel: (() -> Void)?

        init(onPicked: @escaping (URL) -> Void, onCancel: (() -> Void)? = nil) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // Leave security scope open for the session — pipeline reads from this folder later.
            _ = url.startAccessingSecurityScopedResource()
            onPicked(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel?()
        }
    }
}
#endif
