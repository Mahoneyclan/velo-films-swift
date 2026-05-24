# VeloFilms

**Automated Cycling Video Highlight Reel Generator**

VeloFilms is a native macOS and iOS application that automatically creates professional cycling highlight videos by combining dual-camera footage (front + rear), GPS data, YOLO object detection, and dynamic HUD overlays.

## Platform Support

- ✅ **macOS 14.0+** (primary development target)
- ✅ **iOS 17.0+** (full feature parity)
- Built with **Swift 6**, **SwiftUI**, and **AVFoundation**

## Features

### 🎥 Video Processing
- Dual-camera synchronization (Cycliq Fly12 Sport + Fly6 Pro)
- AVAssetReader/Writer-based frame compositing with CoreImage
- Hardware-accelerated H.264 encoding
- Intelligent clip selection using YOLO v8 object detection
- Scene change detection for highlight scoring

### 🗺️ GPS & Overlays
- GPX track parsing and interpolation
- Live minimap with route visualization (MapKit)
- Elevation profile rendering
- Dynamic gauge overlays (speed, cadence, heart rate, elevation, gradient)
- Strava segment integration for PR detection

### 🎨 HUD Layout (1920×1080)
- **Main video**: Center-scaled with letterboxing
- **PiP camera**: 390px height, bottom-right
- **Minimap**: 390×390px, bottom-left
- **Gauges**: 5×194px cells, bottom-center
- **Elevation strip**: 948×75px, flush bottom

### 🎵 Audio
- Background music mixing with volume control
- Camera audio preservation with adjustable levels
- Automatic fade in/out and crossfades between clips

### 📊 Analytics Pipeline
1. **Flatten**: Parse GPX and video metadata
2. **Extract**: Sample frames at 5-second intervals
3. **Detect**: YOLO object detection on sampled frames
4. **Enrich**: GPS interpolation + scoring
5. **Select**: Highlight clip selection algorithm
6. **Build**: Render clips + segment concatenation
7. **Finalize**: Intro/outro + music mix

## Project Structure

```
VeloFilms/
├── Models/
│   ├── Project.swift              # Project management & persistence
│   ├── EnrichRow.swift            # Data schema for enriched CSV
│   ├── AppConfig.swift            # Pipeline constants
│   └── GlobalSettings.swift       # User preferences
├── Pipeline/
│   ├── PipelineExecutor.swift     # Step orchestration
│   ├── BuildStep.swift            # Main build orchestrator
│   ├── ClipCompositor.swift       # Per-clip AVAssetReader rendering
│   └── VideoCompositor.swift      # Custom AVVideoCompositing
├── Rendering/
│   ├── MinimapRenderer.swift      # MapKit-based minimap generation
│   ├── GaugeRenderer.swift        # Dynamic gauge overlay rendering
│   ├── ElevationRenderer.swift    # Elevation profile charts
│   ├── IntroBuilder.swift         # Intro sequence generation
│   └── OutroBuilder.swift         # Outro sequence generation
├── Analysis/
│   ├── ClipSelector.swift         # Highlight selection algorithm
│   ├── SceneDetector.swift        # Scene change detection
│   ├── PartnerMatcher.swift       # Dual-camera pairing
│   └── StravaAuth.swift           # Strava OAuth integration
└── Views/
    ├── ContentView.swift          # Main app layout
    ├── ProjectDetailView.swift    # Pipeline UI
    └── ManualSelectionView.swift  # Manual clip override
```

## Architecture

### Concurrency Model
- **Swift 6 strict concurrency** compliance throughout
- `@Observable` for reactive UI state
- `async/await` for pipeline steps
- **Dedicated OS thread** for AVAssetReader/Writer (VideoToolbox IPC requirement)
- Main actor isolation for UI updates

### Video Compositing Strategy
Two parallel implementations:
1. **ClipCompositor** (default): AVAssetReader + AVAssetWriter on dedicated queue
   - Lower memory footprint
   - Frame-perfect GPU compositing via CIContext
2. **VideoCompositor** (experimental): Custom AVVideoCompositing
   - Fully async frame delivery
   - Better for timeline-based editing

### Data Flow
```
GPX + MP4s → Flatten → Extract → YOLO Detect → Enrich → Select → Build → Final Reel
     └─────────────── Analysis Phase ──────────────┘  └── Render Phase ──┘
```

## Setup

### Requirements
- Xcode 16.0+
- macOS 14.0+ or iOS 17.0+
- YOLOv8n CoreML model (not included — see PLAN.md)
- Optional: Strava API credentials for segment integration

### Configuration
1. Set `projectsRoot` and `inputBaseDir` in Settings
2. Configure camera timezone offsets (Camera Calibration)
3. Place `yolov8n.mlpackage` in app bundle or specify custom path
4. (Optional) Add Strava credentials to `StravaSecrets.swift`

### Build Flags
- `SWIFT_STRICT_CONCURRENCY=complete` enabled
- Minimum deployment: macOS 14.0, iOS 17.0
- SwiftUI lifecycle

## Known Issues & Warnings Audit

### ✅ Resolved (as of current build)
- ~~Deprecated `loadTracks(withMediaType:)` calls~~ → Replaced with modern async filter pattern
- ~~Sendability violations in ClipCompositor~~ → Added `Sendable` conformance + proper capture
- ~~Redundant optional initializers~~ → Removed `= nil` syntax

### ⚠️ Active Warnings
None in core pipeline files (see PLAN.md for remaining TODOs)

### 🔧 Platform-Specific Notes
**macOS**:
- Uses `NSImage` for image loading
- `NSApp.keyWindow` for auth presentation anchor

**iOS**:
- Uses `UIImage` for image loading
- `UIWindowScene` for auth presentation anchor
- Batch size reduced for YOLO (4 vs 8 on Mac)

## Performance

### Typical Processing Times (M2 MacBook Pro)
- **Analysis phase** (60-min ride, 720 frames): ~8 minutes
  - YOLO inference: ~5 min
  - GPS matching: ~30 sec
  - Scene detection: ~1 min
- **Build phase** (30-clip highlight): ~12 minutes
  - Map tile fetch: ~15 sec
  - Gauge rendering: ~1 min
  - Clip compositing: ~10 min (realtime playback speed)
  - Segment concat: ~30 sec

### Memory Usage
- Peak: ~2.5 GB during YOLO batch inference
- Steady-state compositing: ~800 MB
- CIContext shared across frames to reduce overhead

## Credits

VeloFilms is a Swift port and evolution of the original Python/FFmpeg pipeline, rebuilt for native Apple platform integration with SwiftUI, AVFoundation, and CoreML.

**Key Technologies**:
- AVFoundation for video composition
- CoreImage/Metal for GPU-accelerated rendering
- MapKit for minimap generation
- CoreML for YOLO inference
- Swift Concurrency for async pipeline orchestration

## License

[Specify your license here]

---

**Build Status**: ✅ Compiling without warnings (Swift 6 strict concurrency)
**Last Audit**: April 29, 2026
