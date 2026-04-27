import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @Environment(ProjectStore.self) private var store
    @State private var executor = PipelineExecutor()
    @State private var showGPXPicker = false
    @State private var showManualSelection = false
    @State private var showProjectPreferences = false
    @State private var pendingReviewPrompt = false
    @State private var reviewedFlag = false     // mirrors UserDefaults per-project

    private var reviewedKey: String { "reviewed-\(project.id)" }
    private var artifacts: ProjectArtifacts { ProjectArtifacts.check(project) }

    // Gate conditions
    private var setupComplete: Bool   { artifacts.hasVideos && artifacts.gpxExists }
    private var analysisComplete: Bool { artifacts.selectExists }
    private var buildComplete: Bool   { artifacts.finalReelExists }

    // Which steps are part of "analyse" vs "build"
    private var analyseSteps: Set<StepName> { [.flatten, .extract, .enrich, .select] }
    private var buildSteps: Set<StepName>   { [.build, .splash, .concat] }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                step1SetUp
                step2Analyse
                step3Review
                step4Build

                if buildComplete {
                    reelReadyBanner
                }

                if let error = executor.lastError {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showProjectPreferences = true } label: {
                    Label("Project Settings", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showGPXPicker) {
            GPXPickerView(project: project) {
                executor.run(.flatten, project: project)
            }
        }
        .sheet(isPresented: $showManualSelection) {
            ManualSelectionView(project: project)
        }
        .sheet(isPresented: $showProjectPreferences) {
            ProjectPreferencesView(project: project)
        }
        .onAppear {
            registerSteps()
            reviewedFlag = UserDefaults.standard.bool(forKey: reviewedKey)
        }
        .onChange(of: executor.isRunning) {
            if !executor.isRunning {
                store.lastPipelineUpdate = .now
                if pendingReviewPrompt && analysisComplete {
                    pendingReviewPrompt = false
                    showManualSelection = true
                }
            }
        }
        .onChange(of: showManualSelection) {
            // Mark reviewed when the sheet is dismissed
            if !showManualSelection && analysisComplete {
                reviewedFlag = true
                UserDefaults.standard.set(true, forKey: reviewedKey)
            }
        }
    }

    // MARK: - Step 1: Set Up

    private var step1SetUp: some View {
        guidedCard(number: 1, title: "Set Up Ride", isComplete: setupComplete, isLocked: false) {
            VStack(spacing: 12) {
                // Source videos
                HStack(spacing: 10) {
                    Image(systemName: artifacts.hasVideos ? "video.fill" : "video.slash")
                        .foregroundStyle(artifacts.hasVideos ? .green : .secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        if artifacts.hasVideos {
                            Text("\(artifacts.sourceVideoCount) source clip\(artifacts.sourceVideoCount == 1 ? "" : "s") ready")
                        } else {
                            Text("No source videos found")
                            if let base = GlobalSettings.shared.inputBaseDir {
                                Text("Expected: \(base.appending(path: project.name).path)")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                    .lineLimit(1).truncationMode(.middle)
                            } else {
                                Text("Set an Input Videos folder in Settings")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    Spacer()
                }

                Divider()

                // GPX
                HStack(spacing: 10) {
                    Image(systemName: artifacts.gpxExists ? "location.fill" : "location.slash")
                        .foregroundStyle(artifacts.gpxExists ? .green : .secondary)
                        .frame(width: 20)
                    Text(artifacts.gpxExists ? "GPX imported" : "No GPX file — import from Strava or Garmin")
                    Spacer()
                    if artifacts.gpxExists {
                        Button("Re-import") { showGPXPicker = true }
                            .buttonStyle(.bordered).controlSize(.small).tint(.secondary)
                    } else {
                        Button("Import GPX…") { showGPXPicker = true }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Step 2: Analyse

    private var step2Analyse: some View {
        guidedCard(number: 2, title: "Analyse", isComplete: analysisComplete, isLocked: !setupComplete) {
            VStack(spacing: 12) {
                Text("Aligns GPS with video, extracts frame metadata, scores every moment with AI, then auto-selects the best clips.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if executor.isRunning, let step = executor.runningStep, analyseSteps.contains(step) {
                    runningIndicator
                } else if analysisComplete {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Analysis complete")
                        Spacer()
                        Button("Re-run") {
                            pendingReviewPrompt = true
                            reviewedFlag = false
                            UserDefaults.standard.set(false, forKey: reviewedKey)
                            executor.run(.select, project: project)
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(.secondary)
                    }
                } else if !executor.isRunning {
                    centredButton("Run Analysis") {
                        pendingReviewPrompt = true
                        executor.run(.select, project: project)
                    }
                }
            }
        }
    }

    // MARK: - Step 3: Review

    private var step3Review: some View {
        guidedCard(number: 3, title: "Review Selection", isComplete: reviewedFlag, isLocked: !analysisComplete) {
            VStack(spacing: 12) {
                Text("Check the auto-selected clips. Trim, swap, or reorder before the final render.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    if reviewedFlag {
                        Button("Fine-tune Again…") { showManualSelection = true }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Fine-tune Selection…") { showManualSelection = true }
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Step 4: Build

    private var step4Build: some View {
        guidedCard(number: 4, title: "Build Reel", isComplete: buildComplete, isLocked: !reviewedFlag) {
            VStack(spacing: 12) {
                Text("Renders each clip with GPS overlay, builds the intro and outro, then assembles the final video.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if executor.isRunning, let step = executor.runningStep, buildSteps.contains(step) {
                    runningIndicator
                } else if buildComplete {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Reel built")
                        Spacer()
                        Button("Re-build") { executor.run(.concat, project: project) }
                            .buttonStyle(.bordered).controlSize(.small).tint(.secondary)
                    }
                } else if !executor.isRunning {
                    centredButton("Build Reel") {
                        executor.run(.concat, project: project)
                    }
                }
            }
        }
    }

    // MARK: - Reel ready banner

    private var reelReadyBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "film.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your reel is ready").font(.headline)
                Text(project.finalReelURL.lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open in Finder") { reveal(project.finalReelURL) }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Running indicator

    private var runningIndicator: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = executor.currentProgress {
                ProgressView(value: progress.fraction)
            } else {
                ProgressView()
            }
            HStack {
                Text(stepLabel(for: executor.runningStep))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .destructive) { executor.cancel() }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
        }
    }

    private func stepLabel(for step: StepName?) -> String {
        switch step {
        case .flatten: return "Aligning GPS with video…"
        case .extract: return "Extracting frame metadata…"
        case .enrich:  return "Scoring with AI…"
        case .select:  return "Selecting best clips…"
        case .build:   return "Rendering clips with overlays…"
        case .splash:  return "Building intro and outro…"
        case .concat:  return "Assembling final reel…"
        case nil:      return "Running…"
        }
    }

    // MARK: - Guided card container

    @ViewBuilder
    private func guidedCard<Content: View>(
        number: Int,
        title: String,
        isComplete: Bool,
        isLocked: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isComplete ? Color.green
                              : isLocked  ? Color.secondary.opacity(0.15)
                              : Color.accentColor)
                        .frame(width: 30, height: 30)
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.caption.bold()).foregroundStyle(Color.white)
                    } else {
                        Text("\(number)").font(.callout.bold())
                            .foregroundStyle(isLocked ? AnyShapeStyle(.secondary)
                                                      : AnyShapeStyle(Color.white))
                    }
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isLocked ? .secondary : .primary)
            }

            if !isLocked {
                content()
                    .padding(.leading, 40)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .opacity(isLocked ? 0.6 : 1)
    }

    // A full-width centred button helper
    @ViewBuilder
    private func centredButton(_ label: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button(label, action: action)
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Step registration

    private func registerSteps() {
        let modelURL = Bundle.main.url(forResource: "VeloYOLO", withExtension: "mlmodelc")
                    ?? Bundle.main.url(forResource: "VeloYOLO", withExtension: "mlpackage")
                    ?? URL(fileURLWithPath: "/dev/null")
        executor.register(FlattenStep(),                       for: .flatten)
        executor.register(ExtractStep(),                       for: .extract)
        executor.register(EnrichStep(yoloModelURL: modelURL),  for: .enrich)
        executor.register(SelectStep(),                        for: .select)
        executor.register(BuildStep(yoloModelURL: modelURL),   for: .build)
        executor.register(SplashStep(),                        for: .splash)
        executor.register(ConcatStep(),                        for: .concat)
    }

    private func reveal(_ url: URL) {
#if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
#endif
    }
}

// MARK: - GPX source picker

private struct GPXPickerView: View {
    let project: Project
    var onGPXSaved: () -> Void

    @State private var showStrava = false
    @State private var showGarmin = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showStrava = true } label: {
                        Label("Import from Strava", systemImage: "bicycle")
                    }
                    Button { showGarmin = true } label: {
                        Label("Import from Garmin Connect", systemImage: "arrow.down.circle")
                    }
                } header: {
                    Text("Choose the source for **\(project.name)**")
                }
                Section {
                    Text("The GPX is saved into this project. If you already have a .gpx file, place it at:")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(project.gpxFile.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Import GPX")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showStrava) {
                StravaImportView(onComplete: { onGPXSaved(); dismiss() }, targetProject: project)
            }
            .sheet(isPresented: $showGarmin) {
                GarminImportView(onComplete: { onGPXSaved(); dismiss() }, targetProject: project)
            }
        }
        .frame(minWidth: 380, minHeight: 260)
    }
}
