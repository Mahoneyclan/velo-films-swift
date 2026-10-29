// ProjectFolderAccessTests.swift
// Tests that a run stops with a plain message when the project's files can't be read (drive unplugged, or no folder
// permission on iPad), instead of treating every step as not run and starting the analysis over.

import Foundation
import Testing
@testable import VeloFilms

@MainActor
struct ProjectFolderAccessTests {

    /// Counts calls, so a test can tell whether the executor started a step.
    private final class SpyStep: PipelineStep, @unchecked Sendable {
        let name = "spy"
        var runs = 0
        func run(project: Project, reporter: VeloFilms.ProgressReporter) async throws { runs += 1 }
    }

    private func readableProject() throws -> Project {
        let folder = FileManager.default.temporaryDirectory.appending(path: "access-\(UUID().uuidString)")
        let project = Project(name: "Ride", folderURL: folder)
        try ProjectFileManager.createDirectoryStructure(for: project)
        return project
    }

    @Test func readableProjectHasNoProblem() throws {
        let project = try readableProject()
        defer { try? FileManager.default.removeItem(at: project.folderURL) }
        #expect(PipelineExecutor.projectFolderProblem(project) == nil)
    }

    @Test func missingProjectFolderIsReported() {
        let gone = Project(name: "Ride", folderURL: URL(fileURLWithPath: "/Volumes/NotConnected/Fly_Projects/Ride"))
        guard case .projectFolderUnreadable(let folder) = PipelineExecutor.projectFolderProblem(gone) else {
            Issue.record("expected projectFolderUnreadable")
            return
        }
        #expect(folder == "/Volumes/NotConnected/Fly_Projects/Ride")
    }

    @Test func runStopsBeforeAnyStepWhenTheFolderCantBeRead() {
        let gone = Project(name: "Ride", folderURL: URL(fileURLWithPath: "/Volumes/NotConnected/Fly_Projects/Ride"))
        let executor = PipelineExecutor()
        let spy = SpyStep()
        for step in StepName.allCases { executor.register(spy, for: step) }

        executor.run(.build, project: gone)

        #expect(!executor.isRunning)
        #expect(executor.failedStep == .build)
        #expect(executor.lastError?.localizedDescription.contains("Can't read this ride's files") == true)
        #expect(spy.runs == 0)
    }
}
