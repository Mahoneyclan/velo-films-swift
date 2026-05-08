import SwiftUI
import UniformTypeIdentifiers

struct GlobalSettingsView: View {
    private var settings = GlobalSettings.shared
    private enum PickerTarget { case input, projects, fly12Source, fly6Source, music }
    @State private var pickerTarget: PickerTarget = .input
    @State private var showPicker = false

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
                            .disabled(!settings.hasFly6Pro)
                            .onChange(of: settings.hasFly12Sport) { settings.save() }
                        if settings.hasFly12Sport {
                            DirRow(label: "Fly12 Sport source",
                                   url: settings.fly12SourceURL,
                                   onChoose: chooseFly12Source)
                        }
                        Divider()
                        Toggle("Fly6 Pro (rear)", isOn: $settings.hasFly6Pro)
                            .disabled(!settings.hasFly12Sport)
                            .onChange(of: settings.hasFly6Pro) { settings.save() }
                        if settings.hasFly6Pro {
                            DirRow(label: "Fly6 Pro source",
                                   url: settings.fly6SourceURL,
                                   onChoose: chooseFly6Source)
                        }
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

                // MARK: Focus Mode Defaults
                GroupBox("Focus Mode Defaults") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Controls the filter chips in clip selection — view-only, no effect on AI scores.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        FocusSliderRow(label: "First N minutes", icon: "clock",
                                       value: $settings.focusFirstNMinutes, range: 1...60,
                                       unit: "min")
                            .onChange(of: settings.focusFirstNMinutes) { settings.save() }
                        FocusSliderRow(label: "Last N minutes", icon: "clock.badge.checkmark",
                                       value: $settings.focusLastNMinutes, range: 1...60,
                                       unit: "min")
                            .onChange(of: settings.focusLastNMinutes) { settings.save() }

                        Divider()

                        FocusSliderRow(label: "Climb steepness", icon: "arrow.up.right",
                                       value: $settings.focusClimbGradientPct, range: 1...20,
                                       unit: "%", prefix: "≥")
                            .onChange(of: settings.focusClimbGradientPct) { settings.save() }
                            .help("Show clips where gradient ≥ this value")

                        // descentGradientPct stored as negative; show abs value to avoid user confusion
                        let descentAbs = Binding<Double>(
                            get: { abs(settings.focusDescentGradientPct) },
                            set: { settings.focusDescentGradientPct = -abs($0); settings.save() }
                        )
                        FocusSliderRow(label: "Descent steepness", icon: "arrow.down.right",
                                       value: descentAbs, range: 1...20,
                                       unit: "%", prefix: "≥")
                            .help("Show clips where gradient ≤ −this value")

                        Divider()

