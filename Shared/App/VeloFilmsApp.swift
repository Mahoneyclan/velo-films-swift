import SwiftUI

@main
struct VeloFilmsApp: App {
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var settings = GlobalSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectStore)
                .environmentObject(settings)
        }
#if os(macOS)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            GlobalSettingsView()
                .environmentObject(settings)
        }
#endif
    }
}
