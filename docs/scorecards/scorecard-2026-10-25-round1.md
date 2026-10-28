# Velo Films — Engineering Scorecard, Round 1 (baseline)

- **Date:** 2026-10-25
- **Commit scored:** `0eb1729` (main). The working tree also had local changes to `bookmarks.plist` and an untracked `xcuserdata/`, neither of which affects the source.
- **Scope:** `VeloFilms/VeloFilms/` (the only folder in the build): 59 Swift files. `Secrets.swift` was excluded and **not read**, because reading it was denied. Also reviewed: `Scripts/`, `VeloFilmsTests/`, the repo docs and the full git history.
- **Reviewer stance:** independent and strict. The code was scored as it is today, not on intent.

## Overall

| | Score |
|---|---|
| **Overall** | **31.6 / 100 — Grade F** |
| Code subtotal | 19.8 / 60 |
| Documentation subtotal | 11.8 / 40 |

The build-failure cap does not apply, because both platforms build. The Critical-security cap **does apply**: Security is capped at 2/10.

## Scorecard

| # | Category | Weight | Score /10 | Weighted | Reason (evidence in the appendix) |
|---|---|---|---|---|---|
| 1 | Correctness & robustness | 12% | 5 | 6.0 | Builds clean, with 0 `try!`, 0 `as!`, 0 `fatalError` and 1 `preconditionFailure` (StravaAuth.swift:143). Against that: 52 force-unwraps, mostly on framework calls that can return nil (`addMutableTrack(...)!`, `CGContext(...)!`, `cgImage!`, `makeImage()!`). There are 108 `try?`, several of which silently drop user data (ManualSelectionView.swift:442). Real logic bugs exist: a setting that is never loaded (GlobalSettings.swift:125-138 vs :178), a volume of 0 that cannot persist (:118-121), projects lost when a drive is unplugged (Project.swift:131), and delete-then-copy (CopyVideosView.swift:383-386). |
| 2 | Architecture & structure | 10% | 4 | 4.0 | Good bones: a `PipelineStep` protocol, an `FFmpegBridge` protocol, Codable row models and an executor. But 7 files are over 300 lines (ManualSelectionView.swift has 1190) and 42 of 293 functions are over 40 lines (the longest is 158). Views hold business rules: file deletion and step registration in ProjectDetailView.swift:159-168 and :352-380, a duplicate scoring formula in ManualSelectionView.swift:1148-1156, and the copy engine in CopyVideosView.swift:322-425. Logic is duplicated (`AuthPreservingDelegate` twice, reanchor logic twice, default values repeated in Reset buttons). The singleton `GlobalSettings.shared` is referenced 64 times. 112 `UserDefaults.standard` references use string-literal keys. |
| 3 | Swift & SwiftUI idioms | 8% | 5 | 4.0 | Modern APIs are used: `@Observable` (5 uses, 0 `ObservableObject`), async/await, value types (106 structs, 14 classes) and `private` (371 uses). Weak points: about 28 unused declarations (dead code), 23 untyped `JSONSerialization`/`[String: Any]` uses (StravaClient.swift:56-107), snake_case Swift properties (GarminAuth.swift:41-50), `extension_` (ExtractStep.swift:27), `_FolderPickerRepresentable`, several statements per line with `;`, and no explicit access control on internal API. |
| 4 | Concurrency & performance | 8% | 3 | 2.4 | `SWIFT_VERSION = 5.0` (pbxproj:307, :370), and `SWIFT_STRICT_CONCURRENCY` is not set, so checking is minimal. This breaks the owner's Swift 6 standard. Because `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (pbxproj:304), every pipeline step's `run` is main-actor isolated, so the `Task.detached` in PipelineExecutor.swift:37 does **not** move the heavy work (YOLO, frame and file I/O) off the main actor. `ClipVideoCompositor` (VideoCompositor.swift:52) is also implicitly `@MainActor`, yet AVFoundation calls it on its own queues. There is 1 `@unchecked Sendable` (FFmpegBridge.swift:38). Positives: async stderr draining, `AsyncStream` progress reporting and no semaphores. |
| 5 | Security & privacy | 12% | **2 (capped)** | 2.4 | **Critical:** the Strava client secret is compiled into app binaries committed to a **public** GitHub repo (commit 35f66b5), and the same value is still in today's build, so it was never rotated. High: OAuth tokens and the Garmin OAuth1 secret sit in plaintext UserDefaults; the Garmin flow collects the user's password, impersonates Garmin's own mobile app and tells users to turn off MFA; bearer tokens are re-sent to any redirect host. There is no privacy manifest, no Keychain use, no file protection, and the macOS sandbox is off. |
| 6 | Testing | 10% | 1 | 1.0 | No test target. `xcodebuild -list` shows one target and `xcodebuild test` fails: "Scheme VeloFilms is not currently configured for the test action." `VeloFilmsTests/FocusFilterTests.swift` (337 lines, 25 test functions) is in no target and has never run. **No tests ran.** |
| 7 | Doc-comment coverage | 12% | 2 | 2.4 | **116 / 659 non-private declarations documented = 17.6 %.** 0 of 59 files have a `//` header comment. 14 files are at 0 %, including GarminAuth (0/24) and StravaClient (0/17). |
| 8 | Doc-comment quality | 10% | 4 | 4.0 | The best comments explain *why* (FrameSampler.swift:19-25 and :37-38, FocusFilter.swift:97-103, SelectRow.swift:3-7 and :19-21, FFmpegBridge.swift:33-37). But there are **0** `- Parameters:` / `- Returns:` / `- Throws:` tags anywhere, no threading notes, and about 40 comments that point at Python files not in this repo ("Mirrors enrich.py"). Many are one-line restatements. |
| 9 | Accuracy | 8% | 3 | 2.4 | 0 TODO/FIXME/HACK. **19 specific comment/doc mismatches** are listed below, plus a 40-instance class of references to Python modules that don't exist in the repo. Several mislead on important points: the threading comment, the bookmark-persistence comment, "weights should sum to 1.0", and a menu path ("Settings → Camera Calibration") that doesn't exist. |
| 10 | Project docs | 10% | 3 | 3.0 | README.md and CLAUDE.md exist, and CLAUDE.md is accurate. **ARCHITECTURE.md and SECURITY.md are missing.** README has 4 factual errors. `Shared/Steps/Build/README.md`, `PLAN.md` and `QUICKSTART.md` are stale (they claim macOS 14, iOS 17 and Swift 6) and get copied into the app bundle. DocC builds with 0 warnings, but there is no catalog and coverage is 17.6 %. |
| | **Code subtotal** | 60% | | **19.8** | |
| | **Documentation subtotal** | 40% | | **11.8** | |
| | **Total** | 100% | | **31.6** | **Grade F** |

## Key metrics

| Metric | Value | Method |
|---|---|---|
| Swift files (in build, excluding Secrets.swift) | 59 | `swift_metrics.py` (appendix) |
| Lines (total / non-blank, non-comment) | 10,526 / 8,596 | same |
| Doc-comment coverage | 116 / 659 = **17.6 %** | same: type-scope non-private decls with `///` directly above |
| Files with a `//` header | 0 / 59 | first non-blank line starts with `//` |
| Tests | 0 run (no test target); 25 orphan test functions in 1 file | `xcodebuild -list`, `xcodebuild test` |
| Force-unwraps `!` | 52 | regex on code with strings and comments blanked: `!` after identifier/`)`/`]`/`}` and not followed by `=`. Excludes `!=` and prefix `!x`; includes 1 IUO declaration (ProgressReporter.swift:19) |
| `try!` / `as!` / `fatalError` / `preconditionFailure` | 0 / 0 / 0 / 1 | same script |
| `try?` | 108 | `grep -o 'try?'` over the concatenated sources |
| TODO/FIXME/HACK/XXX | 0 | comment text only |
| `print`/`NSLog` | 5 (ConcatStep.swift:212, :282, :430; IntroBuilder.swift:237, :251), none behind `#if DEBUG` | script |
| Files > 300 lines | 7 (1190, 790, 525, 474, 442, 440, 438) | `wc -l` |
| Functions > 40 lines | 42 of 293 (longest: GlobalSettingsView.swift:366 `body`, 158 lines) | brace matching from `func`/`init`/`some View {` lines |
| Unused declarations (approx.) | about 28 real (35 candidates, of which 7 are protocol requirements or `@main`) | `unused_symbols.py` |
| Build warnings, macOS | **0 Swift warnings**; 1 tool notice (`appintentsmetadataprocessor: Metadata extraction skipped`) | clean build, `grep 'warning:' \| sort -u` |
| Build warnings, iOS Simulator | **0 Swift warnings**; 1 tool notice (same) | same |
| DocC (`xcodebuild docbuild`) | **Succeeded, 0 doc warnings** (same 1 tool notice) | same |
| Security findings | **Critical 1 · High 4 · Medium 8 · Low 8** | manual review |

## Change since last scorecard

None (baseline).

## Security findings

