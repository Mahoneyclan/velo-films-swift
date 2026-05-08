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
| **Finish** | Concat | Final `{project name}.mp4` with xfade crossfades between segments |

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
  ML/                     YOLOInference (CoreML direct inference + Swift NMS, batch processing)
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

**Strava import** downloads the GPX (built from streams for reliability), plus segment efforts and laps in a single API call:
- `working/ride.gpx` — trackpoints with speed, elevation, HR, cadence
- `working/segments.json` — segment effort names, start times, durations, grades
- `working/laps.json` — lap names, start times, durations (feeds the Lap timeline in clip selection)

## Settings

**Camera Calibration**

| Setting | Default | Description |
|---------|---------|-------------|
| Fly12 Sport (front) | ✓ | Enable/disable front camera |
| Fly6 Pro (rear) | ✓ | Enable/disable rear camera |
| Fly12Sport offset (s) | 0 | Additional time offset correction |
| Fly12Sport timezone | — | e.g. `UTC+10` |
| Fly6Pro offset (s) | 0 | Additional time offset correction |
| Fly6Pro timezone | — | e.g. `UTC+10` |
| GPX time offset (s) | 0 | Shift GPX track relative to video timestamps |

**Output**

| Setting | Default | Description |
|---------|---------|-------------|
| Highlight duration (min) | 5 | Target length for the finished reel |
| Min gap between clips (s) | 10 | Prevents back-to-back clips from the same moment |
| Show elevation strip | ✓ | Render elevation profile bar at bottom of frame |
| Dynamic gauges (ProRes) | ✗ | Render gauges as a separate alpha layer |
| Music volume (0–1) | 0.7 | Background music level |
| Raw audio volume (0–1) | 0.3 | Original camera audio level |

**Detection & Scoring** *(new)*

| Setting | Default | Description |
|---------|---------|-------------|
| YOLO min confidence | 0.10 | Detections below this threshold are discarded |
| Candidate pool (×target) | 2.5× | How many candidates the AI evaluates before selecting |
| Score weights | see Scoring table | All seven dimensions adjustable via sliders; live proportion bar |

**Focus Mode Defaults** *(new)*

| Setting | Default | Description |
|---------|---------|-------------|
| First N minutes | 20 min | Threshold for the "First Nm" filter chip |
| Last N minutes | 20 min | Threshold for the "Last Nm" filter chip |
| Climb steepness | ≥5% | Minimum gradient to show in Climbs filter |
| Descent steepness | ≥7% | Minimum magnitude to show in Descents filter |
| Group min riders | 5 | Minimum person+bicycle detections for Group filter |

## Focus Mode (Manual Clip Selection)

After the AI selects clips, the manual selection screen lets you filter the visible list. Focus mode is view-only — it never alters AI scores, the underlying `select.jsonl`, or the build pipeline.

**Terrain / time chips** (always visible):

| Filter | What it shows | Configurable in |
|--------|--------------|-----------------|
| All Clips | Every AI-recommended candidate | — |
| First N minutes | Clips from the opening N minutes of the ride | Settings → Focus Mode Defaults |
| Last N minutes | Clips from the closing N minutes | Settings → Focus Mode Defaults |
| Climbs ≥X% | Clips where `gradient_pct ≥ X` | Settings → Focus Mode Defaults |
| Descents ≥X% | Clips where `gradient_pct ≤ −X` | Settings → Focus Mode Defaults |
| Group N+ | Clips with N+ person/bicycle detections | Settings → Focus Mode Defaults |

**Lap timeline** (shown when Strava data is present):

A proportional timeline shows one block per Strava lap, sized and positioned relative to its duration within the ride. Only laps that contain at least one AI-selected clip are shown.

- Tap a lap block to filter clips to that lap
- Tapping the active block returns to All Clips
- Block labels appear when the block is wide enough; `.help()` tooltip shows the full name on hover

**Behaviour:**
- Only one focus filter is active at a time. The YOLO class filter (cyclist / car / person chips) can be active simultaneously — focus filter runs first, class filter chains after.
- If no clips match, a contextual empty state explains why.
- Lap timeline appears only when `laps.json` has been downloaded via Strava import.

**Timezone correction:** Strava lap/segment `start_date` is true UTC; `abs_time_epoch` in the pipeline is local-time-as-UTC (Cycliq wrong-Z). The app derives the offset automatically — `round((rideStart − earliestStravaEpoch) / 3600) × 3600` — so lap/segment epochs align with video epochs regardless of timezone.

## Scoring

Each candidate clip is scored on seven dimensions. **All weights are user-configurable** in **Settings → Detection & Scoring**.

| Dimension | Default weight |
|-----------|---------------|
| YOLO detections (people, vehicles, cyclists) | 0.30 |
| Speed (normalised to 60 km/h) | 0.20 |
| Gradient magnitude | 0.20 |
| Dual-camera bonus | 0.10 |
| Scene change / interesting moment | 0.10 |
| Bounding box area | 0.05 |
| Strava segment bonus | 0.05 |

The Settings screen shows a live proportion bar and a sum badge (green when weights total ~1.0, red otherwise) and a Reset button. YOLO minimum confidence and candidate pool fraction are also adjustable.

## Requirements

- Xcode 26.4+
- macOS 26+ (FFmpeg pipeline); iPadOS 26+ (AVFoundation pipeline — full functionality)
- FFmpeg installed via Homebrew (`brew install ffmpeg`) for the macOS target only
- Strava or Garmin account for GPX import (or drop a `.gpx` file directly into the project folder)
- External drive formatted exFAT or APFS (NTFS is read-only on Apple platforms — pipeline writes will fail)

## Repo location

`/Volumes/GDrive/Github/velo-films-swift`

## Immediate priorities (May 2026)

1. **Device deploy** — direct device build to iPad Air M2 via Xcode
2. **Real-footage QA** — run full pipeline on a real ride; visual QA of gauges, minimap, PiP composite, splash cards
3. **Share/Export** — add `ShareLink` + Photos save after concat; stretch goal: Strava video upload
4. **BGProcessingTask** — wire iOS background task so app can be left running during long renders
5. **Concurrent clip rendering** — `TaskGroup` in `BuildStep` (cap 3 on iPad for thermal management)
6. **App Store decision** — Option A (AVFoundation on macOS too, App Store on both) vs Option B (FFmpeg on Mac, direct distribution)

## YOLO model

`VeloYOLO.mlpackage` in `Shared/ML/` is a YOLO11s model trained on COCO, exported with `nms=False` and `int8=True`. The Swift inference engine (`YOLOInference.swift`) bypasses the Vision framework and decodes the raw `[1, 84, 8400]` output tensor directly, applying per-class NMS in Swift. Re-exporting with `nms=True` is blocked by a coremltools 9.0 bug with the YOLO11 attention op; the current approach is equivalent and faster.

To regenerate the model (e.g. for a different YOLO variant):

```
cd velo-films-swift
python Scripts/export_coreml.py
```

## Known bugs / deferred

- Intermittent xfade "inputs too short" error in intro builder (macOS FFmpeg path)
- Route overview map in splash — currently a black placeholder frame
- `ClipPreviewView` (inline `VideoPlayer` tap preview) — deferred
- `CameraCalibrationView` (frame preview + offset sliders) — deferred
- Metal `flock` warning on first launch — `libCoreFSCache.dylib` lock contention on the Metal shader cache; benign, no functional impact

## License

Private / all rights reserved.
