import SwiftUI

@main
struct VeloFilmsApp: App {
    @State private var projectStore = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(projectStore)
        }
#if os(macOS)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
#endif
#if os(macOS)
        Settings {
            GlobalSettingsView()
                .frame(minWidth: 420, minHeight: 300)
        }
#endif
    }
}
