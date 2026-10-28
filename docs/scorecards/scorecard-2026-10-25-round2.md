# Velo Films — Engineering Scorecard, Round 2

- **Date:** 2026-10-25
- **Commit scored:** `3d77ef1` (main, equal to `origin/main`) **plus the uncommitted working tree** (63 files changed: Garmin removal, Keychain storage, redirect fix, privacy manifest, doc comments, new ARCHITECTURE.md and SECURITY.md). This is the state that was built and scored.
- **Scope:** `VeloFilms/VeloFilms/` (the only folder in the build): 57 Swift files. `Secrets.swift` was excluded from every metric and **not read**. Also reviewed: `Scripts/`, `VeloFilmsTests/`, `.gitignore`, `project.pbxproj`, the repo docs, the full git history and both built apps.
- **Method:** the same scripts as round 1 (`swift_metrics.py`, `unused_symbols.py`, `secret_scan.sh`), re-run unchanged. Additional helper scripts are listed in the appendix.
- **Reviewer stance:** independent and strict. Claims in comments, docs and `docs/review/PROGRESS.md` were checked against the code, not taken on trust.

## Overall

| | Score |
|---|---|
| **Overall** | **53.0 / 100 — Grade D** (round 1: 31.6, F) |
| Code subtotal | 23.4 / 60 (round 1: 19.8) |
| Documentation subtotal | 29.6 / 40 (round 1: 11.8) |

Caps: both platforms build, so the build-failure cap does not apply. **The Critical finding is closed**, so the Security cap no longer applies. One High remains (the Strava client secret inside the app), and the owner has accepted it.

**Quality gate (target 85, no category below 7, no open High or Critical): not met.** Categories below 7: Correctness (5), Architecture (4), Idioms (5), Concurrency (3), Security (5), Testing (1), Accuracy (6). The documentation work moved the score a long way, but the code categories have barely moved, because almost no code changed.

## Scorecard

