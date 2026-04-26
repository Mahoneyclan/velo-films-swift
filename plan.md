# Velo Films — Swift Multiplatform Rewrite Plan

Multiplatform SwiftUI app targeting macOS 14+ and iPadOS 26+, replacing the existing Python/PySide6 pipeline.
Single codebase, two targets. Raw videos live on external drive, accessed via security-scoped bookmarks on iPad.

Hardware: iPad Air 11-inch M2 (8GB RAM), iPadOS 26.4. Mac Mini M1.

---

## Apps / Tools Needed on Mac Mini

### Required

| Tool | Source | Cost | Purpose |
|---|---|---|---|
| Xcode 26.4.1 (17E202) | Mac App Store | Free | IDE, Swift compiler, Simulator, Instruments |
| Apple Developer Program | developer.apple.com | $99/yr | Deploy to physical iPad, TestFlight |
| FFmpegKit | Swift Package (in-project) | Free | iOS video processing — fetched automatically |
| Git | Already installed | Free | Source control |
| Claude Code | Already installed | — | Primary development tool |

### Required for Model Export (one-time, ~30 min)

| Tool | Source | Purpose |
|---|---|---|
| coremltools | `pip install coremltools` | Convert `yolo11s.pt` → Core ML package |
| Existing Python venv | Already installed | Run the export script |

### Strongly Recommended

| Tool | Source | Cost | Purpose |
|---|---|---|---|
| SF Symbols 6 | Apple (free download) | Free | Browse 6,000+ icons for SwiftUI |
| Proxyman | proxyman.io | Free tier | Debug Strava/Garmin OAuth flows |
| TestFlight (on iPad) | App Store | Free | Install dev builds wirelessly |

### Optional

| Tool | Purpose |
|---|---|
| Instruments (bundled with Xcode) | Memory and CPU profiling during video pipeline |
| RocketSim (~$40/yr) | Enhanced Simulator — location simulation, better recording |

---

## Hardware Notes (iPad Air M2)

- **8GB RAM** — half the recommended 16GB. YOLO batch size capped at 2–4. Process frames sequentially, never buffer a full ride in memory. Render clips one at a time.
- **16-core Neural Engine** — Core ML YOLO inference will be fast, likely faster than CPU-bound PyTorch on Mac.
- **USB-C USB 3 (10Gb/s)** — external drive access is viable. Raw videos stay on the drive exactly as they do today.
- **VideoToolbox** — H.264 encoding fully supported. H.265 multi-pass not available on iPadOS; output uses H.264 at 8M bitrate (visually identical, slightly larger files).
- **iPadOS 26** — improved background task budgets for video workloads. Target iPadOS 26 as minimum — this is a personal app, no reason to support older versions.

## External Drive Access

On iPadOS, drive access uses security-scoped bookmarks:
1. First launch: user picks drive root once via Files picker
2. App saves bookmark to UserDefaults — survives app restarts
3. Every subsequent launch: bookmark resolves silently, no user action needed
4. `INPUT_BASE_DIR` and `PROJECTS_ROOT` from `config.py` become two persisted bookmark URLs

Drive must be connected to run the pipeline — same as the current Mac workflow.

**Note:** Drive must be formatted exFAT or APFS. NTFS is read-only on Apple platforms — pipeline writes would fail.

---

## Repo Structure

