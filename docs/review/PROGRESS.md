# Review loop progress

## ▶ RESUME HERE (saved end of 2026-10-28)

**Next session:** ask whether the Fine Tune hand test passed (steps under "Item 3" below); if yes, commit (the
Fine Tune screen, test target and docs are uncommitted). Open question: CLAUDE.md line 2 still says "paid App Store
product". Then item 4: stray-folder guard in ImportView and the remaining scorecard bugs.

### Whole-clip scoring (2026-10-31, uncommitted)
Review found each clip was judged by its first frame only, and detection barely separated moments (50–73% of
group-ride frames ≥ 0.7). The owner's Fine Tune removals were mostly steep but empty road; additions had more in view.
- Enrich pass 2 (`ClipRefiner`, `ClipWindowScorer`): shortlist 1.5 × target, up to 9 frames per clip on the leading
  camera, reuse pass 1 frames; detection = mean of the 2 best frames; action = change in weighted box area
  (noise 0.05, full at +0.25, checked on 4 rides); clip slides ±2 s (inside the files), both cameras together;
  strongest frame becomes the thumbnail. Speed and gradient averaged over the clip. Scene change removed.
- New default weights: gradient 0.20 → 0.10, action (old scene slot, key `scoreWeightScene`) 0.10 → 0.20.
- Tests: 8 new (`ClipWindowScorerTests`); 92 pass on macOS and iPhone 17 simulator.
- **Hand test:** Settings → AI Scoring → Reset to defaults; Re-run analysis on Brymaroo Saturday (note Enrich time vs
  before, expected ~15% longer); Build; check overtakes/passing riders are caught, thumbnails show the action, PiP
  in sync.

### Earlier notes (saved 2026-10-28, before a reboot)

**Objective changed 2026-10-28:** not a paid app any more — "just make it awesome" (reel quality + UX). The App
Store checklist (`docs/APP_STORE.md`) is reference only.

**Answered 2026-10-28: friends via TestFlight** (keep YOLO11s; bundled tracks may return to iPhone/iPad). Item 1 confirmed as next.

