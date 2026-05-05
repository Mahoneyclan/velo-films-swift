# VeloFilms Quick Reference

## 🚀 Quick Start

### Build & Run
```bash
# Open in Xcode
open VeloFilms.xcodeproj

# Build for macOS
xcodebuild -scheme VeloFilms-macOS -configuration Debug

# Build for iOS
xcodebuild -scheme VeloFilms-iOS -configuration Debug
```

### First-Time Setup
1. Launch app → Settings
2. Set **Projects Root** (where output projects go)
3. Set **Input Base Dir** (where source MP4s are)
4. Place `yolov8n.mlpackage` in app bundle
5. Configure camera timezone offsets (if using Cycliq)

---

## 📁 Project Structure at a Glance

```
{Projects Root}/
└── {Ride Name}/          # e.g., "2025-04-20-Wahgunyah"
    ├── working/
    │   ├── ride.gpx
    │   ├── flatten.jsonl
    │   ├── extract.jsonl
    │   ├── enriched.jsonl
    │   ├── select.jsonl
    │   └── segments.json
    ├── clips/
    │   ├── clip_0001.mp4
    │   ├── clip_0002.mp4
    │   └── _middle_01.mp4  # segments
    ├── minimaps/
    │   └── minimap_0001.png
    ├── elevation/
    │   └── elev_0001.png
    └── {Ride Name}.mp4     # FINAL OUTPUT
```

---

## 🔄 Pipeline Steps

| Step | Input | Output | What It Does |
|------|-------|--------|--------------|
| **Flatten** | GPX + MP4 metadata | `flatten.jsonl` | Parse GPS + video timings |
| **Extract** | MP4s + flatten | `extract.jsonl` | Sample frames every 5s |
| **Detect** | Frames + YOLO | `enriched.jsonl` | Object detection + GPS match |
| **Select** | Enriched data | `select.jsonl` | Score & pick best clips |
| **Build** | Select + videos | Rendered clips | Composite with HUD overlays |
| **Finalize** | Segments | Final reel | Concat + intro/outro + music |

---

## 🎨 HUD Layout (1920×1080)

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│           MAIN VIDEO (scaled & padded)             │
│                                                     │
├─────────┬────────────────────┬─────────────────────┤
│ GAUGE   │ GAUGE │ GAUGE │ etc. (5 cells @ 194px) │
├─────────┼────────────────────┼─────────────────────┤
│ MINIMAP │                    │          PiP        │
│ 390×390 │  ELEVATION STRIP   │       390×390       │
│         │      948×75        │                     │
└─────────┴────────────────────┴─────────────────────┘
```

**Coordinates** (bottom-left origin in CIImage):
- Gauges: `x=0, y=75`
- Minimap: `x=972, y=75`
- PiP: `x=1370, y=75`
- Elevation: `x=972, y=0`

---

## ⚙️ Key Configuration

### AppConfig.swift (Constants)
```swift
extractIntervalSeconds: 5.0       // Frame sampling rate
clipPreRollS: 0.5                 // Pre-roll before moment
clipOutLenS: 3.5                  // Output clip length
minGapBetweenClips: 10.0          // Temporal spacing
highlightTargetDurationM: 5.0     // Target reel length
xfadeDuration: 0.2                // Crossfade between clips
videoBitrate: 8_000_000           // 8 Mbps H.264
```

### GlobalSettings.swift (User Preferences)
```swift
highlightTargetMinutes            // Override target length
fly12SportOffset / fly6ProOffset  // Camera sync offsets (seconds)
fly12SportTimezone / fly6ProTimezone
musicVolume / rawAudioVolume      // Audio mix levels
```

---

## 🎯 Scoring Algorithm

```swift
scoreWeighted = 
    detectScore    × 0.30   // YOLO confidence
  + sceneBoost     × 0.10   // Scene change detection
  + speedKmh/60    × 0.20   // Normalized speed
  + gradient/8     × 0.20   // Normalized gradient
  + bboxArea/400k  × 0.05   // Detection size
  + segmentBoost   × 0.05   // Start/end zone bonus
  + dualCamera     × 0.10   // Dual-camera bonus