| # | Category | Weight | Score /10 | Weighted | Reason |
|---|---|---|---|---|---|
| 1 | Correctness & robustness | 12% | 5 | 6.0 | Builds clean. 0 `try!`, 0 `as!`, 0 `fatalError`, 1 `preconditionFailure` (StravaAuth.swift:193). Force-unwraps fell from 52 to 49, only because Garmin was deleted; the other 49 are the same framework-call unwraps (`addMutableTrack(...)!` ×13, `CGContext(...)!`, `cgImage!`). `try?` count is 98. Two Garmin bugs went with the Garmin code. **Every other round 1 bug is still in the code** (pedestrian weight never loaded, GlobalSettings.swift:175 vs :224; mute can't persist, :163-166; projects dropped when a drive is unplugged, Project.swift:186-188; delete-then-copy, CopyVideosView.swift:393-395; manual selections silently lost, ManualSelectionView.swift:452). Several of these are now honestly documented, but documenting a bug doesn't fix it. New: the GPX-drop path locks the Analyse card (see Bugs). |
| 2 | Architecture & structure | 10% | 4 | 4.0 | Unchanged design. Files over 300 lines rose from 7 to **9**: GlobalSettings (309), AppConfig (308) and GaugeRenderer (335) crossed the line only because comments were added. Functions over 40 lines: **37 of 278** (round 1: 42/293; the drop is the deleted Garmin code). Longest is still GlobalSettingsView.swift:371 `body` (158 lines). Business rules still sit in views (CopyVideosView.swift:331 `runCopy`, 104 lines; ProjectDetailView step registration). The Strava-offset formula is duplicated in SegmentMatcher.swift:91-95 and ManualSelectionView.swift:443-449. Positive: `AuthPreservingDelegate` now exists once, and `KeychainStore` is a small, separate security layer. `GlobalSettings.shared` 63 refs, `UserDefaults.standard` 101 refs. |
| 3 | Swift & SwiftUI idioms | 8% | 5 | 4.0 | No real change. Untyped JSON fell from 23 to 17 (`JSONSerialization`/`[String: Any]`; Garmin removed, but StravaClient.swift:93-153 is still untyped). Dead code is **unchanged at 36 code-only candidates (about 29 real)**. Round 2's raw script output shows 20, but only because new doc comments mention the unused names (method note in the appendix). `extension_` (ExtractStep.swift:43), `_FolderPickerRepresentable` and multi-statement lines are still there. `KeychainStore` is clean, typed and idiomatic. |
| 4 | Concurrency & performance | 8% | 3 | 2.4 | Unchanged: `SWIFT_VERSION = 5.0` (pbxproj:307, :370), no `SWIFT_STRICT_CONCURRENCY`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (:304, :367). Step work still runs on the main actor, and the `ClipVideoCompositor` data race (VideoCompositor.swift:66-67, :85) is still there. The comments now **describe** this honestly (PipelineExecutor.swift:52-53, ARCHITECTURE.md:111-114), which counts toward Accuracy, not here. New minor point: `GPXParser.iso8601Epoch` builds two `ISO8601DateFormatter`s per track point (GPXParser.swift:203-208). |
| 5 | Security & privacy | 12% | 5 | 6.0 | **Critical closed:** the leaked secret was rotated (the build now holds a different 40-hex value, `9370…` vs the old `c0ff…`), and history was purged (`35f66b5` is no longer a valid object; 0 git objects contain `c0ff…`; `origin/main` = local `3d77ef1`). **3 of 4 Highs fixed:** tokens are in the Keychain (both items present; UserDefaults holds only `stravaTokenExpiry`), Garmin is removed, and the redirect host check is in place (StravaClient.swift:237-243). PrivacyInfo.xcprivacy is accurate and bundled in both apps. Still open: the **accepted High** (secret inside the app), 6 Medium (2 of them partly fixed: no OAuth `state`; token calls ignore HTTP status; no timeouts; GPS data unprotected; no revoke or "Delete all my data"; no consent; FFmpeg stderr shown to users) and 8 Low. |
| 6 | Testing | 10% | 1 | 1.0 | Unchanged. `xcodebuild -list` shows one target. `xcodebuild test` exits 66: "Scheme VeloFilms is not currently configured for the test action." `VeloFilmsTests/FocusFilterTests.swift` is still in no target. **0 tests ran.** The new security code (Keychain migration, redirect filter) has no automated test. |
| 7 | Doc-comment coverage | 12% | 9 | 10.8 | **617 / 617 non-private type-scope declarations documented = 100 %** (round 1: 116/659 = 17.6 %). `//` file headers: **57 / 57** (was 0/59). `// MARK:` 145. Not a 10, because inside the documented functions the DocC tags are incomplete: `- Parameter(s)` on 64 of 116 functions that take parameters (55 %), `- Returns:` on 47 of 62 non-Void functions (76 %), `- Throws:` on 37 of 41 throwing functions (90 %). There is no DocC catalog. |
| 8 | Doc-comment quality | 10% | 7 | 7.0 | Sample of 26 comments (quoted below). Most now explain *why* and state side effects, threading and failure behaviour. Good examples: KeychainStore.swift:10-17, StravaAuth.swift:77-82, SceneDetector.swift:10-15, JSONLReader.swift:13-14, GPXParser.swift:45-46. They also flag their own limits ("Not currently used", "not synchronised", "Does not revoke"). Weak spots: a band of restating one-liners ("`true` if the step output exists." ×4 at Project.swift:87-94; "Map x position." AppConfig.swift:186; "Weight of speed."; "Stores the callback." FilePickerBridge.swift:86), about 45 % of parameterised functions with no Parameters tag, and only 6 explicit threading notes outside the main types. |
| 9 | Accuracy | 8% | 6 | 4.8 | 0 TODO/FIXME/HACK. **45 specific claims checked; 12 mismatches** (list below). Round 1 had 19 plus a 40-instance class. Most new mismatches are small (a stale inline comment, a sum stated wrongly, radius vs diameter). Two matter more: README's "drop a .gpx file into the project folder" doesn't work in the UI, and the bundled `Steps/Build/README.md`, `PLAN.md` and `QUICKSTART.md` still claim macOS 14, iOS 17 and Swift 6. Two round 1 items are still open: the user-facing "Settings → Camera Calibration" text, and the stale Build docs. |
| 10 | Project docs | 10% | 7 | 7.0 | README.md, **ARCHITECTURE.md (new)**, **SECURITY.md (new, with an incident log)** and CLAUDE.md all exist and are mostly accurate against the code: storage table, pipeline table, platform matrix, Keychain service name and the Concurrency section were all verified. DocC builds with **0 warnings**, but there is no `.docc` catalog. Gaps: the stale Build/*.md files are still in the source tree and app bundle, ARCHITECTURE has the `ride.gpx` imprecision, README has the GPX-drop claim, and SECURITY.md overstates "no … status checks". |
| | **Code subtotal** | 60% | | **23.4** | |
| | **Documentation subtotal** | 40% | | **29.6** | |
| | **Total** | 100% | | **53.0** | **Grade D** |

## Key metrics

| Metric | Round 1 | Round 2 | Method |
|---|---|---|---|
| Swift files (in build, excluding Secrets.swift) | 59 | **57** | `swift_metrics.py` (−3 Garmin, +1 KeychainStore) |
| Lines (total / non-blank, non-comment) | 10,526 / 8,596 | **10,995 / 8,050** | same (code −546, comments +1,015) |
| Doc-comment coverage | 116 / 659 = 17.6 % | **617 / 617 = 100 %** | same: type-scope non-private decls with `///` directly above |
| `///` lines | 283 | **1,234** | same |
| Files with a `//` header | 0 / 59 | **57 / 57** | first non-blank line starts with `//` |
| DocC tags on documented funcs (Parameters / Returns / Throws) | 0 / 0 / 0 | **64 of 116 / 47 of 62 / 37 of 41** | `r2_doctags.py` (appendix) |
| Tests | 0 run; 25 orphan | **0 run; 25 orphan** | `xcodebuild -list`, `xcodebuild test` (exit 66) |
| Force-unwraps `!` | 52 | **49** | `swift_metrics.py` (same regex) |
| `try!` / `as!` / `fatalError` / `preconditionFailure` | 0/0/0/1 | **0/0/0/1** | same |
| `try?` | 108 | **98** | `grep -o 'try?'` over concatenated sources |
| TODO/FIXME/HACK/XXX | 0 | **0** | comment text only |
| `print`/`NSLog` | 5 | **5** (ConcatStep.swift:221, :292, :442; IntroBuilder.swift:272, :288) | script |
| Files > 300 lines | 7 | **9** (1202, 795, 603, 486, 447, 443, 335, 309, 308) | `wc -l` |
| Functions > 40 lines | 42 of 293 | **37 of 278** | brace matching (same script) |
| Unused declarations | 35 candidates (~28 real) | raw script: 20; **comment-stripped: 36 (~29 real)** | `unused_symbols.py`, on the live tree and on a comment-stripped copy (see appendix) |
| Untyped JSON (`JSONSerialization` / `[String: Any]` lines) | 23 | **17** | grep |
| `GlobalSettings.shared` / `UserDefaults.standard` refs | 64 / 112 | **63 / 101** | grep |
| `@Observable` / classes | 5 / 14 | **4 / 13** | grep |
| Build warnings, macOS | 0 Swift + 1 tool notice | **0 Swift + 1 tool notice** (`appintentsmetadataprocessor: Metadata extraction skipped`) | clean build, `grep 'warning:'` |
| Build warnings, iOS Simulator | 0 + 1 | **0 + 1** (same notice) | same |
| DocC warnings | 0 | **0** (only the same tool notice); `VeloFilms.doccarchive` produced | `xcodebuild docbuild` |
| Security findings (open) | C1 · H4 · M8 · L8 | **C0 · H1 (accepted) · M6 (2 partly fixed) · L8 open + 2 accepted · Info 2** | manual review |

## Change since last scorecard

| # | Category | Round 1 | Round 2 | Change | Why |
|---|---|---|---|---|---|
| 1 | Correctness | 5 | 5 | 0 | Garmin removal deleted 3 force-unwraps and 2 Garmin bugs, but every other round 1 bug is still in the code, and a new one (GPX-drop gating) was found. Too small a net change to move the score. |
| 2 | Architecture | 4 | 4 | 0 | No structural change. Two more files crossed 300 lines, but only through added comments, so this is not counted as a regression. Five fewer long functions, all from deleted Garmin code. |
| 3 | Idioms | 5 | 5 | 0 | Six fewer untyped-JSON uses (Garmin). Dead code unchanged once comments are discounted. |
| 4 | Concurrency | 3 | 3 | 0 | No build-setting or isolation change. |
| 5 | Security | 2 (capped) | 5 | **+3** | Critical closed (rotated and purged); 3 of 4 Highs fixed; privacy manifest added and verified in both bundles; Garmin password and impersonation flow gone. Held at 5 by the accepted High, 6 open Mediums and no automated test of the new security code. |
| 6 | Testing | 1 | 1 | 0 | Still no test target. |
| 7 | Doc coverage | 2 | 9 | **+7** | 17.6 % → 100 %; headers 0 → 57. |
| 8 | Doc quality | 4 | 7 | **+3** | From 0 DocC tags to 148 tags; "why", side-effect and limitation notes added; Python references now say "original Python app (not in this repo)". Restating one-liners and the missing Parameters tags keep it below 8. |
| 9 | Accuracy | 3 | 6 | **+3** | 19 mismatches plus the 40-instance class are gone, apart from 2 carried over. 12 smaller mismatches were found in a 45-claim check. |
| 10 | Project docs | 3 | 7 | **+4** | ARCHITECTURE.md and SECURITY.md added and largely accurate; README errors fixed; CLAUDE.md updated. Stale bundled Build/*.md remain. |
| | **Overall** | **31.6 (F)** | **53.0 (D)** | **+21.4** | Docs +17.8, Code +3.6 (all from Security). **No category dropped.** |

## Security findings

Checklist results (12 items, same as round 1):

| # | Item | Result |
|---|---|---|
| 1 | Secrets (incl. history) | `secret_scan.sh`: 112 commits; Secrets.swift never tracked; all historic `clientSecret` literals are the placeholder `"YOUR…"`; **no compiled `.app` binaries in history**; no blob contains `c0ff…` (full object scan). Current build holds `9370…` (the new, rotated secret; accepted). Repo is `PUBLIC`. |
| 2 | Storage | Strava tokens in Keychain (`KeychainStore`, `AfterFirstUnlockThisDeviceOnly`); `security find-generic-password` finds both items; UserDefaults has only `stravaTokenExpiry`; Garmin keys deleted at launch (VeloFilmsApp.swift:21-25). |
| 3 | Data at rest | Unchanged: GPX/JSONL/segments written with no file protection and no backup exclusion. |
| 4 | Network | HTTPS only; redirect token now host-restricted. No OAuth `state`; token exchange and refresh ignore HTTP status; 0 `timeoutInterval`; no retry. |
| 5 | Logging | `os.Logger` used in new code (status codes only, `.public`, no secrets). 5 `print` calls remain in Release. `PipelineExecutor` logs `error.localizedDescription` without a privacy annotation (PipelineExecutor.swift:91); Logger's default for interpolated strings is private, so this is acceptable. |
| 6 | Input validation | GPX name unescaped; resample unbounded (now documented); MP4 `mvhd` parser bounds-checked (FrameSampler.swift:72-84). |
| 7 | WebViews | None (0 `WKWebView`). OAuth uses `ASWebAuthenticationSession`. |
| 8 | Permissions/entitlements | iOS: no extra entitlements. macOS (accepted personal build): signed entitlements still show `network.server`, `downloads.read-write`, `user-selected.read-write`, no sandbox (pbxproj:260-274). |
| 9 | Privacy manifest | `PrivacyInfo.xcprivacy` present; bundled in **both** built apps (`Contents/Resources/PrivacyInfo.xcprivacy` on macOS, app root on iOS). Required-reason APIs found in code: UserDefaults (CA92.1 ✓); `.contentModificationDateKey` (CopyVideosView.swift:301-306, :347-353), `.fileSizeKey` (:387), `attributesOfItem[.size]` (ConcatStep.swift:111), all on user-chosen folders (3B52.1 ✓). No disk-space, boot-time or keyboard APIs (grep = 0). "Data Not Collected" is consistent: there's no developer server. Route coordinates go to Apple MapKit, which is first-party. **Accurate.** |
| 10 | Dependencies | None (no SPM, CocoaPods or Package.resolved). macOS shells out to Homebrew `ffmpeg` (accepted). |
| 11 | Error leakage | Garmin raw bodies gone. FFmpeg's full stderr still reaches the UI (PipelineExecutor.swift:147; ProjectDetailView.swift:8 says so). Strava OAuth error strings are technical ("Strava OAuth callback missing code parameter"). |
| 12 | Debug leftovers | 0 `#if DEBUG`; 5 `print`; no test accounts or debug menus. |

### Findings table (with round 1 tracking)

| ID | Severity | File:line | Issue | Impact (plain English) | Fix | Effort | Round 1 status → now |
|---|---|---|---|---|---|---|---|
| C1 | ~~Critical~~ | git history (`35f66b5`) | Strava secret in committed binaries on a public repo | — | — | — | **Fixed.** Rotated (build value changed `c0ff…` → `9370…`), history purged (object gone, 0 blobs match), force-pushed (`origin/main` = `3d77ef1`). Residual: GitHub's cached views of old commits can't be verified from here (see I1). |
| H1 | High (**accepted**) | StravaAuth.swift:29-30, :99-102, :166-169 | Client secret compiled into the app and sent from the device | Anyone with the app can extract it and impersonate Velo Films to Strava (quota abuse, convincing phishing, revoked API access) | Server-side token exchange; until then, rotate if abused | M–L | Open → **Accepted** by owner, documented in SECURITY.md:59-61 |
| H2 | ~~High~~ | StravaAuth.swift:35-67; KeychainStore.swift | Tokens in UserDefaults | — | — | — | **Fixed.** Keychain, `AfterFirstUnlockThisDeviceOnly`; migration deletes the plain copy only after a successful write (:48-55). Verified on this Mac. |
| H3 | ~~High~~ | (deleted) GarminAuth/GarminClient/GarminImportView | Garmin password and impersonation flow | — | — | — | **Fixed** (feature removed; legacy keys wiped at launch). |
| H4 | ~~High~~ | StravaClient.swift:225-245 | Bearer token re-sent on any redirect | — | — | — | **Fixed.** https + `strava.com`/`*.strava.com` only; header cleared otherwise. A suffix check with a leading dot is correct (`evilstrava.com` is rejected). |
| M1 | Medium | StravaAuth.swift:118-125, :148-150 | No OAuth `state`; the callback isn't checked; any app can claim `velofilms://` | Login CSRF: someone could link the user's app to the attacker's Strava account | Random `state`, verify on callback | S | **Open** |
| M2 | Medium | StravaAuth.swift:103-104, :170-171; all requests | Token exchange and refresh ignore HTTP status; 0 timeouts; no retry | A wrong secret or expired refresh shows "data couldn't be read"; a stalled network hangs the import screen | Check status (map 400/401 to "sign in again"); set `timeoutInterval` | S | Open → **Partly fixed** (API GETs check status, StravaClient.swift:213-215) |
| M3 | ~~Medium~~ | Shared/App/PrivacyInfo.xcprivacy | No privacy manifest | — | — | — | **Fixed**, verified accurate and bundled on both platforms |
| M4 | Medium | StravaClient.swift:95, :119, :136, :153; JSONLWriter.swift:22 | GPS tracks, heart rate and description written with no file protection or backup exclusion | Lost or shared iPad, or an unencrypted backup, reveals home location and full ride history | `.completeFileProtectionUntilFirstUserAuthentication` on iOS; document | S | **Open** (documented SECURITY.md:12) |
| M5 | Medium | StravaAuth.swift:155-158 | Sign-out doesn't revoke on Strava; no "Delete all my data" | The user can't fully withdraw; the token stays valid on the server | Call `/oauth/deauthorize`; add Delete-all (settings, Keychain, project list, caches) | M | **Open** (Garmin part gone) |
| M6 | Medium | MinimapRenderer.swift:58; IntroBuilder.swift:374; StravaImportView | No consent or disclosure before data goes to Strava (US) and Apple Maps | Breaks the owner's consent standard | One-time disclosure screen naming each company and country; withdrawable; offline map fallback | M | **Open** (Garmin and S3 recipients gone) |
| M7 | Low (**accepted**) | pbxproj:260-274, :323-337 | macOS: no sandbox; unused `network.server` and Downloads entitlements | A compromised input or tool runs with full user rights (personal Mac only) | Remove the unused entitlements at least | S | Medium → **Accepted**, downgraded to Low by owner decision (SECURITY.md:62-64) |
| M8 | Medium | PipelineExecutor.swift:147 → ProjectDetailView.swift | Full FFmpeg stderr shown to the user | Leaks file paths into screenshots; poor UX | Plain message plus a "Details" disclosure | S | Open → **Partly fixed** (Garmin raw bodies gone) |
| L1 | Low | StravaClient.swift:199-200 | Activity name inserted into GPX XML unescaped | A ride named `A & B` produces invalid GPX, so Flatten fails | XML-escape | S | **Open** |
| L2 | Low | GPXParser.swift:131-153 | Resample loop unbounded | A corrupt timestamp means memory blow-up or a hang | Reject spans over 48 h | S | **Open** (now documented :45-46) |
| L3 | Low (**accepted**) | FFmpegBridge.swift:34-40 | `ffmpeg` via PATH, unverified | A planted binary runs with app rights (personal Mac) | Absolute path plus signature check | S | **Accepted** (documented :20-22) |
| L4 | Low | ConcatStep.swift:221, :292, :442; IntroBuilder.swift:272, :288 | `print` in Release | Ride names and paths in the console | `Logger` with `.private` | S | **Open** |
| L5 | ~~Low~~ | Scripts/garmin_helper.py | Password on the command line | — | — | — | **Fixed** (deleted) |
| L6 | Low | FilePickerBridge.swift:50; GlobalSettings.swift:286 | `startAccessingSecurityScopedResource` never stopped | Kernel resource leak in long sessions | One owner of scoped access | S | **Open** (documented FilePickerBridge.swift:10-11) |
| L7 | Low | Built app Resources | Gitignored commercial tracks ("The White Stripes - Seven Nation Army.mp3", "Can't Stop.mp3") and Build/PLAN.md, README.md, QUICKSTART.md bundled into both apps (verified in both builds) | Licensing risk if distributed (the iPad build is the App Store product); internal docs ship to users | Exclude from target membership or move out of the synced folder | S | **Open**; higher priority now that iPad is the App Store target |
| L8 | Low | `project.xcworkspace/xcuserdata/…` (3 tracked files) | User Xcode files tracked despite .gitignore | Local paths leak; noisy diffs | `git rm --cached` (with OK) | S | **Open** |
| N1 | Low (new) | KeychainStore.swift:47-58 | `set` deletes the old item before adding the new one; if `SecItemAdd` fails, the token is gone | A transient Keychain failure on refresh signs the user out | `SecItemUpdate`, falling back to `SecItemAdd` on `errSecItemNotFound` | S | **New** |
| N2 | Low (new) | KeychainStore / app launch | Keychain items survive app deletion on iPad; not cleared on fresh install (standard §3) | A reinstall silently reuses an old Strava sign-in | First-launch flag in UserDefaults, then delete items | S | **New** (acknowledged SECURITY.md:65, not fixed) |
| I1 | Info | GitHub | Cached views or forks of pre-purge commits may still exist | The old secret is revoked, so impact is low | Optional GitHub Support purge request | S | New tracking item |
| I2 | Info | scratchpad `backup-velo-films-swift.git` | Local pre-purge mirror still contains the old (revoked) secret | Low; local temp folder only | Delete when no longer needed | S | New |

Open counts: **Critical 0 · High 1 (accepted) · Medium 6 (M2 and M8 partly fixed) · Low 8 open + 2 accepted · Info 2.**

## Documentation

### Doc-quality sample (26 comments, quoted)

Good: explains why, side effects, threading or limits.
1. KeychainStore.swift:10-15: "items use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so … never sync to iCloud Keychain … stay readable after the first unlock so a token refresh can run while the screen is locked … The macOS data-protection keychain is not used because it needs a keychain-access-groups entitlement … (writes fail with -34018)." Gives why, platform difference and workaround.
2. KeychainStore.swift:17: "Calls are synchronous and quick; callers run on the main actor." Threading.
3. KeychainStore.swift:44: "`true` if the Keychain now matches the request (a delete of a missing item counts as success)."
4. StravaAuth.swift:45-47: "The copy is only deleted once the Keychain write succeeds; if it fails, the user is shown as signed out."
5. StravaAuth.swift:79-82: "The 5-minute margin avoids a token expiring part-way through a multi-request download. … - Throws: `StravaError.noToken` … - Note: A refresh replaces both stored tokens." Why, Throws and a side effect.
6. StravaAuth.swift:155: "Deletes the stored tokens. Does not revoke the app's access on strava.com." States a limitation honestly.
7. StravaClient.swift:108-109: "- Throws: … errors writing segments or laps (description write failures are ignored)."
8. StravaClient.swift:222-224: "Security: the bearer token grants access … so it must never be forwarded to another host or over plain http."
9. PipelineExecutor.swift:40-41: "`stepName` itself always runs, even if its output exists. On failure the error is stored in `lastError` and appended to `pipeline.log`." Side effects.
10. PipelineStep.swift:64: "- Returns: `true` if the output exists. Does not check that it is up to date."
11. GlobalSettings.swift:9-11: "changes are written back only when a view calls `save()`. Folder URLs are the exception … UserDefaults key names are permanent."
12. SceneDetector.swift:12-15: "with the defaults (15 s, fps 1) that is 15 frames, which at the default 5-second sampling interval means frames 75 seconds apart … Stateful and not thread-safe."
13. FrameSampler.swift:28-29: "AVFoundation does not expose mvhd.creation_time for NOVATEK mp42 files, so we read it directly from the binary."
14. FrameSampler.swift:126-127: "Frames within ±0.5 s … are accepted, which is much faster than exact-frame decoding and close enough for scoring."
15. JSONLReader.swift:13-14: "a `DecodingError` for the first line that doesn't match `T` (no partial result). - Note: Loads the whole file into memory."
16. JSONLWriter.swift:18: "on failure the previous file is left unchanged."
17. GPXParser.swift:45-46: "Memory and time grow with the ride's duration in seconds; a GPX with a corrupt far-off timestamp produces a very long timeline."
18. ScoreCalculator.swift:29-31: "Gradient counts only when moving (≥ 1 km/h), so GPS elevation noise while stopped doesn't score … The weights aren't normalised."
19. OutroBuilder.swift:14-17: "a 3.7 s collage with the title fading in at 1 s, cross-fading (0.7 s) into 2 s of black … Side effects: replaces `_outro.mp4` and writes working files to `splash_assets/`." Verified against :47-51 and :74.
20. VideoCompositor.swift:66-67: "AVFoundation calls this on its own background queues. The project's default main-actor isolation also applies to this class, and the lazily created `ciContext` is not synchronised."
21. Project.swift:110: "- Note: Synchronous file system access; call it when the screen appears or after a step finishes."

Adequate or weak: says what, not why, or restates the code.

22. Project.swift:87-94: "`true` if the step output exists." repeated four times.
23. AppConfig.swift:186: "Map x position."; :114 "Weight of speed." (GlobalSettings.swift:114).
24. FilePickerBridge.swift:86: "Stores the callback."
25. VideoCompositor.swift:18: "Required by the protocol; post-processing is allowed."
26. PipelineExecutor.swift:33: "Registers the implementation for a step, replacing any earlier one." Fine, but has no `- Parameters:`. 52 of 116 parameterised functions are in the same position (list in `r2-doctags.txt`).

### Accuracy check (45 claims) and every mismatch found

Verified correct (33 of the 45): KeychainStore.swift:10-15 vs :55; :44 vs :49; StravaAuth.swift:45-47 vs :52-53; :79 vs :86 (300 s); :155 vs :156-158; StravaClient.swift:108-109 vs :119; :220-224 vs :237-243; VeloFilmsApp.swift:16-24; PipelineExecutor.swift:40-41 vs :125, :93; :52-53 vs pbxproj:304; ProgressReporter.swift:14; GlobalSettings.swift:9-10; :54 vs ConcatStep.swift:453-458; :81 (`dynamicGauges` read only by the toggle, GlobalSettingsView.swift:355-356); AppConfig.swift:42-44 vs SceneDetector.swift:26; :96-99 vs ScoreCalculator.swift:35-37; ScoreCalculator.swift:29-31 vs :36; SceneDetector.swift:30 vs `CameraBuffer.oldest`; FrameSampler.swift:17, :139-140, :166; ExtractStep.swift:10-11 vs :82; GPXParser.swift:22 vs :169; JSONLWriter.swift:18; OutroBuilder.swift:14-15; GaugeRenderer.swift:222-224 vs drawGaugeCell angles; SegmentMatcher.swift:5 vs AppConfig StravaBoost; YOLOInference.swift:26-27 vs :33, :41-45, :69-71; ProjectPreferences.swift:9-10 vs ClipSelector.swift:17; Project.swift:186-187 vs :188; CopyVideosView.swift:9 vs :393; ARCHITECTURE.md Concurrency (:111-114), storage table (:88-95, `projectStoreV1` Project.swift:165, Keychain service KeychainStore.swift:20), scoring (:73-75), clocks (:79-84); SECURITY.md:11, :16 (only Strava and Apple Maps network use; grep finds 3 `URLSession`/`URLRequest` sites, all Strava), :24 (.gitignore has `**/Secrets.swift` and `*.app/`), :45-47; CLAUDE.md build, layout and Keychain lines; README.md:39-45 pipeline table, :56 "Settings → Time Sync" (GlobalSettingsView.swift:31), :82.

**Mismatches (12):**
1. **PipelineStep.swift:57** (and the doc at :49 "`nil` for steps checked by folder contents"): the inline comment says splash is complete when "splash_assets/ directory populated", but the code checks the single file `clips/_intro.mp4` (:73).
2. **GlobalSettings.swift:107-108:** "the defaults sum to 0.95. scoreWeightDualCamera is added separately". The five composite weights (:111-119) sum to **0.85**; 0.95 only includes the dual-camera bonus the same sentence excludes.
3. **AppConfig.swift:225:** `markerRadius` is documented as "Rider position marker radius, in pixels", but it is used as a diameter (MinimapRenderer.swift:141: `markerRadius / 2`).
4. **AppConfig.swift:244-245:** "iOS: VideoToolbox hardware encoder (Native FFmpegKit build has no libx264)". There is no FFmpegKit (README.md:24), and the iOS branch of `videoCodec` is never reached, because its only callers (ConcatStep.swift:225, :296; ClipCompositor.swift:110) run on macOS only.
5. **FFmpegBridge.swift:6:** "so steps can be tested with a fake runner". Only `ClipCompositor` takes an injected bridge; `ConcatStep` calls `makeBridge()` itself (ConcatStep.swift:58, :69, :101).
6. **FFmpegBridge.swift:48-49:** "satisfying strict-concurrency Sendable checks". The project doesn't build with strict concurrency (Swift 5, no `SWIFT_STRICT_CONCURRENCY`). A minor, anticipatory wording.
7. **ExtractStep.swift:144, :154 (user-facing text):** "Settings → Camera Calibration". The tab is "Time Sync" (GlobalSettingsView.swift:31). *Carried over from round 1 (#13).*
8. **README.md:62:** "Drop a `.gpx` file — drag directly into the project folder". Flatten would find it (FlattenStep.swift:49-58), but the project screen only counts `working/ride.gpx` (Project.swift:44, :123), so the Analyse card stays locked (ProjectDetailView.swift:25, :153).
9. **ARCHITECTURE.md:60:** Flatten "Reads `ride.gpx`". It actually reads the first `.gpx` in `working/`, then the source-clip folder, then the project folder (FlattenStep.swift:49-58).
10. **Shared/Steps/Build/README.md, PLAN.md (:3, :27, :116), QUICKSTART.md:** still claim macOS 14+/iOS 17+ and Swift 6 compliance, and are copied into both app bundles. *Carried over from round 1 (#19).*
11. **EnrichStep.swift:39** ("mirrors enrich.py") and **FlattenStep.swift:47** ("same search order as flatten.py"): two Python references don't say "original Python app, not in this repo", against CLAUDE.md's own new rule. Every other instance was fixed.
12. **SECURITY.md:66:** "no network timeouts or status checks". Overstated: Strava API GETs do check status (StravaClient.swift:213-215); only the token exchange and refresh don't.

### Remaining documentation gaps
- DocC tags missing on 52 parameterised functions, 15 non-Void returns and 4 throwing functions (full list from `r2_doctags.py` in the appendix). Most are protocol conformances (`run(project:reporter:)` in every step, the UIKit picker plumbing) and IntroBuilder helpers.
- No DocC catalog (`*.docc`: 0), so there are no overview articles. ARCHITECTURE.md covers this for now.
- Restating one-liners in Project.swift (`ProjectArtifacts`), AppConfig.swift (`HUD`) and FilePickerBridge.swift.
- Stale Build/*.md files (mismatch 10) should be deleted or moved to `docs/`.

## Bugs noticed (list only)

Still open from round 1: 1 (pedestrian weight not loaded, GlobalSettings.swift:224 saved, never read in :141-201); 2 (mute volume reverts, :163-166); 3 (projects lost when drive unplugged, Project.swift:186-188; now documented); 4 (delete-then-copy, CopyVideosView.swift:393-395; now documented); 5 (manual selections lost silently, ManualSelectionView.swift:452); 6 (score bar differs from real score, ManualSelectionView.swift:1158-1159; now documented); 7 (detect weight 0.30 default vs 0.35 Reset, GlobalSettings.swift:111 vs GlobalSettingsView.swift:497); 8 (Re-run and Delete without confirmation, ProjectDetailView / ProjectListView); 9 (Strava error shown as decode error, StravaAuth.swift:103-104, :170-171); 12 (`NSWindow()` fallback, StravaAuth.swift:182); 13 (`/dev/null` model URL, ProjectDetailView.swift:363); 14 (compositor data race, VideoCompositor.swift:85); 15 (dead code, about 29 symbols).
Gone with Garmin: 10, 11.

Independently confirmed from PROGRESS.md's list: 16 (scene window 75 s, not 15 s; SceneDetector.swift:26 with the 5 s grid); 17 (per-project highlight target ignored; ClipSelector.swift:17 uses `AppConfig.targetClips`); 18 (Enrich segment score ignores the Strava offset; EnrichStep.swift:113 vs SelectStep.swift:62-76); 19 (outro black-clip duration passed as 3.7 s, OutroBuilder.swift:81); 21 (`dynamicGauges` unused); 22 (disabling bicycle drops people, YOLOInference.swift:41-45).

New this round:
- **N-a.** A GPX not named `working/ride.gpx` keeps the Analyse card locked, though Flatten could use it (ProjectDetailView.swift:25, :153; Project.swift:44, :123 vs FlattenStep.swift:49-58). This contradicts README.md:62.
- **N-b.** `KeychainStore.set` deletes before adding, so a failed add loses the token (KeychainStore.swift:47-58).
- **N-c.** `GPXParser.iso8601Epoch` allocates `ISO8601DateFormatter` twice per track point (GPXParser.swift:203-208). Slow on long rides.
- **N-d.** Comment indentation broken mid-closure (Project.swift:186-188). Cosmetic.

---

## Appendix — Evidence and commands

All logs and helper outputs are in `/private/tmp/claude-502/-Volumes-GDrive-Github-velo-films-swift/a3f2ad4b-ae1f-46ad-b281-a349590ecdbd/scratchpad/` (prefix `r2-`).

### Builds, test, DocC (clean DerivedData outside /private/tmp, because coremlc can't write there)
```
xcodebuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/VeloFilms-scorecard-r2-mac build          # exit 0, ** BUILD SUCCEEDED **
xcodebuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/VeloFilms-scorecard-r2-ios build   # exit 0
xcodebuild docbuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/VeloFilms-scorecard-r2-doc        # exit 0, ** BUILD DOCUMENTATION SUCCEEDED **, VeloFilms.doccarchive
xcodebuild test -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS' ...  # exit 66: "Scheme VeloFilms is not currently configured for the test action."
grep 'warning:' r2-build-macos.log | sort -u     # 1 line: appintentsmetadataprocessor notice
grep 'warning:' r2-build-ios.log | sort -u       # same 1 line
grep 'warning:' r2-docbuild.log | grep -v appintents | wc -l   # 0
xcodebuild -list -project VeloFilms/VeloFilms.xcodeproj         # Targets: VeloFilms (only)
grep -nE "SWIFT_VERSION|STRICT_CONCURRENCY|SWIFT_DEFAULT_ACTOR|ENABLE_APP_SANDBOX|INCOMING|DOWNLOADS" VeloFilms/VeloFilms.xcodeproj/project.pbxproj
git diff --stat VeloFilms/VeloFilms.xcodeproj/project.pbxproj   # empty: project settings unchanged
```

### Built-app checks
```
find <mac app> <ios app> -name PrivacyInfo.xcprivacy            # present in both
find <mac app> <ios app> \( -name '*.md' -o -name '*.mp3' \)     # PLAN.md, README.md, QUICKSTART.md, "The White Stripes - Seven Nation Army.mp3", "Can't Stop.mp3" in both
strings -n 40 <binary/debug.dylib> | grep -E '^[0-9a-f]{40}$' | cut -c1-4    # 9370 (round 1: c0ff)
codesign -d --entitlements - --xml <mac app> | plutil -p -       # downloads.read-write, user-selected.read-write, get-task-allow, network.client, network.server; no app-sandbox
```

### Metrics (unchanged scripts)
```
python3 -I swift_metrics.py VeloFilms/VeloFilms --json r2-metrics.json > r2-metrics.txt
python3 -I unused_symbols.py VeloFilms/VeloFilms > r2-unused.txt                          # candidates=20
python3 -I r2_strip_comments.py VeloFilms/VeloFilms r2-nocomments
python3 -I unused_symbols.py r2-nocomments > r2-unused-nocomments.txt                     # candidates=36
python3 -I r2_strip_comments.py r2-head/VeloFilms/VeloFilms r2-head-nc && python3 -I unused_symbols.py r2-head-nc   # 36 (HEAD, pre-change)
python3 -I r2_doctags.py VeloFilms/VeloFilms > r2-doctags.txt                              # Parameters 64/116, Returns 47/62, Throws 37/41
find VeloFilms/VeloFilms -name '*.swift' ! -name Secrets.swift | xargs cat > r2-all.swift.txt
grep -o 'try?' r2-all.swift.txt | wc -l                     # 98
grep -c '@Observable' r2-all.swift.txt                      # 4
grep -cE '^\s*(final )?class ' r2-all.swift.txt             # 13
grep -o 'GlobalSettings.shared' r2-all.swift.txt | wc -l    # 63
grep -o 'UserDefaults.standard' r2-all.swift.txt | wc -l    # 101
grep -cE "JSONSerialization|\[String: Any\]" r2-all.swift.txt   # 17
grep -c '// MARK:' r2-all.swift.txt                         # 145
grep -nE "\b(TODO|FIXME|HACK|XXX)\b" r2-all.swift.txt       # 0
```
**Method note (unused symbols):** `unused_symbols.py` counts word occurrences anywhere in the source, comments included. Round 2 added doc comments that mention unused names (e.g. "see `YOLOClass`", "see `writeFramesToDisk`"), which lowers the raw count from 36 to 20 without removing any code. To compare like with like, the script was also run, unmodified, on a copy with comments stripped (`r2_strip_comments.py`): 36 candidates both before (HEAD) and after. Round 1's 35 was measured with comments present; the HEAD comment-stripped run gives 36, so dead code is effectively unchanged. False positives, as in round 1: the 4 `AVVideoCompositionInstruction` protocol properties and `VeloFilmsApp` (`@main`).

`swift_metrics.py` summary output (round 2):
```
files=57 lines=10995 code_lines=8050
headers=57/57
force_unwrap=49 try!=0 as!=0 fatalError=0 preconditionFailure=1 precondition=0 print/NSLog=5
TODO/FIXME/HACK/XXX=0
doc_coverage=617/617 = 100.0%  (/// lines total=1234)
files_over_300=9   (1202 ManualSelectionView, 795 GlobalSettingsView, 603 IntroBuilder, 486 ConcatStep, 447 CopyVideosView, 443 ProjectDetailView, 335 GaugeRenderer, 309 GlobalSettings, 308 AppConfig)
functions_total=278 functions_over_40=37   (longest: 158 GlobalSettingsView.swift:371 body; 128 ExtractStep.swift:33 run; 125 ManualSelectionView.swift:171 body)
force-unwrap locations: JSONLWriter:30; ProgressReporter:29; StravaAuth:9,118,136; ClipCompositor:152,163,173; GaugeRenderer:327;
  MinimapRenderer:38×2,39×2,106,108,159×2,160×2,204; ConcatStep:315,317,319,321,412; SceneDetector:41; FrameSampler:101;
  IntroBuilder:132,134,220,230,360×2,361×2,364×2,365×2,377,379,525,550,562; OutroBuilder:129,199,202; ManualSelectionView:354×2
```
Per-file: every file is 100 % documented with a header. The full per-file table is in `r2-metrics.txt`.

### What changed in code (comments excluded)
```
git archive HEAD VeloFilms/VeloFilms | tar -x -C r2-head
python3 -I codeonly.py r2-head/VeloFilms/VeloFilms VeloFilms/VeloFilms
#   CODE CHANGED: VeloFilmsApp.swift (removeLegacyGarminData), StravaAuth.swift (Keychain + migration),
#   StravaClient.swift (redirect host check), ProjectDetailView.swift (Garmin button removed)
#   ADDED: Core/Security/KeychainStore.swift   REMOVED: GarminAuth, GarminClient, GarminImportView
#   Everything else: comments/whitespace only.
```

### Security
```
bash secret_scan.sh /Volumes/GDrive/Github/velo-films-swift > r2-secret-scan.txt
#   112 commits; Secrets.swift never tracked; clientSecret literals only "YOUR…"; compiled binaries ever committed: none;
#   visibility PUBLIC
git cat-file -t 35f66b5                                  # fatal: Not a valid object name
git log --all -p | grep -cE '\bc0ff[0-9a-f]{36}\b'       # 0
git cat-file --batch-all-objects --batch-check | (blobs > 1 MB) | strings | grep '^c0ff[0-9a-f]{36}$'   # no hits
git rev-parse HEAD origin/main                           # both 3d77ef1…
defaults read mahoneyclan.VeloFilms | grep -oiE '(strava|garmin)\w* ='   # only stravaTokenExpiry (values not printed)
security find-generic-password -s mahoneyclan.VeloFilms -a stravaAccessToken / -a stravaRefreshToken   # both present (values not printed)
grep -rn "timeoutInterval|FileProtection|isExcludedFromBackup|deauthorize|\"state\"" --include=*.swift    # 0
grep -rn "contentModificationDateKey|fileSizeKey|attributesOfItem|systemUptime|volumeAvailableCapacity|activeInputModes"  # CopyVideosView, ConcatStep only
git ls-files | grep xcuserdata                           # 3 tracked files
```

### Helper scripts added this round (scratchpad, not in the repo)
- `r2_strip_comments.py`: copies Swift sources with `//` and `/* */` comments removed (strings kept), so `unused_symbols.py` can run unmodified on code only.
- `r2_doctags.py`: for each documented non-private `func`/`init`, checks whether its `///` block has `- Parameter(s)` (if it takes parameters), `- Throws:` (if it throws) and `- Returns:` (if it returns a non-Void, non-`some View` type).
