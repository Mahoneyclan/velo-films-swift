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
| FFmpegKit | ~~Swift Package~~ **BLOCKED** — arthenica/ffmpeg-kit repo archived, no Package.swift at root | Free | iOS video processing — cannot add via SPM; iOS pipeline stubs throw until resolved |
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

- **8GB RAM** — half the recommended 16GB. YOLO batch size capped at 2–4. Process frames sequentially, never buffer a full ride in memory.
- **16-core Neural Engine** — Core ML YOLO inference will be fast, likely faster than CPU-bound PyTorch on Mac.
- **USB-C USB 3 (10Gb/s)** — external drive access is viable. Raw videos stay on the drive exactly as they do today. Drive must be exFAT or APFS — NTFS is read-only on Apple platforms.
- **VideoToolbox** — H.264 hardware encoding fully supported. Switching to AVAssetWriter enables H.265 HEVC at ~5 Mbps for smaller output files.
- **Thermal throttling** — M2 iPad will throttle after 5–10 min of sustained video work. Use concurrent `TaskGroup` with a cap of ~3 concurrent clip encodes to manage thermals. For a once-a-week personal tool, this is workable; plug in and leave the app open.
- **iPadOS 26** — improved background task budgets for video workloads. Target iPadOS 26 as minimum — this is a personal app, no reason to support older versions.
- **Mac Mini M1** — retained as the fast development/production machine. macOS FFmpeg path remains for now; may be replaced by AVFoundation in Phase 6.5 if App Store Option A is chosen.

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
- [x] iOS pipeline: **resolved via AVFoundation** — no FFmpegKit needed. ClipCompositor, BuildStep, ConcatStep all have `#if os(macOS)` (FFmpeg) / `#else` (AVFoundation) dual paths. kingslay/FFmpegKit package removed from project (was causing `duplicate _main` linker error).
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
- [x] iOS pipeline: AVFoundation path implemented in `ClipCompositor`, `BuildStep`, `ConcatStep` — all video compositing and concatenation uses AVFoundation `#else` blocks; no FFmpegKit needed

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
- [x] `ConcatStep.swift` — `FFmpegBridge` xfade crossfade concat between intro/middle/outro segments; normalises all inputs to 30fps + 48kHz before xfade chain to unify AVFoundation (1/600 tb, 48kHz) and FFmpeg (1/15360 tb, 96kHz) timebases
- [x] Background music mixing — `BuildStep.mixMusic()` uses `FFmpegBridge amix` with `-stream_loop -1`; random bundled track selected if no user track set; `findMusicTrack()` uses Bundle API with music/ subfolder + root fallback (Xcode flattens subfolder to bundle root)
- [ ] `AudioMixer.swift` — planned as a separate file; functionality absorbed into `BuildStep.mixMusic()`

**Video utilities (planned, not implemented)**
- `VideoCompositor.swift` / `VideoEncoder.swift` — originally planned as AVMutableVideoComposition wrappers; not needed — all composition and encoding handled through `FFmpegBridge` filter_complex strings directly

**Milestone:** Full pipeline runs on macOS, produces a real output video. Visual QA of gauges, minimap, PiP layout, splash cards against Python version output on the same ride.

---

### Phase 5.5 — Focus Mode Filters ✅

View-level focus mode added to `ManualSelectionView`. Does not modify AI scoring, selection, or any pipeline step.

**New files:**
- [x] `Shared/Core/Models/FocusFilter.swift` — `FocusFilter` enum + `FocusFilterContext` struct + `matches(_:in:)` pure filtering logic

**Modified files:**
- [x] `GlobalSettings` — 5 new persisted preferences: `focusFirstNMinutes` (10), `focusLastNMinutes` (10), `focusClimbGradientPct` (3.0%), `focusDescentGradientPct` (3.0%), `focusGroupMinDetections` (5)
- [x] `GlobalSettingsView` — "Focus Mode Defaults" GroupBox with `IntRow` for group threshold + `NumRow` for all other params
- [x] `ManualSelectionView` — `FocusModeBar` + `FocusChip` components; updated `filteredMoments` chains focus filter before existing class filter; loads segment epoch ranges from `segments.json` at view level; improved empty state with context-aware title + description
- [x] `README.md` — Focus Mode section documenting all filters and behaviour

