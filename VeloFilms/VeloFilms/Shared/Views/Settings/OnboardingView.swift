import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @State private var step = 0
    @State private var showProjectsPicker = false
    @State private var showInputPicker    = false
    @Environment(\.dismiss) private var dismiss

    private var settings: GlobalSettings { GlobalSettings.shared }

    private var canFinish: Bool {
        settings.projectsRoot != nil && settings.inputBaseDir != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            stepDots
                .padding(.top, 28)

            TabView(selection: $step) {
                welcomePage.tag(0)
                projectsRootPage.tag(1)
                inputFolderPage.tag(2)
            }
            .animation(.easeInOut, value: step)

            navButtons
                .padding(24)
        }
        .frame(width: 500, height: 400)
        .fileImporter(isPresented: $showProjectsPicker,
                      allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                GlobalSettings.shared.projectsRoot = url
            }
        }
        .fileImporter(isPresented: $showInputPicker,
                      allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                GlobalSettings.shared.inputBaseDir = url
            }
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("Welcome to Velo Films")
                .font(.title.bold())
            Text("Turn your Cycliq ride footage into a polished highlight reel, automatically synced to your GPS route.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Divider().padding(.horizontal, 40)
            VStack(alignment: .leading, spacing: 8) {
                Label("**Input Videos** – where camera clips are copied to from your SD card", systemImage: "folder.badge.plus")
                Label("**Projects Root** – where each ride project folder is created", systemImage: "folder.badge.gear")
            }
            .font(.callout)
            .padding(.horizontal, 40)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectsRootPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gear")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Projects Root Folder")
                .font(.title2.bold())
            Text("Each ride gets its own subfolder here for working files, clips, and the final reel.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            if let url = settings.projectsRoot {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(url.path)
                        .font(.callout.monospaced())
                        .lineLimit(2).truncationMode(.middle)
                }
                .padding(.horizontal, 40)
            }

            Button(settings.projectsRoot == nil ? "Choose Folder…" : "Change…") {
                chooseFolder { GlobalSettings.shared.projectsRoot = $0 }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inputFolderPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Input Videos Folder")
                .font(.title2.bold())
            Text("When you copy from your Cycliq cameras, clips land here in a subfolder named after the ride.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            if let url = settings.inputBaseDir {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(url.path)
                        .font(.callout.monospaced())
                        .lineLimit(2).truncationMode(.middle)
                }
                .padding(.horizontal, 40)
            }

            Button(settings.inputBaseDir == nil ? "Choose Folder…" : "Change…") {
                chooseFolder { GlobalSettings.shared.inputBaseDir = $0 }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Nav

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut, value: step)
            }
        }
    }

    private var navButtons: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .buttonStyle(.bordered)
            } else {
                Button("Skip for now") { dismiss() }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if step < 2 {
                Button("Next") { withAnimation { step += 1 } }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Get Started") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canFinish)
            }
        }
    }

    // MARK: - Folder picker

    private func chooseFolder(_ apply: (URL) -> Void) {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            apply(url)
        }
#endif
    }
}
