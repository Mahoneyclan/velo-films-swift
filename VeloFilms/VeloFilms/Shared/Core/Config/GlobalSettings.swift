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
    var clipOutLenS: Double = 3.5
    var clipPreRollS: Double = 0.5
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
    var yoloMinConfidence: Double = 0.10          // person + bicycle
    var yoloVehicleConfidence: Double = 0.50      // car, motorcycle, bus, truck, traffic light, stop sign

    // MARK: - Per-class YOLO enable + detectScore weight
    var yoloEnablePerson: Bool       = true;  var yoloWeightPerson: Double       = 1.0
    var yoloEnableBicycle: Bool      = true;  var yoloWeightBicycle: Double      = 1.0
    var yoloEnableCar: Bool          = true;  var yoloWeightCar: Double          = 0.3
    var yoloEnableMotorcycle: Bool   = true;  var yoloWeightMotorcycle: Double   = 0.6
    var yoloEnableBus: Bool          = true;  var yoloWeightBus: Double          = 0.2
    var yoloEnableTruck: Bool        = true;  var yoloWeightTruck: Double        = 0.2
    var yoloEnableTrafficLight: Bool = true;  var yoloWeightTrafficLight: Double = 0.1
    var yoloEnableStopSign: Bool     = true;  var yoloWeightStopSign: Double     = 0.1

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
    /// Gradient threshold for Climbs filter (%). Moments with gradientPct ≥ this value match.
    var focusClimbGradientPct: Double = 4.0
    /// Gradient threshold for Descents filter (%). Moments with gradientPct ≤ −this value match.
    var focusDescentGradientPct: Double = -4.0
    /// Minimum person+bicycle detection count for Group Riding filter. Default 5.
    var focusGroupMinDetections: Int = 5

    // MARK: - Selection zone (percentage of ride span)
    /// Fraction of ride duration that counts as the opening zone (default 15%).
    var startZonePct: Double = 0.15
    /// Fraction of ride duration that counts as the closing zone (default 15%).
    var endZonePct: Double = 0.15

    private init() {
        inputBaseDir  = loadURL(pathKey: "inputBaseDirPath", bookmarkKey: "inputBaseDirBookmark")
        projectsRoot  = loadURL(pathKey: "projectsRootPath", bookmarkKey: "projectsRootBookmark")
        fly12SourceURL = loadURL(pathKey: "fly12SourcePath", bookmarkKey: "fly12SourceBookmark")
        fly6SourceURL  = loadURL(pathKey: "fly6SourcePath",  bookmarkKey: "fly6SourceBookmark")
        musicURL       = loadURL(pathKey: "musicPath",       bookmarkKey: "musicBookmark")

        extractIntervalOverride = UserDefaults.standard.object(forKey: "extractIntervalOverride") as? Double
        highlightTargetMinutes  = UserDefaults.standard.double(forKey: "highlightTargetMinutes").nonZero
                                    ?? AppConfig.highlightTargetDurationM
        clipOutLenS             = UserDefaults.standard.double(forKey: "clipOutLenS").nonZero ?? 3.5
        clipPreRollS            = UserDefaults.standard.double(forKey: "clipPreRollS").nonZero ?? 0.5
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
        yoloMinConfidence      = (UserDefaults.standard.object(forKey: "yoloMinConfidence")      as? Double) ?? yoloMinConfidence
        yoloVehicleConfidence  = (UserDefaults.standard.object(forKey: "yoloVehicleConfidence")  as? Double) ?? yoloVehicleConfidence
        yoloEnablePerson       = (UserDefaults.standard.object(forKey: "yoloEnablePerson")       as? Bool)   ?? true
        yoloWeightPerson       = (UserDefaults.standard.object(forKey: "yoloWeightPerson")       as? Double) ?? 1.0
        yoloEnableBicycle      = (UserDefaults.standard.object(forKey: "yoloEnableBicycle")      as? Bool)   ?? true
        yoloWeightBicycle      = (UserDefaults.standard.object(forKey: "yoloWeightBicycle")      as? Double) ?? 1.0
        yoloEnableCar          = (UserDefaults.standard.object(forKey: "yoloEnableCar")          as? Bool)   ?? true
        yoloWeightCar          = (UserDefaults.standard.object(forKey: "yoloWeightCar")          as? Double) ?? 0.3
        yoloEnableMotorcycle   = (UserDefaults.standard.object(forKey: "yoloEnableMotorcycle")   as? Bool)   ?? true
        yoloWeightMotorcycle   = (UserDefaults.standard.object(forKey: "yoloWeightMotorcycle")   as? Double) ?? 0.6
        yoloEnableBus          = (UserDefaults.standard.object(forKey: "yoloEnableBus")          as? Bool)   ?? true
        yoloWeightBus          = (UserDefaults.standard.object(forKey: "yoloWeightBus")          as? Double) ?? 0.2
        yoloEnableTruck        = (UserDefaults.standard.object(forKey: "yoloEnableTruck")        as? Bool)   ?? true
        yoloWeightTruck        = (UserDefaults.standard.object(forKey: "yoloWeightTruck")        as? Double) ?? 0.2
        yoloEnableTrafficLight = (UserDefaults.standard.object(forKey: "yoloEnableTrafficLight") as? Bool)   ?? true
        yoloWeightTrafficLight = (UserDefaults.standard.object(forKey: "yoloWeightTrafficLight") as? Double) ?? 0.1
        yoloEnableStopSign     = (UserDefaults.standard.object(forKey: "yoloEnableStopSign")     as? Bool)   ?? true
        yoloWeightStopSign     = (UserDefaults.standard.object(forKey: "yoloWeightStopSign")     as? Double) ?? 0.1
        scoreWeightDetect     = (UserDefaults.standard.object(forKey: "scoreWeightDetect")     as? Double) ?? scoreWeightDetect
        scoreWeightScene      = (UserDefaults.standard.object(forKey: "scoreWeightScene")      as? Double) ?? scoreWeightScene
        scoreWeightSpeed      = (UserDefaults.standard.object(forKey: "scoreWeightSpeed")      as? Double) ?? scoreWeightSpeed
        scoreWeightGradient   = (UserDefaults.standard.object(forKey: "scoreWeightGradient")   as? Double) ?? scoreWeightGradient
        scoreWeightBboxArea   = (UserDefaults.standard.object(forKey: "scoreWeightBboxArea")   as? Double) ?? scoreWeightBboxArea
        scoreWeightSegment    = (UserDefaults.standard.object(forKey: "scoreWeightSegment")    as? Double) ?? scoreWeightSegment
        scoreWeightDualCamera = (UserDefaults.standard.object(forKey: "scoreWeightDualCamera") as? Double) ?? scoreWeightDualCamera
        candidateFraction     = UserDefaults.standard.double(forKey: "candidateFraction").nonZero ?? candidateFraction

        focusClimbGradientPct   = UserDefaults.standard.double(forKey: "focusClimbGradientPct").nonZero ?? focusClimbGradientPct
        let rawDescent = UserDefaults.standard.double(forKey: "focusDescentGradientPct")
        // rawDescent == 0 → never stored (first launch) — keep property default.
        // rawDescent > 0 → stored before descent became negative-convention → negate to migrate.
        focusDescentGradientPct = rawDescent == 0 ? focusDescentGradientPct : (rawDescent > 0 ? -rawDescent : rawDescent)
        let gmd = UserDefaults.standard.integer(forKey: "focusGroupMinDetections")
        focusGroupMinDetections = gmd > 0 ? gmd : 5
        startZonePct = (UserDefaults.standard.object(forKey: "startZonePct") as? Double) ?? 0.15
        endZonePct   = (UserDefaults.standard.object(forKey: "endZonePct")   as? Double) ?? 0.15
    }

    func save() {
        UserDefaults.standard.set(extractIntervalOverride, forKey: "extractIntervalOverride")
        UserDefaults.standard.set(highlightTargetMinutes,  forKey: "highlightTargetMinutes")
        UserDefaults.standard.set(clipOutLenS,             forKey: "clipOutLenS")
        UserDefaults.standard.set(clipPreRollS,            forKey: "clipPreRollS")
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
        UserDefaults.standard.set(yoloVehicleConfidence,   forKey: "yoloVehicleConfidence")
        UserDefaults.standard.set(yoloEnablePerson,        forKey: "yoloEnablePerson")
        UserDefaults.standard.set(yoloWeightPerson,        forKey: "yoloWeightPerson")
        UserDefaults.standard.set(yoloEnableBicycle,       forKey: "yoloEnableBicycle")
        UserDefaults.standard.set(yoloWeightBicycle,       forKey: "yoloWeightBicycle")
        UserDefaults.standard.set(yoloEnableCar,           forKey: "yoloEnableCar")
        UserDefaults.standard.set(yoloWeightCar,           forKey: "yoloWeightCar")
        UserDefaults.standard.set(yoloEnableMotorcycle,    forKey: "yoloEnableMotorcycle")
        UserDefaults.standard.set(yoloWeightMotorcycle,    forKey: "yoloWeightMotorcycle")
        UserDefaults.standard.set(yoloEnableBus,           forKey: "yoloEnableBus")
        UserDefaults.standard.set(yoloWeightBus,           forKey: "yoloWeightBus")
        UserDefaults.standard.set(yoloEnableTruck,         forKey: "yoloEnableTruck")
        UserDefaults.standard.set(yoloWeightTruck,         forKey: "yoloWeightTruck")
        UserDefaults.standard.set(yoloEnableTrafficLight,  forKey: "yoloEnableTrafficLight")
        UserDefaults.standard.set(yoloWeightTrafficLight,  forKey: "yoloWeightTrafficLight")
        UserDefaults.standard.set(yoloEnableStopSign,      forKey: "yoloEnableStopSign")
        UserDefaults.standard.set(yoloWeightStopSign,      forKey: "yoloWeightStopSign")
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
        UserDefaults.standard.set(focusClimbGradientPct,    forKey: "focusClimbGradientPct")
        UserDefaults.standard.set(focusDescentGradientPct,  forKey: "focusDescentGradientPct")
        UserDefaults.standard.set(focusGroupMinDetections,  forKey: "focusGroupMinDetections")
        UserDefaults.standard.set(startZonePct,              forKey: "startZonePct")
        UserDefaults.standard.set(endZonePct,                forKey: "endZonePct")
    }

    var isDualCamera: Bool { hasFly12Sport && hasFly6Pro }

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
