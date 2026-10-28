// FineTuneModel.swift
// State and rules of the Fine Tune screen: which moments are shown, which is open, which are in the reel and which
// camera each uses. Holds no view code so every rule can be unit tested.

import Foundation
import Observation

/// The Fine Tune screen's state. Edits change `rows` in memory; nothing is written until `save(to:)`.
///
/// A moment is in the reel when one of its camera rows has `recommended == true`. Every manual change sets
/// `manualOverride` on all of the moment's rows, so re-running Select keeps the user's choice.
@MainActor
@Observable
final class FineTuneModel {

    /// The filter chips above the film strip.
    enum Filter: String, CaseIterable, Identifiable {
        case all, inReel, climbs, descents, group, stravaPR
        /// Stable identity for SwiftUI lists.
        var id: String { rawValue }
        /// Chip label.
        var label: String {
            switch self {
            case .all:      return "All"
            case .inReel:   return "In reel"
            case .climbs:   return "Climbs"
            case .descents: return "Descents"
            case .group:    return "Group"
            case .stravaPR: return "Strava PRs"
            }
        }
    }

    /// How the open moment came to be in or out of the reel, shown as a badge on the frame.
    enum PickStatus: Equatable {
        /// Chosen by the app and untouched.
        case aiPick
        /// Added (or switched camera) by the user.
        case userPick
        /// Taken out by the user.
        case removed
        /// Never in the reel.
        case notInReel

        /// Badge text.
        var label: String {
            switch self {
            case .aiPick:    return "AI pick"
            case .userPick:  return "Your pick"
            case .removed:   return "Removed"
            case .notInReel: return "Not in reel"
            }
        }
    }

    /// Every row of `select.jsonl`, edited in place.
    private(set) var rows: [SelectRow]
    /// Moments to review, in time order (see `FineTuneData.reviewPool`).
    private(set) var moments: [PartnerMatcher.Moment]
    /// Strava laps on the ride's clock.
    let laps: [RideLap]
    /// Elevation profile scaled 0…1 for the timeline.
    let elevation: [Double]
    /// First and last moment of the whole ride, seconds.
    let rideStart: Double, rideEnd: Double
    /// Clips wanted, shown as "n of target".
    let target: Int
    /// The active filter chip.
    var filter: Filter = .all
    /// The open moment's id; `nil` until one is chosen (the first visible moment is shown then).
    private var openId: Int?
    /// Thresholds for filters and reasons.
    let context: FocusFilterContext
    /// Row positions in `rows` for each momentId, so lookups don't scan thousands of rows per frame drawn.
    private let rowIndices: [Int: [Int]]
    /// Moments in the reel; kept in step with `rows`.
    private(set) var reelIds: Set<Int>
    /// `true` after an edit that hasn't been saved, so Cancel can ask before throwing it away.
    private(set) var hasUnsavedEdits = false

    /// Creates the model.
    /// - Parameters:
    ///   - data: The ride's selection, laps and elevation.
    ///   - target: Clips wanted.
    ///   - thresholds: Climb, descent and group thresholds; PR moments are taken from `data`.
    init(data: FineTuneData, target: Int, thresholds: FocusFilterContext) {
        rows = data.rows
        laps = data.laps
        elevation = data.elevation
        self.target = target
        let all = PartnerMatcher.group(data.rows.map(\.base))
        rideStart = Double(all.first?.momentId ?? 0)
        rideEnd = Double(all.last?.momentId ?? 0)
        rowIndices = Dictionary(grouping: data.rows.indices, by: { data.rows[$0].base.momentId })
        let inReel = Set(data.rows.filter(\.recommended).map(\.base.momentId))
        reelIds = inReel
        moments = FineTuneData.reviewPool(all, recommendedIds: inReel, target: target)
        context = FocusFilterContext(
            climbGradientPct: thresholds.climbGradientPct,
            descentGradientPct: thresholds.descentGradientPct,
            groupMinDetections: thresholds.groupMinDetections,
            stravaPRMomentIds: Set(data.rows.filter(\.stravaPR).map(\.base.momentId)))
    }

    // MARK: - Reading state

    /// Number of clips in the reel.
    var reelCount: Int { reelIds.count }
    /// `true` once anything was changed by hand (now or in an earlier session).
    var hasManualChanges: Bool { rows.contains { $0.manualOverride != nil } }

    /// Moments passing the active filter, in time order.
    var visible: [PartnerMatcher.Moment] {
        moments.filter { matches($0, filter) }
    }

    /// The open moment: the chosen one if it passes the filter, otherwise the first visible one.
    var current: PartnerMatcher.Moment? {
        let shown = visible
        return shown.first { $0.momentId == openId } ?? shown.first
    }

    /// `true` if any of the moment's rows is in the reel.
    func isInReel(_ id: Int) -> Bool { reelIds.contains(id) }

    /// The camera whose clip is in the reel for a moment, or `nil` when the moment isn't in the reel.
    func reelCamera(of id: Int) -> String? {
        rowsOf(id).first(where: \.recommended)?.base.camera
    }

    /// The camera the moment is described by (and added with by "Add to reel"): the one in the reel, else the
    /// higher-scoring one.
    func camera(for moment: PartnerMatcher.Moment) -> String? {
        reelCamera(of: moment.momentId) ?? moment.primary?.camera
    }

    /// The moment's camera frames in display order: front first, then rear (other names alphabetically).
    func cameraRows(of moment: PartnerMatcher.Moment) -> [EnrichRow] {
        moment.rows.sorted { CameraNames.label(for: $0.camera) < CameraNames.label(for: $1.camera) }
    }

