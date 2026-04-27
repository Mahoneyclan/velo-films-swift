import SwiftUI
import UniformTypeIdentifiers

struct GlobalSettingsView: View {
    private var settings = GlobalSettings.shared
    @State private var showInputPicker    = false
    @State private var showProjectsPicker = false

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Drive Roots
                GroupBox("Drive Roots") {
                    VStack(spacing: 12) {
                        DirRow(label: "Input Videos",
                               url: settings.inputBaseDir,
                               onChoose: chooseInputDir)
                        Divider()
                        DirRow(label: "Projects Root",
                               url: settings.projectsRoot,
                               onChoose: chooseProjectsRoot)
                    }
                    .padding(8)
                }

                // MARK: Camera Setup
                GroupBox("Cameras") {
                    VStack(spacing: 12) {
                        Toggle("Fly12 Sport (front)", isOn: $settings.hasFly12Sport)
                            .disabled(!settings.hasFly6Pro)   // must keep at least one
                            .onChange(of: settings.hasFly12Sport) { settings.save() }
                        Divider()
                        Toggle("Fly6 Pro (rear)", isOn: $settings.hasFly6Pro)
                            .disabled(!settings.hasFly12Sport)
                            .onChange(of: settings.hasFly6Pro) { settings.save() }
                    }
                    .padding(8)
                }

                // MARK: Camera Calibration
                GroupBox("Camera Calibration") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Camera clock timezone — the timezone the camera's internal clock is set to, not your local timezone. Cycliq cameras that sync via GPS use UTC+0.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Divider()
                        Toggle("Camera stores local time (Cycliq UTC bug)", isOn: $settings.cameraCreationTimeIsLocalWrongZ)
                            .onChange(of: settings.cameraCreationTimeIsLocalWrongZ) { settings.save() }
                        Text("On by default — Cycliq cameras record local clock time but label it as UTC. Disable only if your cameras are GPS-synced and store genuine UTC.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Divider()
                        if settings.hasFly12Sport {
                            NumRow(label: "Fly12Sport offset (s)", value: $settings.fly12SportOffset)
                                .onChange(of: settings.fly12SportOffset) { settings.save() }
                            Divider()
                            StrRow(label: "Fly12Sport clock tz", value: $settings.fly12SportTimezone, hint: "UTC+0 or UTC+10")
                                .onChange(of: settings.fly12SportTimezone) { settings.save() }
                        }
                        if settings.hasFly12Sport && settings.hasFly6Pro {
                            Divider()
                        }
                        if settings.hasFly6Pro {
                            NumRow(label: "Fly6Pro offset (s)", value: $settings.fly6ProOffset)
                                .onChange(of: settings.fly6ProOffset) { settings.save() }
                            Divider()
                            StrRow(label: "Fly6Pro clock tz", value: $settings.fly6ProTimezone, hint: "UTC+0 or UTC+10")
                                .onChange(of: settings.fly6ProTimezone) { settings.save() }
                        }
                    }
                    .padding(8)
                }

                // MARK: Pipeline
                GroupBox("Pipeline") {
                    VStack(spacing: 12) {
                        NumRow(label: "Highlight duration (min)",
                               value: $settings.highlightTargetMinutes)
                            .onChange(of: settings.highlightTargetMinutes) { settings.save() }
                        Divider()
                        NumRow(label: "Min gap between clips (s)",
                               value: $settings.minGapBetweenClips)
                            .onChange(of: settings.minGapBetweenClips) { settings.save() }
                        Divider()
                        NumRow(label: "GPX time offset (s)",
                               value: $settings.gpxTimeOffsetS)
                            .onChange(of: settings.gpxTimeOffsetS) { settings.save() }
                        Divider()
                        Toggle("Dynamic gauges (ProRes)", isOn: $settings.dynamicGauges)
                            .onChange(of: settings.dynamicGauges) { settings.save() }
                    }
                    .padding(8)
                }

                // MARK: Audio
                GroupBox("Audio") {
                    VStack(spacing: 12) {
                        NumRow(label: "Music volume (0–1)",
                               value: $settings.musicVolume)
                            .onChange(of: settings.musicVolume) { settings.save() }
                        Divider()
                        NumRow(label: "Raw audio volume (0–1)",
                               value: $settings.rawAudioVolume)
                            .onChange(of: settings.rawAudioVolume) { settings.save() }
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
        .frame(width: 480)
        .fileImporter(isPresented: $showInputPicker,
                      allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                GlobalSettings.shared.inputBaseDir = url
            }
        }
        .fileImporter(isPresented: $showProjectsPicker,
                      allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                GlobalSettings.shared.projectsRoot = url
            }
        }
    }

    private func chooseInputDir() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            GlobalSettings.shared.inputBaseDir = url
        }
#else
        showInputPicker = true
#endif
    }

    private func chooseProjectsRoot() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            GlobalSettings.shared.projectsRoot = url
        }
#else
        showProjectsPicker = true
#endif
    }
}

// MARK: - Sub-views

private struct DirRow: View {
    let label: String
    let url: URL?
    let onChoose: () -> Void

    var body: some View {
        HStack {
            Text(label).frame(width: 180, alignment: .leading)
            Spacer()
            if let url {
                Text(url.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Not set").foregroundStyle(.red)
            }
            Button("Choose…", action: onChoose)
        }
    }
}

private struct NumRow: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label).frame(width: 220, alignment: .leading)
            Spacer()
            TextField("0.0", value: $value, format: .number)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
#if os(macOS)
                .textFieldStyle(.roundedBorder)
#endif
        }
    }
}

private struct StrRow: View {
    let label: String
    @Binding var value: String
    let hint: String

    var body: some View {
        HStack {
            Text(label).frame(width: 220, alignment: .leading)
            Spacer()
            TextField(hint, text: $value)
                .frame(width: 120)
                .multilineTextAlignment(.trailing)
#if os(macOS)
                .textFieldStyle(.roundedBorder)
#endif
        }
    }
}
