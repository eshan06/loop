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
