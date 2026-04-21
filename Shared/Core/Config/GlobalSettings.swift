import Foundation
import Combine

/// User-facing persistent settings — mirrors persistent_config.py.
/// Stored via UserDefaults (@AppStorage in views, or direct access here).
@MainActor
final class GlobalSettings: ObservableObject {
    static let shared = GlobalSettings()

    // MARK: - Drive roots (stored as security-scoped bookmark data on iPadOS)
    @Published var inputBaseDirBookmark: Data? {
        didSet { UserDefaults.standard.set(inputBaseDirBookmark, forKey: "inputBaseDirBookmark") }
    }
    @Published var projectsRootBookmark: Data? {
        didSet { UserDefaults.standard.set(projectsRootBookmark, forKey: "projectsRootBookmark") }
    }

    // Resolved URLs (ephemeral — re-resolved each launch from bookmarks)
    var inputBaseDir: URL?
    var projectsRoot: URL?

    // MARK: - Pipeline overrides (advanced)
    @Published var extractIntervalOverride: Double? = nil
    @Published var highlightTargetMinutes: Double = AppConfig.highlightTargetDurationM

    // MARK: - Camera offsets
    @Published var fly12SportOffset: Double = 0.0
    @Published var fly6ProOffset: Double = 0.0

    // MARK: - Display
    @Published var showElevationPlot: Bool = true
    @Published var dynamicGauges: Bool = true

    private init() {
        inputBaseDirBookmark  = UserDefaults.standard.data(forKey: "inputBaseDirBookmark")
        projectsRootBookmark  = UserDefaults.standard.data(forKey: "projectsRootBookmark")
        extractIntervalOverride = UserDefaults.standard.object(forKey: "extractIntervalOverride") as? Double
        highlightTargetMinutes  = UserDefaults.standard.double(forKey: "highlightTargetMinutes").nonZero ?? AppConfig.highlightTargetDurationM
        fly12SportOffset = UserDefaults.standard.double(forKey: "fly12SportOffset")
        fly6ProOffset    = UserDefaults.standard.double(forKey: "fly6ProOffset")
        showElevationPlot = UserDefaults.standard.bool(forKey: "showElevationPlot")
        dynamicGauges     = (UserDefaults.standard.object(forKey: "dynamicGauges") as? Bool) ?? true

        resolveBookmarks()
    }

    func save() {
        UserDefaults.standard.set(extractIntervalOverride, forKey: "extractIntervalOverride")
        UserDefaults.standard.set(highlightTargetMinutes, forKey: "highlightTargetMinutes")
        UserDefaults.standard.set(fly12SportOffset, forKey: "fly12SportOffset")
        UserDefaults.standard.set(fly6ProOffset,    forKey: "fly6ProOffset")
        UserDefaults.standard.set(showElevationPlot, forKey: "showElevationPlot")
        UserDefaults.standard.set(dynamicGauges,     forKey: "dynamicGauges")
    }

    var effectiveExtractInterval: Double {
        extractIntervalOverride ?? AppConfig.extractIntervalSeconds
    }

    // MARK: - Bookmark resolution

    func resolveBookmarks() {
        inputBaseDir = resolveBookmark(inputBaseDirBookmark)
        projectsRoot = resolveBookmark(projectsRootBookmark)
    }

    private func resolveBookmark(_ data: Data?) -> URL? {
        guard let data else { return nil }
        var isStale = false
        do {
#if os(iOS)
            let url = try URL(resolvingBookmarkData: data,
                              options: .withoutUI,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
#else
            let url = try URL(resolvingBookmarkData: data,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
#endif
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
