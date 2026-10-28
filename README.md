# Velo Films

Turn your [Cycliq](https://cycliq.com) ride footage into a polished highlight reel, automatically scored and synced to your GPS route — on your Mac or iPad.

Velo Films takes raw MP4 files from a Fly12 Sport (front) and/or Fly6 Pro (rear) camera, matches them against a GPX file from Strava, samples the ride every 5 seconds (adjustable) and scores each moment using speed, gradient, YOLO object detection, scene change and Strava segments, then assembles the top clips into a highlight reel with a minimap, speed/cadence gauges, elevation strip, and intro/outro splash screens.

## Screenshots

### macOS
![macOS Main](docs/OSX%20Main.png)
![macOS Fine Tune](docs/OSX%20Fine%20Tune.png)
![macOS Final](docs/OSX%20Final.png)

### iPadOS
![iOS Main](docs/iOS%20Main.png)
![iOS Settings](docs/iOS%20Settings.png)
![iOS AI Settings](docs/iOS%20AI%20Settings.png)

## Platforms

| Platform | Minimum | Render backend |
|----------|---------|----------------|
| macOS | 26+ | FFmpeg (`brew install ffmpeg`) |
| iPadOS | 26+ | AVFoundation + Metal — no FFmpegKit |

The iPad and iPhone version is the App Store product (paid; see [docs/APP_STORE.md](docs/APP_STORE.md)). The Mac version is a personal build (it needs Homebrew FFmpeg and runs
without the App Sandbox, so it can't go on the Mac App Store as is).

## Workflow

**On Mac:** open project → run pipeline → done. Faster rendering, same output.

**On iPad:** ride ends → plug cameras into iPad via USB-C hub → Copy from Camera → pipeline runs → share. No Mac required.

## Pipeline

| Step | What it does |
|------|-------------|
| **Flatten** | Parse the GPX into one point per second, with speed and gradient |
| **Extract** | Build the 5-second sampling grid and match each point to the camera clip that covers it (reads clip timestamps; no frames yet) |
| **Enrich** | Grab a frame at each point; YOLO detection, scene change, GPS telemetry, composite scoring |
| **Select** | Pick the best moments spread across the whole ride (no picks while stopped, gap between picks grows with ride length, always one from the first and last 5 minutes); review and change picks on the **Fine Tune** screen |
| **Build** | Composite each clip with minimap, gauges, elevation, optional PiP |
| **Splash** | Render intro (map card + collage) and outro |
| **Concat** | Join clips with crossfades + sequenced backing music (plays through the library rather than looping one track), music fades out before the outro; add intro/outro |

Steps are dependency-aware — running Build from cold runs all prerequisites automatically.
See [ARCHITECTURE.md](ARCHITECTURE.md) for how each step works and which files it reads and writes.

## Setup

1. Install FFmpeg (macOS only): `brew install ffmpeg`
2. On first launch, set two folders in the onboarding wizard:
   - **Projects Root** — where ride project folders are created
   - **Input Videos** — where clips are copied from the SD card
3. In **Settings → Time Sync**, set your camera timezone (e.g. `UTC+10`) to correct Cycliq's UTC bug

## Importing footage

- **Copy from Camera** — plug in the Cycliq SD card; the importer detects cameras, filters to the selected date, and copies clips
- **Strava** — downloads the ride's GPX, segment efforts, laps, and activity description
- **Your own `.gpx` file** — save it as `working/ride.gpx` inside the project folder (the project screen looks for that name)

## Backing music

Every build (Mac, iPhone, iPad) includes 8 royalty-free tracks plus intro/outro music, for personal use and
friends via TestFlight. Their licences don't cover a public App Store release. Add your own in **Settings → Audio**:

- **Music Folder (easiest):** tap **Choose Music Folder…** and pick any folder, for example in iCloud Drive, Dropbox or
  Google Drive. Every song in it is used, and songs you add to it later (from any device) appear automatically.
  Cloud songs are downloaded when a reel is built.
- **Added Songs:** **Add Music…** copies single MP3/M4A/AAC/WAV files into the app. On the Mac they live in
  `~/Music/Velo Films/` (**Show in Finder** opens it).

Your songs join any built-in ones in each project's track picker and in the reel's playlist. If **Single Track
Override** is set, that one file plays instead of the library. Use only music you have the rights to use in your videos.

## Requirements

- Xcode 26+
- macOS 26+ or iPadOS 26+
- FFmpeg via Homebrew (macOS only)
- External drive formatted exFAT or APFS (NTFS is read-only on Apple platforms)

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md): code layout, pipeline, data storage, platform differences
- [SECURITY.md](SECURITY.md): what data the app holds, how it is protected, known risks
- `docs/review/PROGRESS.md` and `docs/scorecards/`: code review scores and open items

## Development

- Build (macOS): `xcodebuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS' build`
- Build (iPad simulator): `xcodebuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Strava credentials go in `VeloFilms/VeloFilms/Shared/Integrations/Strava/Secrets.swift` (gitignored; never commit it).
- Tests (64, in `VeloFilms/VeloFilmsTests/`): `xcodebuild test -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS'` (or the iPhone 17 simulator destination).

## License

Private / all rights reserved.
