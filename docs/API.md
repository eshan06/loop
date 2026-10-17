# API contract

This is the contract between the iOS app and the backend. The server lane owns this file. The iOS lane requests changes through `coord/ios.md` (see `CLAUDE.md`). Every change gets a line under "Contract changes" in `coord/server.md`.

Version: v1 draft (not frozen yet, see Phase 1 in `PLAN.md`)

## Conventions

- Base URL: the server's address, recorded under "Server status" in `coord/server.md`. Every path below is relative to it.
- Requests and responses are JSON, except photo uploads, which are `multipart/form-data`.
- Field names are `snake_case`. The iOS app decodes with `.convertFromSnakeCase`.
- IDs are integers. Timestamps are ISO 8601 in UTC, like `2026-10-18T15:04:05Z`.
- Authenticated endpoints need `Authorization: Bearer <token>`. Everything except `/health` and `/auth/login` is authenticated.
- Users only ever see listings, people, and stats from their own campus. The server enforces this from the token; the app never sends a campus ID.
- Every value in the examples is made up, including the impact numbers. The real impact figures come from the lookup table described in `docs/ARCHITECTURE.md`.
- Lists are paged with `limit` (default 20, max 50) and `offset` (default 0). Paged responses look like `{"items": [...], "total": 87, "next_offset": 20}`. `next_offset` is `null` on the last page.

Errors always have this shape, with a matching HTTP status:

```json
{ "error": { "code": "not_edu_email", "message": "Use your college .edu email address." } }
```

