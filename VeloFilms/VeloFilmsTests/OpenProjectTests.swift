// OpenProjectTests.swift
// Tests for "Open existing project": recognising a project folder, finding a project already in the list, and
// telling whether a project's drive is connected.

import Foundation
import Testing
@testable import VeloFilms

struct OpenProjectTests {

    /// A fresh empty folder in the temporary directory.
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func folderWithWorkingIsAProject() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try ProjectFileManager.createDirectoryStructure(for: Project(name: "Ride", folderURL: folder))
        #expect(ProjectFileManager.isProjectFolder(folder))
    }

    @Test func rawClipFolderIsNotAProject() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("clip".utf8).write(to: folder.appending(path: "FRONT_0001.MP4"))
        #expect(!ProjectFileManager.isProjectFolder(folder))
    }

    @Test func workingAsAFileDoesNotCount() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appending(path: "working"))
        #expect(!ProjectFileManager.isProjectFolder(folder))
    }

    @Test func findsProjectAlreadyInTheList() {
        let a = Project(name: "Ride A", folderURL: URL(fileURLWithPath: "/Volumes/AData/Projects/Ride A"))
        let b = Project(name: "Ride B", folderURL: URL(fileURLWithPath: "/Volumes/AData/Projects/Ride B"))
        let picked = URL(fileURLWithPath: "/Volumes/AData/Projects/Other/../Ride B/")
        #expect(ProjectStore.project(at: picked, in: [a, b])?.id == b.id)
        #expect(ProjectStore.project(at: URL(fileURLWithPath: "/Volumes/AData/Projects/Ride C"), in: [a, b]) == nil)
    }

    @Test func missingDriveIsNotAvailable() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(Project(name: "Here", folderURL: folder).isFolderAvailable)
        #expect(!Project(name: "Gone", folderURL: folder.appending(path: "missing")).isFolderAvailable)
    }
}
