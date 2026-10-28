// PipelineStep.swift
// The step protocol, the seven named steps, their dependencies and how completion is detected.

import Foundation

/// One stage of the highlight pipeline. Same role as `step_registry.py` in the original Python app.
protocol PipelineStep: Sendable {
    /// Short name used in logs.
    var name: String { get }
    /// Runs the step for `project`, reading the previous step's output and writing its own.
    /// - Parameters:
    ///   - project: The ride project.
    ///   - reporter: Receives progress updates for the UI.
    /// - Throws: `PipelineError` for missing inputs or failed renders, `CancellationError` if cancelled, or
    ///   file errors.
    func run(project: Project, reporter: ProgressReporter) async throws
}

/// The pipeline steps, in run order. Raw values are used in logs and must stay stable.
enum StepName: String, CaseIterable {
    /// GPX → one point per second (`flatten.jsonl`).
    case flatten  = "flatten"
    /// Sampling grid matched to camera clips (`extract.jsonl`).
    case extract  = "extract"
    /// YOLO detection, scene change, GPS and scores (`enriched.jsonl`).
    case enrich   = "enrich"
    /// Picks the highlight clips (`select.jsonl`).
    case select   = "select"
    /// Renders each selected clip with overlays (`clips/clip_*.mp4`).
    case build    = "build"
    /// Renders the intro and outro (`clips/_intro.mp4`).
    case splash   = "splash"
    /// Joins everything into the final reel (`{name}.mp4`).
    case concat   = "concat"

    /// Steps that must complete successfully before this step can run.
    var dependencies: [StepName] {
        switch self {
        case .flatten: return []
        case .extract: return [.flatten]
        case .enrich:  return [.extract]
        case .select:  return [.enrich]
        case .build:   return [.select]
        case .splash:  return [.build]
        case .concat:  return [.splash]
        }
    }

    /// The file whose existence marks this step as complete, or `nil` for Build and Splash, which
    /// `isComplete(for:)` checks separately.
    /// - Parameter project: The project whose folder is checked.
    /// - Returns: The marker file's location, or `nil` for Build and Splash.
    func completionArtifact(for project: Project) -> URL? {
        switch self {
        case .flatten:  return project.flattenJSONL
        case .extract:  return project.extractJSONL
        case .enrich:   return project.enrichedJSONL
        case .select:   return project.selectJSONL
        case .build:    return nil  // any clips/clip_*.mp4
        case .splash:   return nil  // clips/_intro.mp4
        case .concat:   return project.finalReelURL
        }
    }

    /// Whether this step's output already exists on disk. Used to skip finished prerequisites.
    /// - Parameter project: The project to check.
    /// - Returns: `true` if the output exists. Does not check that it is up to date.
    func isComplete(for project: Project) -> Bool {
        guard let artifact = completionArtifact(for: project) else {
            // Build: at least one rendered clip. Splash: the intro exists.
            switch self {
            case .build:
                let files = (try? FileManager.default.contentsOfDirectory(atPath: project.clipsDir.path)) ?? []
                return files.contains { $0.hasPrefix("clip_") && $0.hasSuffix(".mp4") }
            case .splash:
                return FileManager.default.fileExists(atPath: project.clipsDir.appending(path: "_intro.mp4").path)
            default:
                return false
            }
        }
        return FileManager.default.fileExists(atPath: artifact.path)
    }
}