                        HStack {
                            Label("Group min riders", systemImage: "person.3")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Stepper(value: $settings.focusGroupMinDetections, in: 1...20) {
                                Text("\(settings.focusGroupMinDetections) detected")
                                    .font(.caption.bold().monospacedDigit())
                            }
                            .onChange(of: settings.focusGroupMinDetections) { settings.save() }
                        }
                        .help("Show clips with at least this many person + bicycle detections")
                    }
                    .padding(8)
                }

                // MARK: Detection & Scoring
                GroupBox("Detection & Scoring") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Changes take effect on the next Enrich / Select run.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // YOLO confidence
                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label("Min detection confidence", systemImage: "eye")
                                        .font(.caption.bold())
                                    Spacer()
                                    Text(String(format: "%.2f", settings.yoloMinConfidence))
                                        .font(.caption.bold().monospacedDigit())
                                        .foregroundStyle(Color.accentColor)
                                }
                                Slider(value: $settings.yoloMinConfidence, in: 0.05...0.50, step: 0.05)
                                    .onChange(of: settings.yoloMinConfidence) { settings.save() }
                                HStack {
                                    Text("More detections")
                                    Spacer()
                                    Text("Fewer false positives")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .help("Lower = more objects detected but more false positives. Default: 0.10")

                        // Candidate pool
                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label("Candidate pool", systemImage: "list.number")
                                        .font(.caption.bold())
                                    Spacer()
                                    Text(String(format: "%.1f×", settings.candidateFraction))
                                        .font(.caption.bold().monospacedDigit())
                                        .foregroundStyle(Color.accentColor)
                                }
                                Slider(value: $settings.candidateFraction, in: 1.0...5.0, step: 0.5)
                                    .onChange(of: settings.candidateFraction) { settings.save() }
                                let shown = Int((Double(AppConfig.targetClips) * settings.candidateFraction).rounded(.up))
                                Text("Shows ~\(shown) clips in manual selection for \(AppConfig.targetClips)-clip target")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .help("How many candidate clips to display in manual selection. Higher = more choice, longer list.")

                        // Score weights
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                let sum = settings.scoreWeightDetect + settings.scoreWeightScene
                                    + settings.scoreWeightSpeed + settings.scoreWeightGradient
                                    + settings.scoreWeightBboxArea + settings.scoreWeightSegment
                                    + settings.scoreWeightDualCamera
                                let balanced = abs(sum - 1.0) < 0.01

                                HStack {
                                    Text("Score weights").font(.caption.bold())
                                    Spacer()
                                    Text("Sum: \(Int((sum * 100).rounded()))%")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(balanced ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                                        .foregroundStyle(balanced ? Color.green : Color.red)
                                        .clipShape(Capsule())
                                    Button("Reset") {
                                        settings.scoreWeightDetect    = 0.30
                                        settings.scoreWeightScene     = 0.10
                                        settings.scoreWeightSpeed     = 0.20
                                        settings.scoreWeightGradient  = 0.20
                                        settings.scoreWeightBboxArea  = 0.05
                                        settings.scoreWeightSegment   = 0.05
                                        settings.scoreWeightDualCamera = 0.10
                                        settings.save()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                // Proportion bar — colour segments show relative contribution
                                ScoreProportionBar(weights: [
                                    (.green,  settings.scoreWeightDetect),
                                    (.purple, settings.scoreWeightScene),
                                    (.blue,   settings.scoreWeightSpeed),
                                    (.orange, settings.scoreWeightGradient),
                                    (.yellow, settings.scoreWeightBboxArea),
                                    (.teal,   settings.scoreWeightSegment),
                                    (.pink,   settings.scoreWeightDualCamera),
                                ])

                                WeightSliderRow(label: "YOLO detections", icon: "eye",          color: .green,
                                                value: $settings.scoreWeightDetect)    { settings.save() }
                                    .help("Clips with more detected objects (people, cyclists, cars) score higher. Default: 30%")
                                WeightSliderRow(label: "Scene change",    icon: "camera.aperture", color: .purple,
                                                value: $settings.scoreWeightScene)     { settings.save() }
                                    .help("Bonus for visually interesting moments — transitions, changing surroundings. Default: 10%")
                                WeightSliderRow(label: "Speed",           icon: "speedometer",   color: .blue,
                                                value: $settings.scoreWeightSpeed)     { settings.save() }
                                    .help("Faster clips score higher. Normalised to 60 km/h. Default: 20%")
                                WeightSliderRow(label: "Gradient",        icon: "arrow.up.right",color: .orange,
                                                value: $settings.scoreWeightGradient)  { settings.save() }
                                    .help("Steeper climbs and descents score higher. Normalised to 8%. Default: 20%")
                                WeightSliderRow(label: "Object area",     icon: "viewfinder",    color: .yellow,
                                                value: $settings.scoreWeightBboxArea)  { settings.save() }
                                    .help("Objects filling more of the frame score higher. Default: 5%")
                                WeightSliderRow(label: "Strava segment",  icon: "location",      color: .teal,
                                                value: $settings.scoreWeightSegment)   { settings.save() }
                                    .help("Bonus for clips during a Strava segment effort — higher for PRs. Default: 5%")
                                WeightSliderRow(label: "Dual camera",     icon: "camera.on.rectangle", color: .pink,
                                                value: $settings.scoreWeightDualCamera) { settings.save() }
                                    .help("Bonus when both front and rear cameras captured this moment. Default: 10%")
                            }
                        }
                    }
                    .padding(8)
                }

                // MARK: Audio
                GroupBox("Audio") {
                    VStack(spacing: 12) {
                        DirRow(label: "Music track",
                               url: settings.musicURL,
                               onChoose: chooseMusic)
                        Divider()
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
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: pickerTarget == .music
                          ? [.mp3, .mpeg4Audio, .wav, .aiff]
                          : [.folder]) { result in
            guard case .success(let url) = result else { return }
            _ = url.startAccessingSecurityScopedResource()
            if pickerTarget == .input       { GlobalSettings.shared.inputBaseDir   = url }
            else if pickerTarget == .projects    { GlobalSettings.shared.projectsRoot   = url }
            else if pickerTarget == .fly12Source { GlobalSettings.shared.fly12SourceURL = url }
            else if pickerTarget == .fly6Source  { GlobalSettings.shared.fly6SourceURL  = url }
            else if pickerTarget == .music       { GlobalSettings.shared.musicURL        = url }
        }
    }

    private func chooseInputDir() {
#if os(macOS)
        openPanel { GlobalSettings.shared.inputBaseDir = $0 }
#else
        pickerTarget = .input; showPicker = true
#endif
    }

    private func chooseProjectsRoot() {
#if os(macOS)
        openPanel { GlobalSettings.shared.projectsRoot = $0 }
#else
        pickerTarget = .projects; showPicker = true
#endif
    }

    private func chooseFly12Source() {
#if os(macOS)
        openPanel { GlobalSettings.shared.fly12SourceURL = $0 }
#else
        pickerTarget = .fly12Source; showPicker = true
#endif
    }

    private func chooseFly6Source() {
#if os(macOS)
        openPanel { GlobalSettings.shared.fly6SourceURL = $0 }
#else
        pickerTarget = .fly6Source; showPicker = true
#endif
    }

    private func chooseMusic() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["mp3", "m4a", "aac", "wav"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            GlobalSettings.shared.musicURL = url
        }
