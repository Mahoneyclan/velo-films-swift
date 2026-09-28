# Velo Films
Mac + iPad app that turns Cycliq bike-camera footage into a highlight reel: matches clips
to a Strava/Garmin GPX, scores them (speed, gradient, YOLO object detection, scene change),
and renders with map, gauge and elevation overlays.

## Build (verified 2026-09-28: iOS and macOS builds OK)
- macOS: `xcodebuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS' build`
- iPad/iOS: `xcodebuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=iOS Simulator,name=iPhone 17' build`
- No test target: `VeloFilmsTests/FocusFilterTests.swift` exists but isn't in any target.

## Layout
- `VeloFilms/VeloFilms/`: app source (the only folder in the build)
- `VeloFilms/VeloFilms v1` … `v6 (osx)`: old snapshots, gitignored. Ignore them.
- `Shared/ML/`: ML model assets; `Scripts/`: Python helpers (CoreML export, Garmin helper)
- `docs/`: screenshots and notes

## Data layer (no SwiftData)
- Project and pipeline state as files on external drives (FileManager, JSONL); settings in
  UserDefaults/@AppStorage. Strava/Garmin tokens also in UserDefaults.
- Strava credentials: `Shared/Integrations/Strava/Secrets.swift` (gitignored).

## Rules
- The Python scripts in `Scripts/` are build-time tooling (e.g. CoreML export), not a
  runtime backend. (inferred)
- Footage lives on external drives (/Volumes/VDrive, /Volumes/AData). Never delete
  anything there without asking. (inferred from past permission history)
- Build for both macOS and iOS when touching shared code. (inferred)
