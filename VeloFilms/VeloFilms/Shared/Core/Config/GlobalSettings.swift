import Foundation
import Observation

/// User-facing persistent settings — mirrors persistent_config.py.
@Observable
final class GlobalSettings {
    static let shared = GlobalSettings()

    // MARK: - Drive roots
    var inputBaseDir: URL? {
        didSet { UserDefaults.standard.set(inputBaseDir?.path, forKey: "inputBaseDirPath") }
    }
    var projectsRoot: URL? {
        didSet { UserDefaults.standard.set(projectsRoot?.path, forKey: "projectsRootPath") }
    }

    // MARK: - Pipeline timing
    var extractIntervalOverride: Double? = nil
    var highlightTargetMinutes: Double = AppConfig.highlightTargetDurationM
    var minGapBetweenClips: Double = AppConfig.minGapBetweenClips
    var gpxTimeOffsetS: Double = 0.0

    // MARK: - Camera setup
    var hasFly12Sport: Bool = true
    var hasFly6Pro: Bool = true

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

    private init() {
        if let p = UserDefaults.standard.string(forKey: "inputBaseDirPath") {
            inputBaseDir = URL(fileURLWithPath: p)
        }
        if let p = UserDefaults.standard.string(forKey: "projectsRootPath") {
            projectsRoot = URL(fileURLWithPath: p)
        }
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
        UserDefaults.standard.set(dynamicGauges,           forKey: "dynamicGauges")
        UserDefaults.standard.set(hasFly12Sport,            forKey: "hasFly12Sport")
        UserDefaults.standard.set(hasFly6Pro,               forKey: "hasFly6Pro")
    }

    var effectiveExtractInterval: Double {
        extractIntervalOverride ?? AppConfig.extractIntervalSeconds
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
