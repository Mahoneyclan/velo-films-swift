import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Forces the hosting NSWindow into resizable mode.
/// SwiftUI's Settings scene and sheet presentations ignore .windowResizability;
/// this bridges into AppKit to insert .resizable into the window's styleMask directly.
struct ResizableWindowAccessor: View {
    var body: some View {
#if os(macOS)
        _ResizableNSViewBridge()
#else
        EmptyView()
#endif
    }
}

#if os(macOS)
private struct _ResizableNSViewBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            // SwiftUI sheets resize the window whenever preferred content size changes
            // (e.g., every clip toggle updates the stats strip, causing layout re-runs).
            // Setting content hugging to defaultLow lets the hosting view fill the window
            // instead of driving its size — user-initiated resizes still work normally.
            DispatchQueue.main.async {
                window.contentView?.setContentHuggingPriority(.defaultLow, for: .horizontal)
                window.contentView?.setContentHuggingPriority(.defaultLow, for: .vertical)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
