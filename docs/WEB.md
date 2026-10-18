# Web portal

The web version of Loop, the way Depop has both an app and a website. It's a second client on the same backend: every screen below uses endpoints that already exist in `docs/API.md`, so the backend needs no changes.

One person builds it, on its own machine. That person only edits `web/` and this file, so nothing conflicts with the `ios` and `server` lanes. Commit messages start with `web:`, like `web: feed filters (W-6)`. The commit rules in `CLAUDE.md` still apply (no Claude credit lines).

Read these first: this file, then `docs/API.md` (the contract, the source of truth for every field), then `docs/FEATURES.md` (what each feature does and why).

## Stack

- Vite + React + TypeScript, React Router for the routes below. The design system comes from the designer; use its tokens and components, and don't add a UI library on top.
- Build output goes to `web/dist`. Hosted on Vercel, deployed automatically from `main` (see "Deploys").
- No other dependencies unless a screen really needs one. Native `fetch`, native `<input type="file">`, canvas for resizing photos.

```
web/
  index.html
  vite.config.ts      dev proxy for /api
  vercel.json         prod proxy for /api + SPA fallback
  src/
    api/              one function per endpoint, types matching docs/API.md
    routes/           one folder per screen below
    components/       shared pieces (ListingCard, ShareBadge, Avatar, ...)
```

## Brand rules

These come from the iOS app, so the two match:

- Loop Lime `#C7E75A` is an accent, not a theme. Use it only on the main action (Post / Scan button), the "Just posted" tag, the completion checkmark, and "You"/"Yours" labels. Put near-black text on top of it, never white.
- Ink `#191919` for text and the logo. The logo is the approved "Loop" artwork with the two o's drawn as one infinity shape, rendered as an inline SVG (`web/src/components/Logo.tsx`, outline in `web/src/assets/logo-path.ts`, flat ink, no outline or gradient). It is derived from the iOS lane's traced outline (`ios/Tools/loop-logo.json`); if that artwork changes, regenerate the path. The earlier type-only "loop." wordmark is retired.
- Share types (Swap, Free, Donate) always show as badges with the same colors as the app.

## Talking to the API

The API is `http://163.192.218.131:8000`, plain HTTP. A Vercel site is HTTPS, and browsers block an HTTPS page from calling an HTTP server. So the browser never calls the server directly. It calls `/api/...` on our own site, and the dev server (locally) or Vercel (in production) forwards it.

`web/vite.config.ts`:

```ts
server: {
  proxy: {
    '/api': {
      target: 'http://163.192.218.131:8000',
      changeOrigin: true,
      rewrite: (p) => p.replace(/^\/api/, ''),
    },
  },
},
```

`web/vercel.json`:

```json
{
  "rewrites": [
    { "source": "/api/:path*", "destination": "http://163.192.218.131:8000/:path*" },
    { "source": "/(.*)", "destination": "/index.html" }
  ]
}
```

The second rule sends every page route to the React app, so a refresh on `/item/42` works.

Photo URLs come back from the API as absolute `http://163.192.218.131:8000/media/...` URLs, which the browser would also block. Pass every `url`, `photo_url`, and `avatar_url` through one helper before putting it in an `<img>`:

```ts
export const media = (u: string | null) => u && u.replace(/^https?:\/\/[^/]+\/media\//, '/api/media/')
```

First thing to check on the first Vercel deploy: that `POST /scan` (takes 3 to 5 seconds, up to 20) and photo uploads go through the proxy. If Vercel times them out or refuses the HTTP destination, the fix is real HTTPS on the server (Caddy + sslip.io, option 2 in "HTTPS and iOS" in `docs/ARCHITECTURE.md`). That's a server-lane job (see "Requests to the server lane"). Then point both proxies at the HTTPS address and drop the `media` helper.

### Rules from the contract