**Test file:**
- [x] `VeloFilmsTests/FocusFilterTests.swift` — 20 tests covering all filters, edge cases, combined filters, AI-unchanged assertion, performance test on 2160-moment ride. Requires VeloFilmsTests target to be added to Xcode (see integration instructions).

**Filters implemented:**
1. Time-based: First N minutes / Last N minutes (N from GlobalSettings)
2. Terrain: Climbs ≥X% / Descents ≥X% (X from GlobalSettings; nil gradient → fails gracefully)
3. Group riding: person+bicycle detection count ≥ N (reuses `detectedClasses` field from YOLO; N from GlobalSettings)
4. Strava Segment: clips within named segment epoch range (parsed from `segments.json`; chips only shown when segments exist)

**Edge cases handled:**
- No GPS data: nil `gradientPct` → terrain filters exclude the moment (graceful, not a crash)
- No segments.json: `availableSegmentNames` is empty → no segment chips shown
- Very short ride: last-N-minutes threshold clamps to 0 → all moments pass
- No matching clips: `ContentUnavailableView` with filter-specific explanation
- Combined focus + class filter: independent dimensions, both can be active simultaneously

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
- [x] `ImportView` — file picker for drive root setup and project folder selection; + Copy from Camera button
- [x] `StravaImportView` — full end-to-end: OAuth2 via ASWebAuthenticationSession, token auto-refresh, cycling filter, GPX download via streams API (correct timestamps), project creation, cascade-dismiss on import
- [x] `GarminImportView` — full end-to-end: email/password form, Garmin SSO (sso.garmin.com CSRF + ticket exchange), cycling filter, native GPX download, project creation
- [x] `StravaClient.swift` / `StravaAuth.swift` — `StravaActivity` Codable model; `ensureValidToken()` auto-refresh; GPX built from streams with correct activity start timestamp; `AuthPreservingDelegate` preserves Bearer header through cross-host redirects
- [x] `GarminAuth.swift` — garth 0.5.3 mobile SSO flow (`/mobile/api/login` JSON POST, `audience=GARMIN_CONNECT_MOBILE_ANDROID_DI`); raw URL preauth (login-url unencoded to match garth); `NoRedirectDelegate` stops URLSession following service redirect; OAuth1 HMAC-SHA1 signing with explicit query params
- [x] `GarminClient.swift` — `GarminActivity` Codable model; activity list; native GPX download; `AuthPreservingDelegate` preserves Bearer header through redirects
- [x] `CopyVideosView` — copies MP4s from mounted Cycliq volumes (FLY12S, FLY6PRO) to `inputBaseDir/{date} {name}/`; date-filtered file scan; per-file progress + speed log; renames `RIDE_001.MP4` → `Fly12Sport_001.MP4`; creates project on completion

**Milestone:** Complete end-to-end UI flow works in iPad Simulator through to triggering a pipeline run.

---

### Phase 6 — Integration & Device Testing

Cannot be compressed. Needs real rides, real footage, real iPad.

**iOS pipeline is now fully implemented** — AVFoundation replaces FFmpeg for all build/concat steps on iOS.

**Critical path: simulator build → physical device → real footage QA.**