#else
        pickerTarget = .music; showPicker = true
#endif
    }

#if os(macOS)
    private func openPanel(_ apply: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            apply(url)
        }
    }


#endif
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

private struct IntRow: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(label).frame(width: 220, alignment: .leading)
            Spacer()
            TextField("0", value: $value, format: .number)
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

/// Slider row for Focus Mode numeric thresholds (minutes, gradient %).
private struct FocusSliderRow: View {
    let label: String
    let icon: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var prefix: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .frame(width: 120, alignment: .leading)
            Slider(value: $value, in: range, step: 1)
            Text("\(prefix)\(Int(value))\(unit)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// Horizontal proportion bar showing relative weight contributions as coloured segments.
private struct ScoreProportionBar: View {
    let weights: [(Color, Double)]

    var body: some View {
        let total = max(weights.map(\.1).reduce(0, +), 0.001)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(weights.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(weights[i].0)
                        .frame(width: max(0, geo.size.width * weights[i].1 / total - 2))
                        .opacity(weights[i].1 > 0 ? 1 : 0.15)
                }
            }
        }
        .frame(height: 10)
    }
}

/// Single weight slider row: icon · label · slider · percentage.
private struct WeightSliderRow: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var value: Double
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .frame(width: 120, alignment: .leading)
            Slider(value: $value, in: 0...1, step: 0.05)
                .tint(color)
                .onChange(of: value) { onSave() }
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(color)
                .frame(width: 32, alignment: .trailing)
        }
    }
}
