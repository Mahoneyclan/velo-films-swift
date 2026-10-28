# Security

What Velo Films holds, where it is stored, how it is protected, and the risks that remain.
Keep this file current whenever storage, sign-in or network code changes.

## Data the app holds

| Data | Where | Protection today |
|---|---|---|
| Strava client ID and client secret | `VeloFilms/VeloFilms/Shared/Integrations/Strava/Secrets.swift` (gitignored), compiled into the app | Not in git. Extractable from any built app (see Remaining risks). |
| Strava access and refresh tokens | Keychain (`KeychainStore`, service `mahoneyclan.VeloFilms`) | Encrypted. iPad: `AfterFirstUnlockThisDeviceOnly` (no iCloud sync, not restored to other devices). Mac: login keychain, access limited to this app (data-protection keychain needs an entitlement this unsandboxed build lacks; revisit with the App Sandbox). Moved from UserDefaults 2026-10-25; old copies migrated and deleted on first use. |
| Ride GPS tracks (GPX, JSONL) | Project folders on the external drives | Default file permissions only; reveal home location. Open finding (Medium). |
| Camera footage and rendered videos | External drives | Default file permissions. |
| App settings | UserDefaults / @AppStorage | Not sensitive. |
| User's own music (My Music) | Mac: `~/Music/Velo Films/`; iPad: inside the app | Default file permissions. Never bundled: only royalty-free music ships in the app (commercial tracks removed 2026-10-26). `.gitignore` keeps loose tracks in `Resources/music/` out of git; checked 2026-10-26 that no commercial track was ever committed. |

The app has no analytics or tracking. Data is sent only to Strava and (map tiles / snapshots) Apple Maps.

Garmin Connect import was removed on 2026-10-25. It used an unofficial sign-in that collected the Garmin
password and imitated Garmin's mobile app, and Garmin had retired a server it depended on. On launch, the app
deletes the Garmin email and tokens that earlier versions stored (`VeloFilmsApp.removeLegacyGarminData`).

## Secrets rules

- Never commit secrets, built apps (`*.app`) or binaries. `.gitignore` blocks `**/Secrets.swift` and `*.app/`.
- Before every commit, scan the diff and `git log -p` for keys and tokens.
- Any secret compiled into the app can be extracted by anyone who has the app.

## Incident log

### 2026-10-25: Strava client secret exposed in public git history
- **What:** On 2026-05-24, four built app copies (`VeloFilms/VeloFilms v1`–`v4/VeloFilms.app`) were committed to the
  public GitHub repo. Each contained the Strava client secret. They were untracked the same day but remained in history.
- **Found:** Round 1 security review (`docs/scorecards/scorecard-2026-10-25-round1.md`).
- **Actions:**
  1. Owner regenerated the Strava client secret and updated `Secrets.swift`; the old secret no longer works.
     Verified the rebuilt app no longer contains the old value, and Strava sign-in and import work.
  2. Removed `VeloFilms/VeloFilms v1`–`v4` from all local git history with `git filter-repo`. A backup of the
     original history was taken first.
  3. Force-pushed the cleaned history to GitHub on 2026-10-25.
- **Optional:** ask GitHub Support to purge cached views of the old commits (e.g. `35f66b5`). Low priority, because
  the leaked secret no longer works.

## Privacy manifest

`VeloFilms/VeloFilms/Shared/App/PrivacyInfo.xcprivacy` (added 2026-10-25): no tracking, no data collected;
required-reason APIs UserDefaults (CA92.1) and file timestamps (3B52.1). App Store Connect privacy answers must
stay in sync ("Data Not Collected").

## Network protections

- All API calls use HTTPS. No App Transport Security exceptions.
- On a redirect, the Strava sign-in token is only re-sent to https addresses on strava.com
  (`AuthPreservingDelegate` in `StravaClient.swift`). Fixed 2026-10-25.

## Fixed on 2026-10-26

- **Strava sign-in `state` check** (`StravaAuth.authenticate`): a random value is sent with each sign-in and must
  come back in the reply, so a callback another app sends to `velofilms://` is rejected.
- **Status checks and timeouts:** the token calls check Strava's HTTP status before trusting the reply; every
  Strava request uses `StravaNetwork.session` (30 s between bytes, 300 s per request). Errors are shown in plain
  words (`StravaError`).
- **Keychain writes update in place** (`KeychainStore.set`), so a failed write keeps the old token.
- **GPX built from Strava escapes the activity name** (`StravaClient.xmlEscaped`).
- **No `print` in the app:** diagnostics use `os.Logger`, with file and ride names marked private.
- **Pipeline errors** show a plain message; FFmpeg output sits behind a Details disclosure (`ErrorMessageView`),
  and the full error stays in the project's `pipeline.log`.

## Remaining risks (open findings)

Full list with file and line references: latest scorecard in `docs/scorecards/`.

- **High (accepted for now, owner decision 2026-10-25):** the Strava client secret ships inside the app and can be
  extracted. The app is aimed at the App Store, so users can't be asked to supply their own Strava key. The only full
  fix is a server-side token exchange; revisit if Strava's app review asks for it.
- **Low:** the macOS build runs without the App Sandbox and has unused entitlements (incoming network server,
  Downloads read-write). Accepted: the Mac build is for the owner's personal use only; the iPad/iPhone build is the App Store
  product.
- **Low:** on iPad, Keychain items survive deleting the app, so a reinstall may find an old Strava sign-in.
- **Medium:** GPS files unprotected; no token revocation or "Delete all my data"; no consent screen before
  data goes to Strava or Apple Maps.

## Reporting a problem

Contact the owner through the GitHub repository (Mahoneyclan/velo-films-swift). Do not open a public issue for a
security problem.
