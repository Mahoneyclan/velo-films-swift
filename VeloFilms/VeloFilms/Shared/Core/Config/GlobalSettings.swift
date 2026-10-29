// GlobalSettings.swift
// User settings shared by the pipeline steps and the Settings screens.

import Foundation
import Observation

/// App-wide user settings, loaded from UserDefaults at launch.
///
/// Properties are plain stored values; changes are written back only when a view calls `save()`. Folder URLs
/// are the exception and save immediately (`didSet`). UserDefaults key names are permanent: renaming one loses
/// the user's saved value. Ported from `persistent_config.py` in the original Python app (not in this repo).
@Observable
final class GlobalSettings {
    /// The single shared instance used throughout the app.
    static let shared = GlobalSettings()

    // MARK: - Drive roots
    /// Folder where clips copied from the cameras are stored.
    var inputBaseDir: URL? {
        didSet { saveURL(inputBaseDir, pathKey: "inputBaseDirPath", bookmarkKey: "inputBaseDirBookmark") }
    }
    /// Folder where ride project folders are created.
    var projectsRoot: URL? {
        didSet { saveURL(projectsRoot, pathKey: "projectsRootPath", bookmarkKey: "projectsRootBookmark") }
    }

    // MARK: - Pipeline timing
    /// Sampling interval (seconds) chosen by the user, or `nil` to use `AppConfig.extractIntervalSeconds`.
    var extractIntervalOverride: Double? = nil
    /// Target length of the highlight reel, in minutes.
    var highlightTargetMinutes: Double = AppConfig.highlightTargetDurationM
    /// Length of each highlight clip, in seconds.
    var clipOutLenS: Double = 3.5
    /// Seconds of video kept before each selected moment.
    var clipPreRollS: Double = 0.5
    /// Minimum seconds between two selected clips, so the reel doesn't repeat one stretch of road.
    var minGapBetweenClips: Double = AppConfig.minGapBetweenClips
    /// Seconds added to GPX times to line them up with the camera clock.
    var gpxTimeOffsetS: Double = 0.0

    // MARK: - Camera setup
    /// `true` if the rider uses a Fly12 Sport (front) camera.
    var hasFly12Sport: Bool = true
    /// `true` if the rider uses a Fly6 Pro (rear) camera.
    var hasFly6Pro: Bool = true
    /// Folder (usually the camera's SD card) to copy Fly12 Sport clips from.
    var fly12SourceURL: URL? {
        didSet { saveURL(fly12SourceURL, pathKey: "fly12SourcePath", bookmarkKey: "fly12SourceBookmark") }
    }
    /// Folder (usually the camera's SD card) to copy Fly6 Pro clips from.
    var fly6SourceURL: URL? {
        didSet { saveURL(fly6SourceURL, pathKey: "fly6SourcePath", bookmarkKey: "fly6SourceBookmark") }
    }
    /// A single music file that overrides the bundled music library; played (and looped) for the whole reel.
    var musicURL: URL? {
        didSet { saveURL(musicURL, pathKey: "musicPath", bookmarkKey: "musicBookmark") }
    }
    /// The user's music folder (any Files location, e.g. iCloud Drive or Dropbox). Every audio file in it joins the
    /// backing-music library; see `MusicFolder`. Saved as a security-scoped bookmark so access survives relaunches.
    var musicFolderURL: URL? {
        didSet { saveURL(musicFolderURL, pathKey: "musicFolderPath", bookmarkKey: "musicFolderBookmark") }
    }

