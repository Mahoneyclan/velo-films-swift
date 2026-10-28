# App Store readiness — iPad and iPhone

Owner decision (2026-10-27): the **iPad and iPhone** app is sold on the App Store for **$0.99** and must meet every
App Store requirement. The Mac build is for personal use and is held to a lower standard (it is not in this list).

Status key: ❌ blocker (would cause rejection or legal exposure) · ⚠️ needed before submission · ✅ done ·
❓ needs a decision or confirmation.

Research date: 2026-10-27. Sources are listed at the end; re-check them before submission, as terms change.

## 1. Licences — blockers

| # | Item | Status | Finding | Options |
|---|---|---|---|---|
| L1 | **AI model (YOLO11s)** | ❌ | The bundled model's own metadata says "Ultralytics YOLO11s … AGPL-3.0 License". Ultralytics: "All Ultralytics YOLO trained models fall under the AGPL-3.0 License by default"; an Enterprise License "is required if you want to use Ultralytics YOLO without open-sourcing your entire project", including "any commercial product or service". | (a) buy an Ultralytics Enterprise licence (price on request); (b) replace the model with one under a permissive licence (e.g. Apache-2.0/MIT detectors) and re-export to Core ML; (c) use Apple's built-in Vision requests (on-device, free) for people/animals and accept fewer object classes |
| L2 | **Bundled "royalty-free" music** (8 tracks + intro/outro) | ⚠️ Reopened 2026-10-28: app goes to friends via TestFlight only, so all 10 audio files ship in every build again (the Mac-only platform filter was removed). Must be fixed again before any public release. | Licences cover use *in your own videos*, not shipping the file inside an app that's sold. Pixabay: you "cannot sell or distribute Content … on a Standalone basis". YouTube Audio Library standard-licence tracks (TrackTribe, Mini Vandals, Everet Almond, The Grey Room/Golden Palms) are for YouTube videos; sources disagree on use elsewhere. Chosic tracks (Luke Bergs) are usually Creative Commons with attribution. Apple 5.2.1: no third-party copyrighted works "without permission"; keep records. Intro/outro music: origin unknown. | (a) ship **no** music and rely on My Music (already built); (b) buy tracks with an explicit app-bundling licence (or commission); (c) keep only tracks whose licence clearly allows redistribution in an app, with credits shown in the app |
| L3 | **Strava API terms** | ❓ | The agreement doesn't forbid a paid app, but Strava may charge for API use (3.2), bars apps that "compete with or replicate Strava functionality" (1), and limits display of a user's data to that user (1). Apple 5.2.2: you must be "specifically permitted" to use a third-party service. | Describe the app to Strava in the developer review (see S1); keep the written approval for Apple |
| L4 | **Apple Maps images in exported videos** | ❓ | No official statement found on attribution for `MKMapSnapshotter` images; forum reports say the Apple Maps logo is drawn into snapshots. | Confirm the snapshot keeps the Apple logo/legal text in our crop; check the Apple Maps terms in the Developer Program agreement |

### L1 stress test: Apple Vision vs the current model (2026-10-27)

300 random frames from each of two rides (Brymaroo Saturday, gravel group ride; River Loop, road/suburban), comparing
Apple's built-in `VNDetectHumanRectanglesRequest` + `VNClassifyImageRequest` against the YOLO11s results already saved:

| | Brymaroo Saturday | River Loop |
|---|---|---|
| Frames with people: YOLO / Vision | 199 / 135 | 193 / 126 |
| People yes/no agreement | 79% | 76% |
| Bicycle frames Vision also finds (label only, no count) | 88% | 78% |
| Vehicle frames Vision also finds | 71% (but "vehicle" also fires on bicycles: 133 labels vs 7 real) | 74% |
| Top-20% detection-score overlap | 45% | 40% |
| Vision time per frame (Mac, warm) | — | 37 ms |

Finding: Vision alone misses about a third of the frames with people (mostly small or distant riders), can't count
bicycles, can't tell cars from bikes, and has no traffic lights or stop signs. The Fine Tune class filters
(Car, Truck, Traffic Light, Bus, Stop Sign) and the "Group 5+" count would be lost or weakened, and picks would
change a lot (only 40–45% of the top moments agree). Next candidate to test: a detector with a permissive licence
and the same 80 COCO classes (e.g. YOLOX, Apache-2.0), which would keep every feature.

## 2. Strava

| # | Item | Status | Finding |
|---|---|---|---|
| S1 | **Leave "Single Player Mode"** | ❌ | New apps have an athlete capacity of 1 ("can use their app solely for themselves"). Up to 10 athletes from the dashboard; more needs Strava's review, with screenshots of where Strava data appears and the "Connect with Strava" button. Approval not guaranteed. Customers can't sign in until approved. |
| S2 | **Brand rules** | ⚠️ | Use the official "Connect with Strava" button; "Powered by Strava"/"Compatible with Strava" wording; no "Strava" in the app name; Strava logo separate from ours and never the app icon; links to Strava data say "View on Strava". The import screen currently uses a plain button. |
| S3 | **Client secret inside the app** | ❓ accepted | Extractable from any copy. Strava may ask about it at review; the full fix is a small server that does the token exchange. |
| S4 | **Rate limits** | ⚠️ | 200 requests / 15 min and 2,000 / day for the whole app (all customers), 400/4,000 at 10 athletes. Each import makes ~3 requests, so this caps daily imports across all users; ask Strava for more at review. The app now shows a plain "limit reached" message (429). |
| S5 | **Delete Strava data on request / if access ends** | ⚠️ | Agreement 4.4: on termination, delete all Strava Data. Needs "Delete all my data" (P3) and sign-out that revokes access. |

