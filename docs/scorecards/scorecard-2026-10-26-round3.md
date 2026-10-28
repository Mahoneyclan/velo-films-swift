# Velo Films — Engineering Scorecard, Round 3

- **Date:** 2026-10-26
- **Commit scored:** `3d77ef1` (main; local `origin/main` ref also `3d77ef1`) **plus the uncommitted working tree** (round 2 changes, plus round 2 Part A docs and Part B security fixes B1–B6, MusicLibrary, ErrorMessageView). This is the state that was built and scored.
- **Scope:** `VeloFilms/VeloFilms/` (the only folder in the build): 59 Swift files (+MusicLibrary, +ErrorMessageView). `Secrets.swift` was excluded from every metric and **not read**. Also reviewed: the repo docs, `docs/review/PROGRESS.md`, `.gitignore`, `project.pbxproj`, the full git history and both built apps.
- **Method:** the same scripts as rounds 1 and 2 (`swift_metrics.py`, `unused_symbols.py`, `secret_scan.sh`, `r2_doctags.py`, `r2_strip_comments.py`), re-run unchanged. A code-only diff against round 2's comment-stripped tree (`r2-nocomments`) shows exactly which code changed.
- **Reviewer stance:** independent and strict. PROGRESS.md claims were checked against the code, not taken on trust.

## Overall

| | Score |
|---|---|
| **Overall** | **59.0 / 100 — Grade D** (round 2: 53.0 D; round 1: 31.6 F) |
| Code subtotal | 24.6 / 60 (round 2: 23.4) |
| Documentation subtotal | 34.4 / 40 (round 2: 29.6) |

Caps: both platforms build, so the build-failure cap does not apply. No open Critical, so the Security cap does not apply. The only High (Strava client secret inside the app) is **accepted** by the owner.

**Quality gate (target 85, no category below 7, no open High or Critical): not met.** No open Critical or unaccepted High. Categories below 7: Correctness (5), Architecture (4), Idioms (5), Concurrency (3), Security (6), Testing (1). The owner's documentation target (≥ 34/40) **is now met** (34.4). The remaining gap is entirely code: the documentation categories are close to their ceiling, and the code categories have hardly moved in three rounds.

## Scorecard