    // MARK: - Camera calibration (offsets + timezones; "Time Sync" tab in Settings)
    /// Manual clock correction for the Fly12 Sport, in seconds.
    var fly12SportOffset: Double = 0.0
    /// Manual clock correction for the Fly6 Pro, in seconds.
    var fly6ProOffset: Double = 0.0
    /// Fly12 Sport clock time zone, e.g. `"UTC+10"`.
    var fly12SportTimezone: String = "UTC+0"
    /// Fly6 Pro clock time zone, e.g. `"UTC+10"`.
    var fly6ProTimezone: String = "UTC+0"
    /// Same meaning as `CAMERA_CREATION_TIME_IS_LOCAL_WRONG_Z` in the original Python app.
    /// True = camera stores local time mislabelled as UTC (subtract tz offset to correct).
    ///        This is the Cycliq default — cameras record local time but tag it 'Z'.
    /// False = camera stores genuine UTC (GPS-synced) — no correction needed.
    var cameraCreationTimeIsLocalWrongZ: Bool = true

    // MARK: - Audio volumes
    /// Backing-music volume, 0–1.
    var musicVolume: Double = AppConfig.musicVolume
    /// Volume of the cameras' own audio, 0–1.
    var rawAudioVolume: Double = AppConfig.rawAudioVolume

    // MARK: - Display
    /// "Dynamic gauges (ProRes)" toggle in Settings. Saved, but not currently read by any pipeline step.
    var dynamicGauges: Bool = true

    // MARK: - Detection confidence thresholds
    /// Minimum YOLO confidence (0–1) to count a detection. Lower for bicycles because they are small and often partly hidden.
    var yoloBicycleConfidence: Double    = 0.10   // bicycle class
    /// Minimum confidence for a person without a bicycle.
    var yoloPedestrianConfidence: Double = 0.25   // person class (no bicycle in frame)
    /// Minimum confidence for cars, motorcycles, buses and trucks; higher to avoid parked-car noise.
    var yoloVehicleConfidence: Double    = 0.50   // car, motorcycle, bus, truck

    // MARK: - Per-class YOLO enable + detectScore weight
    /// Cyclist — applied to both person and bicycle detections when bicycle is present in the frame.
    var yoloEnableBicycle: Bool      = true;  var yoloWeightBicycle: Double      = 1.0
    /// Pedestrian — person detected without a bicycle. Enable/disable score contribution independently.
    var yoloEnablePedestrian: Bool   = true;  var yoloWeightPedestrian: Double   = 0.3
    /// Car detections: on/off and weight in the detection score. The same pattern applies to the lines below.
    var yoloEnableCar: Bool          = true;  var yoloWeightCar: Double          = 0.3
    /// Motorcycle detections: on/off and weight.
    var yoloEnableMotorcycle: Bool   = true;  var yoloWeightMotorcycle: Double   = 0.6
    /// Bus detections: on/off and weight.
    var yoloEnableBus: Bool          = true;  var yoloWeightBus: Double          = 0.2
    /// Truck detections: on/off and weight.
    var yoloEnableTruck: Bool        = true;  var yoloWeightTruck: Double        = 0.2

    // MARK: - Score weights
    // Relative weights for ScoreCalculator.composite. They are not normalised, so they don't need to sum to 1.0;
    // the five composite defaults sum to 0.95. scoreWeightDualCamera (0.10) is added separately for moments seen by both cameras
    // (PartnerMatcher).

    /// Default score weights: the one source for the initial values and Settings → AI Scoring → Reset to defaults.
    enum DefaultScoreWeights {
        /// YOLO detection.
        static let detect     = 0.30
        /// Scene change.
        static let scene      = 0.10
        /// Speed.
        static let speed      = 0.20
        /// Gradient.
        static let gradient   = 0.20
        /// Strava PR / top-3 effort. 0.15 (raised from 0.05 on 2026-10-27, when segment scoring started working)
        /// lets a PR count about as much as a strong detection without forcing it into the reel.
        static let segment    = 0.15
        /// Dual-camera bonus.
        static let dualCamera = 0.10
    }

