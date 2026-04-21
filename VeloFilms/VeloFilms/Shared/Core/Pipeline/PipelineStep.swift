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
        case .flatten:  return project.flattenCSV
        case .extract:  return project.extractCSV
        case .enrich:   return project.enrichedCSV
        case .select:   return project.selectCSV
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
                return (try? FileManager.default.contentsOfDirectory(atPath: project.clipsDir.path))?.isEmpty == false
            case .splash:
                return (try? FileManager.default.contentsOfDirectory(atPath: project.splashAssetsDir.path))?.isEmpty == false
            default:
                return false
            }
        }
        return FileManager.default.fileExists(atPath: artifact.path)
    }
}
