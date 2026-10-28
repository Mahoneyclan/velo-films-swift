// ReviewCompletionTests.swift
// Tests for what happens when Fine Tune closes: the "reviewed" flag and clearing a built reel that went out of date.

import Foundation
import Testing
@testable import VeloFilms

struct ReviewCompletionTests {

    /// A project in a fresh temporary folder with a `select.jsonl` whose reel is moment 100, plus a private
    /// UserDefaults suite.
    private func makeProject(builtReel: Bool) throws -> (Project, UserDefaults) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "review-\(UUID().uuidString)")
        let project = Project(name: "Ride", folderURL: folder)
        try FileManager.default.createDirectory(at: project.selectJSONL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.clipsDir, withIntermediateDirectories: true)
        try JSONLWriter().write(rows: [Fixtures.select(t: 0), Fixtures.select(t: 100, recommended: true)],
                                to: project.selectJSONL)
        try Data("clip".utf8).write(to: project.clipsDir.appending(path: "c1.mp4"))
        if builtReel { try Data("reel".utf8).write(to: project.finalReelURL) }
        let defaults = try #require(UserDefaults(suiteName: "ReviewCompletionTests-\(UUID().uuidString)"))
        return (project, defaults)
    }

    @Test func marksTheRideReviewed() throws {
        let (project, defaults) = try makeProject(builtReel: false)
        defer { try? FileManager.default.removeItem(at: project.folderURL) }
        #expect(!ReviewCompletion.isReviewed(project, defaults: defaults))
        ReviewCompletion.finish(project: project, reelAtOpen: [100], defaults: defaults)
        #expect(ReviewCompletion.isReviewed(project, defaults: defaults))
    }

    @Test func keepsTheBuiltReelWhenTheSelectionIsUnchanged() throws {
        let (project, defaults) = try makeProject(builtReel: true)
        defer { try? FileManager.default.removeItem(at: project.folderURL) }
        #expect(!ReviewCompletion.finish(project: project, reelAtOpen: [100], defaults: defaults))
        #expect(FileManager.default.fileExists(atPath: project.finalReelURL.path))
    }

    @Test func deletesTheBuiltReelWhenTheSelectionChanged() throws {
        let (project, defaults) = try makeProject(builtReel: true)
        defer { try? FileManager.default.removeItem(at: project.folderURL) }
        #expect(ReviewCompletion.finish(project: project, reelAtOpen: [0, 100], defaults: defaults))
        #expect(!FileManager.default.fileExists(atPath: project.finalReelURL.path))
        #expect(!FileManager.default.fileExists(atPath: project.clipsDir.appending(path: "c1.mp4").path))
    }

    @Test func keyIsTheOneEarlierVersionsWrote() {
        let id = UUID()
        #expect(ReviewCompletion.reviewedKey(for: id) == "reviewed-\(id)")
    }
}
