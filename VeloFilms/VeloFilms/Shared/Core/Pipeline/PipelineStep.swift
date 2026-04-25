import Foundation

/// All pipeline steps conform to this protocol. Mirrors step_registry.py.
protocol PipelineStep {
    var name: String { get }
    func run(project: Project, reporter: ProgressReporter) async throws
}

/// Named pipeline steps in dependency order.
enum StepName: String, CaseIterable {
    case flatten  = "flatten"
    case extract  = "extract"
    case enrich   = "enrich"
    case select   = "select"
    case build    = "build"
    case splash   = "splash"
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

    /// The artifact file that marks this step as complete.
    func completionArtifact(for project: Project) -> URL? {
        switch self {
        case .flatten:  return project.flattenJSONL
        case .extract:  return project.extractJSONL
        case .enrich:   return project.enrichedJSONL
        case .select:   return project.selectJSONL
        case .build:    return nil  // clips/ directory populated
        case .splash:   return nil  // splash_assets/ directory populated
        case .concat:   return project.finalReelURL
        }
    }

    func isComplete(for project: Project) -> Bool {
        guard let artifact = completionArtifact(for: project) else {
            // For steps without a single completion file, check directory non-empty
            switch self {
            case .build:
                let files = (try? FileManager.default.contentsOfDirectory(atPath: project.clipsDir.path)) ?? []
                return files.contains { $0.hasPrefix("_middle_") && $0.hasSuffix(".mp4") }
            case .splash:
                return FileManager.default.fileExists(atPath: project.clipsDir.appending(path: "_intro.mp4").path)
            default:
                return false
            }
        }
        return FileManager.default.fileExists(atPath: artifact.path)
    }
}
