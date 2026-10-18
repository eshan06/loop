# Loop

Loop is an iOS app for college students to swap, give away, and donate clothes on their own campus. You scan an item with the camera, AI fills in the listing, and other students on campus can request it. Built by team Stacked for an Oracle (OCI) hackathon.

The goal is a polished demo with a lot of working features. It only has to handle demo traffic, so pick the simplest thing that works and looks good.

## Read these first

- `PLAN.md` is the shared task board: what each machine is doing right now and what comes next.
- `coord/ios.md` and `coord/server.md` are the two lanes' status logs. Read the other lane's log at the start of every session.
- `docs/FEATURES.md` lists every feature, its tier, and which lane builds which half.
- `docs/API.md` is the contract between the app and the backend.
- `docs/ARCHITECTURE.md` covers the data model, the AI scan pipeline, and the OCI setup.

## Two machines, two lanes

Two Macs run Claude Code at the same time, one per lane. They never edit the same files, so they can push to `main` all day without stepping on each other.

| Lane | Machine | Owns | Writes to |
| --- | --- | --- | --- |
| `ios` | iOS Mac | Every screen in the app | `ios/`, `coord/ios.md`, iOS lines in `PLAN.md` |
| `server` | The Mac with the OCI account | Backend, database, AI calls, the OCI server, seed data | `backend/`, `scripts/`, `docs/API.md`, `coord/server.md`, server lines in `PLAN.md` |

Each machine runs this once after cloning. It sets the lane in a file git ignores and turns on the repo's git hooks:

```
echo ios > .lane      # on the iOS Mac
echo server > .lane   # on the OCI Mac
git config core.hooksPath .githooks
```

If a third person is coding, they work through one of these two machines' lanes and claim tasks in that lane. Only two machines push code at once.

## How the machines talk (GitHub is the channel)

Run `/sync` at the start of every session and before starting each task. It pulls, shows anything that changed in `docs/API.md`, prints the other lane's latest log entry, and lists your open tasks.

Run `/handoff` after finishing each task, and at least every 45 minutes while working. It writes a log entry to your lane's coord file, updates your lines in `PLAN.md`, commits, and pushes.

Between those, the rules are:

1. Only edit your own lane's files. If you need something from the other lane, write a request in your own coord file under "Open requests" (`IOS-1`, `SRV-1`, and so on). The other lane answers in its own file and references the ID.
2. `docs/API.md` belongs to the server lane. The iOS lane asks for changes through a request. The server lane makes the change, notes it under "Contract changes" in `coord/server.md`, and pushes the doc before or with the code.
3. Small commits, pushed often. Always `git pull --rebase` before pushing. If a push is rejected, pull with rebase and push again. Never force-push `main`.
4. If you're blocked, mark the task `[!]` in `PLAN.md`, say why in your coord file, and pick up the next unblocked task. Don't wait idle.

## Commits

Commits never credit Claude. Don't add a `Co-Authored-By: Claude` line or a "Generated with Claude Code" line to any commit message, including commits Claude Code makes on its own. Commit messages start with the lane, like `ios: feed filters (I-11)`.

As a backstop, `.githooks/commit-msg` strips those lines from every commit. It only runs on machines that ran `git config core.hooksPath .githooks`.

## Rules for the code

- The iOS app never calls OCI. Every AI call goes through our backend, so no OCI keys ship in the app.
- Never commit secrets: `key.pem`, anything from `~/.oci/`, API keys, DB passwords, `.env`. Keep `backend/.env.example` current with blank values.
- The app must run without the backend. Mock JSON in `ios/Loop/Mocks/` matches the examples in `docs/API.md`, behind one switch in `APIConfig.swift`.
- When you learn something the hard way (a deploy fix, an OCI quirk), add a line to "Gotchas" below in the same commit. If both lanes touch this file in the same hour, git may ask you to merge by hand. Keep edits small.

## Repo layout

```
CLAUDE.md
PLAN.md
coord/        ios.md, server.md
docs/         FEATURES.md, API.md, ARCHITECTURE.md
ios/          Xcode project, SwiftUI (ios lane)
backend/      FastAPI app (server lane)
scripts/      sync.sh and server helpers
.claude/      shared Claude Code commands
```

`ios/` and `backend/` get created in Phase 0 of `PLAN.md`.

## Stack

- iOS: SwiftUI, iOS 17+, async/await, `URLSession`. No third-party packages unless both lanes agree.
- Backend: Python 3.12, FastAPI, Uvicorn, SQLAlchemy, `mysql-connector-python`, the `oci` SDK.
- Database: MySQL HeatWave on OCI. It only has a private IP, so laptops reach it through an SSH tunnel.
- AI: OCI Generative AI in `us-chicago-1`. `cohere.command-a-vision` reads the photos; `cohere.command-a-03-2025` writes text.
- Server: OCI compute instance, Oracle Linux 9, user `opc`. The repo is cloned to `~/loop` with a venv at `~/loop/backend/.venv`.

## Commands

