# Server lane log

Only the server machine (the one with the OCI account) edits this file. The iOS lane reads it after every pull.

Add new log entries at the top of the Log section, newest first. Keep each entry short. `/handoff` writes them for you.

## Server status

- API base URL: `http://163.192.218.131:8000` — LIVE (systemd `loop-api`, restarts itself on crash and on boot). Plain HTTP, so the iOS app needs the ATS exception (Allow Arbitrary Loads). `GET /health` → `{"status":"ok"}`.
- Vision model (`cohere.command-a-vision`) available on our account: YES, tested 2026-10-17 from the OCI server, ~1-2s per call (1 or 2 JPEGs) → main scan path. `POST /scan` live: ~3-4.5 s end to end (1-3 photos). `labels` is only needed for the fallback.
- Demo accounts: SEEDED (S-15) on campus Vanderbilt (`vanderbilt.edu`): `jordan.park@vanderbilt.edu` (Jordan Park, Kissam), `sam.lee@vanderbilt.edu` (Sam Lee, Zeppos), `riley.chen@vanderbilt.edu` (Riley Chen, E. Bronson Ingram). Log in with the email only. Plus 8 more students, 39 listings, requests and chats. Reset to the clean demo state anytime: `bash scripts/reseed.sh` (keeps these three accounts' ids and sessions).

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
- 2026-10-17 (S-10): `POST /scan` `kinds` must each be `front`, `back`, `label`, or `other` (`avatar` is a 400). iOS: nothing to do if it sends front/back/label.
- Contract v1 frozen (2026-10-17). Changes from now on go through the request process in CLAUDE.md.
- 2026-10-17 (S-13): messages rules spelled out (additive, no shape change): `POST /requests/{id}/messages` trims `body`; empty/missing → 400. Sending marks the sender's side read and bumps the Request's `updated_at` (chat moves to the top of `GET /me/requests`); reading doesn't change `updated_at`. iOS: nothing to do.
- 2026-10-17 (S-15, IOS-2): new "Sizes" section after Enums: the size vocabulary (tops/outerwear/dresses `XS`-`XXL`, bottoms waist `24`-`40` or a letter, shoes `5`-`14` in halves, accessories/bags `One size`). Still free strings, no shape change. `POST /scan` now maps the model's size into it (`Large` → `L`, `W32 L30` → `32`, `US 9 1/2` → `9.5`) and gives accessories/bags with no size `One size` instead of `null`. iOS: nothing to do (matches `SizeVocabulary.swift`).
- 2026-10-17 (S-17): additive, no shape change. New "Where the impact numbers come from" section (after `GET /impact/campus`) with the citation and the per-category table; `GET /impact/campus` rules spelled out (`items_rehomed` = exchanges completed on my campus in the last 7 days, each item counted once; `top_dorm` = owner dorm with the most, ties alphabetical). Listing `impact` values changed (real numbers now) and `water_l` comes back as e.g. `777.0`. iOS: nothing to do (decode as `Double`).
- 2026-10-17 (S-18): clarification, no shape change. Saves: re-saving keeps the original save time, you can save your own listing, PUT/DELETE on a listing you can't see is `404 not_found`. iOS: nothing to do.
- 2026-10-17 (S-19): clarification, no shape change. `GET /listings/{id}/similar` never includes the caller's own listings; score = 3 per shared tag + 2 same category + 1 same size, ties newest; zero-score items only fill when there aren't enough matches; `limit` over 20 treated as 20; source not visible → `404 not_found`. iOS: nothing to do.
- 2026-10-17 (S-20): clarification, no shape change. `POST /listings/{id}/style`: title <= 40 and description <= 200 chars; cache cleared when title/category/color/tags change; same visibility as `GET /listings/{id}` (else `404 not_found`); if the model fails or takes > 15 s the server returns 3 template ideas (200, same shape, not cached) instead of `502 ai_unavailable`; demo listings are pre-cached. iOS: nothing to do (expect ~5 s on a first, uncached call).
- 2026-10-17 (S-21): clarification, no shape change. `GET /leaderboard/dorms`: ties are listed alphabetically and the next rank skips ahead (1, 1, 3); owners without a dorm aren't counted; the first row's `dorm` is always `/impact/campus` `top_dorm`. iOS: nothing to do.

## Open requests to the iOS lane

Give each request an ID (`SRV-1`, `SRV-2`, ...). Move it to "Closed requests" once the iOS lane answers in `coord/ios.md`.

None yet.

## Closed requests

None yet.

## Log

### 2026-10-17 — S-21 done: dorm leaderboard live
- Done: S-21. `GET /leaderboard/dorms` (`app/routers/stats.py`): completed exchanges in the last 7 days on my campus, counted by the listing owner's current dorm (owners with no dorm skipped), most first, ties alphabetical sharing a rank (1, 1, 3). `/impact/campus` `top_dorm` now comes from the same helper (`dorm_board`), so it is always the board's first dorm. Smoke 559 checks, passed twice.
- Contract: clarification, no shape change (see Contract changes). iOS: nothing to do; `LeaderboardEntry` and the mock's ranking already match.
- Heads-up: the demo board right now has a tie at the top (Kissam and Zeppos, 2 each, both rank 1; 8 dorms in all). Seeded completions are relative to reseed time, so the board empties a week after the last reseed. S-25 can give one dorm a clear lead if wanted.
- Now: S-22 (badges).

### 2026-10-17 — S-20 done: Style it live, demo listings pre-warmed
- Done: S-20. `POST /listings/{id}/style` (`app/style.py`, route in `app/routers/listings.py`): cached ideas return instantly (~0.07 s); otherwise `cohere.command-a-03-2025` writes 3 ideas as JSON (validated, title <= 40 / description <= 200 chars), cached in `listings.style_ideas` as `{basis, ideas}` where `basis` hashes title/category/color/tags, so an edit regenerates. Model failure or > 15 s → 3 template ideas from category + color, 200, not cached (a reply landing after the timeout still gets cached). Real model calls take ~4-7 s (not 1.5 s), with rare spikes past 15 s. Demo: `backend/seed/style_ideas.json` snapshot for all 39 listings, baked in by `seed.py` (reseed makes no AI calls); `python -m seed.style_warm [--force]` regenerates it on the server. Smoke 533 checks, passed twice.
- Contract: clarification, no shape change (see Contract changes). iOS: nothing required; the 502 path can stay, it just won't fire. Show a spinner on the first tap of a non-demo listing (~5 s).
- Heads-up: demo reseeded (same data, now with style ideas on every listing).
- Now: S-21 (dorm leaderboard).

### 2026-10-17 — S-19 done: similar items live
- Done: S-19. `GET /listings/{id}/similar` in `app/routers/listings.py`: loads (id, tags, category, size, created_at) for the campus's active listings, minus the source and the caller's own, ranks in Python (3 per shared tag case-insensitive + 2 same category + 1 same size; newest, then id), returns the top `limit` (default 6, max 20) as full Listings via `listings_out`. Source follows GET /listings/{id} visibility (other campus/deleted/someone else's hidden → 404). Smoke 492 checks, passed twice; demo check asserts a Jordan item has 3+ similar items.
- Contract: clarification only (see Contract changes). iOS: nothing to do for I-20.
- Heads-up: smoke can't cover hidden-source 404 until reports (S-24) can hide a listing; the code path is the shared `_visible` check.
- Now: S-20 (style ideas).

### 2026-10-17 — S-18 done: saves live
- Done: S-18. `PUT` and `DELETE /listings/{id}/save` (204, idempotent; re-saving keeps the original save time) and `GET /me/saved` (paged, newest save first, tie-break listing id; any status except `hidden`, so pending/completed items stay with their status) in `app/routers/listings.py`. `saved_by_me` was already filled by the batched serializer (one query per page). Saving your own listing is allowed (API.md only forbids requesting/reporting your own). Not visible (other campus, deleted, someone else's hidden) → 404 `not_found` for PUT and DELETE. Smoke 461 checks, passed twice.
- Contract: clarification only, no shape change (see Contract changes). iOS: nothing to do.
- Heads-up: demo reseeded. Jordan has 3 saved items (puffer, wool coat, flannel), Sam 1, Riley 1; seed `--check` now asserts Jordan has 2+.
- Now: S-19 (similar items).

### 2026-10-17 — S-17 done: cited impact numbers, /impact/me and /impact/campus live
- Done: S-17. `backend/app/impact.py` now = typical garment mass x WRAP per-kg footprint, full citation and derivation in its header comment and in API.md "Where the impact numbers come from". Per item: tops 0.11 kg / 777 L / 2.6 kg CO2e, bottoms 0.48 / 3368 / 11.1, dresses 0.48 / 3375 / 11.1, outerwear 0.44 / 3135 / 10.3, accessories 0.04 / 304 / 1.0, shoes = bottoms, bags = outerwear. `GET /impact/me` (both giver and receiver get the item's full impact) and `GET /impact/campus` (last 7 days, `top_dorm` by owner dorm) live in `app/routers/stats.py`. Demo now: Jordan 1 shared, 11.1 kg CO2e; Vanderbilt 10 items, 98.3 kg CO2e, top dorm Kissam. Smoke 413 checks, passed twice.
- Heads-up, USER MUST SANITY-CHECK THE SOURCE before the judges see it: footprints from WRAP (2017) "Valuing Our Clothes: the cost of UK fashion", p.11 Table 3, 2016 column (23.2 t CO2e and 7,060 m3 water per tonne of clothing) https://www.wrap.ngo/sites/default/files/2020-10/WRAP-valuing-our-clothes-the-cost-of-uk-fashion_WRAP.pdf ; garment masses from Sandin et al. (2019) Mistra Future Fashion report 2019:05, Table 3.1, printed p.28 (T-shirt 110 g, jeans 477 g, dress 478 g, jacket 444 g, socks 43 g) https://research.chalmers.se/publication/514322 . Two sources, because WRAP gives no per-garment weights. ASSUMPTIONS: shoes use the jeans mass and bags the jacket mass (neither source covers footwear or bags), and WRAP's clothing factors are applied to shoes/bags too.
- Heads-up: campus impact only counts the last 7 days, so the seeded exchanges (completed 14-158 h before the seed ran) start dropping off; reseed (`bash scripts/reseed.sh`) the morning of the demo.
- Now: S-18 (saves).

### 2026-10-17 — S-15 done: Vanderbilt demo campus seeded
- Done: S-15. `backend/seed/seed.py` (`python -m seed.seed`, or `seed.reset`, or `bash scripts/reseed.sh` from the Mac) wipes and rebuilds campus `vanderbilt.edu` in one transaction; ran twice on the server, identical state. 8 dorms, 7 meetup spots (4 defaults + Commons Center, Rand Dining Center, Alumni Lawn), 11 students, 39 listings (27 active in the feed, 2 pending, 10 completed over the last 7 days, all 7 categories, swap/free/donate), 16 requests (10 completed, 2 accepted, 4 pending), 13 chat messages, 5 saves. No AI calls. Smoke now 384 checks, all pass; the new demo section is read-only.
- IOS-1: done, exactly those three emails (see Server status). Jordan: 3 pending incoming (Converse x2, cap), an accepted swap with Sam with 1 unread message from Sam, an accepted request on Riley's Docs (outgoing), 1 completed. Sam: 1 pending incoming, the chat with Jordan.
- IOS-2: done. All seed sizes use the vocabulary; scan maps the model's size into it (`backend/app/ai.py` `normalize_size`); documented in API.md "Sizes" (see Contract changes).
- IOS-3: acknowledged, scheduled for S-28 (Tier 3); nothing added yet.
- Heads-up: photos are PLACEHOLDERS from Wikimedia Commons (`backend/seed/photos/`, credits in `ATTRIBUTION.md`); the team's real photos replace them in S-25 by swapping files and editing `manifest.json`. Photo URLs look like `/media/seed/<name>-<hash>.jpg` and change when a photo changes. A reseed deletes every other `vanderbilt.edu` user (their tokens 401) and resets the three demo accounts' data, but their tokens keep working.
- Now: S-16 after the integration run, else S-17.

### 2026-10-17 — S-13 done: chat live
- Done: S-13. Live: `GET /requests/{id}/messages[?after_id=N]` (`{"items": [Message]}` oldest first by id, not paged; any request status; marks read up to the newest returned id, never backwards; non-numeric `after_id` → 400) and `POST /requests/{id}/messages` (201 + Message; body trimmed, 1-1000 chars else 400; only while `accepted` else 409 `wrong_status`). Both: the two people only → 403; other campus/no such request → 404 (same `find_request` helper as `GET /requests/{id}`). `unread_messages` on Requests and `GET /me/unread` `messages` now move with chat (smoke-tested both sides). The 3 s poll is 3 PK lookups + one range scan on `(request_id, id)`, and only writes when there's something new.
- Done: `message_out` in serializers.py; `events.on_message_sent(db, msg, req, actor)` no-op hook for S-23 `new_message`. smoke.sh now 346 checks, all pass (2 runs in a row).
- Contract: send trims and bumps the Request's `updated_at`; reading doesn't. No iOS change.
- Now: S-15 (seed, demo accounts per IOS-1/IOS-2).

### 2026-10-17 — S-12 done: requests live
- Done: S-12. Live: `POST /listings/{id}/requests` (201; note optional, trimmed, 280 max; body may be `{}` or empty; 409 `own_listing` / `already_requested` (open = pending or accepted) / `listing_unavailable` (not active), checked in that order; re-request allowed after declined/cancelled), `GET /me/requests?role=incoming|outgoing` (role required → 400; paged; `updated_at` desc), `GET /requests/{id}` (the two people only → else 403; other campus → 404), `POST /requests/{id}/accept|decline|complete|cancel` (200 + Request; 403 wrong person; 409 `wrong_status`). Accept → listing `pending` and every other pending request on it `declined`; complete (either side) → listing `completed`, `completed_at` set, owner's `items_shared` +1; cancel of an accepted request → listing back to `active`. Each action is one transaction with the listing row locked (`FOR UPDATE`); two simultaneous accepts on one listing: one 200, one 409 (tested).
- Done: `request_out`/`requests_out` in serializers.py (batched, `unread_messages` per viewer from the read markers); `backend/app/events.py` has no-op hooks (`on_request_created/accepted/declined(auto)/completed/cancelled`) called inside each transaction, for S-23 notifications and S-22 badges. `GET /me/unread` `incoming_requests` already counted pending requests on my listings (now smoke-tested). smoke.sh now 288 checks, all pass (3 runs in a row), incl. the pending/completed listing paths S-11 couldn't test.
- Now: S-13.
- Heads-up: no notifications are written yet (S-23), so `GET /me/unread` `notifications` stays 0.

### 2026-10-17 — S-10 done: scan live
- Done: S-10. Live: `POST /scan` (multipart `photos` 1-3, `kinds` one per photo from front/back/label/other, optional `labels`). Validates every upload first, saves and commits the photos, then asks the AI: vision model on the photos (downscaled to 1024 px) → if that fails and `labels` were sent, text model on the labels → else all-null draft with `source: "none"`. Hard 20 s overall deadline. Replies are fence-stripped, parsed and validated (unknown enums → null, tags lowercase list, lengths capped to the POST /listings limits so a draft always posts). Code in `backend/app/ai.py` (replaces `genai_probe.py`; also has `vision_chat`/`text_chat` for "Style it").
- Measured: real photos (t-shirt, 2 hoodies, jeans) all came back `vision` with sensible title/category/color/tags; end-to-end from a Mac 3.0-3.6 s for 1 photo, 4.3 s for 3 photos. Labels fallback ~5 s. Size is usually null unless a label photo shows it.
- Done: smoke.sh now 193 checks, all pass. Fallback (`labels`), both-fail (`none`) and deadline (`none` after the timeout) verified on dev ports with bogus model IDs / a 1 s timeout.
- Contract: `kinds` values clarified as front/back/label/other (not avatar). No iOS change if it sends front,back,label.
- Now: S-12.

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
