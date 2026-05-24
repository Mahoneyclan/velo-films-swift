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

    func updateNSView(_ nsView: NSView, context: Context) {
        // SwiftUI sheets resize the hosting window whenever preferred content size changes
        // (every clip toggle recalculates the stats strip, triggering a layout pass).
        // We counter this by restoring the pre-render frame size after SwiftUI's layout
        // settles, but only when the user is not actively dragging the window edge.
        guard let window = nsView.window,
              window.styleMask.contains(.resizable),
              !window.inLiveResize else { return }
        let savedFrame = window.frame
        DispatchQueue.main.async {
            guard let w = nsView.window, !w.inLiveResize,
                  w.frame != savedFrame else { return }
            w.setFrame(savedFrame, display: false, animate: false)
        }
    }
}
#endif