| Severity | File:line | Issue | Impact (plain English) | Fix | Effort |
|---|---|---|---|---|---|
| **Critical** | git history: commit `35f66b5` (2026-05-24) → `VeloFilms/VeloFilms v1…v4/VeloFilms.app/Contents/MacOS/VeloFilms`. Removed from the tree in `6961aa6`, but still in history on `origin/main`. | Four compiled app binaries containing a 40-hex-character string (`c0ff…`, the Strava client-secret format) were committed to a **public** GitHub repo (`gh repo view` → `PUBLIC`). The same string is in today's Debug build (`VeloFilms.debug.dylib`), so it is still the live secret. It wasn't found in any tracked source, so it comes from the gitignored `Secrets.swift` (not read). | Anyone can download the history, pull out the secret and pose as Velo Films to Strava: abuse your API quota or rate limits, phish users with a real-looking consent screen, or get the app's API access revoked. | **Today:** regenerate the client secret in the Strava API settings. Then purge the binaries from history (`git filter-repo`, needs your explicit OK, then force-push) and ask GitHub to clear cached views. Longer term: do the token exchange on a server. | S (rotate) / M (purge) |
| High | StravaAuth.swift:19-20, :57-59, :118-119 | The client secret ships inside the app and is sent from the device on every token exchange and refresh. | Any copy of the app can be unpacked to recover the secret (`strings` found it in seconds). Moving it to `.xcconfig` would not fix this. | Use a small token-exchange proxy (server-side secret), or Strava's PKCE flow if they support it. Until then, document the risk in SECURITY.md. | M–L |
| High | StravaAuth.swift:25-36; GarminAuth.swift:180, :391-399 | Strava access and refresh tokens, Garmin OAuth1 token **and secret**, Garmin OAuth2 access and refresh tokens, and the Garmin e-mail are stored in **UserDefaults** (a plain plist on disk, included in backups). | Anyone with file or backup access gets long-lived access to the user's Strava and Garmin accounts, including their GPS history. | Store them in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Migrate the existing values, then delete the UserDefaults keys. | M |
| High | GarminAuth.swift:79-80, :114-182, :336, :403-412; GarminImportView.swift:73-105; GarminAuth.swift:15 | The Garmin sign-in collects the user's **password** in-app. It impersonates Garmin's Android/iOS app (`GCM_ANDROID_DARK`, spoofed User-Agents) and downloads the OAuth consumer key and secret at runtime from a third-party S3 bucket (`thegarth.s3.amazonaws.com`) with no integrity check. It also tells users to **disable MFA**. | It weakens users' account security, likely breaks Garmin's terms, is very likely to be rejected by App Review, and trusts a stranger's bucket to supply signing credentials. | Use the official Garmin Connect Developer Program OAuth, or file import (FIT/GPX share sheet). Remove the password flow and the MFA advice. | L |
| High | StravaClient.swift:173-187; GarminClient.swift:76-91 | `AuthPreservingDelegate` re-attaches `Authorization: Bearer <token>` to **every** redirect, whatever the host or scheme. | If a redirect goes to a CDN, signed-URL host or plain-http address, the user's access token is sent to that third party. | Re-add the header only when `newRequest.url?.scheme == "https"` and the host is on an allow-list (`*.strava.com`, `connectapi.garmin.com`). Otherwise follow the redirect without auth (signed URLs don't need it). | S |
| Medium | StravaAuth.swift:70-106 | The OAuth request has no `state` parameter and the callback isn't checked against one. The custom scheme `velofilms://` can be registered by any other app. | Login CSRF or code injection: an attacker could link the user's app to the attacker's Strava account. | Generate a random `state`, check it on callback, and set `prefersEphemeralWebBrowserSession` deliberately. | S |
| Medium | StravaAuth.swift:61-62, :122-123; all `URLSession.shared` calls | The token exchange and refresh ignore the HTTP status and decode whatever comes back. No request sets a timeout (default 60 s request / 7-day resource). Nothing is retried. | Errors become confusing decode failures, and a stalled network hangs the import UI for a long time. | Check the status code (map 401 to re-login), set `timeoutInterval` or a configured session, and retry only transient errors. | S |
| Medium | (missing) `PrivacyInfo.xcprivacy` | No privacy manifest. Required-reason APIs are in use: UserDefaults (112 refs, CA92.1); file timestamps via `.contentModificationDateKey` (CopyVideosView.swift:338-345); file size and attributes (CopyVideosView.swift:378, ConcatStep.swift:103). | App Store submission will be rejected or warned, and App Privacy answers can't be justified. | Add PrivacyInfo.xcprivacy declaring CA92.1, C617.1/DDA9.1 and collected data (precise location, fitness). | S |
| Medium | StravaClient.swift:58, :72, :89, :106; GarminClient.swift:59; JSONLWriter.swift:13 | GPS tracks (home and work locations), heart rate and ride descriptions are written with no file protection class and no backup exclusion. | On a lost or shared iPad, or in an unencrypted Mac backup, a full location history reveals where the user lives. | Write with `.completeFileProtectionUntilFirstUserAuthentication` on iOS. Document in SECURITY.md. Consider `isExcludedFromBackup` for working files. | S |
| Medium | GarminAuth.swift:194-200; StravaAuth.swift:108-110 | Sign-out deletes local tokens only. It doesn't revoke on the server (Strava `/oauth/deauthorize`) and doesn't clear the SSO cookies held by `ssoSession`. There is no "Delete all my data". | Users can't fully withdraw, tokens stay valid on the server, and it breaks the owner's standard. | Add server revocation, cookie clearing and a "Delete all my data" action (settings, Keychain, project list, caches). | M |
| Medium | MinimapRenderer.swift:23-50; IntroBuilder.swift:298-320; StravaImportView/GarminImportView | No consent or disclosure before personal data goes to third parties: route coordinates to Apple (MKMapSnapshotter), tokens and activity data to Strava and Garmin (US), and the IP address to the garth S3 bucket. | It breaks the owner's consent standard and App Privacy accuracy. | Add a one-time consent screen naming each company and country, which the user can withdraw. Fall back to the offline minimap. | M |
| Medium | project.pbxproj:260-264, :323-327; signed entitlements show `network.server = true`, no sandbox | The macOS App Sandbox is disabled, the incoming-network (server) entitlement is on but unused (0 listener code), and Downloads has read-write access. The `.entitlements` files are unused (`CODE_SIGN_ENTITLEMENTS` not set). | A compromised dependency or input file runs with full user privileges, and Mac App Store distribution is impossible. | Enable the sandbox, remove the server and Downloads entitlements, wire in or delete the `.entitlements` files. Use security-scoped bookmarks with `.withSecurityScope`. | M |
| Medium | GarminAuth.swift:150, :157, :233, :270; PipelineExecutor.swift:124 → ProjectDetailView.swift:39 | Raw server bodies (the OAuth1 error includes the full response body, which may contain token material) and the full FFmpeg stderr reach the UI. | It leaks internal detail and possibly secrets into screenshots or support e-mails, and it's poor UX. | Show a plain message; put the detail behind a "Details" disclosure, redacted. | S |
| Low | StravaClient.swift:152-153 | The activity name is inserted into GPX XML without escaping. | A ride named `A & B` or one containing `<` produces an invalid GPX, and Flatten fails. | XML-escape `& < > " '`. | S |
| Low | GPXParser.swift:108-123 | Resampling loops once per second from the first to the last timestamp with no limit. | A corrupt or hostile GPX (one point dated 1970) makes billions of points, so memory runs out or the app hangs. | Reject spans over about 48 h, or clamp. | S |
| Low | FFmpegBridge.swift:22-27 | `ffmpeg` is resolved through `/usr/bin/env` with user-writable Homebrew folders first on PATH. The binary is unpinned and unverified. (Positive: arguments are passed as an array, so there's no shell injection, and file paths are separate `-i` args.) | A planted `ffmpeg` in `/opt/homebrew/bin` runs with app privileges. | Resolve an absolute path once, check its signature and version, and show it in Settings. | S |
| Low | ConcatStep.swift:212, :282, :430; IntroBuilder.swift:237, :251 | `print()` in Release builds logs ride file names and bundle paths. | Minor personal-data leak to the console. | Use `os.Logger` with `privacy: .private`, or `#if DEBUG`. | S |
| Low | Scripts/garmin_helper.py:6-10, :26-28 | Takes the Garmin password as a command-line argument (visible in `ps` and shell history). Not used by the app. | Credential exposure on the dev machine. | Delete the script, or read the password from stdin or the Keychain. | S |
| Low | FilePickerBridge.swift:44; GlobalSettings.swift:221 | `startAccessingSecurityScopedResource()` is never balanced by a stop call. | Leaks kernel resources over a long session. | Pair with `stopAccessing…` or keep one scoped-access owner. | S |
| Low | VeloFilms/VeloFilms/Shared/Resources/music/ (built app Resources) | The gitignored commercial tracks "The White Stripes - Seven Nation Army.mp3" and "Can't Stop.mp3" (plus PLAN.md, README.md, QUICKSTART.md) are copied into the app bundle by the synchronized folder. | Licensing and compliance risk if a build is distributed, plus internal docs ship to users. | Exclude them from the target (build-phase membership exceptions) or move them out of the synced folder. | S |
| Low | VeloFilms.xcodeproj/project.xcworkspace/xcuserdata/… (tracked) | User-specific Xcode files are tracked despite `.gitignore`. | Leaks local paths and creates noisy diffs. | `git rm --cached` (with your OK). | S |

Checklist items with **no finding**: WebViews (0 `WKWebView`); AI/LLM providers (0 references to anthropic, openai or gemini, so no AI output handling); clipboard (0 uses); deep links (no `onOpenURL`); ATS (no exceptions; all endpoints https; the two `http://` strings are XML namespace URIs, StravaClient.swift:150-151); certificate validation (no challenge handlers); SPM/CocoaPods (none, no Package.resolved); debug menus or test accounts (none; 0 `#if DEBUG`).

## Documentation gaps by file (worst first)

Coverage is documented / non-private declarations at type scope. No file has a `//` header.

| File | Lines | Documented | Notes |
|---|---|---|---|
| Shared/Integrations/Garmin/GarminAuth.swift | 440 | 0 / 24 | Security-critical; no docs on the sign-in, token lifetimes or threading |
| Shared/Integrations/Strava/StravaClient.swift | 188 | 0 / 17 | Public API (`recentActivities`, `downloadGPX`, `downloadActivityDetails`) undocumented |
| Shared/Views/Selection/ManualSelectionView.swift | 1190 | 0 / 5 | Largest file, holds the scoring rule duplicate |
| Shared/Views/Pipeline/PipelineView.swift | 131 | 0 / 4 | Unused view |
| Shared/Views/Import/CopyVideosView.swift | 438 | 0 / 3 | Holds the copy engine |
| Shared/Views/Main/ProjectDetailView.swift | 442 | 0 / 3 | |
| Shared/Views/Settings/GlobalSettingsView.swift | 790 | 0 / 2 | |
| Shared/App/VeloFilmsApp.swift, Core/FileManager/JSONLReader.swift, JSONLWriter.swift, Views/Import/ImportView.swift, Views/Main/ContentView.swift, ProjectListView.swift, Views/Settings/OnboardingView.swift | — | 0 % each | |
| Shared/Core/Models/EnrichRow.swift | 78 | 1 / 34 | 28 schema fields have no units or meaning |
| Shared/Core/Models/AppConfig.swift | 200 | 4 / 98 | 94 magic constants with no rationale |
| Shared/Integrations/Garmin/GarminClient.swift | 91 | 1 / 18 | |
| Shared/Core/Models/ExtractRow.swift | 33 | 1 / 15 | |
| Shared/Core/Pipeline/PipelineExecutor.swift | 127 | 1 / 13 | Threading comment is wrong (see below) |
| iPadOS/FilePickerBridge.swift | 89 | 1 / 13 | |
| Shared/Core/Models/Project.swift | 158 | 4 / 42 | |
| Shared/Core/Config/GlobalSettings.swift | 260 | 9 / 47 | |

The full per-file table is in Appendix A.

Missing project docs: **ARCHITECTURE.md**, **SECURITY.md**, a DocC catalog and file headers in all 59 files.

## Misleading or stale comments and docs (full list)

1. **PipelineExecutor.swift:31-33.** Says detaching "runs on the cooperative thread pool — … never block the UI thread". In fact `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (pbxproj:304) makes `PipelineStep.run` and every step struct main-actor isolated, so the work hops back to the main actor.
2. **FFmpegBridge.swift:5.** "iPadOS: placeholder (FFmpegKit would go here…)". No iPadOS placeholder exists; `makeBridge()` is macOS-only (lines 74-78).
3. **FFmpegBridge.swift:36-37 and VideoCompositor.swift:56.** Say they satisfy "Swift 6 concurrency rules" or "requirement in Swift 6". The project compiles in Swift 5 mode (`SWIFT_VERSION = 5.0`).
4. **VideoEncoder.swift:7.** "Replaces FFmpegBridge for all render operations." On macOS, ClipCompositor (ClipCompositor.swift:6, :65-93) and ConcatStep (:151-289) still render with FFmpegBridge.
5. **GlobalSettings.swift:71.** "Score weights (should sum to 1.0)". The defaults in lines 72-77 sum to **0.95**. The Reset button (GlobalSettingsView.swift:492) uses 0.35 for detect, so the defaults conflict.
6. **GlobalSettings.swift:87.** "Minimum person+bicycle detection count". The rule is `max(person, bicycle)`, not a sum (FocusFilter.swift:97-103).
7. **GlobalSettings.swift:205-206.** ".withSecurityScope is macOS-only…". This implies macOS uses security scope, but the options are `[]` on both platforms (lines 207-208).
8. **FilePickerBridge.swift:4-6.** "The resolved URL is persisted as a security-scoped bookmark". `DrivePickerView` throws the bookmark away (`_ = bookmark`, line 84). The doc block also merges two different types' descriptions (lines 4-8).
9. **FilePickerBridge.swift:84.** "caller stores this; see GlobalSettings.inputBaseDirBookmark". No such property exists (it's a UserDefaults key string), and the caller never receives the bookmark.
10. **ScoreCalculator.swift:4.** "weight constants from AppConfig.ScoreWeights". They're user-tunable settings read from GlobalSettings (AppConfig.swift:47-55).
11. **AppConfig.swift:4-6.** "All values are constants matching the Python source. User-overridable settings are in GlobalSettings". AppConfig itself exposes dynamic user settings (`ScoreWeights`, `candidateFraction`, `CameraName.timezoneIdentifier`, `knownOffset`, AppConfig.swift:47-58 and :71-86).
12. **AppConfig.swift:82.** "Reads from GlobalSettings (Camera Calibration)". No such settings section; the tab is "Time Sync" (GlobalSettingsView.swift:26).
13. **ExtractStep.swift:128, :131, :138 (user-facing messages).** Point to "Settings → Camera Calibration", which doesn't exist (the tab is "Time Sync").
14. **ExtractStep.swift:5.** "global 5s grid". The interval is user-configurable (`effectiveExtractInterval`, line 30).
15. **ProjectFileManager.swift:3.** "Creates and **validates** the project directory structure". It does no validation.
16. **README.md "Pipeline" table, Flatten.** "Parse GPX into 5 s trackpoints". The code resamples to **1 Hz** (GPXParser.swift:16, FlattenStep.swift:4).
17. **README.md, Extract.** "Pull one frame per clip". Extract builds one row per grid point per clip and reads no frames (ExtractStep.swift:53-98).
18. **README.md "Importing footage".** "Strava / Garmin — downloads GPX, segment efforts, laps, and activity description in one call". Garmin downloads only the GPX (GarminClient.swift:54-60), and Strava takes two requests (StravaClient.swift:54, :66).
19. **Shared/Steps/Build/README.md.** Claims "macOS 14.0+", "iOS 17.0+" and "Built with Swift 6". The project targets 26.0 (pbxproj:291, :294) in Swift 5 mode. PLAN.md and QUICKSTART.md in the same folder are equally stale and are bundled into the app.

Plus one **class of misleading references: about 40 comments say "Mirrors X.py"** (e.g. PipelineExecutor.swift:6, GlobalSettings.swift:4, EnrichStep.swift:6, GPXParser.swift:17, ScoreCalculator.swift:4, SegmentMatcher.swift:4, ClipCompositor.swift:6, GaugeRenderer.swift:11, :187). Those Python modules aren't in this repo (`Scripts/` only has export_coreml.py and garmin_helper.py), so maintainers can't check them. The full list is in Appendix D.

No TODO/FIXME/HACK/XXX, no commented-out code, and no AI-style notes ("Updated to fix…") were found.

## Bugs noticed (outside docs and security)

1. **GlobalSettings.swift:125-138.** `yoloWeightPedestrian` is saved (:178) but never loaded, so the user's pedestrian weight resets to 0.3 on every launch.
2. **GlobalSettings.swift:118-121.** `musicVolume` and `rawAudioVolume` load through `.nonZero`, so a user who sets 0 (mute) gets the default back next launch. These "0–1" fields (GlobalSettingsView.swift:593-597) also aren't clamped.
3. **Project.swift:131.** `ProjectStore.load()` drops projects whose folder isn't mounted. The next `add`/`remove` calls `save()` (:102, :108), which **permanently erases** those projects from the list whenever the external drive is unplugged.
4. **CopyVideosView.swift:383-386.** Deletes the existing destination file *before* copying. If the copy fails (card pulled, disk full), the old copy is lost. It also overwrites without asking.
5. **ManualSelectionView.swift:442.** `try? JSONLWriter().write(...)`: the user's manual selections are silently lost if the write fails.
6. **ManualSelectionView.swift:1148-1156.** The score-breakdown bar re-implements the scoring formula differently from ScoreCalculator.swift:16-27: no "moving ≥ 1 km/h" gate on gradient, and extra clamping. What's displayed can differ from the real score.
7. **GlobalSettings.swift:72 vs GlobalSettingsView.swift:492.** Default detect weight 0.30 vs Reset value 0.35. Two sources of truth.
8. **ProjectDetailView.swift:159-168.** "Re-run" deletes the Enrich and Select outputs with no confirmation. **ProjectListView.swift:14-25** labels the same action "Delete" and "Remove from list", also with no confirmation.
9. **StravaAuth.swift:61-62, :122-123.** A Strava error response (e.g. 400 invalid code) shows up as a JSON decoding error instead of a clear message.
10. **GarminAuth.swift:261-263.** The form body isn't percent-encoded. An `mfa_token` with reserved characters would break the request.
11. **GarminAuth.swift:97, :109.** The condition `!(oauth2Token?.isExpired == false)` is redundant inside the guard's else branch; `_ = t` is dead.
12. **StravaAuth.swift:133.** `NSApp.keyWindow ?? NSWindow()` anchors the auth sheet to an off-screen window when no key window exists.
13. **ProjectDetailView.swift:352-354.** If the YOLO model is missing, the steps get `/dev/null` as the model URL, which defers a clear failure to an opaque Core ML error.
14. **VideoCompositor.swift:52-80.** `ClipVideoCompositor` is implicitly `@MainActor` (default isolation), but AVFoundation calls `startRequest` on its own queue. The `lazy var ciContext` is set up without synchronisation, which is a data race.
15. Dead code, about 28 symbols, e.g. `PipelineView` (PipelineView.swift:3), `DrivePickerView` (FilePickerBridge.swift:55), `ProjectFileManager.discoverProjects` (:22), `GaugeRenderer.renderFrames` (:27), `Project.finalConcatList` (:37), `ProjectArtifacts.analysisReady` (:66), `GlobalSettings.isDualCamera` (:204), `ProjectPreferences.effectiveTargetClips` (:39), and 18 constants in AppConfig.swift (:9, :30, :38-42, :110-152, :184-189).

---

## Appendix A — Per-file metrics (output of `swift_metrics.py`)

Columns: path, lines, documented/declarations, %, header (Y/n), force-unwraps, TODOs.

```
files=59 lines=10526 code_lines=8596
headers=0/59
force_unwrap=52 try!=0 as!=0 fatalError=0 preconditionFailure=1 precondition=0 print/NSLog=5
TODO/FIXME/HACK/XXX=0
doc_coverage=116/659 = 17.6%  (/// lines total=283)
files_over_300=7
    1190 Shared/Views/Selection/ManualSelectionView.swift
     790 Shared/Views/Settings/GlobalSettingsView.swift
     525 Shared/Steps/Splash/IntroBuilder.swift
     474 Shared/Steps/Concat/ConcatStep.swift
     442 Shared/Views/Main/ProjectDetailView.swift
     440 Shared/Integrations/Garmin/GarminAuth.swift
     438 Shared/Views/Import/CopyVideosView.swift
functions_total=293 functions_over_40=42
    158 Shared/Views/Settings/GlobalSettingsView.swift:366  var body: some View {
    128 Shared/Steps/Extract/ExtractStep.swift:17  func run(project: Project, reporter: ProgressReporter) async throws {
    125 Shared/Views/Selection/ManualSelectionView.swift:161  var body: some View {
    117 Shared/Steps/Enrich/EnrichStep.swift:21  func run(project: Project, reporter: ProgressReporter) async throws {
    113 Shared/Views/Selection/ManualSelectionView.swift:997  var body: some View {
    104 Shared/Views/Import/CopyVideosView.swift:322  private func runCopy(destBase: URL) async {
    100 Shared/Views/Settings/ProjectPreferencesView.swift:11  var body: some View {
     96 Shared/Steps/Select/ClipSelector.swift:18  static func select(moments: [PartnerMatcher.Moment], config: Config = 
     96 Shared/Steps/Concat/ConcatStep.swift:14  func run(project: Project, reporter: ProgressReporter) async throws {
     92 Shared/Steps/Build/BuildStep.swift:17  func run(project: Project, reporter: ProgressReporter) async throws {
     91 Shared/Views/Selection/ManualSelectionView.swift:490  var body: some View {
     88 Shared/Views/Selection/ManualSelectionView.swift:322  private func load() async {
     76 Shared/Views/Import/CopyVideosView.swift:126  private var setupView: some View {
     76 Shared/ML/YOLOInference.swift:144  private func decodeYOLO(_ raw: MLMultiArray) -> [YOLODetection] {
     74 Shared/Steps/Select/SelectStep.swift:15  func run(project: Project, reporter: ProgressReporter) async throws {
     69 Shared/Integrations/Garmin/GarminAuth.swift:114  func signIn(email: String, password: String) async throws {
     67 Shared/Video/VideoCompositor.swift:77  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
     66 Shared/Views/Main/ProjectDetailView.swift:26  var body: some View {
     61 Shared/Views/Main/ProjectListView.swift:8  var body: some View {
     61 Shared/Core/Config/GlobalSettings.swift:96  private init() {
     58 Shared/Views/Import/GarminImportView.swift:55  private var loginForm: some View {
     58 Shared/Core/Pipeline/PipelineExecutor.swift:25  func run(_ stepName: StepName, project: Project) {
     57 Shared/Views/Settings/GlobalSettingsView.swift:15  var body: some View {
     54 Shared/Views/Selection/ManualSelectionView.swift:863  var body: some View {
     53 Shared/Video/FFmpegBridge.swift:16  func execute(arguments: [String]) async throws {
     52 Shared/Views/Settings/GlobalSettingsView.swift:248  var body: some View {
     51 Shared/Views/Settings/GlobalSettingsView.swift:307  var body: some View {
     51 Shared/Views/Selection/ManualSelectionView.swift:646  var body: some View {
     51 Shared/Views/Pipeline/PipelineView.swift:8  var body: some View {
     51 Shared/Steps/Flatten/GPXParser.swift:103  private func resample(_ raw: [RawPoint]) -> [GPXPoint] {
     47 Shared/Views/Import/ImportView.swift:11  var body: some View {
     47 Shared/Integrations/Strava/StravaClient.swift:112  private func buildGPX(from streams: [String: Any], startDate: Date, ac
     46 Shared/Views/Main/ProjectDetailView.swift:95  private var step1SetUp: some View {
     46 Shared/Views/Import/GarminImportView.swift:117  private var activityList: some View {
     45 Shared/Core/Models/SelectRow.swift:87  init(from decoder: Decoder) throws {
     45 Shared/Core/Config/GlobalSettings.swift:158  func save() {
     44 Shared/Views/Settings/GlobalSettingsView.swift:531  var body: some View {
     43 Shared/Core/Models/SelectRow.swift:133  func encode(to encoder: Encoder) throws {
     42 Shared/Views/Main/ProjectDetailView.swift:400  var body: some View {
     42 Shared/ML/YOLOInference.swift:66  func detect(image: CGImage) throws -> (detections: [YOLODetection], de
     42 Shared/Integrations/Garmin/GarminAuth.swift:240  private func exchangeOAuth2(oauth1: GarminOAuth1Token, forLogin: Bool)
     41 Shared/Views/Settings/GlobalSettingsView.swift:143  var body: some View {

per-file: lines | docs/decls | % | header | force! | todo
  Shared/Integrations/Garmin/GarminAuth.swift               440   0/24    0.0% n   3 0
  Shared/Integrations/Strava/StravaClient.swift             188   0/17    0.0% n   0 0
  Shared/Views/Selection/ManualSelectionView.swift         1190   0/5     0.0% n   2 0
  Shared/Views/Pipeline/PipelineView.swift                  131   0/4     0.0% n   0 0
  Shared/Views/Import/CopyVideosView.swift                  438   0/3     0.0% n   0 0
  Shared/Views/Main/ProjectDetailView.swift                 442   0/3     0.0% n   0 0
  Shared/App/VeloFilmsApp.swift                              25   0/2     0.0% n   0 0
  Shared/Core/FileManager/JSONLReader.swift                  12   0/2     0.0% n   0 0
  Shared/Core/FileManager/JSONLWriter.swift                  22   0/2     0.0% n   1 0
  Shared/Views/Import/ImportView.swift                       91   0/2     0.0% n   0 0
  Shared/Views/Main/ContentView.swift                        44   0/2     0.0% n   0 0
  Shared/Views/Main/ProjectListView.swift                    99   0/2     0.0% n   0 0
  Shared/Views/Settings/GlobalSettingsView.swift            790   0/2     0.0% n   0 0
  Shared/Views/Settings/OnboardingView.swift                190   0/2     0.0% n   0 0
  Shared/Core/Models/EnrichRow.swift                         78   1/34    2.9% n   0 0
  Shared/Core/Models/AppConfig.swift                        200   4/98    4.1% n   0 0
  Shared/Integrations/Garmin/GarminClient.swift              91   1/18    5.6% n   0 0
  Shared/Core/Models/ExtractRow.swift                        33   1/15    6.7% n   0 0
  Shared/Core/Pipeline/PipelineExecutor.swift               127   1/13    7.7% n   0 0
  iPadOS/FilePickerBridge.swift                              89   1/13    7.7% n   0 0
  Shared/Core/Models/FlattenRow.swift                        25   1/11    9.1% n   0 0
  Shared/Core/Models/Project.swift                          158   4/42    9.5% n   0 0
  Shared/Video/VideoCompositor.swift                        169   2/18   11.1% n   0 0
  Shared/Steps/Enrich/EnrichStep.swift                      138   1/7    14.3% n   0 0
  Shared/Core/Models/SelectRow.swift                        176   2/13   15.4% n   0 0
  Shared/Integrations/Strava/StravaAuth.swift               169   2/12   16.7% n   3 0
  Shared/Steps/Build/BuildStep.swift                        126   1/6    16.7% n   0 0
  Shared/Steps/Extract/ExtractStep.swift                    145   1/6    16.7% n   0 0
  Shared/Steps/Splash/IntroBuilder.swift                    525   4/21   19.0% n  17 0
  Shared/Core/Config/GlobalSettings.swift                   260   9/47   19.1% n   0 0
  Shared/Steps/Flatten/GPXParser.swift                      234   4/20   20.0% n   0 0
  Shared/Core/Pipeline/ProgressReporter.swift                32   2/10   20.0% n   1 0
  Shared/Steps/Enrich/ScoreCalculator.swift                  33   2/10   20.0% n   0 0
  Shared/Steps/Select/ClipSelector.swift                    134   2/10   20.0% n   0 0
  Shared/Steps/Flatten/FlattenStep.swift                     61   1/5    20.0% n   0 0
  Shared/Steps/Splash/SplashStep.swift                       32   1/5    20.0% n   0 0
  Shared/Steps/Concat/ConcatStep.swift                      474   1/4    25.0% n   5 0
  Shared/Views/Import/GarminImportView.swift                217   1/4    25.0% n   0 0
  Shared/Views/Import/StravaImportView.swift                163   1/4    25.0% n   0 0
  Shared/Steps/Build/GaugeRenderer.swift                    298   5/18   27.8% n   1 0
  Shared/Steps/Build/ClipCompositor.swift                   214   2/7    28.6% n   3 0
  Shared/Steps/Select/SelectStep.swift                      132   2/7    28.6% n   0 0
  Shared/Steps/Enrich/SegmentMatcher.swift                   77   4/13   30.8% n   0 0
  Shared/Views/Settings/ProjectPreferencesView.swift        134   1/3    33.3% n   0 0
  Shared/ML/YOLOInference.swift                             250   3/8    37.5% n   0 0
  Shared/Core/Models/FocusFilter.swift                      114   6/15   40.0% n   0 0
  Shared/Video/FFmpegBridge.swift                            78   2/5    40.0% n   0 0
  Shared/Steps/Select/PartnerMatcher.swift                   48   5/11   45.5% n   0 0
  Shared/Steps/Enrich/GPSEnricher.swift                      21   2/4    50.0% n   0 0
  Shared/Steps/Build/ElevationRenderer.swift                119   1/2    50.0% n   0 0
  Shared/Steps/Splash/OutroBuilder.swift                    191   1/2    50.0% n   3 0
  Shared/Views/Main/ResizableWindowAccessor.swift            83   1/2    50.0% n   0 0
  Shared/Core/Pipeline/PipelineStep.swift                    60   4/7    57.1% n   0 0
  Shared/Steps/Build/MinimapRenderer.swift                  200   3/5    60.0% n  11 0
  Shared/Video/VideoEncoder.swift                           162   3/5    60.0% n   0 0
  Shared/Core/Config/ProjectPreferences.swift                42   6/9    66.7% n   0 0
  Shared/Steps/Enrich/SceneDetector.swift                    85   2/3    66.7% n   1 0
  Shared/Steps/Extract/FrameSampler.swift                   167   8/10   80.0% n   1 0
  Shared/Core/FileManager/ProjectFileManager.swift           60   4/5    80.0% n   0 0

force-unwrap / todo locations:
  ! Shared/Core/FileManager/JSONLWriter.swift: [20]
  ! Shared/Core/Pipeline/ProgressReporter.swift: [19]
  ! Shared/Integrations/Garmin/GarminAuth.swift: [241, 336, 379]
  ! Shared/Integrations/Strava/StravaAuth.swift: [7, 71, 89]
  ! Shared/Steps/Build/ClipCompositor.swift: [131, 142, 152]
  ! Shared/Steps/Build/GaugeRenderer.swift: [290]
  ! Shared/Steps/Build/MinimapRenderer.swift: [29, 29, 30, 30, 90, 92, 143, 143, 144, 144, 188]
  ! Shared/Steps/Concat/ConcatStep.swift: [303, 305, 307, 309, 400]
  ! Shared/Steps/Enrich/SceneDetector.swift: [25]
  ! Shared/Steps/Extract/FrameSampler.swift: [83]
  ! Shared/Steps/Splash/IntroBuilder.swift: [107, 109, 188, 198, 302, 302, 303, 303, 306, 306, 307, 307, 319, 321, 457, 481, 492]
  ! Shared/Steps/Splash/OutroBuilder.swift: [116, 186, 189]
  ! Shared/Views/Selection/ManualSelectionView.swift: [344, 344]
```

## Appendix B — Evidence per category

### 1. Correctness
- Force-unwraps (52) by file: see "force-unwrap locations" in Appendix A. Classified: 13 `addMutableTrack(...)!` (ClipCompositor.swift:131, :142, :152; ConcatStep.swift:303, :305, :307, :309, :400; IntroBuilder.swift:107, :109, :188, :198; OutroBuilder.swift:116); 4 `CGContext(...)!` (MinimapRenderer.swift:188, IntroBuilder.swift:492, OutroBuilder.swift:186) plus `makeImage()!` (OutroBuilder.swift:189); 3 `cgImage…!` (MinimapRenderer.swift:90, :92; IntroBuilder.swift:319); 3 `CFAttributedStringCreate(...)!` (GaugeRenderer.swift:290, IntroBuilder.swift:457, :481); 3 `URL(string:)!` on constants (StravaAuth.swift:7, GarminAuth.swift:241, :336, :379) plus `components.url!` (StravaAuth.swift:71, :89); 12 `min()!/max()!` guarded by `count >= 2` (MinimapRenderer.swift:29-30, :143-144; IntroBuilder.swift:302-307), which is safe; `cameras[camera]!` set on the previous line (SceneDetector.swift:25), safe; `TimeZone(secondsFromGMT: 0)!` (FrameSampler.swift:83), safe; `first!` after an `isEmpty` guard (JSONLWriter.swift:20), safe; `c12!, c6!` after nil checks (ManualSelectionView.swift:344), safe; IUO (ProgressReporter.swift:19).
- `preconditionFailure`: StravaAuth.swift:143.
- `try?` count: `grep -o 'try?' all.swift.txt | wc -l` = 108.

### 2. Architecture
- `wc -l` on every file (Appendix A); long functions listed in Appendix A.
- Duplication: `AuthPreservingDelegate` in StravaClient.swift:173-187 and GarminClient.swift:76-91; reanchor logic in Project.swift:143-157 and ClipCompositor.swift:24-45; default values in GlobalSettings.swift:58-77 repeated in GlobalSettingsView.swift:378-383, :492-497; User-Agent "GCM-iOS-5.22.1.4" in GarminAuth.swift:404 and GarminClient.swift:64.
- Singletons: `GlobalSettings.shared` 64 refs; `UserDefaults.standard` 112 refs.

### 3. Idioms
- `@Observable` 5, `ObservableObject` 0, `@Published` 0; classes 14, structs 106, enums 29; `private` 371, explicit `public/internal` 0.
- Untyped JSON: 23 `JSONSerialization`/`[String: Any]` occurrences (`grep -rn "JSONSerialization\|\[String: Any\]"`).
- Dead code: Appendix C.

### 4. Concurrency
- `grep -nE "SWIFT_VERSION|STRICT_CONCURRENCY|SWIFT_DEFAULT_ACTOR|APPROACHABLE" project.pbxproj` gives SWIFT_VERSION = 5.0 (:307, :370), SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor (:304, :367), SWIFT_APPROACHABLE_CONCURRENCY = YES (:303, :366), and no SWIFT_STRICT_CONCURRENCY.
- Build log confirms `-swift-version 5` and `-default-isolation MainActor`.
- `nonisolated` appears only at PipelineExecutor.swift:84 (and ProgressReporter.swift:16), so no step type opts out of MainActor.
- No `waitUntilExit`, `DispatchSemaphore`, `Thread.sleep` or `.wait(` (grep = 0).

### 5. Security
- Secrets: `secret_scan.sh` (Appendix D). Output: Secrets.swift never tracked; all source-level `clientSecret` literals in history are the placeholder `"YOUR…"`; four committed binaries at `35f66b5` each contain one 40-hex string `c0ff…`; repo visibility `PUBLIC`; `git branch -a --contains 35f66b5` gives `main`, `remotes/origin/main`.
- Current build: `strings -n 8 VeloFilms.app/Contents/MacOS/VeloFilms.debug.dylib | grep -E '^[0-9a-f]{40}$'` returns `c0ff…` (same value).
- `grep -rlE "<the 40-hex value>" --include=*.swift --include=*.py --include=*.json VeloFilms/VeloFilms Scripts` (value from the binary scan, not printed here), excluding Secrets.swift, returns 0 hits, so the value originates in the gitignored Secrets.swift.
- Entitlements actually signed: `codesign -d --entitlements - VeloFilms.app` shows downloads.read-write, user-selected.read-write, get-task-allow (Debug), network.client, network.server, and no app-sandbox.
- `find . -name '*.xcprivacy'` returns nothing. `grep -rn "SecItem|kSecAttr|Keychain"` = 0. `grep -rn "FileProtectionType|completeFileProtection|isExcludedFromBackup"` = 0. `grep -rn "timeoutInterval"` = 0.

### 6. Testing
- `xcodebuild -list` shows Targets: VeloFilms (only); Schemes: VeloFilms.
- `xcodebuild test … -destination 'platform=macOS'` gives `xcodebuild: error: Scheme VeloFilms is not currently configured for the test action.` (exit 66).
- `grep -c "@Test\|func test" VeloFilmsTests/FocusFilterTests.swift` = 25 (XCTest; `@testable import VeloFilms`).
- No shared scheme (`xcshareddata/` absent); the scheme is user-local only.

### 7–8. Doc coverage and quality
- Coverage from `swift_metrics.py`. DocC tag counts over all sources: `- Parameter` 0, `- Returns:` 0, `- Throws:` 0. `// MARK:` 161; files over 150 lines without any MARK: StravaImportView.swift (163).
- Quality sample (17 doc comments):
  - Good, explains *why*:
    - FrameSampler.swift:21-22 ("AVFoundation does not expose mvhd.creation_time for NOVATEK mp42 files, so we read it directly")
    - FrameSampler.swift:37-38 (moov at end of file, so scan the last 4 MB)
    - FocusFilter.swift:100-103 (max vs sum to avoid double-counting)
    - SelectRow.swift:5-7 (flat Codable kept for format stability)
    - SelectRow.swift:19-21 (manual override survives re-run)
    - SegmentMatcher.swift:70-71 (UTC vs local-as-UTC offset)
    - GarminClient.swift:74-75 (why headers are re-added on redirect)
    - AppConfig.swift:24-25 (sceneGapReductionFactor meaning)
  - Adequate, says what but not why:
    - PipelineStep.swift:19 ("Steps that must complete…")
    - PipelineStep.swift:32
    - ProjectPreferences.swift:33
    - GPSEnricher.swift:17
    - GPXParser.swift:203
  - Weak or restating:
    - ProjectFileManager.swift:51 ("Find a GPX file … (returns first match)")
    - ProjectPreferences.swift:38 ("Effective target clip count for this project.")
    - StravaAuth.swift:69 ("Launch the OAuth web flow. Returns the access token on success." No Throws, no threading, no side effect of storing tokens)
    - ProjectFileManager.swift:21 ("Discover project folders…" on an unused function).
  - None document threading, side effects (e.g. writes to UserDefaults or disk) or thrown errors.

### 9. Accuracy
- `grep -rnE "\b(TODO|FIXME|HACK|XXX)\b"` in comments = 0.
- `grep -rnE "[A-Za-z_]+\.py\b|Python" --include=*.swift` = 40 lines (Appendix D).

### 10. Project docs
- `ls README.md CLAUDE.md ARCHITECTURE.md SECURITY.md`: README.md and CLAUDE.md present; ARCHITECTURE.md and SECURITY.md missing.
- Build/README.md lines 9-11 claim macOS 14 / iOS 17 / Swift 6.
- DocC: `xcodebuild docbuild … -derivedDataPath ~/Library/Developer/Xcode/DerivedData/VeloFilms-scorecard-r1-doc` gives `** BUILD DOCUMENTATION SUCCEEDED **`, with 0 DocC warnings and VeloFilms.doccarchive produced.

### Build commands used (clean, separate DerivedData)
```
xcodebuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/VeloFilms-scorecard-r1-mac build
xcodebuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/VeloFilms-scorecard-r1-ios build
xcodebuild docbuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/VeloFilms-scorecard-r1-doc
xcodebuild test -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS'
grep 'warning:' <log> | sort -u | wc -l
```
Results: macOS BUILD SUCCEEDED (0 Swift warnings, 1 appintents notice); iOS BUILD SUCCEEDED (same); DocC SUCCEEDED (same); test failed with exit 66 (no test action). The derivedDataPath must sit outside `/private/tmp`, because coremlc's sandbox couldn't write there (environment issue, not a project issue). Logs are in the session scratchpad: `clean-build-macos.log`, `clean-build-ios.log`, `clean-docbuild.log`, `test.log`.

## Appendix C — Unused-symbol candidates (`unused_symbols.py` output)

False positives: VideoCompositor.swift:14-24 (AVVideoCompositionInstruction protocol requirements) and VeloFilmsApp (`@main`).
```
candidates=35
Shared/Video/VideoCompositor.swift:14: enablePostProcessing
Shared/Video/VideoCompositor.swift:15: containsTweening
Shared/Video/VideoCompositor.swift:16: passthroughTrackID
Shared/Video/VideoCompositor.swift:24: requiredSourceTrackIDs
Shared/Core/Config/GlobalSettings.swift:204: isDualCamera
Shared/Core/Config/ProjectPreferences.swift:39: effectiveTargetClips
Shared/Core/Models/Project.swift:37: finalConcatList
Shared/Core/Models/Project.swift:66: analysisReady
Shared/Core/Models/AppConfig.swift:9: useAVCompositor
Shared/Core/Models/AppConfig.swift:30: requireGpsForSelection
Shared/Core/Models/AppConfig.swift:38: yoloBatchSizeMac
Shared/Core/Models/AppConfig.swift:39: yoloBatchSizeiPad
Shared/Core/Models/AppConfig.swift:40: yoloDetectClasses
Shared/Core/Models/AppConfig.swift:42: YOLOClass
Shared/Core/Models/AppConfig.swift:110: gaugeOrder
Shared/Core/Models/AppConfig.swift:111: enabledGauges
Shared/Core/Models/AppConfig.swift:119: elevStripH
Shared/Core/Models/AppConfig.swift:127: mapY
Shared/Core/Models/AppConfig.swift:129: gaugeY
Shared/Core/Models/AppConfig.swift:133: elevY
Shared/Core/Models/AppConfig.swift:138: paddingX
Shared/Core/Models/AppConfig.swift:139: paddingY
Shared/Core/Models/AppConfig.swift:150: zoomPip
Shared/Core/Models/AppConfig.swift:151: zoomSplash
Shared/Core/Models/AppConfig.swift:152: splashSize
Shared/Core/Models/AppConfig.swift:184: GaugeArc
Shared/Core/Models/AppConfig.swift:185: arcStartDeg
Shared/Core/Models/AppConfig.swift:186: arcEndDeg
Shared/Core/Models/AppConfig.swift:187: arcSpan
Shared/Core/Models/AppConfig.swift:189: dim
Shared/Core/FileManager/ProjectFileManager.swift:22: discoverProjects
Shared/App/VeloFilmsApp.swift:4: VeloFilmsApp
Shared/Steps/Build/GaugeRenderer.swift:27: renderFrames
Shared/Views/Pipeline/PipelineView.swift:3: PipelineView
iPadOS/FilePickerBridge.swift:55: DrivePickerView
```

## Appendix D — Scripts and raw lists

### D1. `swift_metrics.py` (run: `python3 -I swift_metrics.py VeloFilms/VeloFilms --json metrics.json`)
```python
#!/usr/bin/env python3
"""Repeatable Swift code metrics for VeloFilms scorecards.

Usage: python3 -I swift_metrics.py <source_root> [--json out.json]

Excludes: any path containing 'Secrets.swift' (gitignored credentials; not read).
Method (all approximate, regex + brace tracking, no compiler):
  * Strings ("..." and \"\"\"...\"\"\") and comments are blanked before code checks,
    so '!' inside strings/comments is never counted.
  * force_unwrap: a '!' immediately after an identifier char, ')' , ']' or '}' and NOT
    followed by '=' (excludes '!=' and prefix negation '!x'). Includes IUO decls 'T!'.
  * try!, as!, fatalError(, preconditionFailure(, precondition( counted on blanked code.
  * TODO/FIXME/HACK/XXX counted in comments only.
  * functions: lines declaring 'func' or 'init' (or 'var body: some View' / any
    'some View {' computed property) with a body '{'; length = lines from the declaration
    line to the matching '}' inclusive.
  * doc coverage: declarations of types (struct/class/enum/protocol/actor/typealias),
    func/init/subscript, and stored/computed var/let at TYPE scope (all enclosing braces
    are type/extension bodies), not marked private/fileprivate and not inside a
    private/fileprivate type or extension. Enum 'case' lines are excluded.
    'Documented' = the nearest preceding non-blank, non-attribute (@...) line is a '///'
    line or ends a '/** */' block.
  * header: first non-blank line of the file starts with '//'.
"""
import json
import os
import re
import sys

TYPE_KW = r'(?:struct|class|enum|protocol|actor|extension)'
DECL_RE = re.compile(
    r'^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*'
    r'(?P<mods>(?:(?:public|internal|open|private|fileprivate|final|static|class|'
    r'nonisolated|override|mutating|nonmutating|lazy|weak|unowned|convenience|required|'
    r'dynamic|indirect|@\w+(?:\([^)]*\))?)\s+)*)'
    r'(?:private\(set\)\s+|fileprivate\(set\)\s+|internal\(set\)\s+)?'
    r'(?P<mods2>(?:(?:static|final|nonisolated|override|lazy|weak|@\w+)\s+)*)'
    r'(?P<kw>struct|class|enum|protocol|actor|extension|typealias|func|init[?!]?|'
    r'subscript|var|let)\b'
)
FUNC_RE = re.compile(r'\b(func\s+\w|init[?!]?\s*[(<])')
SOMEVIEW_RE = re.compile(r'\bvar\s+\w+\s*:\s*some\s+View\s*\{')


def blank_code(text):
    """Return (code, comments) strings with same length/newlines.

    code: comments and string contents replaced by spaces.
    comments: only comment text kept (code blanked)."""
    out, com = [], []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j == -1 else j
            out.append(' ' * (j - i)); com.append(text[i:j]); i = j
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j == -1 else j + 2
            seg = text[i:j]
            out.append(re.sub(r'[^\n]', ' ', seg)); com.append(seg); i = j
        elif text.startswith('"""', i):
            j = text.find('"""', i + 3)
            j = n if j == -1 else j + 3
            seg = text[i:j]
            out.append('"' + re.sub(r'[^\n]', ' ', seg[1:-1]) + '"')
            com.append(re.sub(r'[^\n]', ' ', seg)); i = j
        elif c == '"':
            j = i + 1
            depth = 0
            while j < n:
                if text[j] == '\\' and j + 1 < n and text[j + 1] == '(':
                    depth += 1; j += 2; continue
                if depth and text[j] == ')':
                    depth -= 1; j += 1; continue
                if text[j] == '\\':
                    j += 2; continue
                if text[j] == '"' and depth == 0:
                    break
                if text[j] == '\n':
                    break
                j += 1
            j = min(j + 1, n)
            seg = text[i:j]
            out.append('"' + re.sub(r'[^\n]', ' ', seg[1:-1]) + ('"' if len(seg) > 1 else ''))
            com.append(re.sub(r'[^\n]', ' ', seg)); i = j
        else:
            out.append(c); com.append('\n' if c == '\n' else ' '); i += 1
    return ''.join(out), ''.join(com)


def analyse(path):
    raw = open(path, encoding='utf-8').read()
    lines = raw.split('\n')
    code, comments = blank_code(raw)
    clines = code.split('\n')
    mlines = comments.split('\n')
    r = {'file': path, 'lines': len(lines) - (1 if raw.endswith('\n') else 0)}
    r['code_lines'] = sum(1 for cl in clines if cl.strip())
    first = next((l for l in lines if l.strip()), '')
    r['header'] = first.lstrip().startswith('//')
    fu = []
    for no, cl in enumerate(clines, 1):
        for m in re.finditer(r'(?<=[\w\)\]\}])!(?!=)', cl):
            pre = cl[:m.start()]
            if re.search(r'\b(try|as)$', pre):
                continue
            fu.append(no)
    r['force_unwrap_lines'] = fu
    r['force_unwrap'] = len(fu)
    r['try_bang'] = len(re.findall(r'\btry!', code))
    r['as_bang'] = len(re.findall(r'\bas!', code))
    r['fatalError'] = len(re.findall(r'\bfatalError\s*\(', code))
    r['preconditionFailure'] = len(re.findall(r'\bpreconditionFailure\s*\(', code))
    r['precondition'] = len(re.findall(r'\bprecondition\s*\(', code))
    r['todo'] = [i for i, ml in enumerate(mlines, 1) if re.search(r'\b(TODO|FIXME|HACK|XXX)\b', ml)]
    r['print'] = len(re.findall(r'\b(print|NSLog|debugPrint)\s*\(', code))

    # brace tracking: stack entries (kind, private, start_line)
    stack = []
    pending = None  # kind waiting for '{'
    funcs = []
    decls = []
    for no, cl in enumerate(clines, 1):
        stripped = cl.strip()
        in_type_scope = all(k == 'type' for k, _, _ in stack)
        in_private = any(p for _, p, _ in stack)
        m = DECL_RE.match(cl)
        kind_here = None
        if m and stripped:
            kw = m.group('kw')
            mods = (m.group('mods') or '') + ' ' + stripped[:stripped.find(kw)]
            is_priv = bool(re.search(r'\b(private|fileprivate)\b(?!\(set\))', mods))
            if kw in ('struct', 'class', 'enum', 'protocol', 'actor', 'extension'):
                # 'class func'/'class var' are members, not types
                if kw == 'class' and re.match(r'\s*(?:@\w+\s+)*(?:\w+\s+)*class\s+(func|var|let)\b', cl):
                    kind_here = None
                else:
                    kind_here = ('type', is_priv)
            elif kw.startswith('init') or kw in ('func', 'subscript'):
                kind_here = ('func', is_priv)
            if in_type_scope and not in_private and kw != 'extension' and not is_priv:
                # doc check
                k = no - 2
                while k >= 0 and (not lines[k].strip() or lines[k].strip().startswith('@')
                                  or lines[k].strip().startswith('#if') or lines[k].strip().startswith('#else')
                                  or lines[k].strip().startswith('#endif')):
                    if not lines[k].strip():
                        break  # blank line breaks adjacency
                    k -= 1
                prev = lines[k].strip() if k >= 0 else ''
                documented = prev.startswith('///') or prev.endswith('*/')
                decls.append({'line': no, 'kw': kw, 'doc': documented, 'text': stripped[:80]})
        is_func_decl = bool(FUNC_RE.search(cl)) and in_type_scope or bool(SOMEVIEW_RE.search(cl))
        if FUNC_RE.search(cl) and not in_type_scope:
            is_func_decl = True  # nested/global funcs too
        for ch_i, ch in enumerate(cl):
            if ch == '{':
                if kind_here is not None and kind_here[0] == 'type' and pending is None:
                    stack.append(('type', kind_here[1], no)); kind_here = ('used', False)
                elif is_func_decl:
                    stack.append(('func', False, no)); is_func_decl = False
                    funcs.append([no, None, stripped[:70]])
                else:
                    stack.append(('block', False, no))
            elif ch == '}':
                if stack:
                    k, _, start = stack.pop()
                    if k == 'func':
                        for f in reversed(funcs):
                            if f[0] == start and f[1] is None:
                                f[1] = no; break
    r['functions'] = [(s, e, e - s + 1, t) for s, e, t in funcs if e]
    r['long_functions'] = [f for f in r['functions'] if f[2] > 40]
    r['decls'] = decls
    r['decl_total'] = len(decls)
    r['decl_doc'] = sum(1 for d in decls if d['doc'])
    r['doc_comment_lines'] = sum(1 for l in lines if l.strip().startswith('///'))
    return r


def main():
    root = sys.argv[1]
    files = []
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if f.endswith('.swift') and 'Secrets.swift' not in f:
                files.append(os.path.join(dp, f))
    files.sort()
    res = [analyse(f) for f in files]
    tot = lambda k: sum(r[k] for r in res)
    print(f"files={len(res)} lines={tot('lines')} code_lines={tot('code_lines')}")
    print(f"headers={sum(r['header'] for r in res)}/{len(res)}")
    print(f"force_unwrap={tot('force_unwrap')} try!={tot('try_bang')} as!={tot('as_bang')} "
          f"fatalError={tot('fatalError')} preconditionFailure={tot('preconditionFailure')} "
          f"precondition={tot('precondition')} print/NSLog={tot('print')}")
    print(f"TODO/FIXME/HACK/XXX={sum(len(r['todo']) for r in res)}")
    dt, dd = tot('decl_total'), tot('decl_doc')
    print(f"doc_coverage={dd}/{dt} = {100*dd/max(dt,1):.1f}%  (/// lines total={tot('doc_comment_lines')})")
    big = [(r['lines'], r['file']) for r in res if r['lines'] > 300]
    print(f"files_over_300={len(big)}")
    for l, f in sorted(big, reverse=True):
        print(f"   {l:5d} {os.path.relpath(f, root)}")
    lf = [(f[2], os.path.relpath(r['file'], root), f[0], f[3]) for r in res for f in r['long_functions']]
    print(f"functions_total={sum(len(r['functions']) for r in res)} functions_over_40={len(lf)}")
    for n, f, s, t in sorted(lf, reverse=True):
        print(f"   {n:4d} {f}:{s}  {t}")
    print("\nper-file: lines | docs/decls | % | header | force! | todo")
    for r in sorted(res, key=lambda r: (r['decl_doc'] / max(r['decl_total'], 1), -r['decl_total'])):
        p = 100 * r['decl_doc'] / max(r['decl_total'], 1)
        print(f"  {os.path.relpath(r['file'], root):55s} {r['lines']:5d} {r['decl_doc']:3d}/{r['decl_total']:<3d} {p:5.1f}% "
              f"{'Y' if r['header'] else 'n'} {r['force_unwrap']:3d} {len(r['todo'])}")
    print("\nforce-unwrap / todo locations:")
    for r in res:
        rel = os.path.relpath(r['file'], root)
        if r['force_unwrap_lines']:
            print(f"  ! {rel}: {r['force_unwrap_lines']}")
        if r['todo']:
            print(f"  TODO {rel}: {r['todo']}")
    if '--json' in sys.argv:
        json.dump(res, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1, default=str)


if __name__ == '__main__':
    main()
```

### D2. `unused_symbols.py` (run: `python3 -I unused_symbols.py VeloFilms/VeloFilms`)
```python
#!/usr/bin/env python3
"""Approximate dead-code finder: declared func/type/var names (any access level)
whose identifier appears exactly once across all Swift sources (word match).
Usage: python3 -I unused_symbols.py <source_root>. Excludes Secrets.swift, protocol
requirement names commonly called by frameworks (body, init, makeCoordinator, etc.)."""
import os, re, sys
root = sys.argv[1]
files = [os.path.join(d, f) for d, _, fs in os.walk(root) for f in fs if f.endswith('.swift') and f != 'Secrets.swift']
text = {f: open(f, encoding='utf-8').read() for f in files}
alltext = '\n'.join(text.values())
skip = {'body','makeCoordinator','makeUIViewController','updateUIViewController','makeNSView','updateNSView',
        'parser','urlSession','presentationAnchor','startRequest','renderContextChanged','cancelAllPendingVideoCompositionRequests',
        'documentPicker','documentPickerWasCancelled','encode','id','description','errorDescription','hash','CodingKeys',
        'sourcePixelBufferAttributes','requiredPixelBufferAttributesForRenderContext','supportsWideColorSourceFrames','main'}
decl = re.compile(r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|static|final|override|nonisolated|mutating|lazy)\s+)*(?:func|struct|class|enum|var|let)\s+([A-Za-z_]\w*)')
out = []
for f, t in text.items():
    depth = 0
    for no, line in enumerate(t.split('\n'), 1):
        m = decl.match(line)
        if m and depth <= 2:
            name = m.group(1)
            if name in skip or len(name) < 3: pass
            else:
                n = len(re.findall(r'\b' + re.escape(name) + r'\b', alltext))
                if n == 1: out.append(f"{os.path.relpath(f, root)}:{no}: {name}")
        depth += line.count('{') - line.count('}')
print(f"candidates={len(out)}")
print('\n'.join(out))
```

### D3. `secret_scan.sh` (run: `bash secret_scan.sh /Volumes/GDrive/Github/velo-films-swift`; prints redacted values only)
```bash
#!/bin/bash
# Repeatable secret scan for velo-films-swift. Prints only redacted values (first 4 chars + …).
# Usage: bash secret_scan.sh /Volumes/GDrive/Github/velo-films-swift
cd "$1" || exit 1
echo "== commits: $(git rev-list --all | wc -l | tr -d ' ')"
echo "== Secrets.swift ever tracked?"; git log --all --format='%h' -- '**/Secrets.swift' | head -5; echo "(blank = never)"
echo "== pickaxe (-S) hits per keyword"
for p in client_secret clientSecret api_key apiKey password Bearer 'sk-' access_token refresh_token consumer_secret oauth_token_secret; do
  echo "  $p: $(git log --all -p -S"$p" --format=%h | grep -E '^[0-9a-f]{7,}$' | tr '\n' ' ')"
done
echo "== assigned literals in diffs (redacted)"
git log --all -p -G'client_?[sS]ecret|consumer_secret|oauth_token_secret' --format='COMMIT %h' \
 | grep -E '^COMMIT|^[+-].*(=|:) *"[^"]{4,}"' | sed -E 's/"([^"]{4})[^"]*"/"\1…"/g' | head -40
echo "== git grep all revisions for secret-like assignments (redacted)"
git rev-list --all | xargs -I{} git grep -I -n -i -E '(secret|password|token)[a-z_]*\s*[:=]\s*"[^" ]{8,}"' {} 2>/dev/null \
 | sed -E 's/"([^"]{4})[^"]*"/"\1…"/g' | awk -F: '{print $2":"$3}' | sort -u | head -20
echo "== compiled binaries ever committed"
git log --all --name-only --format= | grep -E '\.app/Contents/MacOS/' | sort -u
echo "== 40-hex strings (Strava-secret shape) inside committed binaries (redacted)"
for c in $(git log --all --format=%h -- ':(glob)**/*.app/Contents/MacOS/*'); do
  git ls-tree -r "$c" --name-only | grep -E '\.app/Contents/MacOS/' | while IFS= read -r p; do
    n=$(git show "$c:$p" 2>/dev/null | strings -n 8 | grep -E '^[0-9a-f]{40}$' | sort -u | sed -E 's/^(.{4}).*/\1…/' | tr '\n' ' ')
    [ -n "$n" ] && echo "  $c $p -> $n"
  done
done
echo "== remote visibility"; gh repo view --json visibility 2>/dev/null
```

### D4. Comments referencing Python modules not in this repo
```
Shared/Core/Pipeline/PipelineExecutor.swift:6:/// Mirrors pipeline_executor.py. Progress is reported via AsyncStream.
Shared/Core/Pipeline/ProgressReporter.swift:12:/// without knowing anything about the UI. Mirrors progress_reporter.py.
Shared/Core/Config/ProjectPreferences.swift:4:/// Mirrors the per-project fields of persistent_config.py that vary ride-to-ride.
Shared/Core/Pipeline/PipelineStep.swift:3:/// All pipeline steps conform to this protocol. Mirrors step_registry.py.
Shared/Core/Models/Project.swift:19:/// Derived path properties — mirrors io_paths.py.
Shared/Core/Models/AppConfig.swift:3:/// Central configuration — mirrors config.py.
Shared/Core/Models/AppConfig.swift:4:/// All values are constants matching the Python source. User-overridable
Shared/Core/Config/GlobalSettings.swift:4:/// User-facing persistent settings — mirrors persistent_config.py.
Shared/Core/Config/GlobalSettings.swift:43:    /// Mirrors Python's CAMERA_CREATION_TIME_IS_LOCAL_WRONG_Z.
Shared/Core/Models/EnrichRow.swift:4:/// Mirrors enrich.py output schema exactly.
Shared/Core/Models/ExtractRow.swift:4:/// Mirrors extract.py output schema exactly.
Shared/Core/FileManager/ProjectFileManager.swift:4:/// Mirrors io_paths.py. All paths are derived from Project.folderURL.
Shared/Core/Models/FlattenRow.swift:4:/// Mirrors flatten.py output schema exactly.
Shared/Integrations/Strava/StravaAuth.swift:6:/// Mirrors strava_client.py OAuth handling.
Shared/Steps/Splash/SplashStep.swift:4:/// Mirrors splash.py: IntroBuilder + OutroBuilder.
Shared/Steps/Flatten/FlattenStep.swift:4:/// Mirrors flatten.py: locate GPX → parse → resample to 1Hz → write JSONL.
Shared/Steps/Flatten/FlattenStep.swift:47:    // MARK: - GPX location logic (mirrors flatten.py)
Shared/Steps/Splash/OutroBuilder.swift:7:/// Mirrors outro_builder.py. drawtext replaced with CATextLayer via AVVideoCompositionCoreAnimationTool.
Shared/Steps/Splash/IntroBuilder.swift:13:/// Mirrors intro_builder.py. All rendering via AVFoundation + Core Graphics.
Shared/Steps/Enrich/SceneDetector.swift:6:/// Mirrors scene_detector.py: maintains a circular buffer of the last
Shared/Steps/Enrich/ScoreCalculator.swift:4:/// Mirrors score_calculator.py exactly — weight constants from AppConfig.ScoreWeights.
Shared/Steps/Extract/ExtractStep.swift:5:/// Mirrors extract.py: GPX-anchored global 5s grid → per-clip frame rows.
Shared/Steps/Enrich/EnrichStep.swift:6:/// Writes enriched.jsonl. Mirrors enrich.py.
Shared/Steps/Enrich/EnrichStep.swift:39:        // Sort by camera + timestamp for scene continuity (mirrors enrich.py)
Shared/Steps/Flatten/GPXParser.swift:17:/// Mirrors flatten.py: gpxpy parse → 1-second rows with speed + gradient.
Shared/Steps/Select/ClipSelector.swift:4:/// Mirrors select.py: candidate pool → gap filter → zone enforcement → PR auto-include.
Shared/Steps/Select/ClipSelector.swift:37:        // For dual-camera moments, use min(clipNum12, clipNum6) — matches Python's approach.
Shared/Steps/Build/ClipCompositor.swift:6:/// macOS: FFmpegBridge filter_complex + loudnorm (mirrors clip_renderer.py).
Shared/Steps/Enrich/SegmentMatcher.swift:4:/// Mirrors segment_matcher.py: pr_rank=1 → 1.0, rank 2-3 → 0.7, any segment → 0.3.
Shared/Steps/Enrich/GPSEnricher.swift:4:/// Mirrors gps_enricher.py: nearest-neighbour lookup within GPX_TOLERANCE.
Shared/Steps/Build/ElevationRenderer.swift:10:/// Mirrors elevation_prerenderer.py + matplotlib output:
Shared/Steps/Extract/FrameSampler.swift:6:/// Mirrors video_utils.py: fix_cycliq_utc_bug, infer_recording_start, frame extraction.
Shared/Steps/Select/PartnerMatcher.swift:4:/// Mirrors select.py dual-camera grouping logic.
Shared/Steps/Select/SelectStep.swift:4:/// Mirrors select.py: groups by moment_id → score → gap filter → zone enforcement.
Shared/Steps/Build/GaugeRenderer.swift:11:/// Mirrors gauge_prerenderer.py + draw_gauge.py.
Shared/Steps/Build/GaugeRenderer.swift:187:    /// Arc geometry matches draw_gauge.py:
Shared/Steps/Build/BuildStep.swift:5:/// Mirrors build.py: minimaps → elevation strips → gauges → clip render.
```

### D5. One-liners used for idiom and error-handling counts (over the concatenated sources `all.swift.txt`, Secrets.swift excluded)
```bash
find VeloFilms/VeloFilms -name '*.swift' ! -name Secrets.swift -print0 | xargs -0 cat > all.swift.txt
grep -o 'try?' all.swift.txt | wc -l                       # 108
grep -c '@Observable' all.swift.txt                         # 5
grep -cE '^\s*(final )?class ' all.swift.txt               # 14
grep -cE '\bprivate\b' all.swift.txt                       # 371
grep -o 'GlobalSettings.shared' all.swift.txt | wc -l       # 64
grep -o 'UserDefaults.standard' all.swift.txt | wc -l       # 112
grep -cF -e '- Parameter' -e '- Returns:' -e '- Throws:' all.swift.txt   # 0
```
