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
    }

#if os(macOS)
    // Declared as a separate computed property to avoid #if inside the scene builder body,
    // which causes a parse error in Swift 6's scene result builder.
    var settingsScene: some Scene {
        Settings {
            GlobalSettingsView()
        }
    }
#endif
}
