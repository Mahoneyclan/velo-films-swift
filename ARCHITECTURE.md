# Architecture

How Velo Films is put together: the layers, the seven-step pipeline, where data lives, and how the Mac and iPad
builds differ. For security and privacy see [SECURITY.md](SECURITY.md); for setup and use see [README.md](README.md).

## At a glance

- **One SwiftUI codebase, two builds.** The iPad/iPhone build is the paid App Store product (requirements: `docs/APP_STORE.md`). The Mac build is the owner's
  personal tool, rendering with Homebrew FFmpeg and running without the App Sandbox. Platform-specific code sits
  behind `#if os(macOS)` / `#if os(iOS)`.
- **No server and no database.** Each ride is a project folder on an external drive, holding JSON Lines files
  that the pipeline steps pass from one to the next. Settings live in UserDefaults; Strava sign-in tokens live in
  the Keychain.
- **Third-party services:** Strava (ride data, user-initiated) and Apple Maps (map tiles for the overlays). Object
  detection runs on the device with Core ML.

## Folder layout

All app source is in `VeloFilms/VeloFilms/` (Xcode picks up new files there automatically).

| Folder | Contents |
|---|---|
| `Shared/App/` | App entry point (`VeloFilmsApp`), `PrivacyInfo.xcprivacy` |
| `Shared/Core/Config/` | `GlobalSettings` (app settings), `ProjectPreferences` (per-ride settings) |
| `Shared/Core/Models/` | `AppConfig` (constants), `Project` and `ProjectStore`, row models for each JSONL file, `FocusFilter` |
| `Shared/Core/Pipeline/` | `PipelineStep` protocol and `StepName`, `PipelineExecutor`, `ProgressReporter` |
| `Shared/Core/FileManager/` | JSONL reader/writer, project folder helpers |
| `Shared/Core/Security/` | `KeychainStore` |
| `Shared/Core/Media/` | `MusicLibrary` (built-in tracks, music folder, added songs) and `MusicFolder` (the user's chosen cloud/local folder, downloaded at build time) |
| `Shared/Integrations/Strava/` | `StravaAuth` (sign-in, tokens), `StravaClient` (API calls), `Secrets.swift` (gitignored) |
| `Shared/Steps/` | One folder per pipeline step, plus the renderers used by Build and Splash |
| `Shared/Video/` | `FFmpegBridge` (macOS), `VideoEncoder` and `ClipVideoCompositor` (AVFoundation) |
| `Shared/ML/` | `YOLOInference` and the `VeloYOLO.mlpackage` model |
| `Shared/Resources/` | Logo, intro/outro music, royalty-free backing-music tracks. The audio files ship in every build (Mac, iPhone, iPad); remove them before any public App Store release |
| `Shared/Views/` | SwiftUI screens, grouped by area (Main, Import, Selection, Settings, Pipeline) |
| `iPadOS/` | iPad-only folder picker wrapper |

Outside the app: `Scripts/export_coreml.py` (build-time model export), `VeloFilms/VeloFilmsTests/` (unit tests,
see Testing), `docs/` (screenshots, review scorecards and progress).

## Layers

```
Views (SwiftUI)  ──>  PipelineExecutor  ──>  Steps (Flatten … Concat)  ──>  Renderers / Video / ML
      │                                            │
      └──> ProjectStore, GlobalSettings  <─────────┘──> JSONL files in the project folder
      └──> StravaAuth / StravaClient ──> Strava API
```

- **Views** show state and start actions. `ProjectDetailView` is the main screen; it owns a `PipelineExecutor` and
  registers the seven step implementations.
- **PipelineExecutor** runs a step and any prerequisite whose output file is missing, publishes progress, and
  appends failures to `pipeline.log` in the project folder.
- **Steps** read the previous step's file and write their own. Each conforms to `PipelineStep`.
- **Settings** are read through `AppConfig` (fixed constants plus pass-throughs to `GlobalSettings`).

## The pipeline

| # | Step | Reads | Writes | What happens |
|---|---|---|---|---|
| 1 | Flatten | first `.gpx` in `working/`, else in the clip folder, else in the project folder | `flatten.jsonl` | Parse GPX, remove elevation changes recorded while stationary (bad data, e.g. altimeter recalibrating at a stop), resample to 1 point per second, compute speed and gradient. Steep hills are never smoothed |
| 2 | Extract | flatten, source clips | `extract.jsonl` | Build a sampling grid (default every 5 s) over the ride and match each grid point to the clip covering it, using each clip's corrected recording time. No frames are read yet |
| 3 | Enrich | extract, flatten, `segments.json` | `enriched.jsonl`, `frames/*.jpg` | Grab a frame per row; YOLO detection, scene change, GPS telemetry, Strava segment score, composite score |
| 4 | Select | enriched, existing select | `select.jsonl` | Pair front/rear rows by time; ignore stopped moments; best moment from every stretch of riding (one stretch per 3 clips), then best-first, with a gap that scales with the ride (min 30 s); always one moment from the first and last 5 minutes; keep manual overrides |
| 5 | Build | select, flatten | `clips/clip_NNNN.mp4`, overlay PNGs | Render map, elevation and gauge overlays and composite each clip (with picture-in-picture when both cameras filmed it) |
| 6 | Splash | select, flatten, frames | `clips/_intro.mp4`, `_outro.mp4` | Intro (logo, map with stats, collage) and outro (collage, title, fade to black) |
| 7 | Concat | clips, intro, outro | `{project name}.mp4` | Crossfade the clips over sequenced backing music (fading out over the last 3 s), then join intro + middle + outro |

Running a later step runs any earlier step whose output is missing. The step you ask for always runs.
Only one run happens at a time, so GPX import and analysis Re-run are disabled while a step is running. Re-importing the GPX
or pressing Re-run deletes all four analysis outputs, so the next analysis starts again from the GPX.
The **Fine Tune** screen edits `select.jsonl` between Select and Build. On the Mac it opens in its own resizable
window (`FineTuneWindow`, a `WindowGroup` keyed by project id; a sheet can't grow taller than its parent window); on
iPad and iPhone it covers the full screen (an iPad sheet is a smaller card that cut off the film strip). `FineTuneView`
lays it out (side panel when at least 760 × 560 pt, so iPad and Mac; otherwise a scrolling stack, so iPhone, with the
frames first in phone landscape; in the side-panel layout the frames shrink so the film strip always fits);
the open moment shows its front and rear frames together (side by side, stacked on iPhone and iPad portrait) and tapping a frame puts
that camera's clip in the reel. The film strip has a front row above a rear row on iPad and Mac (one row on iPhone). `FineTuneModel` holds the rules (in/out of the reel, camera per clip,
filters, reset, save) with no view code; `FineTuneData` reads the picks, laps and elevation; `MomentReasons` writes
the "Why this moment" lines; `RideTimelineView`, `MomentDetailView`, `FilmStripView` and `FrameImage` are the parts.
A moment is in the reel when one camera row has `recommended`; every manual change sets `manualOverride` on all of
the moment's rows so re-running Select keeps it. When Fine Tune closes, `ReviewCompletion` marks the ride reviewed
(unlocking Build) and deletes a built reel whose clips no longer match the selection.

### Scoring

`ScoreCalculator.composite` is a weighted sum of detection, scene change, speed (capped at 60 km/h), gradient
(capped at 8%, counted only when moving) and Strava segment score (PRs full, 2nd/3rd best 70%, other efforts nothing). The weights are user settings and are not
normalised. A moment filmed by both cameras gets an extra dual-camera bonus during selection (`PartnerMatcher`).

### Clocks and time zones

- Cycliq cameras store local time labelled as UTC. `FrameSampler.applyCycliqUTCFix` subtracts the camera's time
  zone offset (Settings → Time Sync) unless "camera stores local time" is turned off.
- Each clip's start = file creation time − clip duration − manual offset.
- Strava segment and lap times are true UTC. `SegmentMatcher.stravaOffset` estimates a whole-hour offset to line
  them up with the camera clock; Enrich (segment score), Select (segment name, PR flag) and the Fine Tune screen all apply it.
- The GPX time offset setting shifts the whole track.

## Data storage

| What | Where | Notes |
|---|---|---|
| Project folder | `{projectsRoot}/{name}/` on an external drive | `working/` (GPX, JSONL, Strava files), `frames/`, `minimaps/`, `elevation/`, `splash_assets/`, `clips/`, `preferences.json`, `pipeline.log`, final reel |
| Raw clips | `{inputBaseDir}/{name}/` or a folder chosen at project creation | Read only by the pipeline; written by Copy from Camera. The JSONL `video_path` is a full path from the device that ran Extract, so videos are opened by file name inside this device's folder (`Project.videoURL(forStoredPath:)`); the same drive can move between Mac and iPad. Build checks every reel video is reachable before it deletes or renders anything |
| Project list | UserDefaults `projectStoreV1` (name, id, paths) | Projects made earlier are added back with **+ → Open existing project** (a folder with `working/`); projects whose drive isn't connected stay listed as "Drive not connected" |
| App settings | UserDefaults (keys in `GlobalSettings`) | Key names are permanent |
| Music folder | Wherever the user chose (iCloud Drive, Dropbox…); security-scoped bookmark `musicFolderBookmark` | Read in place; tracks used by a reel are copied to a temporary cache first |
| Added songs ("My Music" in code) | Mac: `~/Music/Velo Films/`; iPhone/iPad: the app's Application Support `Music/` | Listed by `MusicLibrary`; tracks are matched by file name |
| Strava tokens | Keychain, service `mahoneyclan.VeloFilms` | See SECURITY.md |
| Strava app key | `Secrets.swift` (gitignored), compiled in | Extractable from the app; accepted risk |

JSONL key names match the original Python app's files and are permanent.

## Platform differences

| | macOS (personal build) | iPadOS / iOS (App Store) |
|---|---|---|
| Clip render | FFmpeg `filter_complex` + `loudnorm` (`ClipCompositor`) | AVFoundation + `ClipVideoCompositor` (Metal-backed Core Image), no loudness normalisation |
| Concat | FFmpeg `xfade`/`acrossfade` | AVFoundation opacity and volume ramps |
| Intro/outro | AVFoundation (`VideoEncoder`) | Same |
| Folder access | Unsandboxed file access | Security-scoped folder picker (`FilePickerBridge`) |
| Keychain | Login keychain | Data-protection keychain, this device only |

## Concurrency

The project builds in Swift 5 mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so types are main-actor
isolated unless marked otherwise. `PipelineExecutor` starts steps from a detached task, but the step types are
main-actor isolated too: their synchronous work runs on the main thread and only their `await`s release it.
`ProgressReporter` is an actor. `ClipVideoCompositor` is called by AVFoundation on background queues.

## Testing

`VeloFilmsTests` (unit tests hosted in the app, macOS and iOS; shared scheme `VeloFilms`) holds 81 tests:
clip selection (`ClipSelectorTests`), the Fine Tune rules and data (`FineTuneModelTests`, `FineTuneDataTests`,
`MomentReasonsTests`, `ReviewCompletionTests`, Swift Testing), opening existing projects (`OpenProjectTests`), finding camera videos on the other device (`VideoLocationTests`) and the moment filters (`FocusFilterTests`, XCTest). Run with
`xcodebuild test -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS'`. No test touches the network or the footage drives. Screens are hand-tested; the steps
for each change are recorded in `docs/review/PROGRESS.md`.

## Known issues

Bugs found during review (not yet fixed) are listed in the latest scorecard in `docs/scorecards/` and in
`docs/review/PROGRESS.md`.
