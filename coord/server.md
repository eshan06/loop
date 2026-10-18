# Server lane log

Only the server machine (the one with the OCI account) edits this file. The iOS lane reads it after every pull.

Add new log entries at the top of the Log section, newest first. Keep each entry short. `/handoff` writes them for you.

## Server status

- API base URL: `http://163.192.218.131:8000` — LIVE (systemd `loop-api`, restarts itself on crash and on boot). Plain HTTP, so the iOS app needs the ATS exception (Allow Arbitrary Loads). `GET /health` → `{"status":"ok"}`.
- Vision model (`cohere.command-a-vision`) available on our account: YES, tested 2026-10-17 from the OCI server, ~1-2s per call (1 or 2 JPEGs) → main scan path. `POST /scan` live: ~3-4.5 s end to end (1-3 photos). `labels` is only needed for the fallback.
- Demo accounts: SEEDED (S-15) on campus Vanderbilt (`vanderbilt.edu`): `jordan.park@vanderbilt.edu` (Jordan Park, Kissam), `sam.lee@vanderbilt.edu` (Sam Lee, Zeppos), `riley.chen@vanderbilt.edu` (Riley Chen, E. Bronson Ingram). Log in with the email only. Plus 8 more students, 39 listings, requests and chats. Reset to the clean demo state anytime: `bash scripts/reseed.sh` (keeps these three accounts' ids and sessions). Demo pairing (S-25): Jordan = Phone 1, Sam = Phone 2 (see "Before the demo").
- Seed photos: PLACEHOLDERS (Wikimedia Commons) until the team adds its own; how to swap them: `backend/seed/photos/README.md`.

Keep this block current. It's the first thing the iOS lane looks at.

## Before the demo

1. Within the last few hours before going on stage (and after every rehearsal): `bash scripts/reseed.sh` from the Mac. It reseeds Vanderbilt, deletes the smoke test's data (smoke.edu, smokeother.edu) and orphan uploads, prints a summary, and must end with `check ok`. `bash scripts/reseed.sh --check` changes nothing and tells you whether the demo campus is still clean (it fails after a rehearsal, or if the seed is over 24 h old: the leaderboard tie and the "live" event drift).
2. Phones stay logged in across a reseed. Phone 1 signs in as **Jordan** (`jordan.park@vanderbilt.edu`, Kissam), Phone 2 as **Sam** (`sam.lee@vanderbilt.edu`, Zeppos). Pull to refresh after a reseed.
3. What each step of the demo path (docs/FEATURES.md) should show:
   1. Phone 1 lands on the feed: 27 active listings, 6 of them Jordan's; bell shows 3 unread (Riley and Ethan want his Converse, Marcus sent a message); banner "10 items rehomed this week, top dorm E. Bronson Ingram". Jordan's profile: no badges yet, Closet Cleanout 9/10, impact 0.
   2. Scan the real jacket (front, back, label): the AI fills the listing in a few seconds.
   3. Fix a field, pick Swap and a meetup spot, post: the jacket is first in the feed, and Jordan earns **Closet Cleanout** (10th listing; badge notification).
   4. Phone 2 searches "jacket": the new jacket is on top (only 2 seed listings match: the puffer and the Levi's trucker jacket). Open it, request it.
   5. Phone 1 gets "Sam requested your item", accepts; they chat. Jordan and Sam have no other request or chat with each other.
   6. Phone 1 marks it done: Jordan and Sam both earn **First Swap**. Jordan's impact goes 0 -> 1 item shared (as outerwear: 0.44 kg textiles, 3,135 L water, 10.3 kg CO2e). Campus banner: 10 -> 11 items rehomed, top dorm E. Bronson Ingram -> **Kissam**.
   7. Leaderboard: before, E. Bronson Ingram 2 and Kissam 2 tied at #1; after, **Kissam 3 alone at #1** (the owner's dorm gets the credit). Profile shows the two new badges.
4. Don't rehearse on the demo accounts after the last reseed, and don't report demo listings (3 reporters hide one).

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
- 2026-10-17 (S-23): clarification, no shape change. Notifications: `GET /notifications` orders by `created_at` then `id`, newest first; `POST /notifications/read` with neither `ids` nor `all: true` (or no body) is `400 bad_request`, `{"ids": []}` is a no-op 204. New_message notifications collapse (one unread per request per person: same `id`, title "Sam sent you 3 messages", newest text in `body`, `created_at` bumped); opening a chat or replying marks your new_message notifications for it read; accept/decline marks the owner's request_received for it read. Titles use first names; `body` is the listing title (new_message: a 140-char message preview). iOS: nothing required; refresh `/me/unread` after leaving a chat so the bell drops.

- 2026-10-17 (S-22): clarification, no shape change. `GET /me/badges`: badges are checked on listing create and on exchange complete (both sides); an earned badge stays earned with `progress == goal`; each new badge writes one `badge_earned` notification (title "You earned <name>", body the description, both IDs `null`). iOS: nothing to do.

- 2026-10-17 (S-24): clarification, no shape change. `POST /listings/{id}/report`: body `{}` or missing is fine; non-string or >200-char `reason` is `400 bad_request`; not visible (other campus, deleted, someone else's hidden) is `404 not_found`; a repeat report is a 204 that counts once. The 3rd distinct reporter hides an `active` or `pending` listing (a `completed` one stays visible). Open requests on a hidden listing are left as they are (owner can't accept: `wrong_status`; can decline; requester can cancel; an accepted exchange can still chat and complete). No owner notification. iOS: nothing to do.

- 2026-10-17 (S-28, IOS-3): additive. New nullable `condition_note` string (<= 140 chars, no trailing period, e.g. "light fading at the cuffs") on `ScanDraft` and `Listing` (key always present, `null` when absent). `POST /listings` and `PATCH /listings/{id}` accept it optionally: trimmed, empty or blank -> `null`, over 140 or not a string -> `400 bad_request`. The draft's note only comes from the vision path (`null` for `source` `labels`/`none` and whenever `condition` is `new`). iOS: decode `condition_note: String?`, show it near the condition, and send the draft's note back in POST /listings (editable).

- 2026-10-17 (S-27): additive, new. `GET /events` (Swap Day tab, I-29): `{"items": [Event]}` for my campus, sorted by `starts_at` (ties `id`); by default only events that haven't ended or ended in the last 24 h, `?include_past=true` for all (other values -> `400 bad_request`). Event = `id, title, description?, kind (swap_day|donation_drive|repair_workshop), status (upcoming|live|ended), is_live, starts_at, ends_at, location_name, lat?, lng?`. `GET /donation-bins` (campus map, I-28): `{"items": [DonationBin]}` sorted by name; DonationBin = `id, name, description?, accepts?, hours?, lat, lng` (coords never null). The MeetupSpot object (`GET /meetup-spots` and `Listing.meetup_spot`) gains nullable `lat`/`lng` (both set or both null; null on a new campus's default spots, set on every Vanderbilt spot). New enums `event.kind`, `event.status`. iOS: you can build I-28 and I-29 against these now; add mocks `events.json` and `donation_bins.json` matching the docs/API.md examples, and add `lat`/`lng` to `meetup_spots.json` (and the `meetup_spot` objects in `listings.json`) so Mock mode shows pins.

## Open requests to the iOS lane

Give each request an ID (`SRV-1`, `SRV-2`, ...). Move it to "Closed requests" once the iOS lane answers in `coord/ios.md`.

None yet.

## Closed requests

None yet.

## Log

### 2026-10-17 — Cross-lane iOS edit: TestFlight build uses the live server (server lane, approved by the user)

- Done: the user asked the server lane to make this one iOS change, since the TestFlight build was stuck on mock data (placeholder art, no Mock/Live switch in Release). `APIConfig.defaultUseMocks` is now `true` in DEBUG and `false` in Release. Build number bumped to 2 (`project.yml` and `project.pbxproj`), and `Info.plist` now reads `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` instead of literal `1.0` / `1`, so bumping the build setting changes the uploaded build.
- Not verified: not built (no Xcode on this Mac; `swiftc -parse` passes). Debug builds and the tests are unchanged.
- iOS lane: pull, build Release, archive build 1.0 (2), upload to TestFlight. Phones sign in again after updating (the live server never saw a sign-in from the mock build).
- Also done: deployed 9ff2fa2 and reseeded; `check ok`.

### 2026-10-17 — S-26 closed, server lane complete
- Done: S-26. The database backup was skipped on purpose: `bash scripts/reseed.sh` rebuilds the demo campus in seconds, which is enough for a hackathon. Recording the backup screen capture is up to the team.
- Now: every server task through Tier 3 is done except S-16, which waits for the two-phone integration run (Sync point C). Send server bugs from that run as requests and I'll fix them under S-16.

### 2026-10-17 — S-25 done: one-command demo reset, seed tuned for the demo story (server lane)
- Done: S-25 (placeholder photos until the team's real photos are added). `bash scripts/reseed.sh` is the one pre-demo command: reseed + delete smoke.edu/smokeother.edu + orphan uploads + summary + live check; `--check` is read-only. Seed tuned so the live demo shows wins: Jordan (Phone 1) earns Closet Cleanout on posting and First Swap on completing, Sam (Phone 2) earns First Swap, Kissam goes from tied #1 to clear #1 and takes the banner's top dorm. Steps in "Before the demo" above; photo swap steps in `backend/seed/photos/README.md`.
- Heads-up: demo seed changed. Jordan no longer has First Swap or a chat with Sam (his accepted chat is now with Marcus on the quarter-zip); Sam's only outgoing request is Riley's skirt; Jordan owns the scarf and camo hoodie too. Smoke now 788 checks.
- Now: S-26 (DB backup + screen capture), S-16 as the integration run turns things up.

### 2026-10-17 — S-27 done: events and donation bins live (server lane)

- Done: S-27. Migration `006_events_bins.sql` applied (`events`, `donation_bins`, nullable `lat`/`lng` DECIMAL(9,6) on `meetup_spots`). New router `app/routers/campus_life.py`: `GET /events` (default: not ended or ended < 24 h ago; `include_past=true` for all; `status` + `is_live` computed per request) and `GET /donation-bins`. MeetupSpot serializer now carries `lat`/`lng` everywhere. Smoke 783 checks, passed twice.
- Contract: see "Contract changes" (additive; iOS can build I-28/I-29 now, mocks need the new JSON).
- Heads-up: demo reseeded. Vanderbilt now has 4 events relative to the seed date in Nashville time: Fall Clothing Drive (live, started 3 days ago, runs 11 more days, Commons Center), Fall Swap Day (3 days out, 11am-3pm, Alumni Lawn), Mend It repair workshop (7 days out, 6-8pm, Rand Hall), Kissam Quad Pop-up Swap (ended 2 days ago, only with `include_past=true`). 4 donation bins (Commons Center, Sarratt, Branscomb Quad, Kissam Quad; 2 with `hours: null`) and coordinates on all 7 meetup spots. Event dates are relative to the reseed: rerun `bash scripts/reseed.sh` before the demo so Swap Day is still upcoming. Other campuses have no events/bins (empty lists).
- Now: S-25 / S-16 when picked.

### 2026-10-17 — S-28 done: condition notes live, answers IOS-3 (server lane)

- Done: S-28. IOS-3 is live now: `condition_note` (nullable string, max 140) on `ScanDraft` and `Listing`, accepted by `POST /listings` and `PATCH /listings/{id}` (trimmed, blank -> `null`, > 140 -> 400). Migration `005_condition_note.sql` (`listings.condition_note VARCHAR(140) NULL`) applied. The vision prompt asks for ONE honest, specific wear observation ("what and where"), never invented, `null` if it looks new; the server caps it at 140 at a word, strips the trailing period, drops "no visible wear"-style and wrinkle-only replies, and forces `null` when `condition` is `new` or the draft came from labels/none. Real-photo test (Wikimedia Commons, live `/scan`, ~3.5-4 s): pilled sweater "minor pilling throughout", worn Adidas "heavy scuffing and dirt on the uppers and soles", Lowa boots "scuffs and dirt on the toes and sides", worn jeans "fading and distressing throughout, small paint splatters on the left leg", faded polo "light fading throughout"; new backpack, Docs, sundress, fleece, Converse -> `null`.
- Contract: see "Contract changes" (additive; iOS decodes `condition_note: String?` and can post it back).
- Heads-up: demo reseeded: 12 demo listings have a `condition_note` (6 in the active feed: converse, fleece, running, polo, birks, bandtee; none on `new` items). Style-ideas snapshot unaffected (39/39 still current). Smoke 752 checks, passed twice.
- Now: S-25 / S-27 when picked.

### 2026-10-17 — S-24 done: reports live, Phase 3 complete (server lane)

- Done: S-24. **This completes Phase 3 on the server lane** (S-17 to S-24 all live). `POST /listings/{id}/report` (204) in `app/routers/listings.py`: locks the listing row, one report per user (repeat counts once), `own_listing` (409) for your own, `404 not_found` for anything you can't see, `reason` optional (<=200). The 3rd distinct reporter sets an `active` or `pending` listing to `hidden` in the same transaction. First time hiding was possible, so every earlier hidden rule got tested: non-owners get 404 on detail, similar, style, save PUT/DELETE, request create, report; it leaves the feed/search, other users' `/me/saved` and similar rows; the owner still gets detail (status `hidden`) and the `/me/listings` active tab. All were already right, no fixes needed. Smoke 727 checks, passed twice.
- Contract: clarification, no shape change (see Contract changes). Open requests on a hidden listing stay as they are; cancelling an accepted one doesn't unhide it. No notification (no type for it). iOS: nothing required; I-25's report button can go live.
- Heads-up: demo data untouched (smoke never reports demo listings). Don't report a demo listing 3 times from 3 accounts during rehearsal or it hides; `bash scripts/reseed.sh` restores it.
- Now: Phase 4 server tasks (S-16 integration fixes, S-25 reseed/reset).

### 2026-10-17 — S-22 done: badges live

- Done: S-22. **`GET /me/badges` is live** (it was the 404 the iOS lane saw; rerun the live walk): all 3 badges in contract order with `progress`/`goal`/`earned_at`. Rules in `app/badges.py` (one table): First Swap = 1 completed exchange either side, Giving Back = 5 of my `donate` listings completed, Closet Cleanout = 10 listings created incl. deleted ones (new column `users.listings_created`, migration 004, backfilled). `check_badges` runs inside the transaction from `events.on_listing_created` (new hook, POST /listings) and `on_request_completed` (both sides); idempotent, one `badge_earned` notification per new badge. Smoke 674 checks, passed twice.
- Contract: clarification, no shape change (see Contract changes). iOS: nothing required.
- Heads-up: demo reseeded. Jordan has First Swap earned (from Noah taking his jeans, back-dated, its notification already read), Giving Back 0/5, Closet Cleanout 4/10; his unread stays 3. Completing the Jordan-Sam swap in the demo earns no new badge (both already have First Swap; Sam got his from Ava's belt). After a complete, refresh `/me/badges` and `/me/unread` to pick up any new badge.
- Now: next open server task (S-24 reports).

### 2026-10-17 — S-23 done: notifications live

- Done: S-23. `app/notifications.py` writes them: `notify(db, user_id, type, title, body, request_id=None, listing_id=None, at=None)` (no commit; S-22 badges call it with `"badge_earned"` and both IDs None) plus builders `request_received/accepted/declined` and `new_message` (collapses into the recipient's unread one). `app/events.py` hooks call them: created → owner, accept → requester, decline and auto-decline → requester, message → the other person; complete and cancel send none (API.md). `GET /notifications` (paged, `unread` total) and `POST /notifications/read` (`ids` or `all`, 204) in `app/routers/notifications.py`; `/me/unread` notifications already counted unread rows. Smoke 626 checks, passed twice.
- Contract: clarification, no shape change (see Contract changes). iOS: nothing required.
- Heads-up: demo reseeded. Seed writes notifications through the same builders: Jordan has 10, 3 unread (Sam's new message, Riley's and Ethan's requests on his Converse), read ones include Riley accepting his Dr. Martens request; Sam has 1 unread (Ava's request). Opening the Jordan-Sam chat in the app clears that message notification.
- Now: S-22 (badges).

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
