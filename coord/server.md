# Server lane log

Only the server machine (the one with the OCI account) edits this file. The iOS lane reads it after every pull.

Add new log entries at the top of the Log section, newest first. Keep each entry short. `/handoff` writes them for you.

## Server status

- API base URL: not deployed yet. It will be `http://163.192.218.131:8000` once S-2 and S-4 land.
- Vision model (`cohere.command-a-vision`) available on our account: listed in the model catalog, but not called yet. S-3 will confirm it.
- Demo accounts: not seeded yet

Keep this block current. It's the first thing the iOS lane looks at.

## Contract changes

Every change to `docs/API.md` gets a line here: what changed and whether the iOS lane needs to update anything.

None yet.

## Open requests to the iOS lane

Give each request an ID (`SRV-1`, `SRV-2`, ...). Move it to "Closed requests" once the iOS lane answers in `coord/ios.md`.

None yet.

## Closed requests

None yet.

## Log

### 2026-10-17 — S-2 done
- Done: S-2. Port 8000/tcp is open in the VCN security list "Allow HTTP(S) to WebServer" (ingress from 0.0.0.0/0, "Loop API") and in firewalld on the server. A test HTTP server on 8000 answered 200 from outside.
- Now: S-3 (vision model check).
- Heads-up: nothing listens on 8000 yet, so `http://163.192.218.131:8000` refuses connections until S-4/S-6.

### 2026-10-17 — S-1 done
- Done: S-1. The OCI stack is up and SSH works. The repo is cloned to `~/loop` on the server (163.192.218.131). Python 3.12 is installed there.
- Now: S-2 (open port 8000), then S-3 (vision model check).

### 2026-10-17 — lane created
- Now: nothing in progress. Start with Phase 0 in `PLAN.md`.