~~Open question for the owner:~~ who will use it — just me / friends via TestFlight / free on the App
Store? If personal/friends: keep the current YOLO11s model (licence issue doesn't apply), and decide whether to put
the 8 royalty-free tracks back into the iPhone/iPad build (they're limited to the Mac build via a platform filter in
`project.pbxproj`, folder exceptions set `C9AB00012FA0000000000001`).

**Proposed "awesome" order (owner to confirm):**
1. Reel ending: final highlight from the finish (and first from the start), music fade-out (backing music is cut
   hard today), "Ride complete" stats card in the outro.
2. Selection: wider spacing (30–64% of picks are <30 s apart), ride-wide coverage (gaps up to 62 min; the
   per-clip shortlist is undone by a global trim; start/end caps fixed at 4), with tests and before/after numbers
   across the 15 analysed rides (analysis script idea: per-ride spacing/coverage/PR counts from select.jsonl).
3. New Fine Tune screen: ride timeline (elevation behind, picks/laps/PRs) + horizontal film strip + one large
   moment + bottom buttons; clickable mock-up first; must work on iPhone too. Split the 1,200-line
   ManualSelectionView while doing it.
4. Test target (code-quality track), stray-folder guard in ImportView (`Fly_Raw` project was created by picking
   the parent folder), remaining scorecard bugs.
5. Optional: suggested iCloud Drive "Velo Films Music" folder (needs iCloud capability in the developer account).

**Item 2 (selection) done 2026-10-28.** Music: all 10 files ship in iPhone/iPad builds again (APP_STORE.md L2
reopened). YOLO only, never Apple Vision.
- `ClipSelector` rewritten: stopped moments (<2 km/h) ignored; gap = max(user min, ½ × riding footage ÷ target);
  best moment from each stretch (one per 3 clips), then best-first; start/finish picks never replace a coverage pick.
- Removed: opening/closing caps, the Zones and Candidate Pool settings (keys retired), scene-change gap halving.
  Fine Tune's Opening/Closing filters keep a fixed 15%. Min-gap default 10 → 30 s (a saved 10 s value stays).
- Checked on 15 rides (Python copy of the Swift logic, same clip counts): picks <30 s apart 10–64% → 0%; longest
  riding without a pick e.g. River Loop 41 → 8.5 min, BrownSnake 31 → 8.8, Brissie 21 → 15; only B2GC worse
  (12.8 → 14.5); average pick score 0–7% lower. Built macOS + iOS, 0 warnings. Owner hand test passed 2026-10-28.
- Committed 2026-10-28 as 8471774 (main, not pushed).

**Item 3 (Fine Tune) built 2026-10-28** from the approved mock-up (https://claude.ai/artifact/H9GtkAuJccDVJiU1CbNBse).
- `ManualSelectionView` (1,196 lines) replaced by FineTuneView/Model/Data, MomentReasons, RideTimelineView,
  MomentDetailView, FilmStripView, FrameImage (all < 260 lines). Lap/segment and object filters left out (owner).
- FocusFilter trimmed to climbs/descents/group/PR; zone filters, `movingTimeZoneBoundaries` and zone % removed.
- Test target added (item 4, part 1): `VeloFilmsTests`, shared scheme; 64 tests pass on macOS and the iPhone 17
  simulator. Old FocusFilterTests fixed (stale helper, rider count expectations from an older rule).
- Owner hand test 2026-10-28 found two problems, both fixed the same day: (a) front/rear had to be chosen with a
  switch; now both frames show together (side by side; stacked on iPhone) and tapping one puts that camera in the
  reel, tapping the one in the reel takes it out; (b) on the Mac the window could widen but not grow taller (a sheet
  is capped at its parent window's height); Fine Tune now opens in its own window. The "reviewed"/stale-reel logic
  moved to `ReviewCompletion` (run by Fine Tune on close). 70 tests pass on macOS and the iPhone 17 simulator.
- Second round (2026-10-28): selected filter chip text was invisible on the Mac (fixed colours + checkmark); film
  strip now has a front row above a rear row on iPad/Mac (one row on iPhone); tapping opens the moment only.
- Hand test owed: open Fine Tune on SCL Riverloop (Mac + iPad/iPhone): resize the Mac window taller, tap front/rear
  frames, timeline drag, add/remove, filters, Reset, Cancel with changes, Save, then Build and check the reel.

**Item 1 (reel ending) done 2026-10-28** (owner dropped the stats card; YOLO stays, no Apple Vision):
- Start/finish picks: `ClipSelector.ensurePick` puts one moment in the first and last 5 min (`AppConfig.rideEdgeWindowS`).
  Simulated on the 15 rides: last pick was up to 58 min before the finish (River Loop, Kippa Ring); now ≤ 5 min everywhere.
- Backing music fades out over the last 3 s of the highlights (`AppConfig.musicFadeOutDuration`; FFmpeg `afade` on
  Mac, volume ramp on iPhone/iPad). Built macOS + iOS, 0 new warnings. Hand test owed: rebuild River Loop.

**Done since round 3 (all built for macOS + iOS with 0 warnings; nothing committed):**
- Elevation: elevation changes while stationary are removed (`GPXParser.removingStationaryElevationChanges`).
- Analyse card: "Busy" state; Re-import/Re-run disabled while running; re-import and Re-run clear all four
  analysis outputs (`ProjectDetailView.invalidateAnalysis`).
- Strava segments/PRs now score (Enrich applies `SegmentMatcher.stravaOffset`); only PR/top-3 score
  (`StravaBoost.any = 0`); segment weight default 0.15; one `DefaultScoreWeights` source + `resetScoreWeights()`.
- Music: Music Folder (any Files/iCloud/Dropbox folder, `MusicFolder.swift`, `MusicFolderSection.swift`,
  downloaded at build time); "My Music" renamed "Added Songs" in the UI; bundled music limited to the Mac build.
- Apple Vision stress test (results in `docs/APP_STORE.md`): Vision alone is a downgrade (misses ~1/3 of people,
  no vehicles/traffic lights, 40–45% top-pick overlap). Not needed if the app isn't distributed.
- Hand tests still owed by the owner: Brymaroo Sunday re-import → Run Analysis → Build (elevation strip, no cliff
  at ~37%); River Loop re-analyse (PR moments picked); Music Folder on Mac and iPad.

---


Loop: SCORE → PLAN → (owner approval) → FIX DOCS → FIX SECURITY → RE-SCORE.
Targets: overall ≥ 85, documentation ≥ 34/40, no open Critical/High, build + tests green.
Stop also after 3 rounds or a round gaining < 3 points.

## Score trend

| Round | Date | Overall | Grade | Code /60 | Docs /40 | Crit | High | Med | Low | Scorecard |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-10-25 | 31.6 | F | 19.8 | 11.8 | 1 | 4 | 8 | 8 | [round 1](../scorecards/scorecard-2026-10-25-round1.md) |
| 2 | 2026-10-25 | 53.0 | D | 23.4 | 29.6 | 0 | 1 (accepted) | 6 | 8 + 2 accepted | [round 2](../scorecards/scorecard-2026-10-25-round2.md) |
| 3 | 2026-10-26 | 59.0 | D | 24.6 | 34.4 | 0 | 0 open (1 accepted) | 3 | 4 + 3 new Low | [round 3](../scorecards/scorecard-2026-10-26-round3.md) |

## Loop stopped after round 3 (3-round limit). Docs target met (34.4 ≥ 34); overall 59 < 85.

After the round 3 score: fixed two Low bugs in this session's new code (re-adding a My Music track deleted it;
a 429/408 on token refresh signed the user out) and the 3 doc mismatches; iPad music picker now accepts AAC.
My Music add/replace verified with a throwaway folder (6/6 checks). Builds green.

## Round 2 — history

Round 1 → 2: +21.4 points (stop rule "< 3 points" not hit; targets not met: overall 53 < 85, docs 29.6 < 34).
Round 2 scorer found 12 doc mismatches and 4 new bugs (see scorecard).

Owner decisions (2026-10-26):
1. Commercial music: remove from the app; add a "My Music" place for users' own tracks; move the owner's two
   commercial tracks there. **Done** (approved 2026-10-26): new `MusicLibrary`; Settings → Audio → My Music
   (Add Music…, Remove with confirmation, Show in Finder on Mac); Mac folder `~/Music/Velo Films/`, iPad folder
   inside the app; the two tracks moved there on the owner's Mac. Git history checked 2026-10-26: the two
   tracks were never committed (`.gitignore` rule `**/Resources/music/*.mp3`), so no history rewrite was needed.
2. Stale `Shared/Steps/Build/README.md`, `PLAN.md`, `QUICKSTART.md`: delete. **Done.**
3. Pre-purge backup mirror (scratchpad): delete. **Done.**
4. Code-quality track (test target, then the bug list): yes, after this round.

### Round 2 Part A (docs) — done 2026-10-26
- Mismatches 1–9, 11, 12 fixed (10 = stale Build docs, deleted). #7 changed two user-facing message strings
  ("Camera Calibration" → "Time Sync"); no logic change.
- DocC tags now complete: Parameters 118/118, Throws 44/44, Returns 67/67 (were 66/118, 40/44, 49/67).
- Restating one-liners rewritten (ProjectArtifacts, HUD.mapX, FilePickerBridge.Coordinator init).
- Builds: macOS and iOS OK, 0 code warnings; DocC 0 warnings.

### Round 2 Part B (security) — B1–B6 done 2026-10-26 (approved at Gate 2)
- B1 token calls check HTTP status; `StravaNetwork.session` timeouts (30 s / 300 s); plain `StravaError`
  messages; cancelling sign-in no longer shows an error. (M2)
- B2 OAuth `state` check. (M1)
- B3 `KeychainStore.set` updates in place, adds only if missing. (N1) Verified with a throwaway Keychain entry:
  8/8 checks passed.
- B4 activity name XML-escaped in generated GPX. (L1)
- B5 all 5 `print` calls → `os.Logger` with private file names. (L4)
- B6 `PipelineError` plain messages + `technicalDetails`; new `ErrorMessageView` with a Details disclosure. (M8)
- Builds: macOS, iOS OK, 0 warnings; DocC 0 warnings.
- Deferred to the code-quality track: B7 delete-all/revoke (M5), B8 consent screen (M6), M4 file protection,
  L2, L6, N2.

## Round 1 — complete

Owner chose to address the Critical finding first.

Fixed:
- 2026-10-25 Critical (leaked Strava client secret): owner regenerated the secret on strava.com and updated
  Secrets.swift. Verified: rebuilt macOS Debug app (15:42) no longer contains the old value; a new value is present.
  Owner confirmed Strava sign-out/sign-in and ride list work with the new secret (2026-10-25).
  Note: a mistyped secret shows only "The data couldn't be read because it is missing" because token calls
  ignore Strava's error replies (Medium finding: status codes); fix in Part B.
- 2026-10-25 History purge (owner approved): `git filter-repo` removed `VeloFilms/VeloFilms v1`–`v4` from all
  local history. 112 commits and tag v1.0 kept; 0 blobs contain the old secret; pack 118 MB → 52 MB.
  Backup mirror taken first (scratchpad). `origin` remote re-added. macOS build OK.
- 2026-10-25 SECURITY.md created (owner approved).
- 2026-10-25 Owner force-pushed the cleaned history (Claude's push was blocked by permission settings).
  GitHub verified: main = 3d77ef1, v1.0 = 52d57ee, matching local. Nothing newer existed on GitHub (was 0eb1729).
- 2026-10-25 Local snapshot folders `VeloFilms/VeloFilms v1`–`v6 (osx)` (~650 MB, untracked) moved to the Trash
  (owner approved). macOS and iOS builds OK afterwards.
- 2026-10-25 High (B2, owner approved): bearer token re-attached on redirect only for https + strava.com /
  garmin.com hosts (and subdomains); otherwise stripped. Files: StravaClient.swift, GarminClient.swift.
  macOS + iOS builds OK, no new warnings. No automated test (no test target). Owner confirmed Strava and Garmin imports work.
- 2026-10-25 High (Garmin password sign-in) closed by removing Garmin Connect import (owner decision "Strava
  only"; Garmin had retired mobile.integration.garmin.com, so sign-in was broken). Deleted GarminAuth.swift,
  GarminClient.swift, GarminImportView.swift, Scripts/garmin_helper.py; removed the button in ProjectDetailView;
  VeloFilmsApp deletes legacy garmin* UserDefaults keys on launch. README, CLAUDE.md, SECURITY.md updated.
  macOS + iOS builds OK, no warnings. Owner confirmed: Garmin button gone, Strava import works.
- 2026-10-25 High (tokens in plain text, owner approved): Strava access/refresh tokens moved to the Keychain
  (new Shared/Core/Security/KeychainStore.swift; StravaAuth.swift migrates old UserDefaults copies, deletes them
  only after a successful Keychain write). macOS + iOS builds OK, no warnings. First attempt used the macOS
  data-protection keychain and failed with -34018 (missing entitlement); tokens stayed safely in UserDefaults.
  Switched macOS to the login keychain. Owner confirmed sign-in works; verified both tokens are in the Keychain and
  gone from ~/Library/Preferences. Leftover: an April sandboxed-build container plist still holds an old token pair
  (owner approved; deleted). Verified: tokens only in the Keychain now.
- 2026-10-25 Extractable Strava client secret: risk accepted for now (App Store target), recorded in SECURITY.md.
- 2026-10-25 Medium (no privacy manifest, owner approved): added Shared/App/PrivacyInfo.xcprivacy (no tracking,
  no collected data; UserDefaults CA92.1, file timestamps 3B52.1, based on a source search). plutil OK; bundled in
  both macOS and iOS builds; builds OK, no warnings.
- **Critical finding closed.** Optional: ask GitHub Support to purge cached old commits (e.g. 35f66b5).
Deferred: nothing yet.

### Part A — documentation (owner approved "A then C", 2026-10-25)
- Added `//` file headers to all 57 Swift files and `///` docs to every non-private declaration
  (coverage 116/659 = 17.6% → 617/617 = 100% by the scorer's script `swift_metrics.py`).
- Fixed misleading comments, including: main-thread claim in PipelineExecutor; FFmpegBridge "iPadOS placeholder";
  "Swift 6" notes (project is Swift 5 mode); VideoEncoder "replaces FFmpegBridge"; score weights "sum to 1.0";
  "person+bicycle" (it is the larger of the two); bookmark/security-scope notes in GlobalSettings and
  FilePickerBridge; AppConfig "all constants"; "Camera Calibration" tab name in comments; Extract "5s grid";
  ProjectFileManager "validates"; elevation strip size (948 → 390 px) and its undrawn labels; GaugeRenderer
  "ProRes .mov" and the muddled arc-angle note; FrameSampler overload "used by Build/Splash" (unused);
  "Mirrors X.py" comments now say they refer to the original Python app (not in this repo).
- README: corrected Flatten (1 Hz, not 5 s), Extract (no frames read), intro sentence; added platform
  distribution note, Documentation and Development sections. New ARCHITECTURE.md. CLAUDE.md: corrected paths,
  build date, documentation rules.
- Verification: comments-only checker (`codeonly.py`, compares code with comments stripped against a snapshot
  taken before Part A; self-tested to fail on a code change) → only comments changed. macOS + iOS builds OK, no
  warnings. DocC docbuild OK, 0 warnings.
- Not changed (strings are code, not comments): ExtractStep error messages still say "Settings → Camera
  Calibration"; the tab is "Time Sync". Listed under bugs.

### Bugs found (not fixed — owner decides)
From the round 1 scorecard (15), plus found during Part A:
16. ~~Scene change compares frames 75 s apart, not 15 s.~~ Scene change removed 2026-10-31 (replaced by the action score).
17. Per-project "highlight target" override is saved but never used; selection uses the global setting.
18. EnrichStep segment score ignores the Strava time-zone offset that SelectStep applies.
19. OutroBuilder passes the 3.7 s duration for the 2 s black clip to crossDissolveChain.
20. ExtractStep error text points to "Settings → Camera Calibration"; the tab is "Time Sync".
21. `dynamicGauges` setting ("Dynamic gauges (ProRes)" toggle) is saved but not used.
22. Disabling the bicycle class also drops people, so the pedestrian setting has no effect then.

### Owner decisions made
- 2026-10-25 Strava only (Garmin removed).
- 2026-10-25 Target is the App Store (Mac + iPad). Consequences: keep the Strava app key built in (users can't be
  asked to create their own Strava API app); Strava app must pass Strava's review to leave Single Player Mode
  (athlete capacity 1); PrivacyInfo.xcprivacy is a release blocker (done).
- 2026-10-25 Refined: **iPad version → App Store; macOS version → personal use only.** The Mac keeps Homebrew
  FFmpeg and runs unsandboxed; the macOS sandbox finding is downgraded to Low (personal build). Mac App Store would
  need AVFoundation-only rendering — not planned.

### Open decisions for the owner
1. Regenerate the Strava client secret (owner action on strava.com/settings/api). Leaked in public git history, commit 35f66b5.
2. Purge the old app binaries from git history (`git filter-repo` + force-push)? Needs explicit OK.
3. Strava token exchange: keep the secret in the app (extractable) or add a small server-side proxy?
4. Garmin sign-in: keep the password-based flow, or replace it with GPX/FIT file import?
5. Turn on the macOS App Sandbox (needed for the Mac App Store; affects drive and FFmpeg access)?
6. Add a test target (needed to meet the "tests pass" target; touches the Xcode project).
