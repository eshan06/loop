# iOS lane log

Only the iOS machine edits this file. The server lane reads it after every pull.

Add new log entries at the top of the Log section, newest first. Keep each entry short. `/handoff` writes them for you.

## Open requests to the server lane

Give each request an ID (`IOS-1`, `IOS-2`, ...). Move it to "Closed requests" once the server lane answers in `coord/server.md`.

- IOS-3 (Tier 3, S-28, low priority): the server lane acknowledged it and scheduled it for S-28. Still open until it ships: a nullable `condition_note` string on `ScanDraft` and `Listing`. The app ignores unknown keys until then.

## Closed requests

- IOS-1: closed 2026-10-17. Server seeded `jordan.park`, `sam.lee`, `riley.chen` @vanderbilt.edu. The sign-in quick-login chips use them.
- IOS-2: closed 2026-10-17. Server uses the size vocabulary and maps scan sizes into it. Matches `SizeVocabulary.swift`.

## Log

### 2026-10-17 — Infinity Loop logo approved and applied; build 1.0 (3) ready for TestFlight (ios lane)
- Done: the approved black infinity Loop logo (no period) is in the app icon (black on white, 1024 px, no alpha), the sign-in wordmark and the launch view. It is traced from `design/Minimalist Loop Infinity Wordmark.png` (committed as the team's source artwork) with `ios/Tools/trace-logo.py` into `ios/Tools/loop-logo.json` and `LoopLogoShape.swift`; `make-app-icon.swift` now draws from the same JSON. The old lime highlighter behind the wordmark is gone; Loop Lime stays on the Scan button, tags and the completion checkmark.
- Synced: the web portal merge and `3da5d5f` (Release builds use the live server, build 2). No conflicts; `web/` and `backend/` untouched. The build-2 commit predates the logo, so any TestFlight build 2 still shows "loop.".
- Build: `CURRENT_PROJECT_VERSION` is now 3 (1.0 (3)); project regenerated with `bash ios/generate.sh`. Release build succeeds and has no Mock/Live switch (live server default). Unit and UI tests pass.
- Now: the archive and upload happen on the other Mac (Archive, Release, Any iOS Device). Not uploaded from here. Next: two real phones (I-17/I-27), real-iPhone camera (I-9).
- Heads-up: every later TestFlight upload needs a new build number above 3.

### 2026-10-17 — Ready to archive for TestFlight (ios lane)
- Done: Release configuration builds clean; added `ITSAppUsesNonExemptEncryption: false` so uploads skip the export-compliance question. The TestFlight build is archived on another Mac with a current Xcode and the team's Apple account. It ships on mock data: the Mock/Live switch is debug-only and `defaultUseMocks` is true. Camera and photo-library usage strings, app icon and launch screen are already in place; version 1.0 (1).
- Heads-up: server lane, nothing needed. The server is plain HTTP, fine for internal TestFlight testers; external testers would need HTTPS.

### 2026-10-17 — First live end-to-end run PASSED (ios lane)
- Done: full Jordan/Sam run on two Simulators against the live server, after the clean S-25 seed: real photos to `/scan` (source `vision`, 3.0 s in the app, 5.4 s raw), AI-filled review, publish (listing 1762, Closet Cleanout earned at posting), Sam found it by search and requested it (request 999), Jordan accepted it (the Converse requests were left alone), two chat messages, complete. Afterwards: both have First Swap, Jordan impact 1 shared (0.44 kg, 3,135 L, 10.3 kg), Sam 1 received, campus 10 to 11, top dorm Kissam, Kissam 3 alone at #1, notifications as expected. Evidence and screenshots in `ios/Screenshots/live-e2e/` (`EVIDENCE.md`); the run is `ios/LoopUITests/LiveE2ETests.swift`, opt-in, plus `ios/Tools/live-state.py` (read-only).
- No frontend bugs found. The only app change is two debug `print`s in the scan failure paths. No contract problems.
- Not covered: real camera and Vision on a phone (I-9), banner animation, the open-thread live "completed" poll on Sam's side (needs a second exchange), `condition_note` (the app drops it: IOS-3 still open).
- Heads-up for the server lane: the demo campus is now dirty (listing 1762 completed, request 999, Jordan and Sam have First Swap, four `/scan` calls left about 10 unattached photos). Not reseeded: waiting until both developers agree the evidence is captured, then `bash scripts/reseed.sh`.

### 2026-10-17 — Live integration check; Simulator ready in Live mode (ios lane)
- Done: synced (only a README move since the last entry). Checked `LiveAPIClient` against the deployed server (`http://163.192.218.131:8000`, ATS exception on, error envelope, 401/404/400 shapes) and ran a read-only audit of every GET endpoint as Jordan, Sam and Riley against the app's models (`ios/Tools/live-audit.py`): no mismatches. The only keys the app ignores are `condition_note` and meetup spot `lat`/`lng`. Enum values in live data are all known. Demo state matches S-25 step 1 (27 active, 6 Jordan's, 3 unread).
- Now: waiting for the go-ahead to run the two-phone test (I-27, I-17) with the agreed accounts and the server lane ready. No live mutations have been run.
- Heads-up: iPhone 15 Pro Simulator is signed out, in Live server mode, with three seed photos in its library. Logging in creates a session only. Run `bash scripts/reseed.sh` after any rehearsal.

