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
            view.window?.styleMask.insert(.resizable)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
