import Foundation
import Observation

/// User-facing persistent settings — mirrors persistent_config.py.
@Observable
final class GlobalSettings {
    static let shared = GlobalSettings()

    // MARK: - Drive roots
    var inputBaseDir: URL? {
        didSet { saveURL(inputBaseDir, pathKey: "inputBaseDirPath", bookmarkKey: "inputBaseDirBookmark") }
    }
    var projectsRoot: URL? {
        didSet { saveURL(projectsRoot, pathKey: "projectsRootPath", bookmarkKey: "projectsRootBookmark") }
    }

    // MARK: - Pipeline timing
    var extractIntervalOverride: Double? = nil
    var highlightTargetMinutes: Double = AppConfig.highlightTargetDurationM
    var minGapBetweenClips: Double = AppConfig.minGapBetweenClips
    var gpxTimeOffsetS: Double = 0.0

    // MARK: - Camera setup
    var hasFly12Sport: Bool = true
    var hasFly6Pro: Bool = true
    var fly12SourceURL: URL? {
        didSet { saveURL(fly12SourceURL, pathKey: "fly12SourcePath", bookmarkKey: "fly12SourceBookmark") }
    }
    var fly6SourceURL: URL? {
        didSet { saveURL(fly6SourceURL, pathKey: "fly6SourcePath", bookmarkKey: "fly6SourceBookmark") }
    }
    var musicURL: URL? {
        didSet { saveURL(musicURL, pathKey: "musicPath", bookmarkKey: "musicBookmark") }
    }

    // MARK: - Camera calibration (offsets + timezones)
    var fly12SportOffset: Double = 0.0
    var fly6ProOffset: Double = 0.0
    var fly12SportTimezone: String = "UTC+0"
    var fly6ProTimezone: String = "UTC+0"
    /// Mirrors Python's CAMERA_CREATION_TIME_IS_LOCAL_WRONG_Z.
    /// True = camera stores local time mislabelled as UTC (subtract tz offset to correct).
    ///        This is the Cycliq default — cameras record local time but tag it 'Z'.
    /// False = camera stores genuine UTC (GPS-synced) — no correction needed.
    var cameraCreationTimeIsLocalWrongZ: Bool = true

    // MARK: - Audio volumes
    var musicVolume: Double = AppConfig.musicVolume
    var rawAudioVolume: Double = AppConfig.rawAudioVolume

    // MARK: - Display
    var dynamicGauges: Bool = true

    // MARK: - Detection
    var yoloMinConfidence: Double = 0.10

    // MARK: - Score weights (should sum to 1.0)
    var scoreWeightDetect: Double    = 0.30
    var scoreWeightScene: Double     = 0.10
    var scoreWeightSpeed: Double     = 0.20
    var scoreWeightGradient: Double  = 0.20
    var scoreWeightBboxArea: Double  = 0.05
    var scoreWeightSegment: Double   = 0.05
    var scoreWeightDualCamera: Double = 0.10

    // MARK: - Candidate pool
    var candidateFraction: Double = 2.5

    // MARK: - Focus Mode Filter defaults
    /// "First N minutes" filter window (minutes).
    var focusFirstNMinutes: Double = 10.0
    /// "Last N minutes" filter window (minutes).
    var focusLastNMinutes: Double = 10.0
    /// Gradient threshold for Climbs filter (%). Moments with gradientPct ≥ this value match.
    var focusClimbGradientPct: Double = 4.0
    /// Gradient threshold for Descents filter (%). Moments with gradientPct ≤ −this value match.
    var focusDescentGradientPct: Double = -4.0
    /// Minimum person+bicycle detection count for Group Riding filter. Default 5.
    var focusGroupMinDetections: Int = 5