## 3. Apple — privacy and data

| # | Item | Status | Notes |
|---|---|---|---|
| P1 | **Privacy policy** web page, linked in App Store Connect **and inside the app** (5.1.1(i)) | ❌ | Must explain what's kept, where, retention/deletion, and how to revoke consent. Needs a public URL (e.g. a GitHub Pages page). |
| P2 | **Consent** before ride data is fetched or map tiles requested (5.1.1(ii), 5.1.2) | ❌ | One screen naming Strava (USA) and Apple Maps; withdrawable in Settings; app still usable without it (local GPX). |
| P3 | **Delete all my data** in Settings | ⚠️ | Keychain tokens, settings, My Music, caches; optionally project folders (with confirmation). |
| P4 | **App Privacy answers** in App Store Connect | ⚠️ | No tracking; no data collected by us (data stays on device). Must match `PrivacyInfo.xcprivacy`. |
| P5 | **Privacy manifest** | ✅ | `Shared/App/PrivacyInfo.xcprivacy` (UserDefaults CA92.1, file timestamps 3B52.1). Re-check when APIs change. |
| P6 | **Clear old Keychain sign-in on fresh install** | ⚠️ | iOS keeps Keychain items after the app is deleted. |
| P7 | **File protection** for GPS files on device | ⚠️ | Rides reveal home location. |
| P8 | **Fitness data not used for marketing** (5.1.3) | ✅ | No ads, analytics or sharing. |
| P9 | **Usage strings** | ⚠️ | Remove Mac-only folder strings from the iOS build; add any needed (e.g. saving to Photos if added). |

## 4. Apple — app completeness and review

| # | Item | Status | Notes |
|---|---|---|---|
| A1 | **Works fully on iPhone and iPad** (2.1) | ⚠️ | Both are in the build (device family 1,2). Every screen must work on small iPhones (Dynamic Type, no cut-off text), and the full pipeline must run on iPhone without overheating (2.4.2). Untested on iPhone so far. |
| A2 | **Long renders when the user switches apps** (2.5.4) | ⚠️ | Use iPadOS/iOS 26 `BGContinuedProcessingTask` (user-started, shows progress, user can cancel; must report progress). Otherwise iOS may stop a render in the background. |
| A3 | **Review access** (2.1(a)) | ⚠️ | Reviewers need a Strava test account with rides **and** sample footage, or a built-in demo project (ask Apple first). Strava Single Player Mode would block the reviewer's own account. |
| A4 | **Review notes** (2.3.1) | ⚠️ | Explain the camera workflow, the USB-C import and the Strava sign-in specifically. |
| A5 | **Screenshots** (2.3.3, 2.3.9) | ⚠️ | iPad and iPhone sizes, showing the app in use, with fictional/non-identifying ride data. |
| A6 | **Encryption export setting** | ⚠️ | Add `ITSAppUsesNonExemptEncryption = NO` (HTTPS and Keychain only). |
| A7 | **Paid Apps agreement, banking and tax** in App Store Connect | ⚠️ | Owner task; required before a paid app can go on sale. |
| A8 | **App icon, name, category** | ❓ | Icon present; check it isn't the default. Category is Health & Fitness; Photo & Video may fit better. |
| A9 | **Sign in with Apple not needed** (4.8) | ✅ | Exempt: the app is a client for a specific third-party service (Strava) to access the user's own content. |
| A10 | **No crashes / force-unwraps on outside data** | ⚠️ | One `preconditionFailure` in Strava sign-in; scorecard bug list. Needs the test target. |

## 5. Quality bar (owner standards, not Apple rules)

Accessibility (VoiceOver labels, Dynamic Type, contrast), 44×44 pt touch targets, progress with steps for long work,
plain-language errors, empty states, and onboarding. Covered by the code-quality track.

## Suggested order

1. Decide L1 (AI model) and L2 (music): they change what's built.
2. Start the Strava developer review (S1) early: it has a waiting time and blocks reviewer sign-in.
3. Privacy: consent (P2), Delete all my data (P3), privacy policy page (P1), fresh-install cleanup (P6).
4. iPhone pass (A1) and background renders (A2).
5. Store setup: agreements (A7), export setting (A6), screenshots (A5), review notes and demo access (A3–A4).

## Sources

- Ultralytics licensing: https://www.ultralytics.com/license
- Strava API Agreement: https://www.strava.com/legal/api
- Strava brand guidelines: https://developers.strava.com/guidelines/
- Strava rate limits and athlete capacity: https://developers.strava.com/docs/rate-limits/
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Pixabay licence summary: https://pixabay.com/service/license-summary/
- `BGContinuedProcessingTask`: https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask (WWDC25 session 227)
- Encryption export: https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
- YouTube Audio Library licensing: secondary sources only (e.g. https://licenseorg.com/guide/music-audio/youtube-audio-library); check each track's licence in YouTube Studio.
