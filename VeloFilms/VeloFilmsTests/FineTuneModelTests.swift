// FineTuneModelTests.swift
// Tests for the Fine Tune screen's rules: adding and removing clips, tapping a camera frame, filters, moving between
// moments, reset and saving.

import Foundation
import Testing
@testable import VeloFilms

@MainActor
struct FineTuneModelTests {

    /// Three moments filmed by both cameras at t = 0, 100, 200. The one at 100 is in the reel on the rear camera,
    /// and the one at 200 is a climb inside a Strava PR.
    private func makeModel() -> FineTuneModel {
        let rows: [SelectRow] = [
            Fixtures.select(t: 0, camera: Fixtures.front, score: 0.6),
            Fixtures.select(t: 0, camera: Fixtures.rear, score: 0.4),
            Fixtures.select(t: 100, camera: Fixtures.front, score: 0.5),
            Fixtures.select(t: 100, camera: Fixtures.rear, score: 0.7, recommended: true),
            Fixtures.select(t: 200, camera: Fixtures.front, score: 0.8, pr: true, segment: "Hill", gradient: 9),
            Fixtures.select(t: 200, camera: Fixtures.rear, score: 0.3, pr: true, segment: "Hill", gradient: 9),
        ]
        let data = FineTuneData(rows: rows, laps: [], elevation: [])
        return FineTuneModel(data: data, target: 1, thresholds: Fixtures.context())
    }

    @Test func startsOnFirstMomentWithReelCount() {
        let model = makeModel()
        #expect(model.current?.momentId == 0)
        #expect(model.reelCount == 1)
        #expect(model.status(of: 100) == .aiPick)
        #expect(!model.hasUnsavedEdits)
    }

    @Test func addingUsesTheCameraShownAndMarksEveryRow() {
        let model = makeModel()
        model.toggleCurrent()   // moment 0, shown on the higher-scoring front camera
        let rows = model.rows.filter { $0.base.momentId == 0 }
        #expect(rows.first { $0.base.camera == Fixtures.front }?.recommended == true)
        #expect(rows.first { $0.base.camera == Fixtures.rear }?.recommended == false)
        #expect(rows.allSatisfy { $0.manualOverride != nil })
        #expect(model.reelCount == 2)
        #expect(model.status(of: 0) == .userPick)
        #expect(model.hasUnsavedEdits)
    }

    @Test func removingAnAIPickShowsRemoved() {
        let model = makeModel()
        model.open(100)
        model.toggleCurrent()
        #expect(!model.isInReel(100))
        #expect(model.status(of: 100) == .removed)
    }

    @Test func tappingTheOtherCameraMovesTheClip() throws {
        let model = makeModel()
        model.open(100)
        model.tapCamera(Fixtures.front)
        let front = model.rows.first { $0.base.momentId == 100 && $0.base.camera == Fixtures.front }
        #expect(front?.recommended == true)
        #expect(model.reelCamera(of: 100) == Fixtures.front)
        #expect(model.reelCount == 1)
        #expect(model.status(of: 100) == .userPick)
    }

    @Test func tappingACameraAddsAMomentNotInTheReel() {
        let model = makeModel()
        model.tapCamera(Fixtures.rear)   // moment 0: the lower-scoring camera, chosen by the user
        #expect(model.reelCamera(of: 0) == Fixtures.rear)
        #expect(model.reelCount == 2)
        #expect(model.hasUnsavedEdits)
    }

    @Test func tappingTheCameraInTheReelRemovesTheMoment() {
        let model = makeModel()
        model.open(100)
        model.tapCamera(Fixtures.rear)
        #expect(!model.isInReel(100))
        #expect(model.reelCamera(of: 100) == nil)
        #expect(model.status(of: 100) == .removed)
    }

    @Test func unknownCameraIsIgnored() {
        let model = makeModel()
        model.tapCamera("Fly99")
        #expect(model.reelCount == 1)
        #expect(!model.hasUnsavedEdits)
    }

    @Test func cameraRowsPutFrontFirst() throws {
        let model = makeModel()
        let rows = model.cameraRows(of: try #require(model.current))
        #expect(rows.map(\.camera) == [Fixtures.front, Fixtures.rear])
    }

    @Test func filtersNarrowTheMoments() {
        let model = makeModel()
        model.filter = .inReel
        #expect(model.visible.map(\.momentId) == [100])
        #expect(model.current?.momentId == 100)
        model.filter = .climbs
        #expect(model.visible.map(\.momentId) == [200])
        model.filter = .stravaPR
        #expect(model.visible.map(\.momentId) == [200])
        model.filter = .descents
        #expect(model.current == nil)
    }

    @Test func stepStopsAtTheEnds() {
        let model = makeModel()
        model.step(-1)
        #expect(model.current?.momentId == 0)
        model.step(5)
        #expect(model.current?.momentId == 200)
    }

    @Test func jumpOpensNearestMoment() {
        let model = makeModel()
        model.jump(toFraction: 0.6)   // t = 120 → nearest is 100
        #expect(model.current?.momentId == 100)
        model.jump(toFraction: 2)     // clamped to the finish
        #expect(model.current?.momentId == 200)
    }

    @Test func clockAndPositions() {
        let model = makeModel()
        #expect(model.clock(3_725) == "1:02:05")
        #expect(model.position(of: 100) == 0.5)
        #expect(model.reelPositions == [0.5])
    }

    @Test func segmentNameComesFromAnyCamera() {
        #expect(makeModel().segmentName(of: 200) == "Hill")
        #expect(makeModel().segmentName(of: 0) == nil)
    }

    @Test func resetClearsEveryManualChoice() {
        let model = makeModel()
        model.toggleCurrent()
        model.resetToAI()
        #expect(!model.hasManualChanges)
        #expect(model.reelCount == 1)
    }

    @Test func saveWritesRowsAndClearsUnsavedFlag() throws {
        let model = makeModel()
        model.toggleCurrent()
        let url = FileManager.default.temporaryDirectory.appending(path: "finetune-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try model.save(to: url)
        let saved: [SelectRow] = try JSONLReader().read(from: url)
        #expect(saved.count == 6)
        #expect(saved.filter(\.recommended).map(\.base.momentId).sorted() == [0, 100])
        #expect(saved.first { $0.base.momentId == 0 }?.manualOverride != nil)
        #expect(!model.hasUnsavedEdits)
    }
}
