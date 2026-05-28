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

    // Called on every SwiftUI re-render. Defer the restore so it runs after
    // SwiftUI's layout engine has finished resetting the window frame.
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let target = context.coordinator.userFrame else { return }
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window, window.frame != target else { return }
            window.setFrame(target, display: true, animate: false)
        }
    }

    // Observes three notifications on the hosting window:
    // - willStartLiveResize: user started dragging → set isUserResizing
    // - didEndLiveResize:    user released → clear flag, record new userFrame
    // - didResize:           any resize → if NOT user-initiated and frame differs
    //                        from userFrame, restore immediately (counters SwiftUI
    //                        resetting the window on every state-change render)
    final class Coordinator: NSObject {
        var userFrame: NSRect?
        private var isUserResizing = false
        private var observers: [NSObjectProtocol] = []

        func startObserving(window: NSWindow) {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willStartLiveResizeNotification,
                object: window, queue: .main
            ) { [weak self] _ in self?.isUserResizing = true })

            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window, queue: .main
            ) { [weak self, weak window] _ in
                self?.isUserResizing = false
                self?.userFrame = window?.frame
            })

            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window, queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window,
                      !self.isUserResizing,
                      let target = self.userFrame,
                      window.frame != target else { return }
                window.setFrame(target, display: true, animate: false)
            })
        }

        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}
#endif