- Auth: `POST /auth/login` with `{ "email": "..." }` returns `token`. Keep it in `localStorage` and send `Authorization: Bearer <token>` on every call except `/health` and `/auth/login`. Any `401` means drop the token and go to `/signin`. Tokens never expire; signing out just forgets the token.
- Errors are always `{ "error": { "code", "message" } }`. Show `message` as is; branch on `code`, never on status alone.
- Paged lists (`/listings`, `/me/listings`, `/me/requests`, `/me/saved`, `/notifications`) return `{ items, total, next_offset }`. Load more with `offset=next_offset` until it's `null`.
- Timestamps are UTC ISO 8601. Show them in the browser's time zone, relative when recent ("2h ago").
- Everything is scoped to the signed-in user's campus by the server. Another campus's listing is `404`, so a shared `/item/42` link only works for classmates. Show a friendly "not found" page.
- `GET /requests/{id}/messages` marks messages read. Only call it when the chat is actually open.

### Photo uploads

The server takes JPEG only, 5 MB max per file, and the iOS app resizes before upload. Do the same in the browser, so any photo a user picks works:

1. `<input type="file" accept="image/*">` plus drag-and-drop and paste. On a phone browser, `accept="image/*" capture="environment"` opens the camera.
2. Draw each file onto a canvas with the longest side at most 1600 px, then `canvas.toBlob(cb, 'image/jpeg', 0.85)`. That turns PNG, WebP, and big camera files into small JPEGs.
3. If the browser can't decode a file (HEIC on desktop Chrome), show "Couldn't read that photo. Try a JPEG or PNG." Don't send it.
4. Send the blob as `multipart/form-data`, named like `photo.jpg`.

## Routes

Signed-out users can only see `/`, `/signin`, and the 404 page; everything else redirects to `/signin` and comes back after login.

| Route | Screen | Tier |
| --- | --- | --- |
| `/` | Landing (signed out) or redirect to `/feed` (signed in) | 1 |
| `/signin` | Sign in | 1 |
| `/welcome` | Profile setup, after first login | 1 |
| `/feed` | Campus feed. Filters live in the URL: `?q=&share_type=&category=&size=` | 1 |
| `/item/:id` | Item detail | 1 |
| `/post` | Post an item: upload photos, AI fills the form, review, post | 1 |
| `/item/:id/edit` | Edit my listing | 1 |
| `/inbox` | Requests list. `?role=incoming` (default) or `?role=outgoing` | 1 |
| `/inbox/:requestId` | Requests list with that request's chat open beside it | 1 |
| `/profile` | My profile and listings. `?tab=active` (default) or `?tab=completed` | 1 |
| `/profile/edit` | Edit profile | 1 |
| `/saved` | Saved items | 2 |
| `/notifications` | All notifications (the bell dropdown shows the latest few) | 2 |
| `/impact` | My impact and campus impact | 2 |
| `/leaderboard` | Dorm leaderboard, big enough to put on a projector | 2 |
| `/events` | Swap Day and other campus events | 3 |
| `/map` | Meetup spots and donation bins on a map | 3 |
| `*` | Not found | 1 |

## Layout

Every signed-in page shares one top bar:

- Left: "loop." wordmark (links to `/feed`) and the campus name from `user.campus.name`.
- Middle: search box. Typing and pressing Enter goes to `/feed?q=...`.
- Right: Post button (Loop Lime, goes to `/post`), Inbox icon with a badge of `messages + incoming_requests`, bell with a badge of `notifications`, avatar menu (Profile, Saved, Impact, Leaderboard, Sign out).
- Badge counts come from `GET /me/unread`. Call it on every route change and every 15 seconds while the tab is visible.

Pages are responsive. Under about 768 px wide, the top bar collapses to the wordmark, search icon, and a menu, and two-pane screens show one pane at a time. The web version is also how Android students use Loop, so mobile web has to work.

## Screens

Each screen lists what it shows, the endpoints it calls, and the states it needs. Every list needs a loading state, an empty state, and an error state with a retry.

### Landing `/` (signed out)

Hero with the mission: keep clothes out of landfills, make clothes cheaper for students, swap on your own campus. A "Sign in with your .edu" button to `/signin`. A short how-it-works strip: snap it, AI writes the listing, a classmate picks it up. Static; no API calls.

### Sign in `/signin`