    /// The row for the camera the moment is described by.
    func shownRow(for moment: PartnerMatcher.Moment) -> EnrichRow? {
        let cam = camera(for: moment)
        return moment.rows.first { $0.camera == cam } ?? moment.primary
    }

    /// How the moment came to be in or out of the reel.
    func status(of id: Int) -> PickStatus {
        let momentRows = rowsOf(id)
        let touched = momentRows.contains { $0.manualOverride != nil }
        if momentRows.contains(where: \.recommended) { return touched ? .userPick : .aiPick }
        return touched ? .removed : .notInReel
    }

    /// The Strava segment at the moment, if any.
    func segmentName(of id: Int) -> String? {
        rowsOf(id).compactMap(\.segmentName).first
    }

    /// Where a moment sits on the timeline, 0 (start) to 1 (finish).
    func position(of id: Int) -> Double {
        guard rideEnd > rideStart else { return 0 }
        return (Double(id) - rideStart) / (rideEnd - rideStart)
    }

    /// Time since the ride started as "h:mm:ss", e.g. "0:16:05".
    /// - Parameter epoch: A moment time, seconds.
    /// - Returns: The clock text (negative times show as 0:00:00).
    func clock(_ epoch: Double) -> String {
        let t = max(0, Int((epoch - rideStart).rounded()))
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    /// Timeline positions (0…1) of every clip in the reel.
    var reelPositions: [Double] {
        reelIds.sorted().map { position(of: $0) }
    }

    // MARK: - Actions

    /// Opens a moment.
    func open(_ id: Int) { openId = id }

    /// Opens the visible moment `offset` places from the open one (clamped to the ends).
    func step(_ offset: Int) {
        let shown = visible
        guard let id = current?.momentId, let i = shown.firstIndex(where: { $0.momentId == id }) else { return }
        openId = shown[min(shown.count - 1, max(0, i + offset))].momentId
    }

    /// Opens the visible moment nearest to `fraction` (0…1) of the ride, for taps and drags on the timeline.
    func jump(toFraction fraction: Double) {
        let t = rideStart + (rideEnd - rideStart) * min(1, max(0, fraction))
        openId = visible.min { abs(Double($0.momentId) - t) < abs(Double($1.momentId) - t) }?.momentId
    }

    /// Adds the open moment to the reel (with the camera shown) or takes it out.
    func toggleCurrent() {
        guard let m = current else { return }
        let add = !isInReel(m.momentId)
        setReel(m.momentId, camera: add ? camera(for: m) : nil)
    }

    /// A tap on one of the open moment's camera frames: puts that camera's clip in the reel (replacing the other
    /// camera if it was in), or takes the moment out when that camera is already the one in the reel.
    /// - Parameter camera: The tapped frame's camera (`EnrichRow.camera`); unknown names are ignored.
    func tapCamera(_ camera: String) {
        guard let m = current, m.rows.contains(where: { $0.camera == camera }) else { return }
        setReel(m.momentId, camera: reelCamera(of: m.momentId) == camera ? nil : camera)
    }

    /// Restores the app's own picks: re-runs `ClipSelector` on the ride and clears every manual choice.
    func resetToAI() {
        let all = PartnerMatcher.group(rows.map(\.base))
        var config = ClipSelector.Config()
        config.targetClips = target
        let picked = ClipSelector.select(moments: all, config: config)
        let primaryIndex = Dictionary(picked.compactMap { m in m.primary.map { (m.momentId, $0.index) } },
                                      uniquingKeysWith: { a, _ in a })
        for i in rows.indices {
            rows[i].recommended = primaryIndex[rows[i].base.momentId] == rows[i].base.index
            rows[i].manualOverride = nil
        }
        hasUnsavedEdits = true
        reelIds = Set(rows.filter(\.recommended).map(\.base.momentId))
        moments = FineTuneData.reviewPool(all, recommendedIds: reelIds, target: target)
    }

    /// Writes the rows back to `select.jsonl`.
    /// - Parameters:
    ///   - url: Destination, normally `Project.selectJSONL`.
    ///   - writer: JSONL writer (injectable for tests; `nil` uses the standard one).
    /// - Throws: Encoding or file errors.
    func save(to url: URL, writer: JSONLWriter? = nil) throws {
        try (writer ?? JSONLWriter()).write(rows: rows, to: url)
        hasUnsavedEdits = false
    }

    // MARK: - Helpers

    /// Puts the moment in the reel with `camera` (or takes it out when `nil`), marking every row as a manual choice.
    private func setReel(_ id: Int, camera: String?) {
        for i in rowIndices[id] ?? [] {
            let chosen = camera != nil && rows[i].base.camera == camera
            rows[i].recommended = chosen
            rows[i].manualOverride = chosen
        }
        if camera != nil { reelIds.insert(id) } else { reelIds.remove(id) }
        hasUnsavedEdits = true
    }

    /// The rows (one per camera) of a moment.
    private func rowsOf(_ id: Int) -> [SelectRow] {
        (rowIndices[id] ?? []).map { rows[$0] }
    }

    /// Whether a moment passes a filter chip.
    private func matches(_ m: PartnerMatcher.Moment, _ filter: Filter) -> Bool {
        switch filter {
        case .all:      return true
        case .inReel:   return isInReel(m.momentId)
        case .climbs:   return FocusFilter.climbs.matches(m, in: context)
        case .descents: return FocusFilter.descents.matches(m, in: context)
        case .group:    return FocusFilter.groupRiding.matches(m, in: context)
        case .stravaPR: return FocusFilter.stravaPR.matches(m, in: context)
        }
    }
}
