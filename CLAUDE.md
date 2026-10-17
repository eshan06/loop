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

Each machine sets its lane once, in a file git ignores:

```
echo ios > .lane      # on the iOS Mac
echo server > .lane   # on the OCI Mac
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

Deploy to the OCI server:

```
ssh -i key.pem opc@<server-ip>
cd ~/loop && git pull && sudo systemctl restart loop-api
```

iOS lane: open `ios/Loop.xcodeproj` and run. The base URL and the mock switch live in `ios/Loop/Config/APIConfig.swift`.

## Gotchas

- The phone can't reach the API unless port 8000 is open in both the VCN security list and the server firewall (`sudo firewall-cmd --add-port=8000/tcp --permanent && sudo firewall-cmd --reload`).
- iOS blocks plain `http://` by default. See "HTTPS and iOS" in `docs/ARCHITECTURE.md`.
- The OCI Free Trial may not include every model. If `cohere.command-a-vision` isn't in the Generative AI Playground's model list, use the fallback scan path in `docs/ARCHITECTURE.md`.
- `No module named oci` means the venv isn't active.
- The Cohere models often wrap JSON replies in ```json fences even when told not to. Strip fences before parsing.