```
velo-films-swift/
├── VeloFilms.xcodeproj
├── Shared/                              # All code shared between Mac + iPad
│   ├── App/
│   │   └── VeloFilmsApp.swift
│   ├── Core/
│   │   ├── Models/                      # Codable structs (replaces Python dataclasses)
│   │   │   ├── Project.swift            # Ride project + paths
│   │   │   ├── AppConfig.swift          # Replaces config.py
│   │   │   ├── FlattenRow.swift         # flatten.csv row
│   │   │   ├── ExtractRow.swift
│   │   │   ├── EnrichRow.swift
│   │   │   └── SelectRow.swift
│   │   ├── Pipeline/
│   │   │   ├── PipelineExecutor.swift   # Replaces pipeline_executor.py
│   │   │   ├── PipelineStep.swift       # Protocol (replaces step_registry.py)
│   │   │   └── ProgressReporter.swift   # AsyncStream-based progress events
│   │   ├── Config/
│   │   │   ├── GlobalSettings.swift     # Replaces persistent_config.py
│   │   │   └── ProjectPreferences.swift
│   │   └── FileManager/
│   │       └── ProjectFileManager.swift # Replaces io_paths.py + security-scoped bookmarks
│   ├── Steps/
│   │   ├── Flatten/
│   │   │   ├── FlattenStep.swift
│   │   │   └── GPXParser.swift          # XMLParser replacing gpxpy
│   │   ├── Extract/
│   │   │   ├── ExtractStep.swift
│   │   │   └── FrameSampler.swift       # AVAssetImageGenerator
│   │   ├── Enrich/
│   │   │   ├── EnrichStep.swift
│   │   │   ├── GPSEnricher.swift        # Nearest-neighbour GPX lookup
│   │   │   ├── YOLODetector.swift       # Core ML — VNImageRequestHandler + VNCoreMLRequest
│   │   │   ├── SceneDetector.swift      # Pixel histogram diff
│   │   │   └── ScoreCalculator.swift    # Scoring weights
│   │   ├── Select/
│   │   │   ├── SelectStep.swift
│   │   │   ├── ClipSelector.swift       # Gap logic, zone bonuses
│   │   │   └── PartnerMatcher.swift     # Temporal tolerance matching across cameras
│   │   ├── Build/
│   │   │   ├── BuildStep.swift
│   │   │   ├── GaugeRenderer.swift      # Core Graphics — arcs, labels, transparency
│   │   │   ├── MinimapRenderer.swift    # MKMapSnapshotter replacing contextily/geopandas
│   │   │   ├── ElevationRenderer.swift  # Core Graphics line chart replacing matplotlib
│   │   │   └── ClipCompositor.swift     # PiP via FFmpegBridge filter_complex
│   │   ├── Splash/
│   │   │   ├── SplashStep.swift
│   │   │   ├── IntroBuilder.swift       # AVVideoComposition + Core Graphics
│   │   │   └── OutroBuilder.swift
│   │   └── Concat/
│   │       ├── ConcatStep.swift         # Stream-copy concat
│   │       └── AudioMixer.swift         # AVAudioMix ducking
│   ├── Video/
│   │   ├── FFmpegBridge.swift           # Protocol abstraction — KEY FILE
│   │   ├── VideoCompositor.swift        # AVMutableVideoComposition
│   │   └── VideoEncoder.swift           # AVAssetWriter + VideoToolbox
│   ├── ML/
│   │   ├── YOLOInference.swift
│   │   └── VeloYOLO.mlpackage          # Exported from yolo11s.pt
│   ├── Integrations/
│   │   ├── Strava/
│   │   │   ├── StravaClient.swift
│   │   │   └── StravaAuth.swift         # ASWebAuthenticationSession
│   │   └── Garmin/
│   │       └── GarminClient.swift
│   ├── Views/                           # SwiftUI
│   │   ├── Main/
│   │   │   ├── ContentView.swift
│   │   │   ├── ProjectListView.swift
│   │   │   └── ProjectDetailView.swift
│   │   ├── Pipeline/
│   │   │   ├── PipelineView.swift
│   │   │   └── StepStatusView.swift
│   │   ├── Selection/
│   │   │   ├── ManualSelectionView.swift  # Touch-optimised — swipe to include/exclude
│   │   │   └── ClipPreviewView.swift
│   │   ├── Settings/
│   │   │   ├── GlobalSettingsView.swift
│   │   │   └── ProjectPreferencesView.swift
│   │   ├── Import/
│   │   │   ├── ImportView.swift
│   │   │   ├── StravaImportView.swift
│   │   │   └── GarminImportView.swift
│   │   └── Calibration/
│   │       └── CameraCalibrationView.swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── music/                       # Bundled tracks
├── macOS/
│   └── FFmpegMac.swift                  # Shells out to /usr/local/bin/ffmpeg
├── iPadOS/
│   ├── FFmpegiOS.swift                  # Wraps FFmpegKit
│   └── FilePickerBridge.swift           # UIDocumentPickerViewController
├── Scripts/
│   └── export_coreml.py                 # One-time yolo11s.pt → VeloYOLO.mlpackage
└── VeloFilmsTests/
```

