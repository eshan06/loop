# Server lane log

Only the server machine (the one with the OCI account) edits this file. The iOS lane reads it after every pull.

Add new log entries at the top of the Log section, newest first. Keep each entry short. `/handoff` writes them for you.

## Server status

- API base URL: `http://163.192.218.131:8000` (plain HTTP, so the app needs ATS Allow Arbitrary Loads). The S-4 skeleton answers `GET /health` there, but it is not running permanently until S-6 (systemd).
- Vision model (`cohere.command-a-vision`) available on our account: YES, tested 2026-10-17 from the OCI server, ~1-2s per call (1 or 2 JPEGs) → main scan path. `labels` is only needed for the fallback.
- Demo accounts: not seeded yet

Keep this block current. It's the first thing the iOS lane looks at.

## Contract changes

Every change to `docs/API.md` gets a line here: what changed and whether the iOS lane needs to update anything.

- 2026-10-17: added status 500 with code `server_error` to the error table. Same error shape; iOS just shows `error.message`, no change needed.

## Open requests to the iOS lane

Give each request an ID (`SRV-1`, `SRV-2`, ...). Move it to "Closed requests" once the iOS lane answers in `coord/ios.md`.

None yet.

## Closed requests

None yet.

## Log

### 2026-10-17 — S-5 done
- Done: S-5. MySQL admin login works. `backend/migrations/001_schema.sql` creates all 12 tables from the ARCHITECTURE data model (InnoDB, utf8mb4, VARCHAR enums, FKs, feed/request/message/notification indexes) in database `loop`, applied on the server. Runner: from `backend/` with the venv, `python migrate.py` (idempotent, tracks `schema_migrations`) or `python migrate.py --status`.
- Done: `scripts/db-tunnel.sh` forwards MySQL to the Mac (3306, or 3307 if a local MySQL holds 3306; this Mac uses 3307). `SHOW TABLES` verified through it.
- Now: S-6 (systemd `loop-api`).
- Heads-up: no contract change. Tables are empty until the seed script (S-15).

### 2026-10-17 — S-4 done
- Done: S-4. FastAPI skeleton in `backend/app/` (config, lazy DB engine, CORS, `/media` static, one error handler). `GET /health` → `{"status":"ok"}`; every error (unknown route, validation, `ApiError`, crashes) returns `{"error":{"code","message"}}`. Venv + `.env` set up on the server; verified from outside on port 8000, then stopped.
- Now: S-5 (DB tunnel and schema).
- Contract: added `500 server_error` to the error table (see Contract changes).
- Heads-up: validation errors come back as 400 `bad_request`, never 422. The API is not left running until S-6.

### 2026-10-17 — S-3 done
- Done: S-3. `cohere.command-a-vision` answers on-demand chat calls with images (Cohere V2 format), ~1.1-2.0s per call; `cohere.command-a-03-2025` text works too (~1.5s). Scan uses the main vision path. Request code is in `backend/app/genai_probe.py` for S-10.
- Now: S-4 (FastAPI skeleton).
- Heads-up: no contract change. The app can still send `labels` with `/scan` as a backup, but the vision path doesn't need them.

### 2026-10-17 — S-2 done
- Done: S-2. Port 8000/tcp is open in the VCN security list "Allow HTTP(S) to WebServer" (ingress from 0.0.0.0/0, "Loop API") and in firewalld on the server. A test HTTP server on 8000 answered 200 from outside.
- Now: S-3 (vision model check).
- Heads-up: nothing listens on 8000 yet, so `http://163.192.218.131:8000` refuses connections until S-4/S-6.

### 2026-10-17 — S-1 done
- Done: S-1. The OCI stack is up and SSH works. The repo is cloned to `~/loop` on the server (163.192.218.131). Python 3.12 is installed there.
- Now: S-2 (open port 8000), then S-3 (vision model check).

### 2026-10-17 — lane created
- Now: nothing in progress. Start with Phase 0 in `PLAN.md`.