    private init() {
        inputBaseDir  = loadURL(pathKey: "inputBaseDirPath", bookmarkKey: "inputBaseDirBookmark")
        projectsRoot  = loadURL(pathKey: "projectsRootPath", bookmarkKey: "projectsRootBookmark")
        fly12SourceURL = loadURL(pathKey: "fly12SourcePath", bookmarkKey: "fly12SourceBookmark")
        fly6SourceURL  = loadURL(pathKey: "fly6SourcePath",  bookmarkKey: "fly6SourceBookmark")
        musicURL       = loadURL(pathKey: "musicPath",       bookmarkKey: "musicBookmark")

        extractIntervalOverride = UserDefaults.standard.object(forKey: "extractIntervalOverride") as? Double
        highlightTargetMinutes  = UserDefaults.standard.double(forKey: "highlightTargetMinutes").nonZero
                                    ?? AppConfig.highlightTargetDurationM
        minGapBetweenClips      = UserDefaults.standard.double(forKey: "minGapBetweenClips").nonZero
                                    ?? AppConfig.minGapBetweenClips
        gpxTimeOffsetS          = UserDefaults.standard.double(forKey: "gpxTimeOffsetS")
        fly12SportOffset        = UserDefaults.standard.double(forKey: "fly12SportOffset")
        fly6ProOffset           = UserDefaults.standard.double(forKey: "fly6ProOffset")
        fly12SportTimezone      = UserDefaults.standard.string(forKey: "fly12SportTimezone") ?? "UTC+0"
        fly6ProTimezone         = UserDefaults.standard.string(forKey: "fly6ProTimezone") ?? "UTC+0"
        cameraCreationTimeIsLocalWrongZ = (UserDefaults.standard.object(forKey: "cameraCreationTimeIsLocalWrongZ") as? Bool) ?? true
        hasFly12Sport = (UserDefaults.standard.object(forKey: "hasFly12Sport") as? Bool) ?? true
        hasFly6Pro    = (UserDefaults.standard.object(forKey: "hasFly6Pro")    as? Bool) ?? true
        musicVolume             = UserDefaults.standard.double(forKey: "musicVolume").nonZero
                                    ?? AppConfig.musicVolume
        rawAudioVolume          = UserDefaults.standard.double(forKey: "rawAudioVolume").nonZero
                                    ?? AppConfig.rawAudioVolume
        dynamicGauges           = (UserDefaults.standard.object(forKey: "dynamicGauges") as? Bool) ?? true

        // Use object(forKey:) for weights/confidence so 0.0 is a valid stored value (not treated as "unset")
        yoloMinConfidence     = (UserDefaults.standard.object(forKey: "yoloMinConfidence")     as? Double) ?? yoloMinConfidence
        scoreWeightDetect     = (UserDefaults.standard.object(forKey: "scoreWeightDetect")     as? Double) ?? scoreWeightDetect
        scoreWeightScene      = (UserDefaults.standard.object(forKey: "scoreWeightScene")      as? Double) ?? scoreWeightScene
        scoreWeightSpeed      = (UserDefaults.standard.object(forKey: "scoreWeightSpeed")      as? Double) ?? scoreWeightSpeed
        scoreWeightGradient   = (UserDefaults.standard.object(forKey: "scoreWeightGradient")   as? Double) ?? scoreWeightGradient
        scoreWeightBboxArea   = (UserDefaults.standard.object(forKey: "scoreWeightBboxArea")   as? Double) ?? scoreWeightBboxArea
        scoreWeightSegment    = (UserDefaults.standard.object(forKey: "scoreWeightSegment")    as? Double) ?? scoreWeightSegment
        scoreWeightDualCamera = (UserDefaults.standard.object(forKey: "scoreWeightDualCamera") as? Double) ?? scoreWeightDualCamera
        candidateFraction     = UserDefaults.standard.double(forKey: "candidateFraction").nonZero ?? candidateFraction

        focusFirstNMinutes      = UserDefaults.standard.double(forKey: "focusFirstNMinutes").nonZero ?? 10.0
        focusLastNMinutes       = UserDefaults.standard.double(forKey: "focusLastNMinutes").nonZero ?? 10.0
        focusClimbGradientPct   = UserDefaults.standard.double(forKey: "focusClimbGradientPct").nonZero ?? focusClimbGradientPct
        let rawDescent = UserDefaults.standard.double(forKey: "focusDescentGradientPct")
        // rawDescent == 0 → never stored (first launch) — keep property default.
        // rawDescent > 0 → stored before descent became negative-convention → negate to migrate.
        focusDescentGradientPct = rawDescent == 0 ? focusDescentGradientPct : (rawDescent > 0 ? -rawDescent : rawDescent)
        let gmd = UserDefaults.standard.integer(forKey: "focusGroupMinDetections")
        focusGroupMinDetections = gmd > 0 ? gmd : 5
    }