**`FFmpegBridge.swift` is the architectural linchpin.** A protocol that both `FFmpegMac.swift` and `FFmpegKit.swift` conform to. All pipeline steps call only the bridge. Existing FFmpeg filter strings port unchanged to both platforms.

```swift
protocol FFmpegBridge {
    func execute(arguments: [String]) async throws -> String
}
// macOS: shells out to /usr/local/bin/ffmpeg
// iPadOS: FFmpegKit.executeAsync(...)
```

---

## Development Phases

### Phase 0 — Dev Environment & Project Setup

Do this before writing a single line of Swift.

- [x] Enrol in Apple Developer Program (allow up to 48 hrs to activate)
- [x] Install Xcode 26.4.1 (17E202)
- [x] Create GitHub repo `velo-films-swift`, clone locally
- [x] Create Xcode multiplatform project targeting macOS 14+ and iPadOS 26+
- [ ] Add Swift Package dependency: FFmpegKit (iOS target only)
- [ ] Run `Scripts/export_coreml.py`: `yolo11s.pt` → `VeloYOLO.mlpackage`, add to project
- [ ] Set up TestFlight for iPad distribution
- [x] Commit skeleton project structure

**Milestone:** Blank app runs in iPad Simulator and on Mac natively.

---

### Phase 1 — Data Models & Config ✅

Foundation everything else builds on. No video, no UI.

- [x] `AppConfig.swift` — all settings from `config.py`, persisted via `@AppStorage` / `Codable`
- [x] `GlobalSettings.swift` — replaces `persistent_config.py`. Covers: drive roots, camera offsets + timezones, extract interval, highlight target, min gap between clips, GPX time offset, music/raw audio volumes, show elevation, dynamic gauges. All values persisted to UserDefaults and consumed by pipeline steps directly.
- [x] `ProjectPreferences.swift` — per-project overrides stored as `preferences.json` in project folder. Fields: `selectedMusicTrack` (filename or empty for random), `highlightTargetMinutes?` (nil = use global), `notes` (free text). Wired into `BuildStep.findMusicTrack()` and `Project.effectiveTargetClips()`.
- [x] **Pipeline wiring fixes** — `ExtractStep` now reads `GlobalSettings.effectiveExtractInterval`; `FlattenStep` reads `GlobalSettings.gpxTimeOffsetS`; `BuildStep.mixMusic` reads `GlobalSettings.musicVolume/rawAudioVolume`; `ClipSelector.Config.minGap` reads `GlobalSettings.minGapBetweenClips`; `AppConfig.targetClips` reads `GlobalSettings.highlightTargetMinutes`; `AppConfig.CameraName.timezoneIdentifier` and `.knownOffset` read from GlobalSettings so camera calibration offsets are actually applied (previously hardcoded to 0).
- [x] `Project.swift` — ride project struct with all path properties from `io_paths.py`; `ProjectStore` embedded here (UserDefaults persistence, save/load project list across launches)
- [x] `ProjectFileManager.swift` — creates/reads project directory structure
- [x] JSONL row models (`FlattenRow`, `ExtractRow`, `EnrichRow`, `SelectRow`) — `Codable`
- [x] `JSONLReader.swift` + `JSONLWriter.swift` — generic helpers used by all steps to read/write JSONL files

**Milestone:** Can create a project, write/read all JSONL formats, settings persist across launches.

---

### Phase 2 — Pipeline Infrastructure ✅

The plumbing before the water.

