// VeloFilmsApp.swift
// App entry point: creates the shared project list and the main and (macOS) Settings windows.

import SwiftUI

/// The app. Owns the `ProjectStore` and injects it into the view hierarchy.
@main
struct VeloFilmsApp: App {
    @State private var projectStore = ProjectStore()

    /// Runs once at launch, before any window appears.
    init() {
        Self.removeLegacyGarminData()
    }

    /// Deletes the Garmin email and OAuth tokens that earlier versions stored in UserDefaults.
    ///
    /// Security: Garmin Connect import was removed, so nothing reads these keys any more, and they
    /// were stored as plain text. Removing a missing key is a no-op, so this is safe on every launch.
    /// The key names are fixed: they are what earlier versions wrote.
    private static func removeLegacyGarminData() {
        for key in ["garminEmail", "garminOAuth1Token", "garminOAuth2Token"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// The main window, plus a Settings window on macOS. "New" menu items are removed on macOS.
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
        }
        .windowResizability(.contentMinSize)
#endif
    }
}
