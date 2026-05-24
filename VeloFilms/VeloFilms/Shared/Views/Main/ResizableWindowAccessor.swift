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
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            context.coordinator.startObserving(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // SwiftUI re-sizes the hosting window on every state change (stats strip recalculates,
        // layout re-runs, window is reset to content's preferred size). If the user has
        // manually dragged the window to a different size, restore their frame.
        guard let window = nsView.window,
              window.styleMask.contains(.resizable),
              !window.inLiveResize,
              let userFrame = context.coordinator.userFrame else { return }
        DispatchQueue.main.async {
            guard let w = nsView.window, !w.inLiveResize,
                  w.frame != userFrame else { return }
            w.setFrame(userFrame, display: false, animate: false)
        }
    }

    // Records the frame only after the user finishes a live resize drag.
    // SwiftUI-driven resizes don't fire didEndLiveResizeNotification, so they
    // don't pollute userFrame.
    final class Coordinator: NSObject {
        var userFrame: NSRect?
        private var observer: NSObjectProtocol?

        func startObserving(window: NSWindow) {
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window, queue: .main
            ) { [weak self, weak window] _ in
                self?.userFrame = window?.frame
            }
        }

        deinit {
            if let o = observer { NotificationCenter.default.removeObserver(o) }
        }
    }
}
#endif
