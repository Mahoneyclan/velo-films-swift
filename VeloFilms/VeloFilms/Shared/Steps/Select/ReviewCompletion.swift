// ReviewCompletion.swift
// What happens when the Fine Tune screen closes: the ride is marked reviewed (unlocking Build) and a built reel that
// no longer matches the selection is deleted so it must be rebuilt. Run by Fine Tune itself, because on the Mac it is
// a separate window and the project screen may not be showing that ride when it closes.

import Foundation

/// The "review finished" rules, kept out of the views so they can be unit tested.
enum ReviewCompletion {

    /// UserDefaults key of the per-project "reviewed" flag. Permanent: earlier versions wrote this key.
    /// - Parameter projectID: The project's `id`.
    /// - Returns: The key, e.g. `"reviewed-<uuid>"`.
    static func reviewedKey(for projectID: UUID) -> String { "reviewed-\(projectID)" }

    /// Whether the project's selection has been reviewed in Fine Tune.
    /// - Parameters:
    ///   - project: The project.
    ///   - defaults: Where the flag is stored (injectable for tests).
    /// - Returns: `true` once Fine Tune has been closed after an analysis.
    static func isReviewed(_ project: Project, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: reviewedKey(for: project.id))
    }

    /// Marks the project reviewed and, if a reel was already built and the clips in it changed, deletes the
    /// built reel, rendered clips, minimaps and elevation strips so Build starts again.
    ///
    /// Side effects: writes UserDefaults and deletes files in the project folder. Deletion failures are ignored:
    /// a leftover file is overwritten by the next build.
    /// - Parameters:
    ///   - project: The project reviewed.
    ///   - reelAtOpen: momentIds in the reel when Fine Tune opened.
    ///   - defaults: Where the flag is stored (injectable for tests).
    /// - Returns: `true` if built outputs were deleted.
    @discardableResult
    static func finish(project: Project, reelAtOpen: Set<Int>, defaults: UserDefaults = .standard) -> Bool {
        defaults.set(true, forKey: reviewedKey(for: project.id))
        let fm = FileManager.default
        guard fm.fileExists(atPath: project.finalReelURL.path),
              reelMomentIds(of: project) != reelAtOpen else { return false }
        removeBuiltOutputs(of: project)
        return true
    }

    /// momentIds in the reel according to `select.jsonl` (empty if it can't be read).
    /// - Parameter project: The project.
    /// - Returns: The moments with a recommended row.
    static func reelMomentIds(of project: Project) -> Set<Int> {
        guard let rows = try? JSONLReader().read(from: project.selectJSONL) as [SelectRow] else { return [] }
        return Set(rows.filter(\.recommended).map(\.base.momentId))
    }

    /// Deletes the final reel, the rendered clips (`.mp4`/`.mov` in `clips/`) and the minimap and elevation images.
    /// - Parameter project: The project.
    static func removeBuiltOutputs(of project: Project) {
        let fm = FileManager.default
        try? fm.removeItem(at: project.finalReelURL)
        for dir in [project.minimapsDir, project.elevationDir] {
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for f in files { try? fm.removeItem(at: dir.appending(path: f)) }
        }
        guard let clips = try? fm.contentsOfDirectory(atPath: project.clipsDir.path) else { return }
        for f in clips where f.hasSuffix(".mp4") || f.hasSuffix(".mov") {
            try? fm.removeItem(at: project.clipsDir.appending(path: f))
        }
    }
}
