# Velo Films

Turn your [Cycliq](https://cycliq.com) ride footage into a polished highlight reel, automatically scored and synced to your GPS route — on your Mac or iPad.

Velo Films takes raw MP4 files from a Fly12 Sport (front) and/or Fly6 Pro (rear) camera, matches them against a GPX file from Strava or Garmin, scores every 5-second clip using speed, gradient, YOLO object detection, and scene-change metrics, then assembles the top clips into a highlight reel with a minimap, speed/cadence gauges, elevation strip, and intro/outro splash screens.

## Screenshots

<!-- iPad -->
![iPad pipeline](docs/screenshot-ipad.png)

<!-- macOS -->
![macOS pipeline](docs/screenshot-macos.png)

## Platforms

| Platform | Minimum | Render backend |
|----------|---------|----------------|
| macOS | 26+ | FFmpeg (`brew install ffmpeg`) |
| iPadOS | 26+ | AVFoundation + Metal — no FFmpegKit |

## Workflow

**On iPad:** ride ends → plug cameras into iPad via USB-C hub → Copy from Camera → pipeline runs → share. No Mac required.

**On Mac:** open project → run pipeline → done. Faster rendering, same output.

## Pipeline

| Step | What it does |
|------|-------------|
| **Flatten** | Parse GPX into 5 s trackpoints |
| **Extract** | Pull one frame per clip, read camera timestamps |
| **Enrich** | YOLO detection, GPS overlay, composite scoring |
| **Select** | Rank and pick top clips; manual review UI |
| **Build** | Composite each clip with minimap, gauges, elevation, optional PiP |
| **Splash** | Render intro (map card + collage) and outro |
| **Concat** | Join clips with crossfades + backing music, add intro/outro |

Steps are dependency-aware — running Build from cold runs all prerequisites automatically.

## Setup

1. Install FFmpeg (macOS only): `brew install ffmpeg`
2. On first launch, set two folders in the onboarding wizard:
   - **Projects Root** — where ride project folders are created
   - **Input Videos** — where clips are copied from the SD card
3. In **Settings → Time Sync**, set your camera timezone (e.g. `UTC+10`) to correct Cycliq's UTC bug

## Importing footage

- **Copy from Camera** — plug in the Cycliq SD card; the importer detects cameras, filters to the selected date, and copies clips
- **Strava / Garmin** — downloads GPX, segment efforts, laps, and activity description in one call
- **Drop a `.gpx` file** — drag directly into the project folder

## Requirements

- Xcode 26+
- macOS 26+ or iPadOS 26+
- FFmpeg via Homebrew (macOS only)
- External drive formatted exFAT or APFS (NTFS is read-only on Apple platforms)

## License

Private / all rights reserved.
