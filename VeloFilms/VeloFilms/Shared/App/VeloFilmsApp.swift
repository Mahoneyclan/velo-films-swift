// VeloFilmsApp.swift
// App entry point: creates the shared project list and the main window, plus the Fine Tune and Settings windows on
// macOS.

import SwiftUI

/// The app. Owns the `ProjectStore` and injects it into the view hierarchy.
@main
struct VeloFilmsApp: App {
    @State private var projectStore = ProjectStore()
    @Environment(\.scenePhase) private var scenePhase

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

    /// The main window, plus Fine Tune and Settings windows on macOS. "New" menu items are removed on macOS.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(projectStore)
        }
#if os(iOS)
        // A drive plugged in while the app was in the background isn't readable until folder access is re-opened;
        // then the project screens re-check which files exist.
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            GlobalSettings.shared.restoreFolderAccess()
            projectStore.lastPipelineUpdate = .now
        }
#endif
#if os(macOS)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
#endif
#if os(macOS)
        // Fine Tune gets its own window so it can be sized freely (a sheet is capped at its parent's height).
        WindowGroup("Fine Tune", id: FineTuneView.windowID, for: UUID.self) { $projectID in
            FineTuneWindow(projectID: projectID)
                .environment(projectStore)
        }
        .defaultSize(width: 1100, height: 780)
        .windowResizability(.contentMinSize)
        Settings {
            GlobalSettingsView()
        }
        .windowResizability(.contentMinSize)
#endif
    }
}
