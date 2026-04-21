# Velo Films — Swift Multiplatform Rewrite Plan

Multiplatform SwiftUI app targeting macOS 14+ and iPadOS 26+, replacing the existing Python/PySide6 pipeline.
Single codebase, two targets. Raw videos live on external drive, accessed via security-scoped bookmarks on iPad.

Hardware: iPad Air 11-inch M2 (8GB RAM), iPadOS 26.4. Mac Mini M1.

---

## Apps / Tools Needed on Mac Mini

### Required

| Tool | Source | Cost | Purpose |
|---|---|---|---|
| Xcode 16+ | Mac App Store | Free | IDE, Swift compiler, Simulator, Instruments |
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

### Phase 0 — Setup (Week 1)

Do this before writing a single line of Swift.

- [ ] Enrol in Apple Developer Program (allow up to 48 hrs to activate)
- [ ] Install Xcode 16+, SF Symbols 6, Proxyman
- [ ] Create GitHub repo `velo-films-swift`, clone locally
- [ ] Create Xcode multiplatform project targeting macOS 14+ and iPadOS 26+
- [ ] Add Swift Package dependency: FFmpegKit (iOS target only)
- [ ] Run `Scripts/export_coreml.py`: `yolo11s.pt` → `VeloYOLO.mlpackage`, add to project
- [ ] Set up TestFlight for iPad distribution
- [ ] Commit skeleton project structure

**Milestone:** Blank app runs in iPad Simulator and on Mac natively.

---

### Phase 1 — Data Models & Config (Week 2)

Foundation everything else builds on. No video, no UI.

- `AppConfig.swift` — all settings from `config.py`, persisted via `@AppStorage` / `Codable`
- `GlobalSettings.swift` + `ProjectPreferences.swift` — replaces `persistent_config.py`
- `Project.swift` — ride project struct with all path properties from `io_paths.py`
- `ProjectFileManager.swift` — creates/reads project directory structure, security-scoped bookmark management for both drive roots
- CSV row models (`FlattenRow`, `ExtractRow`, `EnrichRow`, `SelectRow`) — `Codable`, read/write via Swift CSV

**Milestone:** Can create a project, write/read all CSV formats, settings persist across launches.

---

### Phase 2 — Pipeline Infrastructure (Week 3)

The plumbing before the water.

- `PipelineStep` protocol — replaces `step_registry.py`
- `PipelineExecutor` — runs steps sequentially, handles cancellation, replaces `pipeline_executor.py`
- `ProgressReporter` — `AsyncStream`-based progress events consumed by UI
- Logging — `os.Logger` (unified logging, visible in Console.app and Xcode console)
- Background task handling — `BackgroundTasks` framework wired for iPadOS; unconstrained on macOS

**Milestone:** Stub pipeline with fake steps runs and reports progress to console.

---

### Phase 3 — Data Steps (Weeks 4–7)

All pure logic, no video rendering. Fully testable in Simulator.

**Flatten (1 week)**
- `GPXParser.swift` — `XMLParser` replacing gpxpy, produces 1-second telemetry rows
- `FlattenStep.swift` — writes `flatten.csv` equivalent
- Validate: output matches existing `flatten.csv` on same GPX input

**Extract (1 week)**
- `FrameSampler.swift` — `AVAssetImageGenerator` extracts frames at GPX-anchored grid points
- Multi-camera timing, timezone offsets, `KNOWN_OFFSETS` per camera — direct port of `extract.py` logic
- Validate: frame count and timestamps match existing `extract.csv`

**Enrich (1.5 weeks)**
- `GPSEnricher.swift` — nearest-neighbour GPX lookup, direct port of `gps_enricher.py`
- `YOLODetector.swift` — Core ML inference replacing PyTorch/Ultralytics. `VNImageRequestHandler` + `VNCoreMLRequest`. Serial queue batch processing. Batch size 2–4 on iPad (vs 8 on Mac).
- `SceneDetector.swift` — pixel histogram diff, direct port of `scene_detector.py`
- `ScoreCalculator.swift` — direct port of scoring weights from `score_calculator.py`

**Select (0.5 week)**
- `ClipSelector.swift` — scoring, gap logic, scene-aware gap multiplier, zone bonuses — direct port of `select.py`
- `PartnerMatcher.swift` — 1-second temporal tolerance matching across cameras

**Milestone:** Run phases 0–3 on a real ride on macOS. Compare `select.csv` output against Python version on same input — scores should match within floating-point rounding.

---

### Phase 4 — FFmpeg Bridge & Video Pipeline (Weeks 8–14)

