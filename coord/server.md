# Server lane log

Only the server machine (the one with the OCI account) edits this file. The iOS lane reads it after every pull.

Add new log entries at the top of the Log section, newest first. Keep each entry short. `/handoff` writes them for you.

## Server status

- API base URL: `http://163.192.218.131:8000` — LIVE (systemd `loop-api`, restarts itself on crash and on boot). Plain HTTP, so the iOS app needs the ATS exception (Allow Arbitrary Loads). `GET /health` → `{"status":"ok"}`.
- Vision model (`cohere.command-a-vision`) available on our account: YES, tested 2026-10-17 from the OCI server, ~1-2s per call (1 or 2 JPEGs) → main scan path. `labels` is only needed for the fallback.
- Demo accounts: not seeded yet

Keep this block current. It's the first thing the iOS lane looks at.

## Contract changes

Every change to `docs/API.md` gets a line here: what changed and whether the iOS lane needs to update anything.

- 2026-10-17: added status 500 with code `server_error` to the error table. Same error shape; iOS just shows `error.message`, no change needed.
- 2026-10-17 (S-7): new Conventions rules: timestamps always whole seconds with `Z`; nullable keys always present as `null`; arrays never `null`; decode impact numbers as `Double`; any 401 means sign out; other-campus IDs answer 404. iOS: use `.iso8601`, mark the listed fields optional.
- 2026-10-17 (S-7): new "Photo URLs" section: every URL is absolute (`PUBLIC_BASE_URL` + `/media/<file>`, live: `http://163.192.218.131:8000/media/71.jpg`), opaque, no auth. iOS: load as is, never build URLs.
- 2026-10-17 (S-7): Paging section lists which endpoints are paged, with a JSON example. iOS: one generic `Page<T>` type.
- 2026-10-17 (S-7): new 409 codes `own_listing`, `already_requested`, `listing_unavailable`, `wrong_status` (generic `conflict` stays). iOS: branch on `code`; treat unknown codes as the status's generic one.
- 2026-10-17 (S-7): nullability spelled out for User, Owner, Listing, Request, Notification, ScanDraft. `ScanDraft.tags` is always an array (empty, not `null`). iOS: optionals in models.
- 2026-10-17 (S-7): Listing gains `is_mine`, `my_request_id`, `pending_request_count`, `accepted_request_id` (additive). iOS: add to model and mocks; use `my_request_id` to open chat from detail, `accepted_request_id` for "mark exchanged" on My listings.
- 2026-10-17 (S-7): Request's `listing` summary gains `status` (additive). iOS: add to model and mocks.
- 2026-10-17 (S-7): new endpoints `GET /me/unread` (bell + Requests tab badge counts), `GET /dorms` (dorm picker; empty list means free text), `GET /requests/{id}` (open from a notification, chat refresh). iOS: add mocks.
- 2026-10-17 (S-7): `GET /me/badges` items gain `progress` and `goal`; badge IDs listed as an enum. iOS: add to model and mocks.
- 2026-10-17 (S-7): placeholder examples (`{"...": "User object"}`, `{"...": "ScanDraft"}`) replaced with full JSON; new full examples for `source: none` scan, messages list, notifications page, meetup spots, PATCH /me body. iOS: re-copy these mocks.
- 2026-10-17 (S-7): rules spelled out per endpoint (no change to shapes): success statuses, field length limits for listings and profile, `photo_ids` 1 to 5, `PATCH /listings` replaces photos, DELETE/PATCH on completed listings is 409, `role` required on `/me/requests`, `GET /listings/{id}` works in any status, hidden listings visible to their owner, which events send which notification, email normalization and campus from the last two domain labels. iOS: nothing beyond the above.
- Contract v1 frozen (2026-10-17). Changes from now on go through the request process in CLAUDE.md.

## Open requests to the iOS lane

Give each request an ID (`SRV-1`, `SRV-2`, ...). Move it to "Closed requests" once the iOS lane answers in `coord/ios.md`.

None yet.

## Closed requests

None yet.

## Log

### 2026-10-17 — S-11 done: listings live
- Done: S-11. Live: `GET /listings` (campus feed: `active` only, own listings included with `is_mine: true`, newest first; filters `share_type`, `category`, `size` exact ignoring case; `q` substring over title, brand, tags, case-insensitive; paged, `limit` over 50 is capped to 50, `limit<1`/`offset<0`/unknown enum → 400), `POST /listings` (201; limits and errors per API.md, `too_many_photos` over 5), `GET /listings/{id}` (any status; hidden → 404 except owner; other campus → 404), `PATCH` (partial; `photo_ids` replaces photos in the given order; 403 not owner; 409 `wrong_status` when completed), `DELETE` (204; cascades requests/chats; freed photos can be reused), `GET /me/listings?status=active|completed` (active = active + pending + hidden). Full Listing object incl. `my_request_*`, `pending_request_count`, `accepted_request_id`, `saved_by_me`, owner `items_shared`.
- Done: smoke.sh now 171 checks, all pass. Hidden/pending/completed and request-aggregate fields also checked by hand with DB edits (no request endpoints yet).
- Now: S-10 / S-12.
- Heads-up: enum values are accepted case-insensitively and stored lowercase; tags are trimmed and de-duplicated. `impact` numbers are PROVISIONAL (`backend/app/impact.py`) until S-17 swaps in the cited table; shape won't change. New migration `003_photo_position.sql` (applied).