| Status | `code` values |
| --- | --- |
| 400 | `bad_request`, `not_edu_email`, `too_many_photos`, `photo_too_large` |
| 401 | `unauthorized` |
| 403 | `forbidden` (for example, editing someone else's listing) |
| 404 | `not_found` |
| 409 | `conflict` (for example, requesting your own item or an already-claimed item) |
| 502 | `ai_unavailable` (the AI call failed; the app should fall back) |

`message` is written for users, so the app can show it as is.

## Enums

| Name | Values |
| --- | --- |
| `share_type` | `swap`, `free`, `donate` |
| `condition` | `new`, `like_new`, `good`, `worn` |
| `category` | `tops`, `bottoms`, `outerwear`, `dresses`, `shoes`, `accessories`, `bags` |
| `listing.status` | `active`, `pending`, `completed`, `hidden` |
| `photo.kind` | `front`, `back`, `label`, `other`, `avatar` |
| `request.status` | `pending`, `accepted`, `declined`, `completed`, `cancelled` |
| `notification.type` | `request_received`, `request_accepted`, `request_declined`, `new_message`, `badge_earned` |

A listing becomes `pending` when one of its requests is accepted, and `completed` when that request is completed.

## Objects

### User

```json
{
  "id": 3,
  "name": "Jordan Park",
  "email": "jordan.park@vanderbilt.edu",
  "campus": { "id": 1, "name": "Vanderbilt" },
  "dorm": "Kissam",
  "class_year": 2028,
  "sizes": { "top": "M", "bottom": "30", "shoe": "9" },
  "avatar_url": "https://<server>/media/avatars/3.jpg",
  "items_shared": 4,
  "created_at": "2026-10-18T14:00:00Z"
}
```

Other people appear as an `Owner`, a smaller version without `email`, `sizes`, or `created_at`:

```json
{ "id": 3, "name": "Jordan Park", "dorm": "Kissam", "avatar_url": null, "items_shared": 4 }
```

### Photo

```json
{ "id": 71, "url": "https://<server>/media/71.jpg", "kind": "front" }
```

### Listing

The feed and the detail screen use the same object.

```json
{
  "id": 42,
  "title": "Levi's denim trucker jacket",
  "category": "outerwear",
  "size": "M",
  "color": "Light wash blue",
  "brand": "Levi's",
  "condition": "good",
  "description": "Classic trucker jacket with button front and chest pockets. Light fading at the cuffs.",
  "tags": ["denim", "jacket", "light wash", "vintage"],
  "share_type": "swap",
  "status": "active",
  "photos": [
    { "id": 71, "url": "https://<server>/media/71.jpg", "kind": "front" },
    { "id": 72, "url": "https://<server>/media/72.jpg", "kind": "back" },
    { "id": 73, "url": "https://<server>/media/73.jpg", "kind": "label" }
  ],
  "meetup_spot": { "id": 2, "name": "Commons Center" },
  "owner": { "id": 3, "name": "Jordan Park", "dorm": "Kissam", "avatar_url": null, "items_shared": 4 },
  "impact": { "textile_kg": 0.8, "water_l": 2500, "co2_kg": 10.0 },
  "saved_by_me": false,
  "my_request_status": null,
  "created_at": "2026-10-18T15:04:05Z"
}
```

`impact` holds the estimate for this one item. `my_request_status` is the status of the current user's request on this listing, or `null` if they haven't requested it.

### ScanDraft

What the AI returns from a scan. Every field can be `null` if the model couldn't tell.

```json
{
  "title": "Levi's denim trucker jacket",
  "category": "outerwear",
  "size": "M",
  "color": "Light wash blue",
  "brand": "Levi's",
  "condition": "good",
  "description": "Classic trucker jacket with button front and chest pockets. Light fading at the cuffs.",
  "tags": ["denim", "jacket", "light wash", "vintage"]
}
```

### Request

```json
{
  "id": 9,
  "listing": { "id": 42, "title": "Levi's denim trucker jacket", "photo_url": "https://<server>/media/71.jpg", "share_type": "swap" },
  "requester": { "id": 5, "name": "Sam Lee", "dorm": "Zeppos", "avatar_url": null, "items_shared": 2 },
  "owner": { "id": 3, "name": "Jordan Park", "dorm": "Kissam", "avatar_url": null, "items_shared": 4 },
  "note": "Would you swap for a fleece in size M?",
  "status": "accepted",
  "unread_messages": 1,
  "created_at": "2026-10-18T15:20:00Z",
  "updated_at": "2026-10-18T15:31:00Z"
}
```

### Message

```json
{ "id": 120, "request_id": 9, "sender_id": 5, "body": "Commons at 4?", "created_at": "2026-10-18T15:33:10Z" }
```

### Notification

```json
{
  "id": 33,
  "type": "request_accepted",
  "title": "Jordan accepted your request",
  "body": "Levi's denim trucker jacket",
  "request_id": 9,
  "listing_id": 42,
  "read": false,
  "created_at": "2026-10-18T15:31:00Z"
}
```

## Endpoints

| Method | Path | What it does | Tier |
| --- | --- | --- | --- |
| GET | `/health` | Server is up | 1 |
| POST | `/auth/login` | Log in or sign up with a .edu email | 1 |
| GET | `/me` | Current user | 1 |
| PATCH | `/me` | Update profile | 1 |
| POST | `/photos` | Upload one photo | 1 |
| POST | `/scan` | Upload 1 to 3 photos and get an AI draft | 1 |
| GET | `/meetup-spots` | Meetup spots for my campus | 1 |
| GET | `/listings` | Campus feed with filters | 1 |
| POST | `/listings` | Create a listing | 1 |
| GET | `/listings/{id}` | One listing | 1 |
| PATCH | `/listings/{id}` | Edit my listing | 1 |
| DELETE | `/listings/{id}` | Delete my listing | 1 |
| GET | `/me/listings` | My listings | 1 |
| POST | `/listings/{id}/requests` | Request an item | 1 |
| GET | `/me/requests` | My incoming or outgoing requests | 1 |
| POST | `/requests/{id}/accept` | Owner accepts | 1 |
| POST | `/requests/{id}/decline` | Owner declines | 1 |
| POST | `/requests/{id}/complete` | Either side marks the exchange done | 1 |
| POST | `/requests/{id}/cancel` | Requester withdraws | 1 |
| GET | `/requests/{id}/messages` | Chat messages | 1 |
| POST | `/requests/{id}/messages` | Send a message | 1 |
| GET | `/impact/me` | My impact totals | 2 |
| GET | `/impact/campus` | Campus impact this week | 2 |
| PUT | `/listings/{id}/save` | Save a listing | 2 |
| DELETE | `/listings/{id}/save` | Unsave | 2 |
| GET | `/me/saved` | My saved listings | 2 |
| GET | `/listings/{id}/similar` | Similar listings | 2 |
| POST | `/listings/{id}/style` | Outfit ideas | 2 |
| GET | `/leaderboard/dorms` | Dorms ranked this week | 2 |
| GET | `/me/badges` | All badges, earned or not | 2 |
| GET | `/notifications` | My notifications | 2 |
| POST | `/notifications/read` | Mark notifications read | 2 |
| POST | `/listings/{id}/report` | Report a listing | 2 |

### GET /health

No auth. Returns `{"status": "ok"}`.

### POST /auth/login

```json
{ "email": "jordan.park@vanderbilt.edu" }
```

Returns the token and user. `is_new` is `true` the first time, which tells the app to show profile setup.

```json
{ "token": "3f6c1e0a9b7d4c2e8a51f0d6b2c94e17", "is_new": true, "user": { "...": "User object" } }
```

Errors: `not_edu_email` (400) if the address doesn't end in `.edu`.

### PATCH /me

Send only the fields that change: `name`, `dorm`, `class_year`, `sizes`, `avatar_photo_id`. Returns the User.

### POST /photos

`multipart/form-data` with `file` (JPEG, 5 MB max) and `kind`. Returns a Photo. Use it for avatars and for adding photos without a scan.

The app resizes photos before upload: longest side 1600 px, JPEG quality 0.8.

### POST /scan

`multipart/form-data`:

- `photos`: 1 to 3 JPEG files, 5 MB max each, in the order front, back, label.
- `kinds`: matching kinds, comma-separated, like `front,back,label`.
- `labels` (optional): words from Apple's on-device Vision framework, comma-separated. Only used by the fallback path.

```json
{
  "photos": [
    { "id": 71, "url": "https://<server>/media/71.jpg", "kind": "front" },
    { "id": 72, "url": "https://<server>/media/72.jpg", "kind": "back" },
    { "id": 73, "url": "https://<server>/media/73.jpg", "kind": "label" }
  ],
  "draft": { "...": "ScanDraft" },
  "source": "vision"
}
```

`source` is `vision` (the vision model read the photos), `labels` (the fallback path wrote the draft from on-device labels), or `none` (the AI failed; `draft` has every field `null`). The photos are saved either way, so the user can still fill in the form and post. The server gives the AI 20 seconds before returning `none`.

### GET /meetup-spots

Returns `{"items": [{"id": 2, "name": "Commons Center"}, ...]}` for the user's campus.

### GET /listings

Query parameters, all optional:

- `share_type`: one of the enum values.
- `category`: one of the enum values.
- `size`: exact match, like `M` or `9`.
- `q`: search text, matched against title, brand, and tags.
- `limit`, `offset`.

Returns a paged list of Listings with status `active`, newest first. The current user's own listings are included.

### POST /listings

```json
{
  "title": "Levi's denim trucker jacket",
  "category": "outerwear",
  "size": "M",
  "color": "Light wash blue",
  "brand": "Levi's",
  "condition": "good",
  "description": "Classic trucker jacket with button front and chest pockets.",
  "tags": ["denim", "jacket"],
  "share_type": "swap",
  "meetup_spot_id": 2,
  "photo_ids": [71, 72, 73]
}
```

Required: `title`, `category`, `condition`, `share_type`, `meetup_spot_id`, and at least one ID in `photo_ids`. Returns the new Listing with status 201.

### PATCH /listings/{id} and DELETE /listings/{id}

PATCH takes any subset of the POST fields and returns the Listing. DELETE returns 204. Both return `forbidden` (403) for someone else's listing.

### GET /me/listings

Query: `status=active` or `status=completed` (`pending` listings are included under `active`). Returns a paged list of Listings.

### POST /listings/{id}/requests

```json
{ "note": "Would you swap for a fleece in size M?" }
```

`note` is optional, 280 characters max. Returns the Request with status 201. Returns `conflict` (409) for your own listing, a listing that isn't `active`, or a second request from the same person.

### GET /me/requests

Query: `role=incoming` (requests on my listings) or `role=outgoing` (requests I sent). Returns a paged list of Requests, most recently updated first.

### POST /requests/{id}/accept, /decline, /complete, /cancel

No body. Each returns the updated Request.

- `accept` and `decline`: owner only, request must be `pending`. Accepting declines every other pending request on that listing and sets the listing to `pending`.
- `complete`: either person, request must be `accepted`. Sets the listing to `completed` and adds its impact to both people's totals.
- `cancel`: requester only, request must be `pending` or `accepted`. If it was `accepted`, the listing goes back to `active`.

### GET /requests/{id}/messages

Query: `after_id` (optional). Returns `{"items": [Message, ...]}` in order, oldest first, with only messages newer than `after_id` when it's given. The app polls this every 3 seconds while a chat is open, passing the last ID it has. Reading messages clears `unread_messages` on the Request for the reader. Only the two people on the request can read or send.

### POST /requests/{id}/messages

```json
{ "body": "Commons at 4?" }
```

1 to 1000 characters. Only allowed when the request is `accepted`. Returns the Message with status 201.

### GET /impact/me

```json
{ "items_shared": 4, "items_received": 2, "textile_kg": 3.1, "water_l": 9800, "co2_kg": 38.5 }
```

### GET /impact/campus

Covers the last 7 days.

```json
{ "items_rehomed": 86, "textile_kg": 61.5, "water_l": 194000, "co2_kg": 760.0, "top_dorm": "Kissam" }
```

### PUT and DELETE /listings/{id}/save, GET /me/saved

PUT and DELETE return 204 and are safe to repeat. `GET /me/saved` returns a paged list of Listings.

### GET /listings/{id}/similar

Query: `limit` (default 6). Returns `{"items": [Listing, ...]}`: active listings on the same campus, ranked by shared tags, then same category.

### POST /listings/{id}/style

No body. Returns two or three outfit ideas. The server caches the result per listing, so repeat calls are instant.

```json
{ "ideas": [ { "title": "Weekend layers", "description": "Over a gray hoodie with black jeans and white sneakers." } ] }
```

Returns `ai_unavailable` (502) if the model call fails. The app should hide the sheet and show a short message.

### GET /leaderboard/dorms

Covers the last 7 days.

```json
{ "items": [ { "rank": 1, "dorm": "Kissam", "items_shared": 14 }, { "rank": 2, "dorm": "Zeppos", "items_shared": 11 } ] }
```

### GET /me/badges

```json
{
  "items": [
    { "id": "first_swap", "name": "First Swap", "description": "Complete your first exchange", "earned_at": "2026-10-18T16:02:00Z" },
    { "id": "giving_back", "name": "Giving Back", "description": "Donate five items", "earned_at": null },
    { "id": "closet_cleanout", "name": "Closet Cleanout", "description": "List ten items", "earned_at": null }
  ]
}
```

### GET /notifications and POST /notifications/read

`GET /notifications` returns a paged list of Notifications, newest first, plus `"unread": 3` at the top level. `POST /notifications/read` takes `{"ids": [33, 34]}`, or `{"all": true}`, and returns 204.

### POST /listings/{id}/report

```json
{ "reason": "Not clothing" }
```

Returns 204. A listing with three reports from different users becomes `hidden` and drops out of every list.