    func save() {
        UserDefaults.standard.set(extractIntervalOverride, forKey: "extractIntervalOverride")
        UserDefaults.standard.set(highlightTargetMinutes,  forKey: "highlightTargetMinutes")
        UserDefaults.standard.set(minGapBetweenClips,      forKey: "minGapBetweenClips")
        UserDefaults.standard.set(gpxTimeOffsetS,          forKey: "gpxTimeOffsetS")
        UserDefaults.standard.set(fly12SportOffset,        forKey: "fly12SportOffset")
        UserDefaults.standard.set(fly6ProOffset,           forKey: "fly6ProOffset")
        UserDefaults.standard.set(fly12SportTimezone,      forKey: "fly12SportTimezone")
        UserDefaults.standard.set(fly6ProTimezone,         forKey: "fly6ProTimezone")
        UserDefaults.standard.set(cameraCreationTimeIsLocalWrongZ, forKey: "cameraCreationTimeIsLocalWrongZ")
        UserDefaults.standard.set(musicVolume,             forKey: "musicVolume")
        UserDefaults.standard.set(rawAudioVolume,          forKey: "rawAudioVolume")
        UserDefaults.standard.set(dynamicGauges,            forKey: "dynamicGauges")
        UserDefaults.standard.set(yoloMinConfidence,        forKey: "yoloMinConfidence")
        UserDefaults.standard.set(scoreWeightDetect,        forKey: "scoreWeightDetect")
        UserDefaults.standard.set(scoreWeightScene,         forKey: "scoreWeightScene")
        UserDefaults.standard.set(scoreWeightSpeed,         forKey: "scoreWeightSpeed")
        UserDefaults.standard.set(scoreWeightGradient,      forKey: "scoreWeightGradient")
        UserDefaults.standard.set(scoreWeightBboxArea,      forKey: "scoreWeightBboxArea")
        UserDefaults.standard.set(scoreWeightSegment,       forKey: "scoreWeightSegment")
        UserDefaults.standard.set(scoreWeightDualCamera,    forKey: "scoreWeightDualCamera")
        UserDefaults.standard.set(candidateFraction,        forKey: "candidateFraction")
        UserDefaults.standard.set(hasFly12Sport,            forKey: "hasFly12Sport")
        UserDefaults.standard.set(hasFly6Pro,               forKey: "hasFly6Pro")
        UserDefaults.standard.set(focusFirstNMinutes,       forKey: "focusFirstNMinutes")
        UserDefaults.standard.set(focusLastNMinutes,        forKey: "focusLastNMinutes")
        UserDefaults.standard.set(focusClimbGradientPct,    forKey: "focusClimbGradientPct")
        UserDefaults.standard.set(focusDescentGradientPct,  forKey: "focusDescentGradientPct")
        UserDefaults.standard.set(focusGroupMinDetections,  forKey: "focusGroupMinDetections")
    }

    var effectiveExtractInterval: Double {
        extractIntervalOverride ?? AppConfig.extractIntervalSeconds
    }

    // MARK: - URL bookmark helpers

    // .withSecurityScope is macOS-only; on iOS plain bookmarks + startAccessingSecurityScopedResource() suffice
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []

    private func saveURL(_ url: URL?, pathKey: String, bookmarkKey: String) {
        UserDefaults.standard.set(url?.path, forKey: pathKey)
        guard let url else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }
        if let data = try? url.bookmarkData(options: Self.bookmarkCreationOptions,
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    private func loadURL(pathKey: String, bookmarkKey: String) -> URL? {
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: Self.bookmarkResolutionOptions,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
#if os(iOS)
                _ = url.startAccessingSecurityScopedResource()
#endif
                if stale {
                    if let fresh = try? url.bookmarkData(options: Self.bookmarkCreationOptions,
                                                         includingResourceValuesForKeys: nil,
                                                         relativeTo: nil) {
                        UserDefaults.standard.set(fresh, forKey: bookmarkKey)
                        UserDefaults.standard.set(url.path, forKey: pathKey)
                    }
                }
                return url
            }
        }
        // Fall back to plain path for migration from older builds
        if let p = UserDefaults.standard.string(forKey: pathKey) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