Server lane, on the Mac (DB through the tunnel described in `docs/ARCHITECTURE.md`):

```
cd backend && source .venv/bin/activate
uvicorn app.main:app --reload --port 8000
```

Deploy to the OCI server (push first; pulls, installs deps, migrates, restarts `loop-api`, checks `/health`):

```
bash scripts/deploy.sh
```

iOS lane: open `ios/Loop.xcodeproj` and run. The base URL and the mock switch live in `ios/Loop/Config/APIConfig.swift`.

## Gotchas

- The phone can't reach the API unless port 8000 is open in both the VCN security list and the server firewall (`sudo firewall-cmd --add-port=8000/tcp --permanent && sudo firewall-cmd --reload`).
- iOS blocks plain `http://` by default. See "HTTPS and iOS" in `docs/ARCHITECTURE.md`.
- The OCI Free Trial may not include every model. If `cohere.command-a-vision` isn't in the Generative AI Playground's model list, use the fallback scan path in `docs/ARCHITECTURE.md`.
- `No module named oci` means the venv isn't active.
- Deleting a Campus (or any parent) through the ORM after its children are loaded makes SQLAlchemy null the children's FK and fail; delete with plain SQL (`DELETE FROM campuses ...`) and let `ON DELETE CASCADE` do it.
- `mysql-connector-python` crashes on import under Python 3.13+ (`ssl.PROTOCOL_TLSv1` is gone). Run the backend with Python 3.12; for a quick check through the tunnel on a newer Python, use PyMySQL.
- The Cohere models often wrap JSON replies in ```json fences even when told not to. Strip fences before parsing.
- SELinux on the server: systemd can't exec the venv in `~` (203/EXEC) until `.venv/bin` is labeled `bin_t` (`semanage fcontext -a -t bin_t "/home/opc/loop/backend/.venv/bin(/.*)?"` + `restorecon -R`; `deploy.sh` re-runs restorecon), and it can't read `~/loop/backend/.env` as an `EnvironmentFile`, so the unit has none and the app loads `.env` itself.
- `GET /requests/{id}/messages` moves read markers, so anything that must not change demo data (smoke, checks) should read `GET /requests/{id}` or `/me/unread` instead. Wikimedia Commons answers 429 to fast thumbnail downloads; fetch about one file per second.
- iOS Mac (macOS 13): newest Xcode is 15.2 (Swift 5.9, iOS 17.2 SDK), so no iOS 18 APIs. Folder-synced groups need Xcode 16, so `ios/Loop.xcodeproj` is generated from `ios/project.yml`; after adding or removing Swift files run `bash ios/generate.sh` (Homebrew can't build XcodeGen on macOS 13, the script downloads the release binary).
- Xcode 15 doesn't main-actor-isolate View members: mark `View` structs `@MainActor` or they can't touch the `@MainActor` stores.
- `-useMocks NO` on the command line arrives as the string "NO", not a Bool. `APIConfig` reads it with `bool(forKey:)`.
- Run the iOS tests with `xcodebuild test -project ios/Loop.xcodeproj -scheme Loop -destination 'platform=iOS Simulator,name=iPhone 15 Pro'`. `TEST_RUNNER_LOOP_LIVE=1` also runs the read-only live-server walk-through.
- Apple Vision on the phone is insurance, never a gate: `OnDeviceLabeler` returns whatever it has after 8 seconds, so a stalled Vision call can't hold up `/scan`.
- Real device vs Simulator: the camera needs a real iPhone. To test the photo picker, add media first (`xcrun simctl addmedia booted a.jpg b.heic`); the UI tests use it.
- The sign-in screen (DEBUG builds) has a Mock data / Live server switch, so a phone can talk to the real server with no code change and no launch arguments. Mock and live sessions keep separate tokens.
- Loop Lime (`Theme.lime`, `#C7E75A`) is an accent, not a theme: Scan button, welcome highlighter, Just posted tag, completion checkmark, "You"/"Yours". Near-black (`Theme.onLime`) on top of it. Don't write the hex anywhere else.
- App icon: `swift ios/Tools/make-app-icon.swift` renders "loop." (lime on #191919, no alpha) into the asset catalog; edit the script, not the PNG. The in-app wordmark is type only; welcome-screen text uses `Theme.ink` (#191919).
- To start the Simulator in Live mode without tapping: quit the app, edit `Library/Preferences/com.stacked.loop.plist` in its data container (`xcrun simctl get_app_container booted com.stacked.loop data`), set `useMocks` to false, and reboot the Simulator (its preferences daemon caches the old value). `-resetSession YES` signs out only the mode that is active.
- `python3 -I ios/Tools/live-audit.py` is the read-only live check of server JSON against the Swift models; run it after the server lane changes the API.
- Release (TestFlight) builds always use the live server; only DEBUG builds have the Mock/Live switch. Every TestFlight upload needs a new `CURRENT_PROJECT_VERSION` in `ios/project.yml` (Info.plist reads it from the build setting).
