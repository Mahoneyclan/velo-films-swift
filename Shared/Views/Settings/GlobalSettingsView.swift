import SwiftUI

struct GlobalSettingsView: View {
    @EnvironmentObject var settings: GlobalSettings
    @State private var showInputPicker = false
    @State private var showProjectsPicker = false

    var body: some View {
        Form {
            // MARK: Drive roots
            Section("Drive Roots") {
                LabeledContent("Input Videos") {
                    if let url = settings.inputBaseDir {
                        Text(url.lastPathComponent).foregroundStyle(.secondary)
                    } else {
                        Text("Not set").foregroundStyle(.red)
                    }
                    Button("Choose...") { showInputPicker = true }
                }
                LabeledContent("Projects Root") {
                    if let url = settings.projectsRoot {
                        Text(url.lastPathComponent).foregroundStyle(.secondary)
                    } else {
                        Text("Not set").foregroundStyle(.red)
                    }
                    Button("Choose...") { showProjectsPicker = true }
                }
            }

            // MARK: Camera offsets
            Section("Camera Calibration") {
                HStack {
                    Text("Fly12Sport offset (s)")
                    Spacer()
                    TextField("0.0", value: $settings.fly12SportOffset, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Fly6Pro offset (s)")
                    Spacer()
                    TextField("0.0", value: $settings.fly6ProOffset, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
            }

            // MARK: Pipeline
            Section("Pipeline") {
                HStack {
                    Text("Highlight duration (min)")
                    Spacer()
                    TextField("5.0", value: $settings.highlightTargetMinutes, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Show elevation strip", isOn: $settings.showElevationPlot)
                Toggle("Dynamic gauges (ProRes)", isOn: $settings.dynamicGauges)
            }
        }
        .navigationTitle("Settings")
        .onChange(of: settings.fly12SportOffset) { settings.save() }
        .onChange(of: settings.fly6ProOffset)    { settings.save() }
        .onChange(of: settings.highlightTargetMinutes) { settings.save() }
        .onChange(of: settings.showElevationPlot) { settings.save() }
        .onChange(of: settings.dynamicGauges)     { settings.save() }
#if os(iOS)
        .sheet(isPresented: $showInputPicker) {
            DrivePickerView { url in
                if let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                                        includingResourceValuesForKeys: nil,
                                                        relativeTo: nil) {
                    settings.inputBaseDirBookmark = bookmark
                    settings.resolveBookmarks()
                }
            }
        }
        .sheet(isPresented: $showProjectsPicker) {
            DrivePickerView { url in
                if let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                                        includingResourceValuesForKeys: nil,
                                                        relativeTo: nil) {
                    settings.projectsRootBookmark = bookmark
                    settings.resolveBookmarks()
                }
            }
        }
#endif
    }
}