- [ ] Get a clean simulator build — confirm all iOS 26 build errors resolved (StravaAuth UIWindow, AVMutableVideoComposition, entitlement conditionals, NS*UsageDescription strings)
- [ ] Deploy to iPad via direct device build in Xcode (or TestFlight)
- [ ] Run full pipeline end-to-end on a real ride with real Cycliq footage from external drive
- [ ] Visual QA every rendered output: gauges, minimap, PiP composite, splash cards — output must match macOS FFmpeg quality
- [ ] Memory pressure testing with 10GB+ footage across multiple clips
- [ ] Strava and Garmin OAuth end-to-end on physical device
- [ ] Background processing behaviour — `BGProcessingTask` registration in `PipelineExecutor` iOS path; if pipeline exceeds ~10 min budget, surface "keep app open" message in `PipelineView`. Pipeline already has `ProgressReporter` + step-level completion tracking so resumption from last completed step is feasible.
- [ ] Performance tuning: Core ML batch sizes, VideoToolbox encoder settings, gauge render throughput
- [ ] Concurrent clip rendering — replace sequential `BuildStep` loop with `TaskGroup` (concurrency cap 3 on iPad for thermal/memory management); could halve build step time on M2

**Architectural gaps to close before release:**

**1. In-memory gauge rendering**
Switch `BuildStep` from `GaugeRenderer.writeFramesToDisk()` to `GaugeRenderer.renderFrames()` returning `[CGImage]` in memory — eliminates the temp PNG encode/decode round-trip and reduces disk I/O on every clip.

**3. AVAssetWriter for clip export**
`AVAssetExportSession` locks to H.264 preset bitrates. Switch to `AVAssetWriter` + `AVAssetReaderVideoCompositionOutput`:
- HEVC H.265 at ~5 Mbps vs 8 Mbps H.264 for equivalent quality (matters for iPad storage)
- Full bitrate control
- Enables concurrent clip exports on M2 media engine

---

### Phase 6.5 — App Store Decision (required before Phase 7)

**Must decide before submitting to either App Store.**

| Option | macOS | iPad | Impact |
|---|---|---|---|
| **A — App Store both** | Drop FFmpeg; AVFoundation on macOS too | App Store | `#if os(macOS)` pipeline splits disappear. Lose `loudnorm` audio normalisation. Single pipeline codebase. Recommended. |
| **B — Direct distribution Mac** | Keep FFmpeg; notarized DMG outside App Store | App Store | Maintain dual pipeline forever. Better audio quality on Mac. Heavier maintenance. |

**Recommendation: Option A.** The dual code path is maintenance overhead, the quality difference is marginal for this use case, and App Store on both platforms is the right product move. The FFmpeg path on macOS would be replaced by the same AVFoundation pipeline already shipping on iPad.

---

### Phase 7 — Polish & Release

- [ ] App icon and launch screen
- [ ] Background task handling (`BGProcessingTask`) with progress persistence and resume
- [ ] iPad multitasking — Split View and Slide Over (SwiftUI handles most of this automatically)
- [ ] Error handling and user-facing messages for all failure modes
- [ ] Progress persistence UX — user guidance to keep app open during long renders; "pipeline is running" indicator
- [ ] Final drive format check UX (warn if NTFS detected — writes will fail)
- [ ] App Store submission: Mac App Store + App Store (iPad). Sandbox, entitlements, and privacy strings already fixed.
- [ ] VTFrameProcessor evaluation — iOS 26 ML-based super-resolution + temporal noise filtering on Cycliq footage (enhancement, not blocking)
- [ ] TestFlight setup for beta distribution

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

## Code Quality Backlog

Complexity issues identified by audit (April 2026). Listed priority-first.

### #1 — Row model field explosion (high)
`SelectRow` repeats all 28 fields of `EnrichRow` verbatim, then `asEnrichRow` reconstructs an `EnrichRow` by spelling out all 28 by hand. Fix: `SelectRow` should *contain* an `EnrichRow` plus its 7 new fields (`recommended`, `stravaPR`, `isSingleCamera`, `paired`, `segmentName`, `segmentDistance`, `segmentGrade`). Adding a field to `EnrichRow` then flows through automatically; `asEnrichRow` disappears entirely.
- [x] Refactor `SelectRow` to embed `EnrichRow` as `var base: EnrichRow`
- [x] Remove `asEnrichRow` computed property
- [x] Update all callsites (`ManualSelectionView`, `BuildStep`, `SelectStep`, etc.)