The hardest phase. Video QA requires real footage on real hardware.

**FFmpegBridge (1 week)**

Design and test the bridge protocol before touching anything else in this phase. Validate on macOS with a trivial FFmpeg command (probe a video file), then confirm FFmpegKit runs the same command on the iPad Simulator.

**Build Step (3 weeks)**
- `GaugeRenderer.swift` — Core Graphics rewrite of `gauge_prerenderer.py`. Arc drawing, text labels, semi-transparency. Most complex single rendering component. Output: per-clip PNG or video strip matching existing 972×194px composite geometry.
- `ElevationRenderer.swift` — Core Graphics line chart replacing matplotlib elevation plot. Matches existing 948×75px strip.
- `MinimapRenderer.swift` — `MKMapSnapshotter` replaces contextily/geopandas/matplotlib. Route polyline + position marker per clip. Simpler code, better-looking output. Output: 390×390px PNG per clip.
- `ClipCompositor.swift` — assembles PiP layout via `FFmpegBridge`. Port existing `filter_complex` strings from `clip_renderer.py` directly — they work unchanged on both platforms.

**Splash Step (1.5 weeks)**
- `IntroBuilder.swift` / `OutroBuilder.swift` — `AVVideoComposition` + Core Graphics for title cards and ride stats overlay
- Route overview map via `MKMapSnapshotter` at splash resolution

**Concat + Audio (1 week)**
- `ConcatStep.swift` — `FFmpegBridge` stream-copy concat, direct port of `concat.py`
- `AudioMixer.swift` — `FFmpegBridge -filter_complex amix` for background music with ducking

**Milestone:** Full pipeline runs on macOS, produces a real output video. Visual QA of gauges, minimap, PiP layout, splash cards against Python version output on the same ride.

---

### Phase 5 — SwiftUI GUI (Weeks 12–16, parallel with Phase 4)

Can be built and iterated in Simulator while Phase 4 is being tested on device.

**Weeks 12–13**
- `ProjectListView` — sidebar list of rides, create/delete/archive
- `ProjectDetailView` — project info, step status indicators, action buttons
- `PipelineView` — step-by-step progress with log output panel

**Week 14**
- `ManualSelectionView` — swipe left/right on clip cards to include/exclude. Inline video preview. Touch-native; will be genuinely better than the current Qt version.
- `ClipPreviewView` — `VideoPlayer` from AVKit

**Week 15**
- `GlobalSettingsView` + `ProjectPreferencesView` — all config fields grouped and labelled, matching the settings hierarchy in `config.py`
- `CameraCalibrationView` — frame preview with offset sliders

**Week 16**
- `ImportView` — file picker (iPadOS: `UIDocumentPickerViewController`; macOS: `NSOpenPanel`) for drive root setup and project folder selection
- `StravaImportView` + `GarminImportView` — OAuth via `ASWebAuthenticationSession`

**Milestone:** Complete end-to-end UI flow works in iPad Simulator through to triggering a pipeline run.

---

### Phase 6 — Integration & Device Testing (Weeks 17–20)

Cannot be compressed. Needs real rides, real footage, real iPad.

- Deploy to iPad via TestFlight
- Run each pipeline step on a real ride with real Cycliq footage from external drive
- Visual QA every rendered output: gauges, minimap, PiP composite, splash cards
- Memory pressure testing with 10GB+ footage across multiple clips
- Background processing behaviour — document what renders survive app backgrounding; adapt UX (progress persistence, resume on foreground) if needed
- Performance tuning: Core ML batch sizes, VideoToolbox encoder settings, gauge render throughput
- Strava and Garmin OAuth end-to-end on both macOS and iPadOS

---

### Phase 7 — Polish (Weeks 21–23)

- App icon and launch screen
- iPad multitasking — Split View and Slide Over (SwiftUI handles most of this automatically)
- Error handling and user-facing messages for all failure modes
- Archive / export flow
- Final drive format check UX (warn if NTFS detected — writes will fail)

---

## Summary Timeline

| Phase | Weeks | Claude Code autonomy |
|---|---|---|
| 0. Setup | 1 | Mostly — you activate the Developer account |
| 1. Data models | 1 | Yes |
| 2. Pipeline infrastructure | 1 | Yes |
| 3. Data steps | 4 | Yes — testable in Simulator |
| 4. Video pipeline | 7 | Partial — video QA needs you and a device |
| 5. SwiftUI GUI | 5 | Yes — visible in Simulator |
| 6. Device testing | 4 | No — this is entirely you |
| 7. Polish | 3 | Mostly |
| **Total** | **~26 weeks** | |

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