    /// Weight of the YOLO detection score.
    var scoreWeightDetect: Double    = DefaultScoreWeights.detect
    /// Weight of the scene-change score.
    var scoreWeightScene: Double     = DefaultScoreWeights.scene
    /// Weight of speed.
    var scoreWeightSpeed: Double     = DefaultScoreWeights.speed
    /// Weight of gradient (climbs and descents).
    var scoreWeightGradient: Double  = DefaultScoreWeights.gradient
    /// Weight of Strava PR and top-3 efforts.
    var scoreWeightSegment: Double   = DefaultScoreWeights.segment
    /// Bonus added when both cameras have footage of the moment.
    var scoreWeightDualCamera: Double = DefaultScoreWeights.dualCamera

    /// Restores every score weight to `DefaultScoreWeights` and saves.
    func resetScoreWeights() {
        scoreWeightDetect     = DefaultScoreWeights.detect
        scoreWeightScene      = DefaultScoreWeights.scene
        scoreWeightSpeed      = DefaultScoreWeights.speed
        scoreWeightGradient   = DefaultScoreWeights.gradient
        scoreWeightSegment    = DefaultScoreWeights.segment
        scoreWeightDualCamera = DefaultScoreWeights.dualCamera
        save()
    }

    // MARK: - Focus Mode Filter defaults
    /// Gradient threshold for Climbs filter (%). Moments with gradientPct ≥ this value match.
    var focusClimbGradientPct: Double = 4.0
    /// Gradient threshold for Descents filter (%). Moments with gradientPct ≤ −this value match.
    var focusDescentGradientPct: Double = -4.0
    /// Minimum rider count for the Group Riding filter (see `FocusFilter.riderCount`). Default 5.
    var focusGroupMinDetections: Int = 5

    // Retired UserDefaults keys, left unread and never reused: "candidateFraction", "startZonePct", "endZonePct"
    // (selection stopped using a shortlist and opening/closing zones on 2026-10-28).
    private init() {
        inputBaseDir  = loadURL(pathKey: "inputBaseDirPath", bookmarkKey: "inputBaseDirBookmark")
        projectsRoot  = loadURL(pathKey: "projectsRootPath", bookmarkKey: "projectsRootBookmark")
        fly12SourceURL = loadURL(pathKey: "fly12SourcePath", bookmarkKey: "fly12SourceBookmark")
        fly6SourceURL  = loadURL(pathKey: "fly6SourcePath",  bookmarkKey: "fly6SourceBookmark")
        musicURL       = loadURL(pathKey: "musicPath",       bookmarkKey: "musicBookmark")
        musicFolderURL = loadURL(pathKey: "musicFolderPath", bookmarkKey: "musicFolderBookmark")

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
        yoloBicycleConfidence    = (UserDefaults.standard.object(forKey: "yoloBicycleConfidence")    as? Double) ?? 0.10
        yoloPedestrianConfidence = (UserDefaults.standard.object(forKey: "yoloPedestrianConfidence") as? Double) ?? 0.25
        yoloVehicleConfidence    = (UserDefaults.standard.object(forKey: "yoloVehicleConfidence")    as? Double) ?? 0.50
        yoloEnableBicycle      = (UserDefaults.standard.object(forKey: "yoloEnableBicycle")      as? Bool)   ?? true
        yoloEnablePedestrian   = (UserDefaults.standard.object(forKey: "yoloEnablePedestrian")   as? Bool)   ?? true
        yoloWeightBicycle      = (UserDefaults.standard.object(forKey: "yoloWeightBicycle")      as? Double) ?? 1.0
        yoloEnableCar          = (UserDefaults.standard.object(forKey: "yoloEnableCar")          as? Bool)   ?? true
        yoloWeightCar          = (UserDefaults.standard.object(forKey: "yoloWeightCar")          as? Double) ?? 0.3
        yoloEnableMotorcycle   = (UserDefaults.standard.object(forKey: "yoloEnableMotorcycle")   as? Bool)   ?? true
        yoloWeightMotorcycle   = (UserDefaults.standard.object(forKey: "yoloWeightMotorcycle")   as? Double) ?? 0.6
        yoloEnableBus          = (UserDefaults.standard.object(forKey: "yoloEnableBus")          as? Bool)   ?? true
        yoloWeightBus          = (UserDefaults.standard.object(forKey: "yoloWeightBus")          as? Double) ?? 0.2
        yoloEnableTruck        = (UserDefaults.standard.object(forKey: "yoloEnableTruck")        as? Bool)   ?? true
        yoloWeightTruck        = (UserDefaults.standard.object(forKey: "yoloWeightTruck")        as? Double) ?? 0.2
        scoreWeightDetect     = (UserDefaults.standard.object(forKey: "scoreWeightDetect")     as? Double) ?? scoreWeightDetect
        scoreWeightScene      = (UserDefaults.standard.object(forKey: "scoreWeightScene")      as? Double) ?? scoreWeightScene
        scoreWeightSpeed      = (UserDefaults.standard.object(forKey: "scoreWeightSpeed")      as? Double) ?? scoreWeightSpeed
        scoreWeightGradient   = (UserDefaults.standard.object(forKey: "scoreWeightGradient")   as? Double) ?? scoreWeightGradient
        scoreWeightSegment    = (UserDefaults.standard.object(forKey: "scoreWeightSegment")    as? Double) ?? scoreWeightSegment
        scoreWeightDualCamera = (UserDefaults.standard.object(forKey: "scoreWeightDualCamera") as? Double) ?? scoreWeightDualCamera

        focusClimbGradientPct   = UserDefaults.standard.double(forKey: "focusClimbGradientPct").nonZero ?? focusClimbGradientPct
        let rawDescent = UserDefaults.standard.double(forKey: "focusDescentGradientPct")
        // rawDescent == 0 → never stored (first launch) — keep property default.
        // rawDescent > 0 → stored before descent became negative-convention → negate to migrate.
        focusDescentGradientPct = rawDescent == 0 ? focusDescentGradientPct : (rawDescent > 0 ? -rawDescent : rawDescent)
        let gmd = UserDefaults.standard.integer(forKey: "focusGroupMinDetections")
        focusGroupMinDetections = gmd > 0 ? gmd : 5
    }