```

**Target Clips**: `(highlightTargetMinutes × 60) / clipOutLenS`  
Default: `(5.0 × 60) / 3.5 ≈ 86 clips`

---

## 🐛 Troubleshooting

### "No video track found"
- Check source MP4 codec (must be H.264 or HEVC)
- Verify file isn't corrupt

### "GPS tolerance exceeded"
- GPX and video timestamps don't align
- Adjust `gpxTimeOffsetS` in Settings
- Check camera timezone configuration

### "YOLO model not found"
- Download `yolov8n.mlpackage` from [source]
- Place in app bundle `Resources/Models/`
- Or specify custom path in code

### Clips out of sync (dual camera)
- Adjust `fly12SportOffset` / `fly6ProOffset`
- Positive = camera is ahead, negative = behind
- Iterate in 0.5s increments

### Memory pressure during build
- Reduce YOLO batch size (`yoloBatchSizeMac` in AppConfig)
- Close other apps
- On iOS: ensure 4GB+ device

---

## 📊 Performance Tips

### Speed Up Analysis
- Use SSD for source videos
- Increase YOLO batch size (if memory allows)
- Parallelize frame extraction (not yet implemented)

### Speed Up Rendering
- Disable PiP if not needed (`pipRow: nil`)
- Reduce output resolution (edit `AppConfig.HUD.outputW/H`)
- Use faster H.264 preset (not yet configurable)

### Reduce Memory
- Lower YOLO batch size
- Process in segments (not yet implemented)
- Clear clip cache between segments

---

## 🔐 Strava Integration

### Setup
1. Create app at [developers.strava.com](https://developers.strava.com)
2. Set callback domain: `localhost`
3. Copy Client ID & Secret
4. Add to `StravaSecrets.swift`:
   ```swift
   enum StravaSecrets {
       static let clientID = "YOUR_CLIENT_ID"
       static let clientSecret = "YOUR_CLIENT_SECRET"
   }
   ```
5. Add URL scheme to Info.plist:
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
       <dict>
           <key>CFBundleURLSchemes</key>
           <array><string>velofilms</string></array>
       </dict>
   </array>
   ```

### Usage
- App auto-authenticates on first segment fetch
- Tokens stored in UserDefaults (⚠️ consider Keychain)
- Auto-refresh before expiry

---

## 🧪 Testing (Example)

```swift
import Testing

@Suite("Pipeline")
struct PipelineTests {
    @Test("Extract creates valid JSONL")
    func extractStep() async throws {
        let project = Project(
            name: "test-ride",
            folderURL: URL(fileURLWithPath: "/tmp/test-ride")
        )
        // Setup sample data...
        let step = ExtractStep()
        try await step.run(project: project, reporter: ProgressReporter())
        
        #expect(FileManager.default.fileExists(atPath: project.extractJSONL.path))
    }
}
```

---

## 🚨 Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `stepNotRegistered` | Pipeline step missing | Check `PipelineExecutor.register()` calls |
| `missingInput` | Prerequisite file missing | Run earlier pipeline step |
| `renderFailed` | AVAssetWriter error | Check disk space, file permissions |
| `noToken` | Strava not authenticated | Tap "Connect Strava" in Settings |

---

## 📱 Platform Differences

| Feature | macOS | iOS |
|---------|-------|-----|
| NavigationSplitView | ✅ | ❌ (uses NavigationStack) |
| YOLO Batch Size | 8 | 4 |
| Background Processing | ❌ | ⚠️ (BGProcessingTask planned) |
| File Picker | NSOpenPanel | UIDocumentPickerViewController |
| Image Loading | NSImage | UIImage |

---

## 🎬 Example Workflow

```swift
// 1. Create project
let project = Project(
    name: "2026-04-29-TestRide",
    folderURL: URL(fileURLWithPath: "~/Projects/2026-04-29-TestRide")
)
try project.createOutputDirectories()

// 2. Add GPX
// Place ride.gpx in working/ folder

// 3. Run pipeline
let executor = PipelineExecutor()
executor.run(.build, project: project)  // Runs all dependent steps

// 4. Result
// Final reel at ~/Projects/2026-04-29-TestRide/2026-04-29-TestRide.mp4
```

---

## 📚 Further Reading

- **README.md**: Full feature overview
- **PLAN.md**: Development roadmap & architecture
- **AUDIT_REPORT.md**: Detailed code review findings
- **AppConfig.swift**: All algorithmic constants
- **EnrichRow.swift**: Data schema reference

---

**Last Updated**: April 29, 2026  
**Version**: 0.9 Beta  
**Build**: ✅ Clean (Swift 6)
