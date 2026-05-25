# Velo Films

Turn your [Cycliq](https://cycliq.com) ride footage into a polished highlight reel, automatically scored and synced to your GPS route — on your Mac or iPad.

## What it does

Velo Films takes raw MP4 files from a Fly12 Sport (front) and/or Fly6 Pro (rear) camera, matches them against a GPX file downloaded from Strava or Garmin, scores every 5-second clip using speed, gradient, YOLO object detection, and scene-change metrics, then assembles the top-scoring clips into a single video complete with a minimap, speed/cadence gauges, elevation strip, and intro/outro splash screens.

**The portable workflow:** ride ends → plug Cycliq cameras into iPad via USB-C hub → Copy from Camera in VeloFilms → pipeline runs → share the highlight reel. No Mac required. A direct alternative to the Cycliq app, with automated highlight selection, dual-camera sync, and GPS overlays the Cycliq app does not offer.

## Platforms

- **macOS 26+** — full pipeline via system FFmpeg (`/opt/homebrew/bin/ffmpeg`); `Process()` spawn for filter_complex operations
- **iPadOS 26+** — full pipeline via AVFoundation: `ClipCompositor` uses `AVMutableComposition` + `ClipVideoCompositor` (Metal GPU CIImage compositing) exported via `VideoEncoder.exportInProcess()` (in-process `AVAssetReader` + `AVAssetWriter` — bypasses `mediaserverd` sandbox restrictions on external-drive security-scoped URLs); build/concat steps use A/B track opacity crossfades with audio volume ramps; music mixing via `AVMutableComposition` dual audio tracks. No FFmpegKit dependency.

Both platforms share all pipeline logic; `#if os(macOS)` / `#else` blocks select the appropriate render backend. iPad is the primary portable product; Mac is retained for fast development and production runs.

## Pipeline

Each ride project goes through five phases:

| Phase | Steps | Output |
|-------|-------|--------|
| **Get GPX** | Flatten | `flatten.jsonl` — GPX trackpoints at 5 s intervals |
| **Analyse** | Extract → Enrich → Select | `extract.jsonl`, `enrich.jsonl`, `select.jsonl` |
| **Review** | Manual selection UI | User can add/remove clips before build |
| **Build** | Build → Splash | Per-clip composites with HUD overlays, intro/outro |
| **Finish** | Concat | `_middle.mp4` (clips + backing music), then `_intro + _middle + _outro` → `{project name}.mp4` |

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
    Concat/               ConcatStep (phase 1: clips+music→_middle; phase 2: intro+middle+outro→final)
  Video/                  FFmpegBridge (shared protocol)
  Views/
    Main/                 ContentView, ProjectListView, ProjectDetailView
    Import/               CopyVideosView, StravaImportView, GarminImportView, ImportView
    Pipeline/             PipelineView (live progress log)
    Selection/            ManualSelectionView (thumbnail grid with toggle + focus filters)
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

**Strava import** downloads the GPX (built from streams for reliability), plus segment efforts, laps, and activity description in a single API call:
- `working/ride.gpx` — trackpoints with speed, elevation, HR, cadence
- `working/segments.json` — segment effort names, start times, durations, grades
- `working/laps.json` — lap names, start times, durations (feeds the Lap timeline in clip selection)
- `working/description.txt` — activity description; third-party tool sections (`-- From Wandrer`, `-- myWindsock Report --`) are stripped; remaining lines overlaid on the intro map card

## Settings

**Time Sync** (cameras + GPS alignment)

| Setting | Default | Description |
|---------|---------|-------------|
| Fly12 Sport (front) | ✓ | Enable/disable front camera |
| Fly6 Pro (rear) | ✓ | Enable/disable rear camera |
| Fly12Sport offset (s) | 0 | Additional time offset correction |
| Fly12Sport timezone | — | e.g. `UTC+10` |
| Fly6Pro offset (s) | 0 | Additional time offset correction |
| Fly6Pro timezone | — | e.g. `UTC+10` |
| GPX time offset (s) | 0 | Shift GPX track forward/backward relative to video timestamps |

**Output**

| Setting | Default | Description |
|---------|---------|-------------|
| Highlight duration (min) | 5 | Target length for the finished reel |
| Min gap between clips (s) | 10 | Prevents back-to-back clips from the same moment |
| Opening zone | 15% | Fraction of *moving* time classed as the opening; long stops don't distort the boundary |
| Closing zone | 15% | Fraction of *moving* time classed as the closing; long stops don't distort the boundary |
| Show elevation strip | ✓ | Render elevation profile bar at bottom of frame |
| Dynamic gauges (ProRes) | ✗ | Render gauges as a separate alpha layer |
| Music volume (0–1) | 0.7 | Background music level |
| Raw audio volume (0–1) | 0.3 | Original camera audio level |

**AI Scoring**

Each GroupBox in the AI Scoring tab carries a "Re-run: Enrich" or "Re-run: Select" tag indicating which pipeline step must re-run for the change to take effect.

*YOLO Class Filters* — requires **Enrich**

| Setting | Default | Description |
|---------|---------|-------------|
| Cyclist (enable + weight) | ✓ 100% | Person + bicycle detected together |
| Pedestrian (enable + weight) | ✓ 30% | Person detected without a bicycle in the same frame |
| Car (enable + weight) | ✓ 30% | |
| Motorcycle (enable + weight) | ✓ 60% | |
| Bus (enable + weight) | ✓ 20% | |
| Truck (enable + weight) | ✓ 20% | |

*Detection Confidence* — requires **Enrich**

| Setting | Default | Description |
|---------|---------|-------------|
| Cyclists | 0.10 | Minimum YOLO confidence for cyclist (person + bicycle) detections |
| Pedestrians | 0.25 | Minimum YOLO confidence for person (no bicycle) |
| Vehicles | 0.50 | Minimum YOLO confidence for car/motorcycle/bus/truck |

*Candidate Pool* — requires **Select**

| Setting | Default | Description |
|---------|---------|-------------|
| Pool size | 2.5× | How many candidates the AI evaluates before selecting the final clips |

*Score Weights* (collapsed by default) — requires **Select**

| Dimension | Default | Description |
|-----------|---------|-------------|
| YOLO detections | 35% | Cyclist/pedestrian/vehicle detection score |
| Speed | 20% | Normalised to 60 km/h |
| Gradient | 20% | Normalised to 8% |
| Dual-camera bonus | 10% | Both cameras captured this moment |
| Scene change | 10% | Visually interesting transitions |
| Strava segment | 5% | Bonus during a segment effort; higher for PRs |

Weights should sum to 100% — a live proportion bar and sum badge (green/red) are shown when the section is expanded.

**Focus Mode Defaults**

| Setting | Default | Description |
|---------|---------|-------------|
| Climb steepness | ≥4% | Minimum gradient to show in Climbs filter |
| Descent steepness | ≥4% | Minimum magnitude to show in Descents filter |
| Group min riders | 5 | Minimum riders for Group filter — counted as max(persons, bicycles) per camera to avoid double-counting cyclists |

## Focus Mode (Manual Clip Selection)

After the AI selects clips, the manual selection screen lets you filter the visible list. A first-open banner explains the basics (dismissed permanently). Focus mode is view-only — it never alters AI scores, the underlying `select.jsonl`, or the build pipeline.

**Filter chips:**

| Filter | What it shows |
|--------|--------------|
| All Clips | Every clip in the candidate pool |
| Opening | Clips within the opening zone |
| Closing | Clips within the closing zone |
| Climbs ≥X% | gradient_pct ≥ X |
| Descents ≥X% | gradient_pct ≤ −X |
| Group N+ | N+ person/bicycle detections (max across cameras) |
| Strava PRs | Clips during a segment effort ranked PR (#1) |
| Segment ▾ | Dropdown — clips during a specific Strava segment effort (only segments with clips in the candidate pool are listed) |

**Lap timeline** — proportional timeline of Strava laps. Tap a block to filter to that lap.

**YOLO class filter bar** — chips for each detected class (Cyclist, Pedestrian, Car, Truck, Bus, Motorcycle). "Cyclist" shows clips where person + bicycle were detected together; "Pedestrian" shows clips where person was detected *without* a bicycle in the same frame.

**Behaviour:**
- Focus filter and class filter can be active simultaneously — focus runs first, class filter chains after.
- Segment filter stacks independently on top of both.
- Only segments whose clips are in the candidate pool appear in the dropdown (prevents empty results).
- Timezone correction applied automatically: Strava lap/segment epochs (true UTC) are offset to align with abs_time_epoch (Cycliq local-as-UTC).

## Scoring

Each candidate clip is scored on six dimensions. Weights are user-configurable in **Settings → AI Scoring → Score Weights**.

| Dimension | Default weight |
|-----------|---------------|
| YOLO detections | 35% |
| Speed (normalised to 60 km/h) | 20% |
| Gradient magnitude (normalised to 8%) | 20% |
| Dual-camera bonus | 10% |
| Scene change / interesting moment | 10% |
| Strava segment bonus | 5% |

**Cyclist vs. pedestrian scoring:** person detections are weighted at full cyclist weight (100% by default) when a bicycle is also detected in the frame (cyclist context). When person is detected without a bicycle (pedestrian context), a separate lower weight (30% by default) is applied. This prevents pedestrians at intersections from inflating scores.

## Requirements

- Xcode 26.4+
- macOS 26+ (FFmpeg pipeline); iPadOS 26+ (AVFoundation pipeline — full functionality)
- FFmpeg installed via Homebrew (`brew install ffmpeg`) for the macOS target only
- Strava or Garmin account for GPX import (or drop a `.gpx` file directly into the project folder)
- External drive formatted exFAT or APFS (NTFS is read-only on Apple platforms — pipeline writes will fail)

## Repo location

`/Volumes/GDrive/Github/velo-films-swift`

## Immediate priorities (May 2026)

1. **iOS device build** — direct device build to iPad Air M2 via Xcode; QA full pipeline on device
2. **Real-footage QA** — run full pipeline on a real ride; visual QA of new HUD layout, PiP composite, splash cards
3. **Share/Export** — add `ShareLink` + Photos save after concat; stretch goal: Strava video upload
4. **BGProcessingTask** — wire iOS background task so app can be left running during long renders
5. **Concurrent clip rendering** — `TaskGroup` in `BuildStep` (cap 3 on iPad for thermal management)
6. **App Store decision** — Option A (AVFoundation on macOS too, App Store on both) vs Option B (FFmpeg on Mac, direct distribution)

## Pipeline architecture notes

**Gradient smoothing:** `GPXParser` computes `gradient_pct` using a ±15 s centered window (30 s total) rather than adjacent 1-second points. GPS vertical accuracy is ±5–15 m; a 1-second window over 5 m of travel amplifies that to ±100%+ false gradient on flat terrain. The 30-second window reduces noise to < 3% on flat roads while still resolving real climbs and descents.

**Two-pass Concat:** `ConcatStep` runs in two phases:
1. `clip_NNNN.mp4` files are joined with xfade crossfades and backing music mixed in → `_middle.mp4`. Music is looped by adding N explicit `-i music.path` copies + `concat` audio filter + `atrim` (macOS), or `AVMutableCompositionTrack` segment copy loop (iOS). rawAudioVolume and musicVolume are applied here.
2. `_intro + _middle + _outro` are joined with xfade crossfades, audio passthrough only — each segment already carries its own music.

**HUD layout (1920×1080):**
```
x=0     x=390  x=398          x=1362  x=1370       x=1920
┌───────┬───────────────────────┬────────────────────┐  y=615
│  Map  │  5 Gauges  972×194   │  PiP (dual cam)    │  390px
│390×390│  (bottom-aligned)    │  scaled to 465px   │
├───────┤                       │  (map+elev height) │  y=1005
│ Elev  │  open video           │                    │  75px
│390×75 │  (x=398 to x=1370)   │                    │
└───────┴───────────────────────┴────────────────────┘  y=1080
```
Single-camera mode uses the same layout without PiP. The pipeline infers single/dual from files present — no extra configuration needed beyond the camera toggles in Settings.

**Intro map card overlay:** If `working/description.txt` exists, its content is overlaid as left-side text on the intro map splash card. Lines starting with `--` are stripped; all other lines are shown.

**Audio ownership per segment:**
- `_intro.mp4` — `intro.mp3` baked in by `IntroBuilder`
- `_middle.mp4` — raw clip audio + looped backing music mixed by `ConcatStep`
- `_outro.mp4` — `outro.mp3` baked in by `OutroBuilder`

## YOLO model

`VeloYOLO.mlpackage` in `Shared/ML/` is a YOLO11s model trained on COCO, exported with `nms=False` and `int8=True`. The Swift inference engine (`YOLOInference.swift`) bypasses the Vision framework and decodes the raw `[1, 84, 8400]` output tensor directly, applying per-class NMS in Swift. Three confidence thresholds are applied at decode time: bicycle, pedestrian, vehicle.

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