- [x] `PipelineStep` protocol — replaces `step_registry.py`
- [x] `PipelineExecutor` — runs steps sequentially, handles cancellation, replaces `pipeline_executor.py`
- [x] `PipelineExecutor` re-run fix — `forceRun: Bool` flag in `dependencyChain()` ensures target step always executes even when `isComplete` returns true; dependencies still cache-hit normally
- [x] `ProgressReporter` — `AsyncStream`-based progress events consumed by UI
- [x] `os.Logger` unified logging (visible in Xcode console and Console.app)
- Per-step log files — deferred indefinitely; pipeline runs cleanly and Xcode console provides sufficient visibility during development.
- [ ] Background task handling — `BackgroundTasks` framework wired for iPadOS; unconstrained on macOS

**Milestone:** Stub pipeline with fake steps runs and reports progress to console.

---

### Phase 3 — Data Steps (Flatten · Extract · Enrich · Select) ✅

All pure logic, no video rendering. Fully testable in Simulator.

**Flatten** ✅
- [x] `GPXParser.swift` — `XMLParser` replacing gpxpy, produces 1-second telemetry rows
- [x] `FlattenStep.swift` — writes `flatten.jsonl` equivalent

**Extract** ✅
- [x] `FrameSampler.swift` — `AVAssetImageGenerator` extracts frames at GPX-anchored grid points
- [x] Multi-camera timing, timezone offsets, `KNOWN_OFFSETS` per camera — direct port of `extract.py` logic

**Enrich** ✅
- [x] `GPSEnricher.swift` — nearest-neighbour GPX lookup
- [x] `YOLOInference.swift` (in `Shared/ML/`) — Core ML inference replacing PyTorch/Ultralytics. `VNImageRequestHandler` + `VNCoreMLRequest`. Serial queue batch processing. *(plan had this as `YOLODetector.swift` in `Steps/Enrich/` — actual location differs)*
- [x] `SceneDetector.swift` — pixel histogram diff
- [x] `ScoreCalculator.swift` — scoring weights
- [x] `SegmentMatcher.swift` — detects known route segments and applies segment-based score boosts *(not in original plan; added during implementation)*

**Select** ✅
- [x] `ClipSelector.swift` — scoring, gap logic, scene-aware gap multiplier, zone bonuses
- [x] `PartnerMatcher.swift` — 1-second temporal tolerance matching across cameras

**Milestone:** Run phases 0–3 on a real ride on macOS. Compare output against Python version on same input — scores should match within floating-point rounding.

---

### Phase 4 — FFmpeg Bridge & Video Pipeline ✅

The hardest phase. Video QA requires real footage on real hardware.

**FFmpegBridge**
- [x] `FFmpegBridge` protocol — `execute(arguments: [String]) async throws -> String`
- [x] `FFmpegMacBridge` — direct `Process()` exec of `/opt/homebrew/bin/ffmpeg`; no shell wrapper so filter_complex arguments (spaces, quotes, colons) are passed verbatim. Fixes word-split bugs that broke `drawtext='Velo Films'` and xfade filters.
- [ ] `FFmpegiOS` — FFmpegKit wrapper (iPadOS target; deferred until iPad testing phase)

**Build Step**
- [x] `GaugeRenderer.swift` — Core Graphics rewrite of `gauge_prerenderer.py`. Arc drawing, text labels, semi-transparency. Output: per-clip PNG strip.
- [x] `ElevationRenderer.swift` — Core Graphics line chart replacing matplotlib elevation plot.
- [x] `MinimapRenderer.swift` — `MKMapSnapshotter` replaces contextily/geopandas/matplotlib. Route polyline + position marker per clip.
- [x] `ClipCompositor.swift` — assembles PiP layout via `FFmpegBridge`. Ports `filter_complex` strings from `clip_renderer.py` unchanged.