| # | Category | Weight | Score /10 | Weighted | Reason |
|---|---|---|---|---|---|
| 1 | Correctness & robustness | 12% | 5 | 6.0 | Builds clean on both platforms. 0 `try!`, 0 `as!`, 0 `fatalError`, 1 `preconditionFailure` (StravaAuth.swift:206). Force-unwraps unchanged at 49 (same framework-call sites). `try?` 98 → 100. Fixed since round 2: Strava errors no longer surface as "data couldn't be read" (old bug 9), "Camera Calibration" message text (bug 20), Keychain delete-then-add (N-b). **Every other round 1/2 bug is still in the code** (pedestrian weight never loaded, GlobalSettings.swift:224 saved / never read in load; mute can't persist, :163-166; projects dropped when a drive is unplugged, Project.swift:195-197; delete-then-copy, CopyVideosView.swift:393; `/dev/null` model URL, ProjectDetailView.swift:361; detect weight 0.30 vs Reset 0.35, GlobalSettingsView.swift:497). New: **MusicLibrary.addTrack deletes the user's file if they pick a file already in My Music** (MusicLibrary.swift:91-95), the Single Track Override can't be cleared, and a 429 on token refresh signs the user out (see Bugs). |
| 2 | Architecture & structure | 10% | 4 | 4.0 | `MusicLibrary` is a clean, UI-free service in its own folder and `ErrorMessageView` is a small reusable view: good moves. But files over 300 lines stay at **9**, and GlobalSettingsView grew 795 → **906** lines (MyMusicSection added in the same file). Functions over 40 lines: **39 of 291** (round 2: 37/278). Longest still GlobalSettingsView.swift:371 `body` (158). Business rules still in views (CopyVideosView `runCopy`; MyMusicSection's add/remove flow is thin and fine). Strava-offset formula still duplicated (SegmentMatcher / ManualSelectionView). `MusicLibrary` and `KeychainStore` are static enums over `FileManager.default` / `SecItem*`, not behind protocols, so they can't be unit-tested without the real file system/Keychain. |
| 3 | Swift & SwiftUI idioms | 8% | 5 | 4.0 | Improvements: all 5 `print` calls → `os.Logger` with privacy annotations; plain-language `LocalizedError` enums (`StravaError`, `MusicLibraryError`, `PipelineError`); typed `JSONEncoder` for the token request. Unchanged: dead code **36 code-only candidates** (raw 20; same as round 2); untyped JSON 16 lines in StravaClient (+2 `[String: Any]` in KeychainStore, required by the Security API); `extension_`, `_FolderPickerRepresentable`. Not enough to move a whole point. |
| 4 | Concurrency & performance | 8% | 3 | 2.4 | Unchanged: `SWIFT_VERSION = 5.0` (pbxproj:307, :370), no strict concurrency, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Steps still do synchronous work on the main thread; the `ClipVideoCompositor` `ciContext` race (VideoCompositor.swift:93, :168) and `GPXParser` formatter allocation per point are still there. New: `ensureValidToken` can run two refreshes concurrently (main-actor re-entrancy across `await`), minor. |
| 5 | Security & privacy | 12% | 6 | 7.2 | **Verified fixed this round:** M1 OAuth `state` (StravaAuth.swift:116-150), M2 status checks + timeouts (StravaAuth.swift:173-177; StravaClient.swift:239-246), M8 FFmpeg output behind Details (PipelineExecutor.swift:148-166; ErrorMessageView.swift), L1 GPX name escaped (StravaClient.swift:196, :213-219), L4 0 `print`, L7 no commercial music or `.md` in either bundle (checked), N1 Keychain update-in-place (KeychainStore.swift:60-64). Still open: **3 Medium** (M4 file protection, M5 no revoke / Delete all my data, M6 no consent screen), 4 Low (L2, L6, L8, N2) and 4 new Low/Info (below). No automated test of any security code. Accepted: H1, M7, L3. |
| 6 | Testing | 10% | 1 | 1.0 | Unchanged. `xcodebuild -list`: one target. `xcodebuild test` exits 66: "Scheme VeloFilms is not currently configured for the test action." **0 tests ran.** `VeloFilmsTests/FocusFilterTests.swift` still in no target. PROGRESS.md's "8/8 checks passed" Keychain verification was a manual throwaway check, not a repeatable test. |
| 7 | Doc-comment coverage | 12% | 10 | 12.0 | **635 / 635 = 100 %** (non-private type-scope declarations); `//` headers **59 / 59**; `///` lines 1,472. DocC tags now complete: **Parameters 119/119, Returns 68/68, Throws 44/44** (round 2: 64/116, 47/62, 37/41). PROGRESS.md's 118/67/44 claim verified (the +1/+1 are the new files). Minor, not scored: `PipelineError` cases (PipelineExecutor.swift:139-142) have no `///` while `StravaError`/`MusicLibraryError` cases do; still no `.docc` catalog (not required by the standard). |
| 8 | Doc-comment quality | 10% | 8 | 8.0 | New comments are strong: why, side effects, security reasoning and platform differences (MusicLibrary.swift:9-12, :37-38, :76-77, :101-102; KeychainStore.swift:44-45, :54-55; StravaAuth.swift:81-83, :114-115, :165-166; StravaClient.swift:236-238; PipelineExecutor.swift:144-145, :155-156). Round 2's restating one-liners in `ProjectArtifacts` and `HUD.mapX` were rewritten. Still some thin ones: "Weight of speed." (GlobalSettings.swift:114), "Creates the delegate." / "Called with the chosen folder." (FilePickerBridge.swift:91-93), and private helpers in MyMusicSection without notes. |
| 9 | Accuracy | 8% | 8 | 6.4 | 0 TODO/FIXME/HACK. **48 claims checked; 3 mismatches** (round 2: 12), all small. All 12 round 2 mismatches verified fixed (10 by deleting the stale Build/*.md). |
| 10 | Project docs | 10% | 8 | 8.0 | README (My Music section, GPX instruction corrected), ARCHITECTURE (Media folder, My Music storage row), SECURITY (Fixed 2026-10-26 list, My Music row) and CLAUDE.md all match the code. Stale Build/*.md deleted. DocC builds with 0 warnings. Gaps: README doesn't mention the Single Track Override; SECURITY's Remaining risks doesn't list the new Low items (it points to the scorecard); still no DocC catalog. |
| | **Code subtotal** | 60% | | **24.6** | |
| | **Documentation subtotal** | 40% | | **34.4** | |
| | **Total** | 100% | | **59.0** | **Grade D** |

## Key metrics

| Metric | Round 1 | Round 2 | Round 3 | Method |
|---|---|---|---|---|
| Swift files (in build, excl. Secrets.swift) | 59 | 57 | **59** | `swift_metrics.py` |
| Lines (total / code) | 10,526 / 8,596 | 10,995 / 8,050 | **11,513 / 8,290** | same |
| Doc-comment coverage | 17.6 % | 100 % (617/617) | **100 % (635/635)** | same |
| `///` lines | 283 | 1,234 | **1,472** | same |
| Files with `//` header | 0/59 | 57/57 | **59/59** | same |
| DocC tags (Parameters / Returns / Throws) | 0 | 64/116 · 47/62 · 37/41 | **119/119 · 68/68 · 44/44** | `r2_doctags.py` |
| Tests | 0 run | 0 run | **0 run** (exit 66) | `xcodebuild test` |
| Force-unwraps | 52 | 49 | **49** | `swift_metrics.py` |
| `try!` / `as!` / `fatalError` / `preconditionFailure` | 0/0/0/1 | 0/0/0/1 | **0/0/0/1** | same |
| `try?` | 108 | 98 | **100** | grep |
| `print`/`NSLog` | 5 | 5 | **0** | same |
| TODO/FIXME/HACK/XXX | 0 | 0 | **0** | same |
| Files > 300 lines | 7 | 9 | **9** (1202, 906, 632, 480, 447, 441, 335, 309, 309) | `wc -l` |
| Functions > 40 lines | 42/293 | 37/278 | **39/291** | same |
| Unused declarations (comment-stripped) | ~35 | 36 | **36** (raw 20) | `unused_symbols.py` on `r2_strip_comments.py` output |
| Untyped JSON lines | 23 | 17 | **18** (16 StravaClient, 2 KeychainStore Security-API dicts) | grep |
| `GlobalSettings.shared` / `UserDefaults.standard` | 64/112 | 63/101 | **63/101** | grep |
| `@Observable` / classes | 5/14 | 4/13 | **4/13** | grep |
| `// MARK:` | — | 145 | **145** | grep |
| Build warnings macOS / iOS | 0+1 / 0+1 | 0+1 / 0+1 | **0+1 / 0+1** (only the appintents "Metadata extraction skipped" notice) | clean builds |
| DocC warnings | 0 | 0 | **0**; `VeloFilms.doccarchive` produced | `xcodebuild docbuild` |
| Security findings open | C1 H4 M8 L8 | C0 H1(acc) M6 L8+2acc | **C0 · H0 open (1 accepted) · M3 · L4 + 4 new Low/Info · 3 accepted** | manual |

## Change since last scorecard

| # | Category | Round 1 | Round 2 | Round 3 | Change R2→R3 | Why |
|---|---|---|---|---|---|---|
| 1 | Correctness | 5 | 5 | 5 | 0 | Three bugs fixed (Strava error text, Time Sync text, Keychain write); three new ones found in new or newly read code; the long-standing list is untouched. |
| 2 | Architecture | 4 | 4 | 4 | 0 | Good new service (`MusicLibrary`), but GlobalSettingsView grew by 111 lines and long functions rose 37 → 39. |
| 3 | Idioms | 5 | 5 | 5 | 0 | Logger and typed errors are better; dead code and untyped JSON unchanged. |
| 4 | Concurrency | 3 | 3 | 3 | 0 | No build-setting or isolation change. |
| 5 | Security | 2 (capped) | 5 | 6 | **+1** | Six findings closed (M1, M2, M8, L1, L4, L7) plus N1. Held at 6 by three open Mediums (consent, delete-all/revoke, file protection on the App Store iPad build) and zero security tests. |
| 6 | Testing | 1 | 1 | 1 | 0 | Still no test target. |
| 7 | Doc coverage | 2 | 9 | 10 | **+1** | DocC tags 100 % complete. |
| 8 | Doc quality | 4 | 7 | 8 | **+1** | Restating lines rewritten; new comments explain why and security reasoning. |
| 9 | Accuracy | 3 | 6 | 8 | **+2** | 12 → 3 mismatches, all minor. |
| 10 | Project docs | 3 | 7 | 8 | **+1** | Stale Build docs deleted; README/ARCHITECTURE/SECURITY updated for My Music and the security fixes. |
| | **Overall** | **31.6 (F)** | **53.0 (D)** | **59.0 (D)** | **+6.0** | Docs +4.8, Code +1.2 (all Security). No category dropped. Round gain ≥ 3, so the PROGRESS.md stop rule is not triggered by score; it is triggered by "3 rounds". |

## Security findings

Checklist (12 items, same as rounds 1–2):

| # | Item | Result |
|---|---|---|
| 1 | Secrets (incl. history) | `secret_scan.sh`: 112 commits; Secrets.swift never tracked; historic `clientSecret` literals only `"YOUR…"`; no compiled binaries in history. Built macOS and iOS apps each hold one 40-hex value starting `9370` (the rotated secret; accepted H1). Repo `PUBLIC`. No secret-shaped literals in the working tree outside Secrets.swift. |
| 2 | Storage | Tokens in Keychain; `set` now updates in place (KeychainStore.swift:60-64). Fresh-install clearing still missing (N2). |
| 3 | Data at rest | Unchanged: no file protection or backup exclusion (M4). My Music on iPad lives in Application Support with default protection (not personal data; fine). |
| 4 | Network | HTTPS only; `StravaNetwork.session` 30 s / 300 s timeouts; token and API calls check status; `state` checked; redirect token host-restricted. No retry (acceptable). |
| 5 | Logging | 0 `print`. `Logger` with `.private` for file/ride names (ConcatStep.swift:228, :299, :449); `.public` only for counts, status codes and bundled resource names. |
| 6 | Input validation | GPX name escaped (all five XML characters). Resample still unbounded (L2). New file input: MusicLibrary checks extensions; `lastPathComponent` prevents path traversal; but delete-before-copy (R3-L1). |
| 7 | WebViews | None. `ASWebAuthenticationSession` only. |
| 8 | Entitlements | Unchanged. macOS: `network.server`, `downloads.read-write`, `user-selected.read-write`, no sandbox (accepted M7). |
| 9 | Privacy manifest | Present in both bundles. New code adds no required-reason APIs (MusicLibrary uses `contentsOfDirectory` with no resource keys, `trashItem`, `copyItem`). Still accurate. |
| 10 | Dependencies | None. |
| 11 | Error leakage | FFmpeg output now behind Details (M8 fixed). Residual: `missingInput` messages still put internal file names and full paths on the main screen (R3-L3). |
| 12 | Debug leftovers | 0 `#if DEBUG`, 0 `print`. |

### Findings table (tracking rounds 1 → 2 → 3)

| ID | Severity | File:line | Issue | Fix | Effort | R1 → R2 → **R3** |
|---|---|---|---|---|---|---|
| C1 | ~~Critical~~ | git history | Strava secret in committed binaries | — | — | Open → Fixed → **Fixed** (build value still `9370…`) |
| H1 | High (**accepted**) | StravaAuth.swift:29-30, :171-172 | Client secret compiled into the app | Server-side token exchange | M–L | Open → Accepted → **Accepted** |
| H2 | ~~High~~ | KeychainStore.swift | Tokens in UserDefaults | — | — | Open → Fixed → **Fixed** |
| H3 | ~~High~~ | (deleted) Garmin | Garmin password flow | — | — | Open → Fixed → **Fixed** |
| H4 | ~~High~~ | StravaClient.swift:254-270 | Bearer token on any redirect | — | — | Open → Fixed → **Fixed** |
| M1 | ~~Medium~~ | StravaAuth.swift:116, :120, :149-150 | No OAuth `state` | — | — | Open → Open → **Fixed** (random UUID sent and compared) |
| M2 | ~~Medium~~ | StravaAuth.swift:173-177; StravaClient.swift:227-229, :239-246 | Token calls ignore status; no timeouts | — | — | Open → Partly → **Fixed** |
| M3 | ~~Medium~~ | PrivacyInfo.xcprivacy | No privacy manifest | — | — | Open → Fixed → **Fixed** |
| M4 | Medium | StravaClient.swift (GPX/segments/laps writes); JSONLWriter.swift | GPS data with no file protection / backup exclusion | `.completeFileProtectionUntilFirstUserAuthentication` on iPad | S | Open → Open → **Open** |
| M5 | Medium | StravaAuth.swift:157-159 | Sign-out doesn't revoke; no "Delete all my data" | `/oauth/deauthorize` + Delete-all | M | Open → Open → **Open** (deferred to code-quality track) |
| M6 | Medium | MinimapRenderer; IntroBuilder; StravaImportView | No consent before data goes to Strava (US) / Apple Maps | One-time disclosure, withdrawable | M | Open → Open → **Open** (deferred) |
| M7 | Low (**accepted**) | pbxproj | macOS unsandboxed, unused entitlements | Remove unused entitlements | S | Medium → Accepted → **Accepted** |
| M8 | ~~Medium~~ | PipelineExecutor.swift:148-166; ErrorMessageView.swift | FFmpeg stderr shown to user | — | — | Open → Partly → **Fixed** (residual: R3-L3) |
| L1 | ~~Low~~ | StravaClient.swift:196, :213-219 | GPX name unescaped | — | — | Open → Open → **Fixed** |
| L2 | Low | GPXParser.swift | Resample loop unbounded | Reject spans > 48 h | S | Open → Open → **Open** |
| L3 | Low (**accepted**) | FFmpegBridge.swift | `ffmpeg` via PATH | — | S | Open → Accepted → **Accepted** |
| L4 | ~~Low~~ | ConcatStep, IntroBuilder | `print` in Release | — | — | Open → Open → **Fixed** (0 `print`) |
| L5 | ~~Low~~ | Scripts/garmin_helper.py | Password on CLI | — | — | Open → Fixed → **Fixed** |
| L6 | Low | FilePickerBridge.swift:50; GlobalSettingsView.swift:73, :116, :132 | `startAccessingSecurityScopedResource` never stopped | One owner of scoped access | S | Open → Open → **Open** (MusicLibrary.addTrack does stop correctly) |
| L7 | ~~Low~~ | Built app Resources | Commercial tracks and Build/*.md bundled | — | — | Open → Open → **Fixed** (both bundles: 8 royalty-free tracks + intro/outro, 0 `.md`; git history has no commercial track names) |
| L8 | Low | `project.xcworkspace/xcuserdata/` | 3 user files tracked | `git rm --cached` (with OK) | S | Open → Open → **Open** |
| N1 | ~~Low~~ | KeychainStore.swift:60-64 | Delete-then-add could lose token | — | — | — → New → **Fixed** |
| N2 | Low | KeychainStore / launch | Keychain survives app deletion; no fresh-install clear | First-launch flag | S | — → New → **Open** (acknowledged SECURITY.md:79) |
| I1 | Info | GitHub | Cached pre-purge commits | Optional GitHub purge | S | — → New → **Open** |
| I2 | Info | scratchpad backup mirror | Old secret in local mirror | Delete | S | — → New → **Closed** (PROGRESS.md: deleted; `backup-velo-films-swift.git` no longer in the scratchpad listing) |
| **R3-L1** | Low (new) | MusicLibrary.swift:91-95 | `addTrack` deletes the destination before copying. If the chosen file is already in My Music (easy on Mac: Add Music… opens anywhere, including `~/Music/Velo Films/`), source == destination, so the user's file is **permanently removed** (not trashed) and the copy then fails. A failed copy of a same-named file also loses the old copy. | Skip when `source.standardizedFileURL == destination.standardizedFileURL`; copy to a temp name then `replaceItemAt` | S | **New** |
| **R3-L2** | Low (new) | StravaAuth.swift:176, :99-102 | Any 4xx from the token endpoint, including **429 rate-limit** and 408, is treated as "refresh token revoked": tokens are deleted and the user is signed out | Treat only 400/401 as rejected; map 429 to a "wait and retry" message | S | **New** |
| **R3-L3** | Low (new) | ExtractStep.swift:44, :62, :67, :161; EnrichStep.swift:52, :119; SelectStep.swift:37; FlattenStep.swift:71; BuildStep.swift:45 | `missingInput` text is technical ("extract.jsonl is empty", "Unrecognized camera name") and can include full folder paths, shown on the main screen with no Details split | Plain message + path in `technicalDetails` | S | **New** (residual of M8) |
| **R3-I1** | Info (new) | Shared/Resources/music/_Royalty Free/ | 8 "royalty-free" tracks ship in the App Store iPad build with no licence or attribution record in the repo. Some sources (e.g. chosic.com, YouTube Audio Library, Pixabay) require attribution or forbid redistributing tracks as standalone files inside an app | Record each track's licence; keep only tracks whose licence allows in-app redistribution | S | **New** |

Open counts: **Critical 0 · High 0 open (1 accepted) · Medium 3 · Low 4 carried + 3 new · Info 2 (I1, R3-I1) · Accepted 3 (H1, M7, L3).**

### New-code review notes (no extra findings beyond the above)
- **StravaAuth `state`:** `UUID().uuidString` (122 random bits) is sent and compared exactly; a missing `state` fails the check. Cancel is caught in StravaImportView.swift:113 and shows no error. Correct.
- **KeychainStore.set:** `SecItemUpdate`, then `SecItemAdd` only on `errSecItemNotFound`; the doc's "previous value still stored on failure" holds. `requestTokens` ignores the `Bool` result, so a failed Keychain write still returns a token for this session but the user is signed out next launch (minor; listed under Bugs).
- **ErrorMessageView:** shows `localizedDescription` plus Details only for `PipelineError`; text is selectable; colour is paired with an icon (not colour alone). Fine.
- **MusicLibrary:** extensions checked, folder fixed, `lastPathComponent` blocks traversal, security scope started/stopped. Removal is restricted to files directly inside My Music. Only issue is R3-L1.

## Documentation

### Doc-quality sample (quoted)

Good:
1. MusicLibrary.swift:9-10: "Users add their own tracks (which may be licensed only for personal use) to My Music, so commercial music is never distributed with the app." Why.
2. MusicLibrary.swift:37-38: "Xcode's synced folder copies `Resources/music/` files into the bundle root, so the root is searched too". Workaround explained (verified in both bundles).
3. MusicLibrary.swift:101-102: "macOS moves the file to the Trash, because the folder may hold the user's only copy." Why + platform difference.
4. KeychainStore.swift:44-45: "On `false` after a write, the previous value (if any) is still stored." Failure behaviour.
5. KeychainStore.swift:54-55: "Security: update in place … so a failed write never leaves the user with no token at all".
6. StravaAuth.swift:81-82: Throws list including "the stored tokens are then deleted". Side effect.
7. StravaAuth.swift:114-115: "a callback that this sign-in didn't start (e.g. another app opening velofilms://) is rejected." Security reasoning.
8. StravaClient.swift:236-238: "30 s is the longest wait for the next byte; 300 s caps a whole request, which covers the largest stream download". Explains magic numbers.
9. PipelineExecutor.swift:155-156: "the last 40 lines of FFmpeg's output, where the cause is." Why.
10. ErrorMessageView.swift:9: "Keeps raw tool output off the main screen while still letting the user copy it".
11. AppConfig.swift:225-226: markerRadius documented as a diameter, with why the name is kept.
12. GlobalSettings.swift:107-109: weights "not normalised … the five composite defaults sum to 0.85" (verified).

Weak: "Weight of speed." (GlobalSettings.swift:114); "Creates the delegate." (FilePickerBridge.swift:91); "Called with the chosen folder." (:89); `PipelineError` cases undocumented (PipelineExecutor.swift:139-142).

### Accuracy check (48 claims)

Verified correct (45): KeychainStore.swift:10-17, :44-45, :54-55; StravaAuth.swift:13-15, :45-47, :81-83, :110-112, :114-115, :156, :165-166; StravaError messages vs cases (:241-266); StravaClient.swift:56, :69, :194-196, :210, :236-238, :247-251; PipelineExecutor.swift:43-44, :56-57, :144-145, :155-156; ErrorMessageView.swift:9, :28 (`appendToLog` writes `\(error)`, which includes full stderr); MusicLibrary.swift:9-12, :22-24, :37-38, :65-66, :76-77, :101-102; ConcatStep.swift:458-462; GlobalSettingsView.swift:2 (six tabs, verified :28-43), :53, :619-620; ProjectPreferencesView.swift:25; ExtractStep.swift:150, :160 (tab "Time Sync", toggle label matches GlobalSettingsView.swift:258); GlobalSettings.swift:107-109; AppConfig.swift:225-226, :244-245; FFmpegBridge.swift:5-7; PipelineStep.swift:48-50, :71; Project.swift:88-89; README.md:62, :66-69, :92; ARCHITECTURE.md:29, :61, :95, :113-116; SECURITY.md:15 (git history checked), :58-67, :79.

**Mismatches (3):**
1. **ProjectDetailView.swift:8:** "Error text shown here comes straight from `PipelineError` (including FFmpeg's full output on failure)." Stale: the view now uses `ErrorMessageView` (:46-47), the message is plain, and FFmpeg's output (last 40 lines) is behind a Details disclosure.
2. **ProjectPreferencesView.swift:36** ("Random picks a different track each build.") and **README.md:71** ("Your tracks join the built-in ones in each project's track picker and in the reel's playlist"): both ignore the Single Track Override (GlobalSettingsView.swift:593-597). When it is set, ConcatStep.swift:464-467 plays only that file, so the per-project choice and the library are silently ignored. README doesn't mention the override at all.
3. **MusicLibrary.swift:130, :140** ("Use MP3, M4A, AAC or WAV") vs the iPad importer GlobalSettingsView.swift:681 (`[.mp3, .mpeg4Audio, .wav]`): raw `.aac` files can't be picked on iPad, although the error text tells the user AAC is supported. (The Mac panel uses `audioExtensions` and does allow AAC.)

All 12 round 2 mismatches: **fixed** (1 PipelineStep.swift:59; 2 GlobalSettings.swift:107-108; 3 AppConfig.swift:225; 4 AppConfig.swift:244-245; 5 FFmpegBridge.swift:5-7; 6 FFmpegBridge.swift:49-53; 7 ExtractStep.swift:150, :160; 8 README.md:62; 9 ARCHITECTURE.md:61; 10 Build/*.md deleted; 11 EnrichStep.swift:10, :62, FlattenStep.swift:7, :59; 12 SECURITY.md:56-67).

### Remaining documentation gaps
- No DocC catalog / overview articles (ARCHITECTURE.md covers this).
- `PipelineError` cases undocumented.
- README: add one line on the Single Track Override; SECURITY.md: add R3-L1/L2 and the music-licence item to Remaining risks.

## Bugs noticed (list only)

Still open from rounds 1/2: 1 pedestrian weight never loaded (GlobalSettings.swift:224 saved, not read in load); 2 mute volume reverts (`.nonZero`, :163-166); 3 projects lost when drive unplugged (Project.swift:195-197; comment indentation still broken, N-d); 4 delete-then-copy (CopyVideosView.swift:393); 5 manual selections lost silently (ManualSelectionView.swift:452); 6 score bar differs from real score; 7 detect weight 0.30 default vs 0.35 Reset (GlobalSettingsView.swift:497); 8 Re-run/Delete with no confirmation; 12 `NSWindow()` fallback (StravaAuth.swift:193); 13 `/dev/null` model URL (ProjectDetailView.swift:361); 14 compositor `ciContext` race (VideoCompositor.swift:93, :168); 15 dead code (36 candidates, ~29 real); 16 scene window 75 s not 15 s; 17 per-project highlight target ignored (`effectiveTargetClips` unused); 18 Enrich segment score ignores Strava offset; 19 outro black-clip duration 3.7 s; 21 `dynamicGauges` unused; 22 disabling bicycle drops people; N-a GPX not named `working/ride.gpx` keeps Analyse locked (now documented honestly in README:62, behaviour unchanged); N-c two `ISO8601DateFormatter`s per track point.

Fixed since round 2: 9 (Strava errors now plain and status-checked), 20 ("Camera Calibration" → "Time Sync"), N-b (Keychain update in place).

New this round:
- **B3-a.** `MusicLibrary.addTrack` deletes the user's file when they add a track that is already in My Music (MusicLibrary.swift:91-95). Data loss on Mac. (R3-L1)
- **B3-b.** The Single Track Override can't be cleared from the UI: `DirRow` has only "Choose…" (GlobalSettingsView.swift:595, DirRow :725) and nothing sets `musicURL = nil`. Once set, every reel uses that one file until the file is deleted.
- **B3-c.** A 429/408 from the token endpoint during refresh signs the user out (StravaAuth.swift:99-102, :176). (R3-L2)
- **B3-d.** `requestTokens` ignores `KeychainStore.set`'s result (StravaAuth.swift:181-182): on a Keychain write failure the sign-in appears to succeed but is gone at next launch, with no message.
- **B3-e.** Two overlapping `ensureValidToken()` calls can both refresh (no in-flight refresh task); Strava rotates refresh tokens, so the second may fail and sign the user out. Unlikely with today's sequential UI.
- **B3-f.** ProjectPreferencesView's track Picker keeps a saved `selectedMusicTrack` that no longer exists (e.g. removed from My Music) as an invalid selection; ConcatStep then silently falls back to a random track.
- **B3-g.** iPad "Single Track Override" picker allows `.aiff` (GlobalSettingsView.swift:71) while My Music rejects AIFF; minor inconsistency.

## Quickest wins to reach 85

Honest assessment: **85 is not reachable from documentation work.** Docs are at 34.4/40 (max 40). Code is 24.6/60 and needs about +26 points. Realistic ceilings after a focused code-quality track: Testing 1→7 (+6.0), Correctness 5→7 (+2.4), Security 6→8 (+2.4), Concurrency 3→6 (+2.4), Architecture 4→6 (+2.0), Idioms 5→7 (+1.6), plus docs to 9s (+2.8) ≈ **79–80**. Reaching 85 also needs Swift 6 strict concurrency and splitting the four largest files.

In order of points per hour:
1. **Add a test target (+4 to +6 points).** Wire in `FocusFilterTests.swift` (25 tests), then add pure-logic tests that need no network: `StravaClient.xmlEscaped`, `StravaError`/`PipelineError` messages and `technicalDetails`, `ScoreCalculator.composite`, `GPXParser` resampling, `SegmentMatcher.stravaOffset`, `MusicLibrary` (against a temp folder once the folder is injectable), `KeychainStore` round-trip. Also enable the scheme's test action so `xcodebuild test` runs.
2. **Fix the small bug list (+2.4 Correctness, +some Security).** Each is a few lines: pedestrian weight load, mute volume `.nonZero`, 0.30 vs 0.35 detect default, MusicLibrary self-copy (R3-L1), clear button for the override, 429 handling (R3-L2), confirmations for Re-run/Delete, first-launch Keychain clear (N2). Add a test for each as it's fixed.
3. **Close the three Mediums (+2.4 Security).** iPad file protection on project files (M4, one attribute per write), Strava `/oauth/deauthorize` plus "Delete all my data" (M5), one consent screen naming Strava (USA) and Apple Maps (M6). These are App Store-relevant for the iPad build anyway.

Cheap extras: delete the ~29 confirmed unused symbols (+0.8 Idioms); fix the 3 doc mismatches (+0.8 Accuracy); move `MyMusicSection` and other tabs out of GlobalSettingsView.swift (Architecture).

---

## Appendix — Evidence and commands

Logs and outputs: `/private/tmp/claude-502/-Volumes-GDrive-Github-velo-films-swift/a3f2ad4b-ae1f-46ad-b281-a349590ecdbd/scratchpad/r3/`.

### Builds, test, DocC (clean DerivedData, run with the sandbox disabled because coremlc can't write under /private/tmp)
```
xcodebuild -project VeloFilms/VeloFilms.xcodeproj -scheme VeloFilms -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/VeloFilms-scorecard-r3-mac build         # exit 0, ** BUILD SUCCEEDED **
xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/VeloFilms-scorecard-r3-ios build    # exit 0, ** BUILD SUCCEEDED **
xcodebuild docbuild ... -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/VeloFilms-scorecard-r3-doc                       # exit 0, ** BUILD DOCUMENTATION SUCCEEDED **, VeloFilms.doccarchive
xcodebuild test ... -destination 'platform=macOS'          # exit 66: "xcodebuild: error: Scheme VeloFilms is not currently configured for the test action."
grep 'warning:' <each log> | grep -v 'Metadata extraction skipped' | grep -v 'multiple matching destinations'   # 0 lines in all three logs
xcodebuild -list                                             # Targets: VeloFilms (only)
grep SWIFT_VERSION|STRICT_CONCURRENCY|SWIFT_DEFAULT_ACTOR project.pbxproj   # 5.0 (:307, :370); MainActor (:304, :367); no strict concurrency
```

### Built-app checks
```
find <mac app> <ios app> \( -name '*.mp3' -o -name '*.m4a' -o -name '*.md' -o -name PrivacyInfo.xcprivacy \)
#   both: intro.mp3, outro.mp3, 8 royalty-free tracks (Duck In The Alley, Out On My Skateboard, Scale The Wall, Soaring,
#   Windy Road Back To You, Luke-Bergs-Bliss, guitar_obsession-bicycle-road, susan-lu4esm-neon-pulse), PrivacyInfo.xcprivacy; 0 .md
strings -n 40 <binary/debug.dylib> | grep -E '^[0-9a-f]{40}$' | cut -c1-4    # 9370 (one in each app)
codesign -d --entitlements - --xml <mac app> | plutil -p -   # downloads.read-write, user-selected.read-write, get-task-allow, network.client, network.server
```

### Git checks
```
git log --all --name-only --format= | grep -iE '\.(mp3|m4a|wav|aac)$' | sort -u
#   only intro.mp3, outro.mp3, the 8 _Royalty Free tracks and 5 earlier copies of royalty-free tracks in music/ — no commercial names
bash secret_scan.sh <repo> > r3/secret-scan.txt           # 112 commits; Secrets.swift never tracked; literals only "YOUR…"; no binaries; PUBLIC
git ls-files | grep xcuserdata                             # 3 tracked files (L8)
git rev-parse --short HEAD                                 # 3d77ef1 (remotes/origin/main present)
```

### Metrics (unchanged scripts)
```
python3 -I swift_metrics.py VeloFilms/VeloFilms --json r3/metrics.json > r3/metrics.txt
#   files=59 lines=11513 code_lines=8290; headers=59/59; force_unwrap=49 try!=0 as!=0 fatalError=0 preconditionFailure=1 print/NSLog=0
#   doc_coverage=635/635 (/// lines 1472); files_over_300=9; functions_total=291 functions_over_40=39
python3 -I unused_symbols.py VeloFilms/VeloFilms             # candidates=20 (raw)
python3 -I r2_strip_comments.py VeloFilms/VeloFilms r3/nc && python3 -I unused_symbols.py r3/nc   # candidates=36 (same as round 2)
python3 -I r2_doctags.py VeloFilms/VeloFilms                 # withparams 119/119, throws 44/44, returns 68/68, gaps 0
grep counts over concatenated sources: try? 100; @Observable 4; classes 13; GlobalSettings.shared 63; UserDefaults.standard 101;
  JSONSerialization|[String: Any] 18; // MARK: 145; TODO/FIXME/HACK/XXX 0
```

### What changed in code since round 2 (comments and blank lines excluded)
```
diff of r2-nocomments (round 2 tree, comment-stripped) vs r3/nc, ignoring blank/whitespace-only lines:
  107 GlobalSettingsView  90 StravaAuth  23 ConcatStep  22 StravaClient  18 ProjectPreferencesView  17 PipelineExecutor
  15 KeychainStore  6 IntroBuilder  4 PipelineView  4 ProjectDetailView  4 ExtractStep  2 StravaImportView
  ADDED: Core/Media/MusicLibrary.swift, Views/Pipeline/ErrorMessageView.swift
  Every other file: comments only. Matches PROGRESS.md's description of Part A (docs) and B1–B6.
```

### Helper scripts added this round
- `r3/builds.sh`: runs the three clean builds and the test action in sequence, saving logs and exit codes. No other new helpers; all metrics used the round 1/2 scripts unchanged.
