# Plan

This is the shared task board for the two machines. Each phase lists what the iOS lane and the server lane do at the same time. The two lanes meet at the sync points between phases.

How to use it:

- Edit only your own lane's lines. iOS tasks start with `I-`, server tasks with `S-`. Keeping to your own lines lets git merge both lanes' changes without conflicts.
- Status marks: `[ ]` not started, `[~]` in progress, `[x]` done, `[!]` blocked. When you mark something `[!]`, explain why in your coord file.
- Don't renumber tasks. If you add one, give it the next free number in your lane and put it in the right phase.
- `/handoff` updates these marks for you.

Feature details are in `docs/FEATURES.md`. Endpoint details are in `docs/API.md`.

## Phase 0: Setup

Both lanes work in parallel. Neither needs anything from the other yet.

### iOS lane
- [ ] I-1 Create the Xcode project in `ios/` (SwiftUI, iOS 17, bundle id `com.stacked.loop`). Use folder-synced groups so new files don't churn `project.pbxproj`.
- [ ] I-2 Set up folders: `Config/`, `Models/`, `Networking/`, `Mocks/`, `Features/<Screen>/`, `DesignSystem/`.
- [ ] I-3 `APIConfig.swift` with the base URL and a `useMocks` switch. Add the ATS exception from `docs/ARCHITECTURE.md`.
- [ ] I-4 Codable models that match every object in `docs/API.md`.
- [ ] I-5 Mock JSON for every endpoint, copied from the examples in `docs/API.md`, and an `APIClient` that serves them when `useMocks` is on.
- [ ] I-6 Design tokens in `DesignSystem/`: colors, type scale, spacing, corner radii, the share-type badges.

### Server lane
- [x] S-1 Confirm the OCI stack is deployed and you can SSH in. Clone this repo to `~/loop` on the server.
- [x] S-2 Open port 8000 in the VCN security list and in `firewalld`.
- [x] S-3 In the Generative AI Playground, check whether `cohere.command-a-vision` is available. Write the answer in `coord/server.md` because it decides the scan path.
- [ ] S-4 FastAPI skeleton in `backend/` with `GET /health`, `.env.example`, `requirements.txt`, and a venv on the server.
- [ ] S-5 SSH tunnel to MySQL from your Mac, and the schema from `docs/ARCHITECTURE.md` created as a migration script.
- [ ] S-6 Run the API on the server under systemd (`loop-api` service) so it survives you closing the laptop.

**Sync point A:** the iOS app, with mocks off, calls `GET /health` on the real server from a simulator and gets `{"status":"ok"}`. Both lanes note it in their coord file.

## Phase 1: Freeze the contract

Short, about 30 minutes. Both lanes read `docs/API.md` start to finish.

### iOS lane
- [ ] I-7 Read `docs/API.md` against the screens you're about to build. Put every missing field or awkward shape in `coord/ios.md` as a request.

### Server lane
- [ ] S-7 Answer every iOS request, update `docs/API.md`, and write "Contract v1 frozen" under "Contract changes" in `coord/server.md`.

**Sync point B:** contract v1 is frozen. After this, changes go through the request process in `CLAUDE.md`.

## Phase 2: Tier 1, built in parallel

The iOS lane builds against mocks, and the server lane builds the real endpoints. Neither waits on the other.

### iOS lane
- [ ] I-8 Sign-in with .edu email, then profile setup (name, photo, class year, dorm, sizes).
- [ ] I-9 Scan: camera with three guided shots (front, back, label) and upload from photo library.
- [ ] I-10 Review listing: show the AI-filled draft, every field editable, share type, meetup spot, post.
- [ ] I-11 Feed: two-column grid, share-type filter chips, category and size filters, search, pull to refresh.
- [ ] I-12 Item detail: photo carousel, tag chips, owner card, Request button.
- [ ] I-13 Requests: send, accept, decline, and an inbox split into Incoming and Outgoing.
- [ ] I-14 Chat inside an accepted request, polling for new messages every 3 seconds.
- [ ] I-15 Profile: my listings with Active and Completed tabs, edit, delete, mark exchanged.
- [ ] I-16 Tab bar with the raised scan button, plus empty and error states for every list.

### Server lane
- [ ] S-8 Auth: `POST /auth/login` with the .edu check, campus from the email domain, bearer tokens. `GET /me` and `PATCH /me`.
- [ ] S-9 Photos: `POST /photos`, saved to disk and served from `/media`.
- [ ] S-10 Scan: `POST /scan` calls the vision model and returns a validated draft. Include the fallback path and a timeout.
- [ ] S-11 Listings: create, read, update, delete, plus the feed with filters, search, and paging.
- [ ] S-12 Requests: create, accept, decline, complete, cancel. Accepting one request declines the others on that listing.
- [ ] S-13 Messages: list after an ID, send.
- [ ] S-14 Meetup spots per campus.
- [ ] S-15 Seed script with 30 to 40 listings using real photos of the team's clothes, plus three demo accounts.

**Sync point C, integration:** the iOS lane turns mocks off. Both lanes walk the demo path in `docs/FEATURES.md` on a real phone. Each lane logs what broke on its side as tasks below.

### Integration fixes
- [ ] I-17 Fix whatever the iOS side of the integration run turns up.
- [ ] S-16 Fix whatever the server side of the integration run turns up.

## Phase 3: Tier 2, in parallel pairs

Each feature has an iOS half and a server half. The server lane ships the endpoint first, and the iOS lane builds against mocks until it lands.

### iOS lane
- [ ] I-18 Impact screen: personal totals and campus totals, plus the impact banner on the feed.
- [ ] I-19 Saved: heart on cards and detail, and a Saved tab.
- [ ] I-20 Similar items row on item detail.
- [ ] I-21 "Style it" sheet on item detail.
- [ ] I-22 Dorm leaderboard.
- [ ] I-23 Badges on the profile.
- [ ] I-24 Notifications: bell with an unread count, and a notifications list.
- [ ] I-25 Report button on item detail.

### Server lane
- [ ] S-17 Impact lookup table with a cited source, plus `GET /impact/me` and `GET /impact/campus`.
- [ ] S-18 Saves: save, unsave, list.
- [ ] S-19 Similar items by tag overlap.
- [ ] S-20 `POST /listings/{id}/style` using the text model, cached per listing.
- [ ] S-21 Dorm leaderboard.
- [ ] S-22 Badge rules and `GET /me/badges`.
- [ ] S-23 Notifications written on request and message events, plus list and mark-read.
- [ ] S-24 Reports, with listings auto-hidden after three reports.

## Phase 4: Polish and demo

### iOS lane
- [ ] I-26 App icon, launch screen, and a pass for spacing, animation, and loading states.
- [ ] I-27 Install on two phones logged in as two demo accounts.

### Server lane
- [ ] S-25 Reseed with the best photos, and reset script so the demo starts from a clean state.
- [ ] S-26 Back up the database and record a screen capture of the full demo in case the network fails.

**Final sync:** both lanes rehearse the demo path twice, start to finish, on the real server.

## Tier 3 (only if Phase 4 is done early)

- [ ] I-28 Campus map of donation bins and meetup spots.
- [ ] I-29 Swap Day events tab.
- [ ] I-30 Onboarding carousel that explains the mission.
- [ ] S-27 Events endpoint and seed data.
- [ ] S-28 Condition explanation from the vision model ("light fading at the cuffs").