**Splash Step**
- [x] `IntroBuilder.swift` — 3-clip xfade chain (logo → route map → frame collage). `encodeStill()` normalises all source images to `W×H` via `scale/pad` before xfade so dimension mismatches never occur. Logo loaded from bundle or `Shared/Resources/velo_films.png`.
- [x] `IntroBuilder` music mixing — `mixSplashMusic()` replaces silent audio track with `intro.mp3` via `loudnorm` + `volume=0.85`. Falls back to silent if no audio asset found.
- [x] `OutroBuilder.swift` — builds `outro_collage.png` from recommended frames (same `renderCollage` as intro), animated `drawtext 'Velo Films'` overlay, fade-to-black xfade, then mixes `outro.mp3` if available. Shared IntroBuilder helpers made non-private so OutroBuilder can call them directly.
- [x] Resource finders — `findResourceImage(named:)` / `findResourceAudio(named:)` check bundle first, then `Shared/Resources/` fallback.
- [ ] Route overview map in splash via `MKMapSnapshotter` — placeholder black frame used currently
- [x] Outro xfade timebase mismatch fix — `outro_black.mp4` `color=` lavfi source defaulted to 25 fps (tbn 1/12800) while collage was 30 fps (tbn 1/15360); added `r=30` to the color filter so both timebases match before xfade
- [ ] xfade "inputs too short" error — intermittent `18 > 2` crash in intro xfade chain needs root-cause verification after FFmpegMacBridge fix

**Concat + Audio**
- [x] `ConcatStep.swift` — `FFmpegBridge` concat; video stream-copied, audio re-encoded to AAC 48kHz to normalise timebases across intro/middle/outro segments (silent audio drop occurs with full `-c copy` when segments were encoded in separate passes)
- [ ] `AudioMixer.swift` — `FFmpegBridge -filter_complex amix` for background music with ducking *(not yet implemented — `ConcatStep` currently produces silent or direct audio output)*

**Video utilities (planned, not implemented)**
- `VideoCompositor.swift` / `VideoEncoder.swift` — originally planned as AVMutableVideoComposition wrappers; not needed — all composition and encoding handled through `FFmpegBridge` filter_complex strings directly

**Milestone:** Full pipeline runs on macOS, produces a real output video. Visual QA of gauges, minimap, PiP layout, splash cards against Python version output on the same ride.

---

### Phase 5 — SwiftUI GUI (parallel with Phase 4) ✅

Can be built and iterated in Simulator while Phase 4 is being tested on device.

**Project, Detail & Pipeline Views**
- [x] `ProjectListView` — sidebar list of rides, create/delete/archive
- [x] `ProjectDetailView` — project info, step status indicators, action buttons
- [x] `PipelineView` — step-by-step progress with log output panel
- `StepStatusView` — originally planned as a separate component; step status rendering is inline in `PipelineView` and not needed as a standalone file
- `LogViewerView` — deferred; not required.

**Manual Selection & Clip Preview**
- [x] `ManualSelectionView` — scored moment list, touch tap to toggle. At most one selection per moment; zero allowed. Shows top `max(targetClips × 2, recommended + 20)` moments sorted by score.
- [x] `ManualSelectionView` moment display fix — shows all autoselect candidates (not only previously saved moments); remembers saved `recommended` state across re-opens.
- [x] `MomentCard` — always two columns (Fly12Sport col 0, Fly6Pro col 1). Missing camera shows `PlaceholderCard` (grey fill, dashed border, "No footage", non-interactive). Matches Python `manual_selection_window.py` model where position encodes camera identity.
- [x] `PerspectiveCard` — PiP composite: primary camera thumbnail full-size + partner camera thumbnail overlaid at 30% width bottom-right (8pt margin). Matches Python `_create_perspective_card()`.
- [x] `PlaceholderCard` — grey fill, dashed stroke border, "No footage" label. Matches Python `_create_placeholder_card()`.
- [ ] `ClipPreviewView` — `VideoPlayer` inline clip preview on tap (deferred)

