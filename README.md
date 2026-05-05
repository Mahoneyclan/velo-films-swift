# Velo Films

Turn your [Cycliq](https://cycliq.com) ride footage into a polished highlight reel, automatically scored and synced to your GPS route — on your Mac or iPad.

## What it does

Velo Films takes raw MP4 files from a Fly12 Sport (front) and/or Fly6 Pro (rear) camera, matches them against a GPX file downloaded from Strava or Garmin, scores every 5-second clip using speed, gradient, YOLO object detection, and scene-change metrics, then assembles the top-scoring clips into a single video complete with a minimap, speed/cadence gauges, elevation strip, and intro/outro splash screens.

**The portable workflow:** ride ends → plug Cycliq cameras into iPad via USB-C hub → Copy from Camera in VeloFilms → pipeline runs → share the highlight reel. No Mac required. A direct alternative to the Cycliq app, with automated highlight selection, dual-camera sync, and GPS overlays the Cycliq app does not offer.

## Platforms

- **macOS 26+** — full pipeline via system FFmpeg (`/opt/homebrew/bin/ffmpeg`); `Process()` spawn for filter_complex operations
- **iPadOS 26+** — full pipeline via AVFoundation: `ClipCompositor` uses `AVMutableComposition` + `ClipVideoCompositor` (Metal GPU CIImage compositing); build/concat steps use A/B track opacity crossfades with audio volume ramps; music mixing via `AVMutableComposition` dual audio tracks. No FFmpegKit dependency.

Both platforms share all pipeline logic; `#if os(macOS)` / `#else` blocks select the appropriate render backend. iPad is the primary portable product; Mac is retained for fast development and production runs.

## Pipeline

Each ride project goes through five phases:

| Phase | Steps | Output |
|-------|-------|--------|
| **Get GPX** | Flatten | `flatten.jsonl` — GPX trackpoints at 5 s intervals |
| **Analyse** | Extract → Enrich → Select | `extract.jsonl`, `enrich.jsonl`, `select.jsonl` |
| **Review** | Manual selection UI | User can add/remove clips before build |
| **Build** | Build → Splash | Per-clip composites with HUD overlays, intro/outro |
| **Finish** | Concat | Final `highlights.mp4` with xfade crossfades between segments |

Steps are dependency-aware — running "Build" from cold will automatically run all prerequisite steps.

## Project structure

```
Shared/
  App/                    App entry point, scene setup
  Core/
    Config/               GlobalSettings (user prefs), AppConfig (pipeline constants)
    FileManager/          JSONLReader/Writer, ProjectFileManager
    Models/               Project, AppConfig, row types (Flatten/Extract/Enrich/Select)
    Pipeline/             PipelineExecutor, PipelineStep protocol, ProgressReporter
  Integrations/
    Strava/               OAuth + activity list + GPX download
    Garmin/               OAuth + activity list + FIT→GPX conversion
  ML/                     YOLOInference (CoreML, batch processing)
  Steps/
    Flatten/              GPXParser → FlattenStep
    Extract/              FrameSampler + binary mvhd reader → ExtractStep
    Enrich/               GPSEnricher, SceneDetector, ScoreCalculator, SegmentMatcher
    Select/               ClipSelector, PartnerMatcher (dual-camera pairing) → SelectStep
    Build/                ClipCompositor, GaugeRenderer, ElevationRenderer, MinimapRenderer
    Splash/               IntroBuilder, OutroBuilder → SplashStep
    Concat/               ConcatStep (FFmpeg xfade crossfades between intro/middles/outro)
  Video/                  FFmpegBridge (shared protocol)
  Views/
    Main/                 ContentView, ProjectListView, ProjectDetailView
    Import/               CopyVideosView, StravaImportView, GarminImportView, ImportView
    Pipeline/             PipelineView (live progress log)
    Selection/            ManualSelectionView (thumbnail grid with toggle)
    Settings/             GlobalSettingsView, OnboardingView, ProjectPreferencesView
macOS/                    FFmpegMac (native binary wrapper)
iPadOS/                   FFmpegiOS, FilePickerBridge
```

## Camera quirks

Cycliq cameras record local time but tag it as UTC in the MP4 `mvhd` box (the "Cycliq UTC bug"). Velo Films corrects for this by reading the raw binary creation time and subtracting the camera's configured UTC offset. Set the correct timezone in **Settings → Camera Calibration** (e.g. `UTC+10`, `UTC+10:30`).

AVFoundation does not expose `mvhd.creation_time` for NOVATEK mp42 containers, so Velo Films reads it directly by scanning the last 4 MB of each file.

## First-time setup

On first launch, an onboarding wizard prompts for two folders:

- **Projects Root** — where each ride's working folder is created
- **Input Videos** — where clips are copied from the SD card (one subfolder per ride)

These can be changed later in **Settings → Drive Roots**.

## Importing footage

Open **+ → Copy from Camera** with the Cycliq SD card inserted. The importer:
- Detects which cameras are mounted
- Filters clips to the selected ride date
- Copies one card at a time, adding to the same destination folder on each run
- Renames files to `Fly12Sport_0001.MP4` / `Fly6Pro_0001.MP4` for unambiguous camera identification

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Fly12 Sport (front) | ✓ | Enable/disable front camera |
| Fly6 Pro (rear) | ✓ | Enable/disable rear camera |
| Fly12Sport offset (s) | 0 | Additional time offset correction |
| Fly12Sport timezone | — | e.g. `UTC+10` |
| Fly6Pro offset (s) | 0 | Additional time offset correction |
| Fly6Pro timezone | — | e.g. `UTC+10` |
| Highlight duration (min) | 5 | Target length for the finished reel |
| Min gap between clips (s) | 10 | Prevents back-to-back clips from the same moment |
| GPX time offset (s) | 0 | Shift GPX track relative to video timestamps |
| Show elevation strip | ✓ | Render elevation profile bar at bottom of frame |
| Dynamic gauges (ProRes) | ✗ | Render gauges as a separate alpha layer |
| Music volume (0–1) | 0.7 | Background music level |
| Raw audio volume (0–1) | 0.3 | Original camera audio level |

## Scoring

Each candidate clip is scored on five dimensions (weights sum to 1.0):

| Dimension | Weight |
|-----------|--------|
| YOLO detections (people, vehicles, cyclists) | 0.30 |
| Dual-camera bonus | 0.10 |
| Speed (normalised to 60 km/h) | 0.20 |
| Gradient magnitude | 0.20 |
| Scene change / interesting moment | 0.10 |
| Bounding box area | 0.05 |
| Strava segment bonus | 0.05 |

## Requirements

- Xcode 26.4+
- macOS 26+ (FFmpeg pipeline); iPadOS 26+ (AVFoundation pipeline — full functionality)
- FFmpeg installed via Homebrew (`brew install ffmpeg`) for the macOS target only
- Strava or Garmin account for GPX import (or drop a `.gpx` file directly into the project folder)
- External drive formatted exFAT or APFS (NTFS is read-only on Apple platforms — pipeline writes will fail)

## Repo location

`/Volumes/GDrive/Github/velo-films-swift`

## Immediate priorities (May 2026)

1. **Clean simulator build** — confirm all iOS 26 build errors resolved (StravaAuth UIWindow deprecation, AVMutableVideoComposition API, entitlement conditionals, NS*UsageDescription strings)
2. **Device deploy** — direct device build to iPad Air M2 via Xcode
3. **Real-footage QA** — run full pipeline on a real ride; visual QA of gauges, minimap, PiP composite, splash cards
4. **Share/Export** — add `ShareLink` + Photos save after concat; stretch goal: Strava video upload
5. **BGProcessingTask** — wire iOS background task so app can be left running during long renders
6. **Concurrent clip rendering** — `TaskGroup` in `BuildStep` (cap 3 on iPad for thermal management)
7. **App Store decision** — Option A (AVFoundation on macOS too, App Store on both) vs Option B (FFmpeg on Mac, direct distribution)

## Known bugs / deferred

- Intermittent xfade "inputs too short" error in intro builder (macOS FFmpeg path)
- Route overview map in splash — currently a black placeholder frame
- `ClipPreviewView` (inline `VideoPlayer` tap preview) — deferred
- `CameraCalibrationView` (frame preview + offset sliders) — deferred

## License

Private / all rights reserved.
