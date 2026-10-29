// VideoLocationTests.swift
// Tests for finding a ride's camera videos on this device when the project files hold paths from another device
// (analysed on the Mac, built on the iPad, or the other way round), and for the check that stops Build early.

import Foundation
import Testing
@testable import VeloFilms

@MainActor
struct VideoLocationTests {

    private let macPath = "/Volumes/AData/Fly_Raw/2026-10-14 SCL Riverloop/Fly12Sport_3014.MP4"
    private let iPadPath = "/private/var/mobile/Library/LiveFiles/com.apple.filesystems.userfsd/2E233516/Fly_Raw/"
        + "2026-10-23 Brymaroo - Friday/Fly12Sport_3073.MP4"

    private func project(_ name: String, source: URL? = nil) -> Project {
        Project(name: name, folderURL: URL(fileURLWithPath: "/drive/Fly_Projects/\(name)"), sourceVideoURL: source)
    }

    @Test func macPathFoundInThisDevicesRawFolder() {
        let iPadRaw = URL(fileURLWithPath: "/private/var/mobile/LiveFiles/X/Fly_Raw")
        let url = project("2026-10-14 SCL Riverloop").videoURL(forStoredPath: macPath, inputBase: iPadRaw)
        #expect(url.path(percentEncoded: false)
                == "/private/var/mobile/LiveFiles/X/Fly_Raw/2026-10-14 SCL Riverloop/Fly12Sport_3014.MP4")
    }

    @Test func iPadPathFoundInTheMacRawFolder() {
        let macRaw = URL(fileURLWithPath: "/Volumes/AData/Fly_Raw")
        let url = project("2026-10-23 Brymaroo - Friday").videoURL(forStoredPath: iPadPath, inputBase: macRaw)
        #expect(url.path(percentEncoded: false)
                == "/Volumes/AData/Fly_Raw/2026-10-23 Brymaroo - Friday/Fly12Sport_3073.MP4")
    }

    @Test func folderChosenForTheProjectWinsOverSettings() {
        let chosen = URL(fileURLWithPath: "/other/Ride clips")
        let p = project("2026-10-14 SCL Riverloop", source: chosen)
        #expect(p.videoFolder(inputBase: URL(fileURLWithPath: "/Volumes/AData/Fly_Raw")) == chosen)
        #expect(p.videoURL(forStoredPath: macPath, inputBase: nil).path(percentEncoded: false)
                == "/other/Ride clips/Fly12Sport_3014.MP4")
    }

    @Test func noFolderSetKeepsTheStoredPath() {
        let p = project("2026-10-14 SCL Riverloop")
        #expect(p.videoFolder(inputBase: nil) == nil)
        #expect(p.videoURL(forStoredPath: macPath, inputBase: nil).path(percentEncoded: false) == macPath)
    }

    @Test func buildCheckPassesWhenEveryVideoIsThere() throws {
        let raw = FileManager.default.temporaryDirectory.appending(path: "raw-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raw) }
        let p = project("Ride")
        try FileManager.default.createDirectory(at: raw.appending(path: "Ride"), withIntermediateDirectories: true)
        try Data().write(to: raw.appending(path: "Ride/Fly12Sport_3014.MP4"))
        var row = Fixtures.enrich(t: 0)
        row.videoPath = macPath
        try BuildStep.checkVideosReachable([row], in: p, inputBase: raw)
    }

    @Test func buildCheckNamesTheMissingVideo() {
        let raw = FileManager.default.temporaryDirectory.appending(path: "raw-\(UUID().uuidString)")
        var row = Fixtures.enrich(t: 0)
        row.videoPath = macPath
        #expect {
            try BuildStep.checkVideosReachable([row], in: project("Ride"), inputBase: raw)
        } throws: { error in
            guard case PipelineError.missingInput(let message) = error else { return false }
            return message.contains("Fly12Sport_3014.MP4") && message.contains("/Ride")
        }
    }
}