**Settings & Calibration Views**
- [x] `GlobalSettingsView` — Drive Roots, Camera Calibration (offsets + timezones), Pipeline (highlight duration, min gap, GPX offset, elevation/gauge toggles), Audio (music volume, raw audio volume)
- [x] `ProjectPreferencesView` — music track picker (dropdown of available tracks + Random option), highlight duration override toggle, notes text editor
- [ ] `CameraCalibrationView` — frame preview with offset sliders (deferred)

**Import, Drive Setup & OAuth**
- [x] `ImportView` — file picker for drive root setup and project folder selection
- [x] `StravaImportView` — full end-to-end: OAuth2 via ASWebAuthenticationSession, token auto-refresh, cycling filter, GPX download via streams API (correct timestamps), project creation, cascade-dismiss on import
- [x] `GarminImportView` — full end-to-end: email/password form, Garmin SSO (sso.garmin.com CSRF + ticket exchange), cycling filter, native GPX download, project creation
- [x] `StravaClient.swift` / `StravaAuth.swift` — `StravaActivity` Codable model; `ensureValidToken()` auto-refresh; GPX built from streams with correct activity start timestamp
- [x] `GarminAuth.swift` (new) — Garmin SSO flow; CSRF extract; service ticket exchange; session verification via `/currentuser-service/user/info`; MFA detection
- [x] `GarminClient.swift` — `GarminActivity` Codable model; activity list; native GPX download

**Milestone:** Complete end-to-end UI flow works in iPad Simulator through to triggering a pipeline run.

---

### Phase 6 — Integration & Device Testing

Cannot be compressed. Needs real rides, real footage, real iPad.

- Deploy to iPad via TestFlight
- Run each pipeline step on a real ride with real Cycliq footage from external drive
- Visual QA every rendered output: gauges, minimap, PiP composite, splash cards
- Memory pressure testing with 10GB+ footage across multiple clips
- Background processing behaviour — document what renders survive app backgrounding; adapt UX (progress persistence, resume on foreground) if needed
- Performance tuning: Core ML batch sizes, VideoToolbox encoder settings, gauge render throughput
- [x] Strava and Garmin OAuth end-to-end — complete on macOS; iPadOS needs device test

---

### Phase 7 — Polish & Release

- App icon and launch screen
- iPad multitasking — Split View and Slide Over (SwiftUI handles most of this automatically)
- Error handling and user-facing messages for all failure modes
- Archive / export flow
- Final drive format check UX (warn if NTFS detected — writes will fail)

---

## Summary Timeline

| Phase | Deliverable | Claude Code autonomy |
|---|---|---|
| 0. Setup | Dev environment, Xcode project, TestFlight | Mostly — you activate the Developer account |
| 1. Data models | Codable rows, project persistence, config | Yes |
| 2. Pipeline infrastructure | Executor, progress reporting, logging | Yes |
| 3. Data steps | Flatten · Extract · Enrich · Select pipeline | Yes — testable in Simulator |
| 4. Video pipeline | Gauges · Minimap · Compositor · Splash · Concat | Partial — video QA needs you and a device |
| 5. SwiftUI GUI | All views — pipeline, selection, settings, import | Yes — visible in Simulator |
| 6. Device testing | Real footage on real iPad, end-to-end QA | No — this is entirely you |
| 7. Polish & release | App icon, error handling, archive/export flow | Mostly |

---

## Key Decisions (Resolved)

| Decision | Choice | Reason |
|---|---|---|
| Minimum OS | iPadOS 26 / macOS 14 | Personal app, no need for older device support. Latest background task APIs. |
| Video source location | External USB-C drive | Same workflow as today. Security-scoped bookmarks handle iPadOS access. |
| Music assets | Bundle in app | Simpler than requiring user import. ~50MB addition to app size. |
| Background rendering UX | Keep app frontmost + progress persistence | iPadOS 26 improved budgets help; still show guidance to user for long renders. |
| Output codec on iPad | H.264 via VideoToolbox | H.265 multi-pass not available on iPadOS. Visually identical at 8M bitrate. |
| YOLO batch size on iPad | 2–4 | 8GB RAM constraint. Mac target can use 8. |