    /// Writes every non-folder setting to UserDefaults. Call after changing settings.
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
        UserDefaults.standard.set(yoloBicycleConfidence,    forKey: "yoloBicycleConfidence")
        UserDefaults.standard.set(yoloPedestrianConfidence, forKey: "yoloPedestrianConfidence")
        UserDefaults.standard.set(yoloVehicleConfidence,   forKey: "yoloVehicleConfidence")
        UserDefaults.standard.set(yoloEnableBicycle,       forKey: "yoloEnableBicycle")
        UserDefaults.standard.set(yoloEnablePedestrian,    forKey: "yoloEnablePedestrian")
        UserDefaults.standard.set(yoloWeightPedestrian,    forKey: "yoloWeightPedestrian")
        UserDefaults.standard.set(yoloWeightBicycle,       forKey: "yoloWeightBicycle")
        UserDefaults.standard.set(yoloEnableCar,           forKey: "yoloEnableCar")
        UserDefaults.standard.set(yoloWeightCar,           forKey: "yoloWeightCar")
        UserDefaults.standard.set(yoloEnableMotorcycle,    forKey: "yoloEnableMotorcycle")
        UserDefaults.standard.set(yoloWeightMotorcycle,    forKey: "yoloWeightMotorcycle")
        UserDefaults.standard.set(yoloEnableBus,           forKey: "yoloEnableBus")
        UserDefaults.standard.set(yoloWeightBus,           forKey: "yoloWeightBus")
        UserDefaults.standard.set(yoloEnableTruck,         forKey: "yoloEnableTruck")
        UserDefaults.standard.set(yoloWeightTruck,         forKey: "yoloWeightTruck")
        UserDefaults.standard.set(scoreWeightDetect,        forKey: "scoreWeightDetect")
        UserDefaults.standard.set(scoreWeightScene,         forKey: "scoreWeightScene")
        UserDefaults.standard.set(scoreWeightSpeed,         forKey: "scoreWeightSpeed")
        UserDefaults.standard.set(scoreWeightGradient,      forKey: "scoreWeightGradient")
        UserDefaults.standard.set(scoreWeightSegment,       forKey: "scoreWeightSegment")
        UserDefaults.standard.set(scoreWeightDualCamera,    forKey: "scoreWeightDualCamera")
        UserDefaults.standard.set(hasFly12Sport,            forKey: "hasFly12Sport")
        UserDefaults.standard.set(hasFly6Pro,               forKey: "hasFly6Pro")
        UserDefaults.standard.set(focusClimbGradientPct,    forKey: "focusClimbGradientPct")
        UserDefaults.standard.set(focusDescentGradientPct,  forKey: "focusDescentGradientPct")
        UserDefaults.standard.set(focusGroupMinDetections,  forKey: "focusGroupMinDetections")
    }

    /// `true` when both cameras are in use.
    var isDualCamera: Bool { hasFly12Sport && hasFly6Pro }

    /// The sampling interval in seconds: the user's override if set, otherwise the default.
    var effectiveExtractInterval: Double {
        extractIntervalOverride ?? AppConfig.extractIntervalSeconds
    }

    // MARK: - URL bookmark helpers

    // Plain bookmarks on both platforms: the macOS app is unsandboxed, so .withSecurityScope isn't needed;
    // on iOS plain bookmarks plus startAccessingSecurityScopedResource() are enough.
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
        if let url = resolveBookmark(pathKey: pathKey, bookmarkKey: bookmarkKey) { return url }
        // Fall back to plain path for migration from older builds
        if let p = UserDefaults.standard.string(forKey: pathKey) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    /// Resolves a saved folder bookmark and, on iOS, opens access to it; refreshes a stale bookmark.
    /// - Returns: The folder, or `nil` when there is no bookmark or it can't be resolved (e.g. drive not connected).
    private func resolveBookmark(pathKey: String, bookmarkKey: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: Self.bookmarkResolutionOptions,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
#if os(iOS)
        // Security: access is limited to the folders the user picked; it is never released because the pipeline
        // reads from them for the whole session.
        _ = url.startAccessingSecurityScopedResource()
#endif
        if stale, let fresh = try? url.bookmarkData(options: Self.bookmarkCreationOptions,
                                                     includingResourceValuesForKeys: nil,
                                                     relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            UserDefaults.standard.set(url.path, forKey: pathKey)
        }
        return url
    }

    /// Re-opens access to the Input Videos and Projects folders and the camera folders.
    ///
    /// On iPad a bookmark only gives access if the drive was connected when it was resolved, and the app resolves
    /// them at launch. Calling this when the app comes to the front picks up a drive plugged in since then.
    /// A folder whose drive is still missing is left as it is.
    /// - Note: Main actor; reads UserDefaults and touches the file system.
    func restoreFolderAccess() {
        if let url = resolveBookmark(pathKey: "inputBaseDirPath", bookmarkKey: "inputBaseDirBookmark"),
           url != inputBaseDir { inputBaseDir = url }
        if let url = resolveBookmark(pathKey: "projectsRootPath", bookmarkKey: "projectsRootBookmark"),
           url != projectsRoot { projectsRoot = url }
        if let url = resolveBookmark(pathKey: "fly12SourcePath", bookmarkKey: "fly12SourceBookmark"),
           url != fly12SourceURL { fly12SourceURL = url }
        if let url = resolveBookmark(pathKey: "fly6SourcePath", bookmarkKey: "fly6SourceBookmark"),
           url != fly6SourceURL { fly6SourceURL = url }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