### #2 — ISO8601 formatter instantiated in every loop iteration (high)
`ISO8601DateFormatter()` is constructed fresh inside loops in `FlattenStep`, `ExtractStep` (×2 per grid-point), and `EnrichStep`. Formatters are expensive to initialise.
- [ ] Add `static let shared` to a `DateFormatting` helper or `ISO8601DateFormatter` extension
- [ ] Replace all inline `ISO8601DateFormatter().string(from:)` calls with the shared instance

### #3 — FFmpeg audio encoding args duplicated 7+ times (high)
`-c:a aac -ar 48000 -ac 2 -b:a 192k` (and the 128k variant) is copy-pasted across `BuildStep`, `IntroBuilder`, `OutroBuilder`, and `ConcatStep`.
- [ ] Extract `enum FFmpegAudio` with `static let high` / `static let medium` string constants
- [ ] Replace all copy-pasted argument strings with the enum values

### #4 — Dual-camera grouping runs twice (medium)
`PartnerMatcher.group()` is called in `SelectStep` and again in `BuildStep` (which first converts `SelectRow` → `EnrichRow` via `asEnrichRow`). Pure duplicate work on every build run.
- [ ] After `SelectStep`, cache grouped moments or pass them through the pipeline output
- [ ] `BuildStep` reads the cached result instead of re-grouping (depends on #1 fix)

### #5 — Fade filter FFmpeg strings duplicated (medium)
`fade=t=in/out` filter string construction appears independently in `BuildStep`, `IntroBuilder`, and `OutroBuilder`.
- [ ] Extract `func fadeFilter(fadeInDuration:totalDuration:fadeOutDuration:) -> String` helper in `FFmpegBridge` or a shared utility

### #6 — Resource lookup duplicated in IntroBuilder (medium)
`findResourceImage(named:)` and `findResourceAudio(named:)` are near-identical functions that differ only in which file extensions they search.
- [ ] Merge into `func findResource(named: String, extensions: [String]) -> URL?`

### #7 — Single-clip concat branch duplicates main path (low)
`BuildStep.concatenateWithXfade()` has a 20-line `segments.count == 1` branch that duplicates the full FFmpeg invocation.
- [ ] Extract `encodeSingleClip(...)` helper to match the structure of the multi-clip path

### #8 — IntroBuilder/OutroBuilder declared as enum (low)
Both are `enum` namespaces with no cases. The intent is "static utility, no instances" but `struct` with `private init()` is the conventional Swift idiom and allows future dependency injection.
- [ ] Convert both to `struct` with `private init()`

### #9 — Step isComplete() logic split across files (low)
Completion-check logic lives partly in `PipelineStep` enum and partly in individual step files / `PipelineExecutor`.
- [ ] Make `isComplete(for: Project) -> Bool` a required protocol method on `PipelineStep`
- [ ] Move all completion logic into each step's own implementation

---

## Key Decisions (Resolved)

| Decision | Choice | Reason |
|---|---|---|
| Minimum OS | iPadOS 26 / macOS 14 | Personal app, no need for older device support. Latest background task APIs. |
| Product target | Dual-OS (macOS + iPad) — iPad is the product | Portability is the core value: ride ends → plug in cameras → pipeline runs → share. Competes directly with Cycliq's own app. Mac remains for fast development/production runs. |
| Programming language | Swift + SwiftUI | Only language with full AVFoundation, Core ML, Metal, MKMapSnapshotter access. No alternative. |
| iOS video pipeline | AVFoundation (no FFmpegKit) | FFmpegKit SPM package archived; AVFoundation with VideoToolbox hardware encoding performs comparably on M2. |
| Video source location | External USB-C drive | Same workflow as today. Security-scoped bookmarks handle iPadOS access. |
| Music assets | Bundle in app | Simpler than requiring user import. ~50MB addition to app size. |
| Background rendering UX | Keep app frontmost + progress persistence | iPadOS 26 improved budgets help; still show guidance to user for long renders. |
| Output codec on iPad | H.264 via VideoToolbox (upgrade to H.265 in Phase 7) | H.265 multi-pass not available via AVAssetExportSession; switching to AVAssetWriter enables HEVC at ~5 Mbps. |
| YOLO batch size on iPad | 2–4 | 8GB RAM constraint. Mac target can use 8. |
| App Store strategy | Option A — App Store on both platforms (pending final decision) | Drop FFmpeg on macOS, use AVFoundation everywhere. Eliminates `#if os(macOS)` dual pipeline. Loses loudnorm only. |

---

## Research: AVFoundation compositor & iOS FFmpeg implications

Concise findings from recent research:

- AVFoundation compositing options: AVMutableVideoComposition + AVVideoCompositionCoreAnimationTool (fast to implement, good for HUD overlays) and AVVideoCompositing (custom Metal compositor for per-frame GPU-accelerated compositing and precise xfade behavior). See full report: /Volumes/GDrive/Github/velo-films-swift/avfoundation-compositor.md

- iOS FFmpeg implications: resolved — iOS pipeline fully implemented via AVFoundation with no FFmpegKit dependency. AVAssetWriter + VideoToolbox hardware H.264 encode is used throughout. No FFmpegKit required.

Actionable improvements identified (May 2026):
1. Pre-convert gauge `CGImage` array to `[CIImage]` at instruction init time — removes repeated per-frame conversion inside the compositor.
2. Switch `BuildStep` to call `GaugeRenderer.renderFrames()` (in-memory `[CGImage]`) instead of `writeFramesToDisk()` — eliminates the temp PNG encode/decode round-trip entirely.
3. Switch clip export to `AVAssetWriter` — gives HEVC H.265 at ~5 Mbps vs 8 Mbps H.264 for equivalent quality (matters for iPad storage), full bitrate control, and ability to run multiple clip exports concurrently on the M2 media engine.
4. Evaluate `VTFrameProcessor` (new in iOS 26) — ML-based super-resolution and temporal noise filtering on CVPixelBuffer output; could meaningfully improve Cycliq action-cam footage quality.

---

## iOS-specific actions & checklist

Purpose: consolidate immediate, medium and long-term tasks required to support on-device rendering and parity with the macOS ffmpeg pipeline. Prioritised for developer execution.

Priority: High — required before reliable iPad testing

- [x] Replace repo-path fallbacks with bundle or app-dir lookups ✅ (2026-04-30)
  - `ProjectPreferencesView.discoverTracks()` — removed stale `/Volumes/.../Shared/Resources/music` hardcode; now uses Bundle API with music/ subdirectory + root fallback
  - `BuildStep.findMusicTrack()` — same Bundle API pattern, 5 bundled tracks found correctly
  - `IntroBuilder`/`OutroBuilder` — use `findResourceImage/Audio` which check bundle first

- [x] FFmpegKit dependency removed ✅ — iOS pipeline fully implemented via AVFoundation. No FFmpegKit needed.

- Fix security-scoped bookmark lifecycle
  - File: `VeloFilms/VeloFilms/Shared/Core/Config/GlobalSettings.swift`
  - Ensure `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` lifecycle is balanced. Either hold access for project lifetime and stop on project close/app termination, or acquire/release around I/O calls.

Priority: Medium — improve stability and developer experience

- Prevent FFmpeg deadlocks on macOS (helps parity debugging)
  - File: `VeloFilms/VeloFilms/Shared/Video/FFmpegBridge.swift` (FFmpegMacBridge)
  - Change `Process` usage to read stdout/stderr asynchronously using `fileHandle.readabilityHandler` and accumulate output while process runs; add a configurable timeout and argument logging.

- [x] Consolidate duplicate Shared sources ✅ (2026-04-29) — old top-level `Shared/`, `macOS/`, `iPadOS/`, `VeloFilmsTests/` directories deleted; canonical path is `VeloFilms/VeloFilms/Shared/`

Priority: Low — polish and policy

- Background export UX
  - Implement cancellable exports, progress UI, and guidance that long exports should stay in foreground (see BGProcessingTask item in Phase 6 below).

---