### 2026-10-17 — S-14 done: meetup spots live
- Done: S-14. `GET /meetup-spots` live: `{"items": [{id, name}]}` for the caller's campus, sorted by name, 401 without token. Every campus has spots: a new campus gets 4 defaults at first login (Campus Center, Main Dining Hall, Main Library entrance, Student Union), and an older campus with none gets them on its first `GET /meetup-spots`. Defaults live in `backend/app/campus.py` (`DEFAULT_MEETUP_SPOTS`, `get_or_create_campus`); `meetup_spot_out` in serializers.py is ready for S-11's Listing.
- Done: smoke.sh now 71 checks, all pass.
- Now: S-10 / S-11.
- Heads-up: spot IDs differ per campus (and S-15 may give the demo campus real spot names), so never hardcode them; a listing `meetup_spot_id` must be one of the IDs from `GET /meetup-spots`.

### 2026-10-17 — S-9 done: photo uploads live
- Done: S-9. `POST /photos` live (multipart `file` + `kind`, 201 Photo). Server re-encodes every upload: EXIF orientation applied, RGB, longest side 1600, JPEG q85, random hex filename under `/media/`. Errors per API.md: `photo_too_large` over 5 MB, `bad_request` for non-JPEG/broken file, missing or unknown `kind`, missing file; 401 without token. `kind` is case-insensitive. Photo URLs load with no auth (200 `image/jpeg`).
- Done: smoke.sh now 63 checks, all pass (uploads, EXIF rotate, resize, error codes, avatar via `PATCH /me` showing in `GET /me`).
- Now: S-10 (scan); it reuses `backend/app/photos.py` (`read_upload` / `save_photo`).
- Heads-up: the server only accepts JPEG (checked by content, not by the part's Content-Type). Convert HEIC/PNG to JPEG on the phone before upload, as API.md already says.

### 2026-10-17 — S-8 done: auth and profile live
- Done: S-8. Live on the server: `POST /auth/login` (.edu check, campus from the last two domain labels, new campus named after the domain, 32-char bearer tokens that never expire), `GET /me`, `PATCH /me` (limits per API.md; `dorm` must match `GET /dorms` when the campus has a list, case-insensitive; `avatar_photo_id` must be your own photo), `GET /me/unread` (real counts from notifications, pending requests on my listings, unread messages), `GET /dorms`. All 13 tables have ORM models; shared User/Owner/Photo builders in `backend/app/serializers.py`.
- Done: `scripts/smoke.sh` (44 checks, all pass against the live server). Run `bash scripts/smoke.sh` anytime; it makes throwaway users on campus `smoke.edu`.
- Now: S-9 (photos).
- Heads-up: `is_new` is `true` only on the very first login, per the contract. If someone quits during profile setup, the next login says `is_new: false` with `name: null`, so the app should also show profile setup whenever `user.name` is `null`. Validation errors are `400 bad_request` with the field name at the start of `message` (e.g. `name: must be 1 to 80 characters.`).

### 2026-10-17 — S-7 done, contract v1 frozen
- Done: S-7. No iOS requests were filed, so the server lane reviewed `docs/API.md` against every Tier 1 and Tier 2 screen and the demo path, filled the gaps, and froze v1. Migration `002_dorms.sql` (new `dorms` table) is applied on the server; `/health` OK after deploy.
- Now: Phase 2, starting with S-8 (auth, `/me`).
- Contract: 4 new 409 codes; new `GET /me/unread`, `GET /dorms`, `GET /requests/{id}`; Listing adds `is_mine`, `my_request_id`, `pending_request_count`, `accepted_request_id`; Request.listing adds `status`; badges add `progress`/`goal`; nullability, date format, photo URL and paging rules written down. Full list under Contract changes.
- Heads-up: iOS should copy mock JSON fresh from `docs/API.md` (several examples changed or are new; all 29 JSON blocks parse). No real conflicts with FEATURES.md; where they read differently, API.md wins: the feed's share-type chips are single-select (`share_type` takes one value), profile setup picks the dorm from `GET /dorms` (free text only when that list is empty), and a hidden listing stays visible to its owner under My listings.

### 2026-10-17 — S-6 done, server half of Sync point A ready
- Done: S-6. The API runs under systemd as `loop-api` (enabled, `Restart=always`); killing it brings it back in ~2s. `GET http://163.192.218.131:8000/health` → `{"status":"ok"}` from outside. Unit: `scripts/loop-api.service`. Deploy from the Mac: `bash scripts/deploy.sh` (pull, pip, migrate, restart, health check).
- Sync point A: server half ready. iOS lane: turn mocks off and call `/health` from the simulator (plain HTTP, needs the ATS exception), then note it in `coord/ios.md`.
- Now: Phase 1 / S-7 (answer iOS requests, freeze contract v1).
- Heads-up: every deploy restarts the API, so it's down for a few seconds.

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