- One email field and a Continue button. `POST /auth/login`.
- `not_edu_email` shows its message under the field.
- On success, save the token. `is_new: true` goes to `/welcome`, otherwise to `/feed` (or the page they were sent from).
- Below the form, in development builds only: three buttons that sign in as the demo accounts (see "Demo accounts").

### Profile setup `/welcome` and Edit profile `/profile/edit`

Same form, two routes. `/welcome` says "Set up your profile" and goes to `/feed` when saved; `/profile/edit` goes back to `/profile`.

- Avatar: pick a photo, resize it, `POST /photos` with `kind=avatar`, then send its `id` as `avatar_photo_id`.
- Name (required, 1 to 80), class year (four-digit), dorm, sizes (top, bottom, shoe).
- Dorm is a select from `GET /dorms`. If the list is empty, show a text field instead.
- Save: `PATCH /me` with only the fields that changed. `sizes` must be sent as the whole object.

### Feed `/feed`

- Campus impact banner at the top: `GET /impact/campus`. "86 items rehomed this week · 61.5 kg of textile · 194,000 L of water". Links to `/impact`. Hide it if `items_rehomed` is 0.
- Filters sidebar (a drawer on mobile): share type (All, Swap, Free, Donate), category (the 7 enum values), size (the size vocabulary in `docs/API.md` for the chosen category). Every change updates the URL query and refetches.
- Grid of listing cards, 4 to 5 columns on desktop, 2 on mobile: `GET /listings` with the filters and `q`. Load more at the bottom with `next_offset`.
- Card: `photos[0]`, title, size, share-type badge, heart (save toggle, Tier 2). Your own listings show a "Yours" tag. A listing you just posted shows a Loop Lime "Just posted" tag for a few seconds.
- Empty search: "Nothing matches yet" with a button to clear filters.

### Item detail `/item/:id`

- `GET /listings/{id}`. `404` shows the not-found page.
- Left: photo gallery (big main photo, thumbnails, arrow keys move between photos). Right: title, share-type badge, size, condition, `condition_note`, brand, color, description, tags as chips, meetup spot, and this item's impact ("keeps 0.44 kg of textile out of landfill").
- Owner card: avatar, name ("Loop member" if `null`), dorm, "N items shared".
- Main action, based on the listing:
  - `is_mine`: Edit (to `/item/:id/edit`), Delete (confirm, then `DELETE /listings/{id}`, back to `/profile`). Completed listings can't be edited or deleted.
  - `my_request_status` is `pending`: a disabled "Requested" button, plus Cancel request (`POST /requests/{my_request_id}/cancel`).
  - `my_request_status` is `accepted`: "Open chat", to `/inbox/{my_request_id}`.
  - `status` isn't `active`: "No longer available".
  - Otherwise: Request. Opens a dialog with an optional note (280 characters max), then `POST /listings/{id}/requests`. `already_requested` shows "Requested"; `listing_unavailable` shows its message.
- Tier 2 on this page:
  - Heart: `PUT` / `DELETE /listings/{id}/save`, using `saved_by_me` for the starting state.
  - Style it: a button that opens a dialog with `POST /listings/{id}/style` ideas (title + description cards).
  - Similar items: a row of cards from `GET /listings/{id}/similar`. Hide the row if it's empty.
  - Report: in a "..." menu, a dialog with an optional reason, `POST /listings/{id}/report`. Then "Thanks, we'll take a look." Hidden for your own listing.

### Post an item `/post`

The web version of Scan. One page in three steps.

