# Velo Films
Mac + iPad + iPhone app (iPad/iPhone = paid App Store product that must meet every App Store requirement, see docs/APP_STORE.md; Mac = owner's personal build, lower bar, uses Homebrew FFmpeg) that turns Cycliq bike-camera footage into a highlight reel: matches clips
to a Strava GPX (or a .gpx file placed in the project), scores them (speed, gradient, YOLO object detection, scene change),
and renders with map, gauge and elevation overlays.

## Build (verified 2026-10-28: iOS and macOS builds and tests OK)
- macOS: `xcodebuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS' build`
- iPad/iOS: `xcodebuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Tests: `xcodebuild test -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS'` (84 tests in `VeloFilms/VeloFilmsTests/`; also passes on the iPhone 17 simulator).

## Layout
- `VeloFilms/VeloFilms/`: app source; `VeloFilms/VeloFilmsTests/`: unit tests (the two folders in the build)
- `VeloFilms/VeloFilms/Shared/ML/`: YOLO model (`VeloYOLO.mlpackage`); `Scripts/`: Python helper (CoreML export)
- See ARCHITECTURE.md for the pipeline and data layout, SECURITY.md for data protection
- `docs/`: screenshots and notes

## Data layer (no SwiftData)
- Project and pipeline state as files on external drives (FileManager, JSONL); settings in
  UserDefaults/@AppStorage. Strava sign-in tokens in the Keychain (`Shared/Core/Security/KeychainStore.swift`).
- Garmin Connect import was removed on 2026-10-25 (unofficial sign-in broke; see SECURITY.md).
- Strava credentials: `VeloFilms/VeloFilms/Shared/Integrations/Strava/Secrets.swift` (gitignored).

## Rules
- The Python scripts in `Scripts/` are build-time tooling (e.g. CoreML export), not a
  runtime backend. (inferred)
- Footage lives on external drives (/Volumes/VDrive, /Volumes/AData). Never delete
  anything there without asking. (inferred from past permission history)
- Build for both macOS and iOS when touching shared code. (inferred)

## Documentation rules (from the 2026-10 review)
- Every file starts with a `//` header (purpose, place in the app); every non-private type, function and property
  gets a `///` comment with Parameters/Returns/Throws where relevant.
- Comments explain why and stay true: update them in the same change as the code. No "Mirrors X.py" without
  saying it refers to the original Python app; no TODOs or AI-style notes.
- Keep README.md, ARCHITECTURE.md and SECURITY.md current when behaviour, structure or data handling changes.
- No secrets in source; sign-in tokens only in the Keychain (`KeychainStore`).
