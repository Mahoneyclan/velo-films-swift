// FineTuneView.swift
// The Fine Tune screen: review the clips the app picked and change them by hand. Opens from the project screen
// (its own resizable window on the Mac, a sheet on iPad and iPhone); saves to select.jsonl. Stacked layout on
// iPhone, side panel on iPad and Mac.

import SwiftUI

/// Review screen for clip selection. Manual choices are stored as `SelectRow.manualOverride` and survive
/// re-running the Select step.
struct FineTuneView: View {
    /// The project being reviewed.
    let project: Project
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif
    @Environment(ProjectStore.self) private var store

    /// The Mac window's scene id; the window's value is the project's `id`.
    static let windowID = "fine-tune"

    @State private var model: FineTuneModel?
    /// Moments in the reel when the screen opened, to tell whether a built reel went out of date.
    @State private var reelAtOpen: Set<Int>?
    @State private var loadFailed = false
    @State private var confirmReset = false
    @State private var confirmDiscard = false
    @State private var saveError: String?

    /// Below this width the screen stacks vertically (iPhone, narrow windows); above it the details move into a
    /// side panel beside a larger frame.
    private static let wideLayoutMinWidth: CGFloat = 760

    /// Loading, empty or the review layout, with Cancel and Save in the toolbar.
    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    GeometryReader { geo in
                        if geo.size.width >= Self.wideLayoutMinWidth {
                            wide(model, stackFrames: geo.size.height > geo.size.width)
                        } else {
                            compact(model)
                        }
                    }
                } else if loadFailed {
                    ContentUnavailableView("Nothing to fine-tune yet", systemImage: "film.stack",
                                           description: Text("Run Analysis on this ride first, then come back to choose clips."))
                } else {
                    ProgressView("Loading moments…")
                }
            }
            .toolbar { toolbar }
            .confirmationDialog("Reset to the AI's picks?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset to AI Picks", role: .destructive) { model?.resetToAI() }
            } message: {
                Text("Every clip you added, removed or switched camera on goes back to the app's choice.")
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { close() }
            }
            .alert("Couldn't save your choices", isPresented: Binding(get: { saveError != nil },
                                                                     set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check the drive holding this project is connected, then try again.\n\nDetails: \(saveError ?? "")")
            }
        }
        #if os(macOS)
        .frame(minWidth: 740, minHeight: 560)
        #endif
        .task { load() }
        .onDisappear(perform: finish)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if model?.hasUnsavedEdits == true { confirmDiscard = true } else { close() }
            }
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text("Fine Tune").font(.headline)
                if let model {
                    Text("\(project.name) · \(model.reelCount) of \(model.target) clips")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }.disabled(model == nil)
        }
    }

    // MARK: - Layouts

    /// iPhone and narrow windows: everything stacked and scrollable (large text never cuts anything off), with the
    /// controls pinned at the bottom in thumb reach.
    private func compact(_ model: FineTuneModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                timeline(model)
                chips(model, wrap: false)
                detail(model)
                FilmStripView(model: model, framesDir: project.framesDir, thumbWidth: 112, twoRows: false) { confirmReset = true }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom) {
            controls(model)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.bar)
        }
    }

    /// iPad and Mac: timeline across the top, the frames beside a details panel, film strip along the bottom.
    /// - Parameter stackFrames: `true` when the screen is taller than wide (iPad portrait): front above rear fills
    ///   the height instead of two small frames side by side.
    /// The timeline and film strip keep their full height; the frames shrink to fit what is left, so the strip's
    /// rows are never pushed off the bottom of the screen.
    private func wide(_ model: FineTuneModel, stackFrames: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            timeline(model)
            HStack(alignment: .top, spacing: 16) {
                frame(model, stacked: stackFrames)
                    .frame(maxWidth: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: 14) {
                    chips(model, wrap: true)
                    ScrollView { info(model) }
                    controls(model)
                }
                .padding(16)
                .frame(width: 340)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            }
            .frame(maxHeight: .infinity)
            FilmStripView(model: model, framesDir: project.framesDir, thumbWidth: 128, twoRows: true) { confirmReset = true }
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .padding(20)
    }

    // MARK: - Parts

    private func timeline(_ model: FineTuneModel) -> some View {
        RideTimelineView(
            elevation: model.elevation,
            laps: model.laps.enumerated().map { (label: "L\($0.offset + 1)", position: model.position(of: Int($0.element.startEpoch))) },
            reelPositions: model.reelPositions,
            current: model.current.map { model.position(of: $0.momentId) },
            currentClock: model.current.map { model.clock(Double($0.momentId)) } ?? "–",
            totalClock: model.clock(model.rideEnd),
            onScrub: { model.jump(toFraction: $0) },
            onStep: { model.step($0) })
    }

    /// Text colour of the selected chip: the window background, so it contrasts with its `Color.primary` fill in
    /// light and dark mode.
    #if os(macOS)
    private static let chipSelectedText = Color(nsColor: .windowBackgroundColor)
    #else
    private static let chipSelectedText = Color(uiColor: .systemBackground)
    #endif

    /// Filter chips: one scrolling row on iPhone, wrapped in the iPad/Mac side panel.
    @ViewBuilder
    private func chips(_ model: FineTuneModel, wrap: Bool) -> some View {
        let buttons = ForEach(FineTuneModel.Filter.allCases) { f in
            let on = model.filter == f
            Button { model.filter = f } label: {
                Label(f.label, systemImage: "checkmark")
                    .labelStyle(ChipLabelStyle(showsIcon: on))
                    .font(.subheadline.weight(on ? .semibold : .regular))
                    .padding(.horizontal, 14).frame(minHeight: 36)
                    // Fixed colours: the `.background` style resolved to the fill colour on the Mac panel and hid the
                    // selected chip's text.
                    .foregroundStyle(on ? Self.chipSelectedText : Color.primary)
                    .background(on ? Color.primary : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(.secondary.opacity(on ? 0 : 0.5)))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
        if wrap {
            WrapLayout(spacing: 8) { buttons }
        } else {
            ScrollView(.horizontal) { HStack(spacing: 8) { buttons } }.scrollIndicators(.hidden)
        }
    }

    /// Frame and info stacked (iPhone).
    @ViewBuilder
    private func detail(_ model: FineTuneModel) -> some View {
        frame(model, stacked: true)
        info(model)
    }

    /// The open moment's camera frames (stacked or side by side), or an empty state when the filter matches nothing.
    @ViewBuilder
    private func frame(_ model: FineTuneModel, stacked: Bool) -> some View {
        if let m = model.current {
            MomentFrames(rows: model.cameraRows(of: m), reelCamera: model.reelCamera(of: m.momentId),
                         framesDir: project.framesDir, clock: model.clock(Double(m.momentId)),
                         status: model.status(of: m.momentId), stacked: stacked) { model.tapCamera($0) }
        } else {
            ContentUnavailableView {
                Label("No \(model.filter.label.lowercased()) moments", systemImage: "eye.slash")
            } description: {
                Text("None of the moments to review match this filter.")
            } actions: {
                Button("Show All") { model.filter = .all }
            }
            .frame(minHeight: 200)
        }
    }

    @ViewBuilder
    private func info(_ model: FineTuneModel) -> some View {
        if let m = model.current, let row = model.shownRow(for: m) {
            MomentInfo(
                cameras: m.rows.map(\.camera),
                reasons: MomentReasons.reasons(for: m, row: row, segmentName: model.segmentName(of: m.momentId),
                                               isPR: model.context.stravaPRMomentIds.contains(m.momentId),
                                               ctx: model.context))
        }
    }

    private func controls(_ model: FineTuneModel) -> some View {
        ReelControls(inReel: model.current.map { model.isInReel($0.momentId) } ?? false,
                     onStep: { model.step($0) },
                     onToggle: { model.toggleCurrent() })
            .disabled(model.current == nil)
    }

    // MARK: - Data

    private func load() {
        guard model == nil else { return }
        do {
            let data = try FineTuneData.load(project: project)
            reelAtOpen = Set(data.rows.filter(\.recommended).map(\.base.momentId))
            let s = GlobalSettings.shared
            model = FineTuneModel(data: data, target: AppConfig.targetClips, thresholds: FocusFilterContext(
                climbGradientPct: s.focusClimbGradientPct, descentGradientPct: s.focusDescentGradientPct,
                groupMinDetections: s.focusGroupMinDetections, stravaPRMomentIds: []))
        } catch {
            loadFailed = true
        }
    }

    private func save() {
        guard let model else { return }
        do {
            try model.save(to: project.selectJSONL)
            close()
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Closes the window (Mac) or the sheet (iPad, iPhone).
    private func close() {
        #if os(macOS)
        dismissWindow(id: Self.windowID, value: project.id)
        #else
        dismiss()
        #endif
    }

    /// Runs when the screen goes away (Save, Cancel or the window's close button): marks the ride reviewed and
    /// clears a built reel that no longer matches the selection, then tells the project screen to refresh.
    private func finish() {
        guard let reelAtOpen else { return }
        ReviewCompletion.finish(project: project, reelAtOpen: reelAtOpen)
        store.lastPipelineUpdate = .now
    }
}

#if os(macOS)
/// The Mac Fine Tune window: finds the project by id (windows can be reopened after a relaunch) and shows it.
struct FineTuneWindow: View {
    /// The project's `id`, the window's value.
    let projectID: UUID?
    @Environment(ProjectStore.self) private var store

    /// Fine Tune for the project, or a note if the project was removed.
    var body: some View {
        if let project = store.projects.first(where: { $0.id == projectID }) {
            FineTuneView(project: project)
        } else {
            ContentUnavailableView("Project not found", systemImage: "questionmark.folder",
                                   description: Text("This ride was removed from the project list. Close this window."))
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
#endif

/// A filter chip's label: the title, with a checkmark in front when the chip is selected (so selection isn't shown
/// by colour alone).
private struct ChipLabelStyle: LabelStyle {
    /// `true` to show the checkmark.
    let showsIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            if showsIcon { configuration.icon.imageScale(.small) }
            configuration.title
        }
    }
}