1. **Photos.** A big drop zone: drag, paste, or click to pick up to 3 photos. Each one gets a label you can change: Front, Back, Label (defaults by order). Thumbnails can be reordered and removed. "Continue" sends them to `POST /scan` (`photos` files in order, `kinds` like `front,back,label`; no `labels` field, that's iOS-only).
2. **Reading your item.** A loading state while the AI works (3 to 5 seconds normally, up to 20). Make it feel alive: the photos with a scanning shimmer and "Reading the label...".
3. **Review.** The form, prefilled from `draft`: title, category, size, color, brand, condition, condition note, description, tags (editable chips, up to 10). Plus share type (Swap, Free, Donate) and meetup spot (select from `GET /meetup-spots`).
   - `source` is `vision`: a small "Filled in by AI, check it over" note, with the AI-filled fields subtly marked.
   - `source` is `none`: "We couldn't read this one. Fill it in below." and an empty form. Not an error.
   - Optional extra photos, up to 5 in total: each one goes through `POST /photos` with `kind=other`.
   - Post: `POST /listings` with every field plus `photo_ids` (the scan's photo IDs, then any extras). Required: title, category, condition, share type, meetup spot. On `201`, go to `/feed` with the new card at the top showing "Just posted".

Limits to enforce in the form (the server checks them too): title 1 to 120, size 20, color 60, brand 80, condition note 140, description 2000, up to 10 tags of up to 30 characters.

### Edit listing `/item/:id/edit`

The review form from `/post`, filled from `GET /listings/{id}`. Photos can be removed, reordered, or added (`POST /photos`, `kind=other`). Save: `PATCH /listings/{id}` with the changed fields (`photo_ids` replaces the whole list, in order). Owner only; anyone else gets sent back to the item.

### Inbox `/inbox` and `/inbox/:requestId`

Two panes on desktop, the main place the website beats the phone.

- **Left: request list.** Tabs Incoming / Outgoing: `GET /me/requests?role=incoming|outgoing`. Each row: the listing photo and title, the other person's name and avatar, the status, the note's first line, the time, and an unread dot with `unread_messages`. Incoming `pending` rows sit at the top with a "New request" tag.
- **Right: the open request.** `GET /requests/{id}` for the header (listing summary linking to `/item/:id`, the other person, status). Then, by status and side (compare `owner.id` and `requester.id` with your user ID):
  - Owner, `pending`: the note, Accept and Decline buttons (`POST /requests/{id}/accept` or `/decline`). Accepting one declines the others, so refetch the list.
  - Requester, `pending`: "Waiting for {name}" and Cancel request.
  - `accepted`: the chat. `GET /requests/{id}/messages` on open, then every 3 seconds with `after_id` set to the last message ID, plus `GET /requests/{id}` with each poll to notice the other person completing or cancelling. Composer at the bottom (1 to 1000 characters, Enter sends, Shift+Enter for a new line): `POST /requests/{id}/messages`. Buttons: "Mark exchanged" (`POST /requests/{id}/complete`) and, for the requester, Cancel.
  - `completed`: a celebration panel: Loop Lime checkmark, the item's impact counting up from zero, and any badge just earned (check `GET /me/badges` for an `earned_at` in the last minute). Then the chat history, read-only.
  - `declined` / `cancelled`: a short line saying so; history read-only.
- Stop polling when the chat closes or the browser tab is hidden.
- Mobile: the list is the page, and opening a request replaces it, with a back arrow.

### My profile `/profile`

- Header: avatar, name, dorm, class year, campus, "N items shared", Edit profile button.
- Impact summary (Tier 2): `GET /impact/me`, three numbers (textile kg, water L, CO₂ kg), links to `/impact`.
- Badges (Tier 2): `GET /me/badges`. Earned ones in color with the date; the rest grayed out with "3 of 5" from `progress` / `goal`.
- Listings, tabs Active / Completed: `GET /me/listings?status=active|completed`, as a grid of cards. On Active:
  - `pending_request_count > 0`: a "2 requests" tag linking to `/inbox?role=incoming`.
  - `status` is `pending` with an `accepted_request_id`: "Mark exchanged" (`POST /requests/{accepted_request_id}/complete`) and "Open chat".
  - `status` is `hidden`: a "Hidden after reports" tag. The owner can still edit or delete it.

### Saved `/saved` (Tier 2)

Grid of cards from `GET /me/saved`, with load more. Unsaving removes the card. Empty state: "Tap the heart on anything you like."

### Notifications (Tier 2)

- Bell dropdown: `GET /notifications?limit=8`, a "Mark all read" link (`POST /notifications/read` with `{"all": true}`), and "See all" to `/notifications`.
- `/notifications`: the full paged list.
- Clicking one marks it read (`{"ids": [id]}`) and goes to `/inbox/{request_id}` for request and message types, or `/profile` for `badge_earned`.

### Impact `/impact` (Tier 2)

- Mine: `GET /impact/me`. Big numbers for textile, water, and CO₂, plus items shared and received. Turn them into something people can feel ("about 31 showers") only if the comparison is sourced; otherwise just the numbers.
- Campus this week: `GET /impact/campus`, with the top dorm.
- A "Where these numbers come from" note citing the two sources in `docs/API.md`. Judges ask.

### Leaderboard `/leaderboard` (Tier 2)

`GET /leaderboard/dorms`. Ranked dorms with items shared this week, ties share a rank. Highlight the signed-in user's dorm with a "You" label. Design it to look good full screen on a projector: big type, the top three standing out. Empty: "No exchanges this week yet."

### Events `/events` (Tier 3)

`GET /events`. Cards grouped as Happening now (`is_live`), Upcoming, and Recently ended. Each shows the kind, title, description, time in the local time zone, and location.

### Map `/map` (Tier 3)

Meetup spots with coordinates from `GET /meetup-spots` and every bin from `GET /donation-bins` (name, what it accepts, hours) as two kinds of pins. Needs a map library; Leaflet with OpenStreetMap tiles needs no API key. Skip it if time is short.

### Not found `*`

Also used for any `404` from the API. "This one's not here. It may have been swapped already." with a link back to the feed.

## Build order

Work top to bottom. Tier 1 has to work end to end before Tier 2. Mark tasks here as you go: `[ ]` not started, `[~]` in progress, `[x]` done.

- [x] W-1 Vite + React + TS project in `web/`, design system tokens and fonts in, `vite.config.ts` proxy, React Router with every route as a placeholder.
- [x] W-2 API client: token handling, 401 → sign in, error shape, paging, the `media` helper, types for every object in `docs/API.md`.
- [x] W-3 Top bar and layout, responsive, unread badges from `/me/unread`.
- [x] W-4 Landing, sign in, profile setup.
- [x] W-5 Vercel project connected; first production deploy; check `/scan` and uploads through the proxy.
- [x] W-6 Feed: grid, filters in the URL, search, load more, impact banner.
- [x] W-7 Item detail with every action state.
- [x] W-8 Post an item: drop zone, resize to JPEG, scan, review form, post.
- [x] W-9 Inbox: two panes, accept/decline/cancel, chat polling, mark exchanged, celebration.
- [x] W-10 Profile with Active/Completed listings, edit listing, edit profile.
- [x] W-11 Run the demo path below on the deployed site.
- [x] W-12 Saved, hearts everywhere.
- [x] W-13 Notifications bell and page.
- [x] W-14 Impact page, badges on the profile.
- [x] W-15 Leaderboard, projector-ready.
- [x] W-16 Style it, similar items, report on item detail.
- [~] W-17 Polish pass: loading skeletons, transitions, mobile widths, keyboard focus, alt text on every photo.
- [x] W-18 Events (Tier 3).
- [x] W-19 Map (Tier 3).

## Demo accounts

All on the Vanderbilt campus. Sign in with the email only; there are no passwords.

- `jordan.park@vanderbilt.edu`: Jordan Park, Kissam. Has pending incoming requests, an accepted swap with Sam, and a completed exchange.
- `sam.lee@vanderbilt.edu`: Sam Lee, Zeppos. Has the chat with Jordan.
- `riley.chen@vanderbilt.edu`: Riley Chen, E. Bronson Ingram.

The server lane can reset this data to the clean demo state at any time (`bash scripts/reseed.sh`), so don't count on things you posted while testing still being there.

## Demo path on the web

What "it works" means for W-11. Use two browser windows, one normal and one private, signed in as two accounts.

1. Window 1 signs in as Jordan and lands on the feed.
2. Jordan clicks Post, drags in three photos of a jacket, and the AI fills in the listing.
3. Jordan fixes one field, picks Swap and a meetup spot, and posts. The jacket is at the top of the feed.
4. Window 2 signs in as Sam, searches for the jacket, opens it, and requests it.
5. Jordan's bell and inbox badge update; Jordan accepts, and the two windows trade chat messages.
6. Jordan marks it exchanged. The celebration plays, and the impact banner and Jordan's profile update.
7. End on `/leaderboard` full screen.

Bonus for the live demo: do step 2 from the laptop and step 4 from the iPhone app. Same backend, so it just works.

## Deploys

Every push to `main` that changes `web/` deploys to production on its own. One-time setup, done in the Vercel dashboard by whoever owns the Vercel account:

1. Add New → Project → import the Loop GitHub repo.
2. Root Directory: `web`. Framework preset: Vite (build `npm run build`, output `dist`).
3. Settings → Git: turn on skipping deployments when nothing in the root directory changed. The iOS and server lanes push to `main` all day, and their commits shouldn't trigger web builds.
4. No environment variables. The API address lives in `vercel.json` and `vite.config.ts`, and nothing secret ships to the browser.

Pull requests get their own preview URL automatically, if you ever work on a branch.

## Rules

- Only edit `web/` and this file. Don't edit `coord/` or `docs/API.md`; those belong to the other lanes. If something is needed from the backend, add it under "Requests to the server lane" below and tell the server-lane person.
- No secrets in `web/`. There aren't any to need: the API has no keys, and login is email only.
- `docs/API.md` is the source of truth. If the server returns something different from the doc, tell the server lane.
- The website never calls OCI or any AI service directly. Every AI feature goes through our backend.

## Status log

### 2026-10-18: first full build (branch `web/portal`, not pushed to `main` yet)
- Done: W-1 to W-4, W-6 to W-10, W-12 to W-16, W-18, W-19. Every route in the table exists. `npm run build` and `npm test` (14 unit tests) pass.
- Checked by hand against the live server through the dev proxy, on a throwaway campus (`webtest.edu`, so the demo data was not touched): sign in, profile setup, drag-and-drop photos, `/scan` (about 6 s, `source: vision`), review form with AI marks, post, "Just posted" tag, request, accept, polling for new messages and the unread badges, chat send, mark exchanged, celebration with count-up and the First Swap badge, profile impact and badges. Read-only on the Vanderbilt demo campus: feed, leaderboard, map pins, mobile feed at 390 px.
- Not done: W-5 (Vercel project and first deploy: needs the account owner), so `/scan` and uploads through Vercel's proxy are still unchecked there. W-11 (demo path on the deployed site) waits on that. W-17 is partly done (skeletons, focus rings, alt text, reduced motion); a pass at tablet widths and the other screens at 390 px is left.
- Run locally: `cd web && npm install && npm run dev` (proxies `/api` to the server).

### 2026-10-18: Vercel project and preview checked (W-5, W-11)
- Vercel project `loop-web` (personal Hobby account, id `prj_DN4PiBQFzEPpvYi3ODenqOoq0y1x`): Vite, root `web`, `npm run build`, output `dist`, Node 24.x (20.x is discontinued on Vercel), skip builds when `web/` is unchanged. `web/vercel.json` is unchanged. Vercel Authentication is on, so the preview needs a Vercel login or a bypass secret.
- **Vercel can proxy to the plain HTTP backend.** Through the preview, `/api/health`, login, `/photos`, `/scan` (5 to 6 s, `source: vision`), `/media`, publish, request, accept, chat, complete, badges and `/style` all worked. No HTTPS change is needed on the server.
- Same flow driven in the browser on the preview with throwaway users on `webtest.edu`: no console errors, every `/api/*` call 200, no horizontal overflow at 390 px on any route.
- **Git link is not set up.** The repo is `eshan06/loop`, but the Vercel GitHub app is installed on the `hwangolise` account only, so the project is not connected to the repo and pushes do not deploy by themselves. To get "every push to `main` deploys": the repo owner installs the Vercel GitHub app on `eshan06/loop`, then connects `loop-web` to it under Settings, Git, and sets the production branch to `main`.
- Deploys made through the API from a Git ref are tagged `production` unless a target is set, so previews were created with `target: staging`. Do not create a deployment from `main` through the API until the link exists.
- Not covered: Vercel build logs (the connection can't read them) and a real iPhone or Android browser.

## Requests to the server lane

None yet.