### 2026-10-17 — I-26 done: typography-first logo, app icon, ink welcome screen (ios lane)
- Done: I-26. App icon is "loop." in Loop Lime on solid #191919 (`ios/Tools/make-app-icon.swift` renders it into the asset catalog; verified on the Simulator home screen). In-app wordmark is type only (glyph removed, period added) in near-black `Theme.ink`; launch background is now #FAF8F4 instead of white. Sign-in typography uses `Theme.ink` with accessible secondary colors; the Loop Lime highlighter and black buttons stay. Clean build, 35 unit + 12 UI tests pass, including the read-only live-server walk.
- Synced: 12 new server commits (S-25 reseed/demo story, S-26, S-27 events and donation bins). Additive only: `lat`/`lng` on meetup spots (the app's `MeetupSpot` ignores them) and new `GET /events`, `GET /donation-bins`. No iOS change needed. Not built, by design: I-28 map, I-29 Swap Day, and IOS-3 (showing `condition_note`, now live on the server; the app still ignores it).
- Now: Sync point C on two phones (I-27, I-17): Jordan on Phone 1, Sam on Phone 2, per "Before the demo" in `coord/server.md`; real-iPhone camera check (I-9).
- Heads-up: no live mutations were run. Run `bash scripts/reseed.sh` after any rehearsal.

### 2026-10-17 — Re-synced after S-22, S-24, S-28; compatible, ready for coordinated live testing
- Done: pulled S-22 (badges), S-24 (reports), S-28 (`condition_note`). Read the API.md diffs and the router/schema changes: all additive, nothing breaks the app. `GET /me/badges` now answers 200 live and decodes into `Badge`; the Badges row on Profile shows again. `POST /listings/{id}/report` matches what `LiveAPIClient.report` sends. `condition_note` is now in live listings; the app ignores the key (IOS-3 stays open on the iOS side: adopting it is a feature, not done).
- Tests: clean run against the live server, 35 unit + 11 UI, 0 failures (one earlier unit run hit a 401 in the live read-only test, then passed on 3 reruns; not reproduced).
- Needs: nothing. Next: Sync point C on two phones (I-17), real-iPhone camera check (I-9), I-26.
- Heads-up: demo data reports hide at 3 reporters; don't rehearse reports on demo listings.

### 2026-10-17 — Frontend readiness audit and Loop Lime
- Done: scan pipeline audit (camera flow, library per step, resize and JPEG upload order, Apple Vision, `/scan` request format, skeletons, retry and manual fallback, post and feed refresh, request to chat to complete, Mock to Live). Fixed: retry no longer overwrites what the user typed; a failed post resumes photo uploads instead of redoing them; image encoding moved off the main thread; library picks are decoded with ImageIO (a 31 MB HEIC works); Vision has an 8 s deadline; the keyboard no longer covers the form; `new_message` banners now fire again when a collapsed notification gets another message (docs/API.md says it keeps its `id`); detail refreshes when a request notification arrives; the feed clears filters so a new post is visible; the Mock/Live switch on the sign-in screen works without code changes; `-useMocks NO` was being ignored and now works. Loop Lime added as `Theme.lime`.
- Verified: clean build; 35 unit tests and 11 UI tests pass, including the live read-only ones (`TEST_RUNNER_LOOP_LIVE=1`). Every live GET decodes into the app's models. Request formatting for `POST /scan` matches `backend/app/routers/scan.py` (repeated `photos` parts, `kinds`, `labels`).
- Now: real iPhone run for the camera, then Sync point C (I-17) on two phones, then I-26.
- Needs: nothing new. FYI, not a request: `GET /me/badges` returns 404 on the live server today (S-22 not deployed). The app hides the badge row until it works, and the celebration skips the badge card, so nothing breaks. Tell me when S-22 is live and I'll rerun the live walk.
- Heads-up: no live mutations were run (no post, request, accept, or complete). Logging in as the demo accounts for read-only checks creates a few sessions on the server and nothing else.

### 2026-10-17 — iOS frontend builds, passes its tests, and runs on the live server
- Done: I-1 to I-8, I-10 to I-16, I-18 to I-25 (screens), verified in the iPhone 15 Pro Simulator on iOS 17.2. Clean build succeeds. 12 unit tests and 7 UI tests pass (`xcodebuild test`, see the Gotchas in `CLAUDE.md`); the UI tests walk sign-in, profile setup, scan with sample photos, review, post, save, request, accept, chat, mark done with badge, impact and leaderboard, filters, search, Style it, report, edit, and the empty states, all on the stateful mock. Screenshots are in `ios/Screenshots/`.
- Done: a read-only walk of the live server as Jordan (`TEST_RUNNER_LOOP_LIVE=1`): sign-in, feed with real photos, detail, requests, profile, impact. Every response decodes into the app's models. Sync point A is met.
- Now: I-9 stays `[~]`: the camera itself (live preview, shutter, permission denied) can't be tested in the Simulator, so it needs a real iPhone. Next: Sync point C on two phones (I-17), then I-26 (app icon, polish).
- Needs: nothing new. IOS-3 stays open (Tier 3).
- Heads-up: the live test is read-only on purpose. I did NOT run request, accept, post, or complete against the live server, so those mutations are untested live; the mock mirrors the contract and the decoding is verified. Don't be surprised by two extra sessions for the demo accounts. No server change needed from the iOS side.

### 2026-10-17 — Phase 0 and the Tier 1 and 2 screens written; first build blocked on Xcode
- Done: I-7 (contract v1 covers every screen; my only asks are IOS-1 to IOS-3). Written, not yet compiled: I-1 to I-6 and I-8 to I-16, I-18 to I-25. The whole app runs on a stateful in-memory mock (`useMocks = true`; launch arg `-useMocks NO` switches to the live server without code changes), seeded from `ios/Loop/Mocks/*.json` copied from API.md shapes.
- Now: waiting for Xcode 15.2 on the iOS Mac, then the first Simulator build, fixing compile errors, and Sync point A (`/health` from the Simulator against the live server).
- Needs: IOS-1 (demo account emails), IOS-2 (size vocabulary), IOS-3 (optional condition note).
- Heads-up: the iOS Mac is on macOS 13, so it's Xcode 15.2 / iOS 17.2 SDK. Folder-synced groups need Xcode 16, so `ios/Loop.xcodeproj` is generated from `ios/project.yml` by XcodeGen (`bash ios/generate.sh`) and committed. Only the iOS lane runs it.

### 2026-10-17 — lane created
- Now: nothing in progress. Start with Phase 0 in `PLAN.md`.
