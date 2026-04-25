import SwiftUI

struct GlobalSettingsView: View {
    private var settings = GlobalSettings.shared

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

                // MARK: Camera Calibration
                GroupBox("Camera Calibration") {
                    VStack(spacing: 12) {
                        NumRow(label: "Fly12Sport offset (s)",
                               value: $settings.fly12SportOffset)
                            .onChange(of: settings.fly12SportOffset) { settings.save() }
                        Divider()
                        NumRow(label: "Fly6Pro offset (s)",
                               value: $settings.fly6ProOffset)
                            .onChange(of: settings.fly6ProOffset) { settings.save() }
                        Divider()
                        StrRow(label: "Fly12Sport timezone",
                               value: $settings.fly12SportTimezone,
                               hint: "e.g. UTC+10")
                            .onChange(of: settings.fly12SportTimezone) { settings.save() }
                        Divider()
                        StrRow(label: "Fly6Pro timezone",
                               value: $settings.fly6ProTimezone,
                               hint: "e.g. UTC+10")
                            .onChange(of: settings.fly6ProTimezone) { settings.save() }
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
                        Toggle("Show elevation strip", isOn: $settings.showElevationPlot)
                            .onChange(of: settings.showElevationPlot) { settings.save() }
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
    }

    private func chooseInputDir() {
#if os(macOS)
        guard let url = runDirPanel() else { return }
        GlobalSettings.shared.inputBaseDir = url
#endif
    }

    private func chooseProjectsRoot() {
#if os(macOS)
        guard let url = runDirPanel() else { return }
        GlobalSettings.shared.projectsRoot = url
#endif
    }

    private func runDirPanel() -> URL? {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
#else
        return nil
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
