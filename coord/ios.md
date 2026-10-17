# iOS lane log

Only the iOS machine edits this file. The server lane reads it after every pull.

Add new log entries at the top of the Log section, newest first. Keep each entry short. `/handoff` writes them for you.

## Open requests to the server lane

Give each request an ID (`IOS-1`, `IOS-2`, ...). Move it to "Closed requests" once the server lane answers in `coord/server.md`.

- IOS-1 (for S-15): please seed the three demo accounts as `jordan.park@vanderbilt.edu`, `sam.lee@vanderbilt.edu`, `riley.chen@vanderbilt.edu`. The sign-in screen's debug quick-login buttons use these (`ios/Loop/Config/DemoAccounts.swift`). If you pick other emails, tell me and I'll change that file.
- IOS-2 (for S-10 prompt and S-15 seed): sizes in this vocabulary so the exact-match size filter works: tops/outerwear/dresses `XS S M L XL XXL`; bottoms waist `24`–`40` or letter sizes; shoes `5`–`14` in halves (`9`, `9.5`); accessories/bags `One size`. The Review screen's size picker uses the same list (`ios/Loop/Features/Scan/SizeVocabulary.swift`); anything else shows as "Other: <value>", so no breakage, just weaker filtering.
- IOS-3 (Tier 3, S-28, low priority): if you add the vision model's condition note, a nullable `condition_note` string on `ScanDraft` and `Listing` (and accepted by POST/PATCH /listings). No rush; the app ignores unknown keys until then.

## Closed requests

None yet.

## Log

### 2026-10-17 — Phase 0 and the Tier 1 and 2 screens written; first build blocked on Xcode
- Done: I-7 (contract v1 covers every screen; my only asks are IOS-1 to IOS-3). Written, not yet compiled: I-1 to I-6 and I-8 to I-16, I-18 to I-25. The whole app runs on a stateful in-memory mock (`useMocks = true`; launch arg `-useMocks NO` switches to the live server without code changes), seeded from `ios/Loop/Mocks/*.json` copied from API.md shapes.
- Now: waiting for Xcode 15.2 on the iOS Mac, then the first Simulator build, fixing compile errors, and Sync point A (`/health` from the Simulator against the live server).
- Needs: IOS-1 (demo account emails), IOS-2 (size vocabulary), IOS-3 (optional condition note).
- Heads-up: the iOS Mac is on macOS 13, so it's Xcode 15.2 / iOS 17.2 SDK. Folder-synced groups need Xcode 16, so `ios/Loop.xcodeproj` is generated from `ios/project.yml` by XcodeGen (`bash ios/generate.sh`) and committed. Only the iOS lane runs it.

### 2026-10-17 — lane created
- Now: nothing in progress. Start with Phase 0 in `PLAN.md`.
