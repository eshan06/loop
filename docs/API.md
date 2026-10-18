# API contract

This is the contract between the iOS app and the backend. The server lane owns this file. The iOS lane requests changes through `coord/ios.md` (see `CLAUDE.md`). Every change gets a line under "Contract changes" in `coord/server.md`.

Version: v1, frozen 2026-10-17. Changes from now on go through the request process in `CLAUDE.md`.

## Conventions

- Base URL: the server's address, recorded under "Server status" in `coord/server.md` (today `http://163.192.218.131:8000`). Every path below is relative to it.
- Requests and responses are JSON, except photo uploads, which are `multipart/form-data`.
- Field names are `snake_case`. The iOS app decodes with `.convertFromSnakeCase`.
- IDs are integers. The one exception is badge IDs, which are strings like `first_swap`.
- Timestamps are ISO 8601 in UTC with a `Z` and whole seconds, never fractional, like `2026-10-18T15:04:05Z`. Swift's `.iso8601` date decoding strategy reads them as is.
- Nullable fields are always present with the value `null`; the server never leaves a key out. A field is non-null unless this doc says it can be `null`.
- Lists inside objects (`tags`, `photos`, `items`) are always arrays, possibly empty, never `null`.
- The server may add new fields later. The app should ignore keys it doesn't know (Swift `Codable` does this by default).
- Impact numbers (`textile_kg`, `water_l`, `co2_kg`) are JSON numbers that may or may not have a decimal point. Decode them as `Double`.
- Authenticated endpoints need `Authorization: Bearer <token>`. Everything except `/health` and `/auth/login` is authenticated. Tokens don't expire. Signing out just means the app forgets the token. Any `401` means the app should drop the token and go back to sign-in.
- Users only ever see listings, people, and stats from their own campus. The server enforces this from the token; the app never sends a campus ID. Anything from another campus answers `404 not_found`, as if it didn't exist.
- Every value in the examples is made up, including the impact numbers. The real impact figures come from the lookup table described in `docs/ARCHITECTURE.md`.
- Success statuses: `200` with a body, `201` with a body when something was created (noted per endpoint), `204` with no body.

### Photo URLs

Every `url`, `photo_url`, and `avatar_url` is a complete absolute URL that the app loads as is. The server builds it from its `PUBLIC_BASE_URL` setting plus `/media/<file>`, so on the live server a photo looks like `http://163.192.218.131:8000/media/71.jpg`. The part after `/media/` is opaque: the app never builds or parses photo URLs itself. Examples in this doc use `https://<server>` as a placeholder host. Photos are JPEG and need no auth to load.

### Paging

Lists are paged with `limit` (default 20, max 50) and `offset` (default 0). Paged responses look like this, where `next_offset` is `null` on the last page:

```json
{ "items": [], "total": 87, "next_offset": 20 }
```

These endpoints are paged: `GET /listings`, `GET /me/listings`, `GET /me/requests`, `GET /me/saved`, `GET /notifications`. Every other list endpoint returns `{"items": [...]}` with everything in one go and ignores `limit` and `offset` (except `GET /listings/{id}/similar`, which takes `limit`).

### Errors

Errors always have this shape, with a matching HTTP status:

```json
{ "error": { "code": "not_edu_email", "message": "Use your college .edu email address." } }
```

| Status | `code` values |
| --- | --- |
| 400 | `bad_request`, `not_edu_email`, `too_many_photos`, `photo_too_large` |
| 401 | `unauthorized` |
| 403 | `forbidden` (for example, editing someone else's listing, or accepting a request that isn't on your listing) |
| 404 | `not_found` |
| 409 | `conflict`, `own_listing`, `already_requested`, `listing_unavailable`, `wrong_status` (see below) |
| 500 | `server_error` (a bug on our side; the app shows `message` and lets the user retry) |
| 502 | `ai_unavailable` (the AI call failed; the app should fall back) |

The 409 codes:

| `code` | When |
| --- | --- |
| `own_listing` | Requesting or reporting your own listing. |
| `already_requested` | Requesting a listing you already have a `pending` or `accepted` request on. The app should show "Requested". |
| `listing_unavailable` | Requesting a listing that isn't `active` (someone else's request was accepted, or it's done). |
| `wrong_status` | The request or listing isn't in a state that allows the action, like accepting a declined request, messaging on a request that isn't `accepted`, or editing a completed listing. |
| `conflict` | Any other conflict. |

`message` is written for users, so the app can show it as is. The app should branch on `code`, not on the status alone, and treat a code it doesn't know like the generic one for that status.

Validation problems (a missing required field, a value outside an enum, text that's too long) come back as `400 bad_request`, never `422`, with `message` naming the field.

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
| `scan.source` | `vision`, `labels`, `none` |
| `badge.id` | `first_swap`, `giving_back`, `closet_cleanout` |
| `event.kind` | `swap_day`, `donation_drive`, `repair_workshop` |
| `event.status` | `upcoming`, `live`, `ended` |

A listing becomes `pending` when one of its requests is accepted, and `completed` when that request is completed.

### Sizes

`size` on a Listing or ScanDraft, and `sizes` on a User, are free strings (not an enum: any value within the length limit is accepted), but the server writes them in one vocabulary so the feed's exact-match `size` filter works:

| Category | Values |
| --- | --- |
| `tops`, `outerwear`, `dresses` | `XS`, `S`, `M`, `L`, `XL`, `XXL` |
| `bottoms` | the waist `24` to `40` (`32` for 32x30), or a letter size |
| `shoes` | US size `5` to `14` in halves: `9`, `9.5` |
| `accessories`, `bags` | `One size` |

The seed data uses only these values. `POST /scan` maps the model's answer into them where it clearly fits (`Large` → `L`, `W32 L30` → `32`, `US 9 1/2` → `9.5`, `one-size` → `One size`) and keeps anything else as is; an accessory or bag with no size gets `One size`. The app shows a value outside the list as "Other: <value>".

## Objects

### User

The current user, from `/auth/login`, `GET /me`, and `PATCH /me`.

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

Nullable: `name`, `dorm`, `class_year`, `avatar_url`, and each of `sizes.top`, `sizes.bottom`, `sizes.shoe` (`sizes` itself is always an object). A brand-new user has all of these `null` until profile setup. `items_shared` is the number of this user's listings with status `completed`.

Other people appear as an `Owner`, a smaller version without `email`, `sizes`, or `created_at`:

```json
{ "id": 3, "name": "Jordan Park", "dorm": "Kissam", "avatar_url": null, "items_shared": 4 }
```

In an Owner, `name`, `dorm`, and `avatar_url` can be `null`. The app shows "Loop member" when `name` is `null`.

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
  "condition_note": "light fading at the cuffs",
  "description": "Classic trucker jacket with button front and chest pockets. Light fading at the cuffs.",
  "tags": ["denim", "jacket", "light wash", "vintage"],
  "share_type": "swap",
  "status": "active",
  "photos": [
    { "id": 71, "url": "https://<server>/media/71.jpg", "kind": "front" },
    { "id": 72, "url": "https://<server>/media/72.jpg", "kind": "back" },
    { "id": 73, "url": "https://<server>/media/73.jpg", "kind": "label" }
  ],
  "meetup_spot": { "id": 2, "name": "Commons Center", "lat": 36.14155, "lng": -86.79725 },
  "owner": { "id": 3, "name": "Jordan Park", "dorm": "Kissam", "avatar_url": null, "items_shared": 4 },
  "impact": { "textile_kg": 0.8, "water_l": 2500, "co2_kg": 10.0 },
  "is_mine": false,
  "saved_by_me": false,
  "my_request_status": null,
  "my_request_id": null,
  "pending_request_count": 0,
  "accepted_request_id": null,
  "created_at": "2026-10-18T15:04:05Z"
}
```

- Nullable: `size`, `color`, `brand`, `condition_note`, `description`, `meetup_spot` (if the spot was removed), `my_request_status`, `my_request_id`, `accepted_request_id`.
- `condition_note` is one short wear observation, like "light fading at the cuffs" (at most 140 characters, no trailing period). It comes from the scan draft or the owner, and is `null` when there's nothing to note. The key is always present.
- `meetup_spot` is the same object `GET /meetup-spots` returns, including `lat` and `lng` (either can be `null`).
- `photos` has at least one photo, in the order they were attached (front, back, label after a scan). Feed cards show `photos[0]`.
- `impact` holds the estimate for this one item.
- `is_mine` is `true` when the current user owns the listing. Item detail shows Edit instead of Request.
- `my_request_status` and `my_request_id` describe the current user's latest request on this listing, or are `null` if they haven't requested it. Item detail shows "Requested" for `pending`, and opens the chat with `my_request_id` for `accepted`. After a `declined` or `cancelled` request the user may request again.
- `pending_request_count` and `accepted_request_id` are for the owner. `pending_request_count` is how many `pending` requests the listing has, and `accepted_request_id` is the request that was accepted while the listing is `pending`, so My listings can mark the exchange done with `POST /requests/{id}/complete`. For anyone but the owner they are always `0` and `null`.

### ScanDraft

What the AI returns from a scan. Every field except `tags` can be `null` if the model couldn't tell. `tags` is always an array, empty if the model gave none. `category` and `condition` are always one of the enum values or `null`.

`condition_note` is one short, specific wear observation the vision model saw in the photos, like "light fading at the cuffs" or "small pill on the left sleeve": at most 140 characters, no trailing period, so it posts as is. It's `null` when the item looks new or the model can't tell (and always `null` when `condition` is `new` or `source` is `labels` or `none`, since labels can't show wear).

```json
{
  "title": "Levi's denim trucker jacket",
  "category": "outerwear",
  "size": "M",
  "color": "Light wash blue",
  "brand": "Levi's",
  "condition": "good",
  "condition_note": "light fading at the cuffs",
  "description": "Classic trucker jacket with button front and chest pockets. Light fading at the cuffs.",
  "tags": ["denim", "jacket", "light wash", "vintage"]
}
```

### Request

```json
{
  "id": 9,
  "listing": { "id": 42, "title": "Levi's denim trucker jacket", "photo_url": "https://<server>/media/71.jpg", "share_type": "swap", "status": "pending" },
  "requester": { "id": 5, "name": "Sam Lee", "dorm": "Zeppos", "avatar_url": null, "items_shared": 2 },
  "owner": { "id": 3, "name": "Jordan Park", "dorm": "Kissam", "avatar_url": null, "items_shared": 4 },
  "note": "Would you swap for a fleece in size M?",
  "status": "accepted",
  "unread_messages": 1,
  "created_at": "2026-10-18T15:20:00Z",
  "updated_at": "2026-10-18T15:31:00Z"
}
```

- Nullable: `note`.
- `listing` is a short summary. `listing.photo_url` is the listing's first photo. `listing.status` is the listing's status.
- `unread_messages` counts messages from the other person that the current user hasn't read yet.
- The app works out which side the current user is on by comparing `requester.id` and `owner.id` with its own user ID.

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

Nullable: `body`, `request_id`, `listing_id`. Where a tap goes: `request_received`, `request_accepted`, `request_declined`, and `new_message` open the request (`request_id`); `badge_earned` has both IDs `null` and opens the profile.

## Endpoints

| Method | Path | What it does | Tier |
| --- | --- | --- | --- |
| GET | `/health` | Server is up | 1 |
| POST | `/auth/login` | Log in or sign up with a .edu email | 1 |
| GET | `/me` | Current user | 1 |
| PATCH | `/me` | Update profile | 1 |
| GET | `/me/unread` | Unread counts for the tab bar and the bell | 1 |
| GET | `/dorms` | Dorm names for my campus | 1 |
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
| GET | `/requests/{id}` | One request | 1 |
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
| GET | `/events` | Campus events: Swap Day and friends | 3 |
| GET | `/donation-bins` | Donation bins for the campus map | 3 |

### GET /health

No auth. Returns `{"status": "ok"}`.

### POST /auth/login

```json
{ "email": "jordan.park@vanderbilt.edu" }
```

The server trims and lowercases the email. The campus comes from the domain after `@`, using its last two labels, so `jordan@alumni.vanderbilt.edu` and `jordan@vanderbilt.edu` land on the same campus. A domain the server hasn't seen before gets a new campus named after it (`tufts.edu` becomes "Tufts").

Returns the token and user. `is_new` is `true` the first time, which tells the app to show profile setup. Logging in again with the same email returns the same user and a new token; old tokens keep working.

```json
{
  "token": "3f6c1e0a9b7d4c2e8a51f0d6b2c94e17",
  "is_new": true,
  "user": {
    "id": 3,
    "name": null,
    "email": "jordan.park@vanderbilt.edu",
    "campus": { "id": 1, "name": "Vanderbilt" },
    "dorm": null,
    "class_year": null,
    "sizes": { "top": null, "bottom": null, "shoe": null },
    "avatar_url": null,
    "items_shared": 0,
    "created_at": "2026-10-18T14:00:00Z"
  }
}
```

Errors: `not_edu_email` (400) if the address doesn't end in `.edu`.

### GET /me

Returns the User.

### PATCH /me

Send only the fields that change: `name`, `dorm`, `class_year`, `sizes`, `avatar_photo_id`. Returns the User.

```json
{
  "name": "Jordan Park",
  "dorm": "Kissam",
  "class_year": 2028,
  "sizes": { "top": "M", "bottom": "30", "shoe": "9" },
  "avatar_photo_id": 88
}
```

- `name`: 1 to 80 characters.
- `dorm`: one of the names from `GET /dorms`. If that list is empty for the campus, any text up to 80 characters.
- `class_year`: a four-digit year, like `2028`.
- `sizes`: replaces all three sizes, so send the whole object. Each value is a string up to 16 characters, or `null`.
- `avatar_photo_id`: a photo the user uploaded with `POST /photos` and `kind=avatar`. `null` removes the avatar.

Any field can be set to `null` to clear it, except `name`.

### GET /me/unread

Small and cheap, so the app can call it whenever it comes to the foreground or switches tabs.

```json
{ "notifications": 3, "messages": 2, "incoming_requests": 1 }
```

- `notifications`: unread notifications (the bell).
- `messages`: unread chat messages across all the user's requests.
- `incoming_requests`: `pending` requests on the user's own listings.

The Requests tab badge is `messages + incoming_requests`.

### GET /dorms

Dorm names for the user's campus, for the picker in profile setup. Sorted by name. Empty for a campus the server has no list for, in which case the app shows a text field instead.

```json
{ "items": ["Branscomb", "Kissam", "Zeppos"] }
```

### POST /photos

`multipart/form-data` with `file` (JPEG, 5 MB max) and `kind` (one of the `photo.kind` values). Returns a Photo with status 201. Use it for avatars (`kind=avatar`) and for adding photos without a scan.

The app resizes photos before upload: longest side 1600 px, JPEG quality 0.8.

Errors: `photo_too_large` (400) over 5 MB, `bad_request` (400) if the file isn't a JPEG or `kind` is missing.

### POST /scan

`multipart/form-data`:

- `photos`: 1 to 3 JPEG files, 5 MB max each, in the order front, back, label.
- `kinds`: matching kinds, comma-separated, like `front,back,label`. Must have one kind per photo. Each is `front`, `back`, `label`, or `other` (not `avatar`).
- `labels` (optional): words from Apple's on-device Vision framework, comma-separated. Only used by the fallback path.

Returns status 200:

```json
{
  "photos": [
    { "id": 71, "url": "https://<server>/media/71.jpg", "kind": "front" },
    { "id": 72, "url": "https://<server>/media/72.jpg", "kind": "back" },
    { "id": 73, "url": "https://<server>/media/73.jpg", "kind": "label" }
  ],
  "draft": {
    "title": "Levi's denim trucker jacket",
    "category": "outerwear",
    "size": "M",
    "color": "Light wash blue",
    "brand": "Levi's",
    "condition": "good",
    "condition_note": "light fading at the cuffs",
    "description": "Classic trucker jacket with button front and chest pockets. Light fading at the cuffs.",
    "tags": ["denim", "jacket", "light wash", "vintage"]
  },
  "source": "vision"
}
```

`source` is `vision` (the vision model read the photos), `labels` (the fallback path wrote the draft from on-device labels), or `none` (the AI failed; `draft` has every field `null` and `tags` empty). The photos are saved either way, so the user can still fill in the form and post. The server gives the AI 20 seconds before returning `none`. An AI failure is never an error response from `/scan`; only bad uploads are.

When `source` is `none`, the response looks like this:

```json
{
  "photos": [
    { "id": 74, "url": "https://<server>/media/74.jpg", "kind": "front" }
  ],
  "draft": {
    "title": null,
    "category": null,
    "size": null,
    "color": null,
    "brand": null,
    "condition": null,
    "condition_note": null,
    "description": null,
    "tags": []
  },
  "source": "none"
}
```

The app passes the photo IDs to `POST /listings` as `photo_ids`.

Errors: `too_many_photos` (400) for more than 3, `photo_too_large` (400) over 5 MB, `bad_request` (400) for no photos, a non-JPEG, or `kinds` that don't match the photos.

### GET /meetup-spots

Meetup spots for the user's campus, sorted by name:

```json
{
  "items": [
    { "id": 2, "name": "Commons Center", "lat": 36.14155, "lng": -86.79725 },
    { "id": 5, "name": "Student Union", "lat": null, "lng": null }
  ]
}
```

`lat` and `lng` (added for the campus map, Tier 3) are WGS84 degrees as JSON numbers; decode them as `Double?`. They are both set or both `null`. A spot without coordinates still works everywhere else; the map just leaves it off. A new campus's default spots have none; every Vanderbilt demo spot has them.

### GET /listings

Query parameters, all optional:

- `share_type`: one of the enum values.
- `category`: one of the enum values.
- `size`: exact match, ignoring case, like `M` or `9`.
- `q`: search text, matched case-insensitively as a substring against title, brand, and tags.
- `limit`, `offset`.

Returns a paged list of Listings with status `active`, newest first. The current user's own listings are included (with `is_mine: true`). An unknown enum value in a filter is `400 bad_request`.

### POST /listings

```json
{
  "title": "Levi's denim trucker jacket",
  "category": "outerwear",
  "size": "M",
  "color": "Light wash blue",
  "brand": "Levi's",
  "condition": "good",
  "condition_note": "light fading at the cuffs",
  "description": "Classic trucker jacket with button front and chest pockets.",
  "tags": ["denim", "jacket"],
  "share_type": "swap",
  "meetup_spot_id": 2,
  "photo_ids": [71, 72, 73]
}
```

Required: `title`, `category`, `condition`, `share_type`, `meetup_spot_id`, and at least one ID in `photo_ids`. The rest are optional and can be `null`.

Limits: `title` 1 to 120 characters, `size` 20, `color` 60, `brand` 80, `condition_note` 140, `description` 2000, up to 10 `tags` of up to 30 characters each, and 1 to 5 `photo_ids`. Every photo must have been uploaded by the current user and not already be on another listing. `meetup_spot_id` must be a spot on the user's campus. Breaking any of these is `400 bad_request` (`too_many_photos` for more than 5 photos). Optional text fields (`size`, `color`, `brand`, `condition_note`, `description`) are trimmed, and an empty string is stored as `null`.

Returns the new Listing with status 201. It starts out `active`.

### GET /listings/{id}

Returns one Listing in any status, so links from requests and notifications keep working after an exchange. A `hidden` listing is `404 not_found` for everyone but its owner.

### PATCH /listings/{id} and DELETE /listings/{id}

PATCH takes any subset of the POST fields, with the same limits, and returns the Listing. Sending `photo_ids` replaces the listing's photos with that list, in that order. DELETE returns 204 and also removes the listing's requests and chats. Both return `forbidden` (403) for someone else's listing, and `wrong_status` (409) for a `completed` listing.

### GET /me/listings

Query: `status=active` (the default) or `status=completed`. `active` also includes `pending` listings, and `hidden` ones so the owner can see them. Returns a paged list of Listings, newest first.

### POST /listings/{id}/requests

```json
{ "note": "Would you swap for a fleece in size M?" }
```

`note` is optional, 280 characters max. The body can be `{}`. Returns the Request with status 201 and sends the owner a `request_received` notification.

Errors (409): `own_listing` for your own listing, `listing_unavailable` for a listing that isn't `active`, `already_requested` if you already have a `pending` or `accepted` request on it. After a `declined` or `cancelled` request, you can request again.

### GET /me/requests

Query: `role=incoming` (requests on my listings) or `role=outgoing` (requests I sent). `role` is required. Returns a paged list of Requests in every status, most recently updated first.

### GET /requests/{id}

Returns one Request. Only the requester and the owner can see it; anyone else gets `forbidden` (403). The chat screen calls this alongside the message poll to notice when the other person completes or cancels.

### POST /requests/{id}/accept, /decline, /complete, /cancel

No body. Each returns the updated Request with status 200.

- `accept` and `decline`: owner only, request must be `pending`. Accepting declines every other pending request on that listing and sets the listing to `pending`.
- `complete`: either person, request must be `accepted`. Sets the listing to `completed` and adds its impact to both people's totals.
- `cancel`: requester only, request must be `pending` or `accepted`. If it was `accepted`, the listing goes back to `active`.

Errors: `forbidden` (403) for the wrong person, `wrong_status` (409) if the request isn't in a status that allows the action.

Notifications: `accept` sends the requester `request_accepted`. `decline` sends `request_declined`, and so does every other request that an `accept` declines. `complete` and `cancel` send none.

### GET /requests/{id}/messages

Query: `after_id` (optional). Returns `{"items": [Message, ...]}` in order, oldest first: every message on the request, or only messages newer than `after_id` when it's given. Not paged. The app polls this every 3 seconds while a chat is open, passing the last ID it has.

```json
{
  "items": [
    { "id": 120, "request_id": 9, "sender_id": 5, "body": "Commons at 4?", "created_at": "2026-10-18T15:33:10Z" },
    { "id": 121, "request_id": 9, "sender_id": 3, "body": "Works for me, see you there.", "created_at": "2026-10-18T15:33:40Z" }
  ]
}
```

Reading marks every message up to the newest one returned as read for the reader, which clears `unread_messages` on the Request. Messages can be read in any request status. Only the two people on the request can read or send; anyone else gets `forbidden` (403). Reading doesn't change the Request's `updated_at`.

### POST /requests/{id}/messages

```json
{ "body": "Commons at 4?" }
```

1 to 1000 characters after trimming spaces at the ends; an empty or missing `body` is `bad_request` (400). Only allowed when the request is `accepted`, otherwise `wrong_status` (409). Returns the Message with status 201 and sends the other person a `new_message` notification. Sending also marks the sender's side as read up to their message and bumps the Request's `updated_at`, so the chat moves to the top of `GET /me/requests`.

### GET /impact/me

```json
{ "items_shared": 4, "items_received": 2, "textile_kg": 3.1, "water_l": 9800, "co2_kg": 38.5 }
```

`items_shared` counts my completed listings and `items_received` my completed requests. The impact totals add up both sides' items.

### GET /impact/campus

Covers the last 7 days. `top_dorm` is `null` when no exchange has a dorm yet.

```json
{ "items_rehomed": 86, "textile_kg": 61.5, "water_l": 194000, "co2_kg": 760.0, "top_dorm": "Kissam" }
```

`items_rehomed` counts exchanges completed on my campus in the last 7 days, and the totals add up each of those items once. `top_dorm` is the owner's dorm with the most of them (the same count as `GET /leaderboard/dorms`), ties broken alphabetically.

### Where the impact numbers come from

Each item's `impact` is a typical garment mass for its category times a footprint per kilogram of clothing. The full derivation is in the comment at the top of `backend/app/impact.py`.

- Footprint per kg: WRAP (2017), "Valuing Our Clothes: the cost of UK fashion", page 11, Table 3, 2016 column: 23.2 t CO2e and 7,060 m³ of water per tonne of clothing over its whole life cycle, so 23.2 kg CO2e and 7,060 L per kg. <https://www.wrap.ngo/sites/default/files/2020-10/WRAP-valuing-our-clothes-the-cost-of-uk-fashion_WRAP.pdf>
- Garment masses: Sandin, Roos, Spak, Zamani & Peters (2019), "Environmental assessment of Swedish clothing consumption: six garments, sustainable futures", Mistra Future Fashion report 2019:05 (RISE / Chalmers), Table 3.1 (printed page 28): T-shirt 110 g, jeans 477 g, dress 478 g, jacket 444 g, socks 43 g. <https://research.chalmers.se/publication/514322>

| category | stands in for | textile_kg | water_l | co2_kg |
| --- | --- | --- | --- | --- |
| tops | T-shirt | 0.11 | 777 | 2.6 |
| bottoms | jeans | 0.48 | 3368 | 11.1 |
| dresses | dress | 0.48 | 3375 | 11.1 |
| outerwear | jacket | 0.44 | 3135 | 10.3 |
| accessories | socks | 0.04 | 304 | 1.0 |
| shoes | jeans mass (assumption: neither source covers footwear) | 0.48 | 3368 | 11.1 |
| bags | jacket mass (assumption: neither source covers bags) | 0.44 | 3135 | 10.3 |

### PUT and DELETE /listings/{id}/save, GET /me/saved

PUT and DELETE return 204 and are safe to repeat. `GET /me/saved` returns a paged list of saved Listings in any status except `hidden`, most recently saved first.

Saving again keeps the original save time. You can save your own listing. A listing you can't see (another campus, deleted, or someone else's `hidden` listing) is `404 not_found` for both PUT and DELETE. Every Listing's `saved_by_me` reflects the caller's saves.

### GET /listings/{id}/similar

Query: `limit` (default 6, max 20; a larger value is treated as 20). Returns `{"items": [Listing, ...]}`: active listings on the same campus, ranked by shared tags, then same category. Never includes the listing itself or the caller's own listings. Can be empty.

The ranking score is 3 per shared tag (case-insensitive) + 2 for the same category + 1 for the same size, ties newest first. Listings that share nothing only fill the row when there aren't enough matches. The source listing follows `GET /listings/{id}` visibility: another campus, deleted, or someone else's `hidden` listing is `404 not_found`.

### POST /listings/{id}/style

No body. Returns two or three outfit ideas. The server caches the result per listing, so repeat calls are instant.

```json
{ "ideas": [ { "title": "Weekend layers", "description": "Over a gray hoodie with black jeans and white sneakers." } ] }
```

Each `title` is at most 40 characters and each `description` at most 200. The cache is cleared when the listing's title, category, color, or tags change. Any listing the caller can see can be styled (same visibility as `GET /listings/{id}`: another campus, deleted, or someone else's `hidden` listing is `404 not_found`).

If the model call fails or takes longer than 15 seconds, the server returns three template ideas built from the category and color instead, with the same shape and status 200, and doesn't cache them, so the next call tries the model again. In practice the endpoint doesn't return `ai_unavailable` (502); the app can keep handling it by hiding the sheet and showing a short message. Demo listings come with ideas already cached.

### GET /leaderboard/dorms

Covers the last 7 days: completed exchanges, counted by the owner's dorm. Dorms with none are left out, so the list can be empty. Ties share a rank and are listed alphabetically, and the next rank skips ahead (1, 1, 3). Owners without a dorm aren't counted. The first row's `dorm` is always `GET /impact/campus`'s `top_dorm`.

```json
{ "items": [ { "rank": 1, "dorm": "Kissam", "items_shared": 14 }, { "rank": 2, "dorm": "Zeppos", "items_shared": 11 } ] }
```

### GET /me/badges

Always returns every badge, in this order. `earned_at` is `null` until the badge is earned. `progress` and `goal` let the profile show "3 of 5"; `progress` stops at `goal`.

```json
{
  "items": [
    { "id": "first_swap", "name": "First Swap", "description": "Complete your first exchange", "earned_at": "2026-10-18T16:02:00Z", "progress": 1, "goal": 1 },
    { "id": "giving_back", "name": "Giving Back", "description": "Donate five items", "earned_at": null, "progress": 3, "goal": 5 },
    { "id": "closet_cleanout", "name": "Closet Cleanout", "description": "List ten items", "earned_at": null, "progress": 6, "goal": 10 }
  ]
}
```

- First Swap: one completed exchange, on either side.
- Giving Back: five of my `donate` listings completed.
- Closet Cleanout: ten listings created, counting ones since deleted or completed.

Badges are checked when you create a listing and when one of your exchanges completes (both sides). Once earned, a badge stays earned and shows `progress` equal to `goal`. Each newly earned badge writes one `badge_earned` notification, never repeated: `title` "You earned First Swap" (the badge's `name`), `body` the badge's `description`, both IDs `null`.

### GET /notifications and POST /notifications/read

`GET /notifications` returns a paged list of Notifications, newest first, plus `unread` (the total unread, across all pages) at the top level:

```json
{
  "items": [
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
  ],
  "total": 1,
  "next_offset": null,
  "unread": 1
}
```

`POST /notifications/read` takes `{"ids": [33, 34]}`, or `{"all": true}`, and returns 204. IDs that aren't the user's are ignored. Marking is idempotent. A body with neither (or `{"all": false}`) is `bad_request` (400); `{"ids": []}` is a 204 that changes nothing.

Ordering is newest `created_at` first, ties broken by `id`, newest first. How rows are written (additive detail, nothing for the app to do):

- Nobody is notified about their own action. Titles use the other person's first name; `body` is the listing title, except `new_message`, whose `body` is a preview of the newest message.
- `new_message` collapses: while you still have an unread `new_message` for a request, another message on it updates that notification (same `id`; the title counts the unread messages, like "Sam sent you 3 messages"; `body` and `created_at` move to the newest message) instead of adding one.
- Opening the chat (`GET /requests/{id}/messages` returning messages) or replying in it marks your `new_message` notifications for that request read.
- Accepting or declining a request marks the owner's `request_received` notification for it read.

### POST /listings/{id}/report

```json
{ "reason": "Not clothing" }
```

`reason` is optional, 200 characters max. Returns 204. Reporting the same listing twice counts once. Reporting your own listing is `own_listing` (409). A listing with three reports from different users becomes `hidden` and drops out of the feed, search, similar items, and saved lists.

How it works (additive detail, nothing for the app to do):

- The body can be `{}` or missing. A `reason` that isn't a string, or is over 200 characters, is `bad_request` (400). Only listings the caller can see can be reported: another campus, deleted, or someone else's `hidden` listing is `404 not_found`.
- The third distinct reporter hides an `active` or `pending` listing. A `completed` listing keeps its reports but stays visible, since it's exchange history.
- Open requests on a hidden listing stay as they are. The owner can't accept a `pending` one (`wrong_status`, because the listing isn't `active`) but can decline it, and the requester can cancel. An `accepted` exchange can still chat and complete (completing moves the listing to `completed` as usual). Cancelling an accepted request doesn't unhide the listing.
- The owner gets no notification (there is no notification type for it). The owner still sees the listing in `GET /listings/{id}` and the `active` tab of `GET /me/listings` with `status: "hidden"`, and can edit or delete it.

### GET /events

The Swap Day tab (Tier 3). Events on the user's campus, sorted by `starts_at`, oldest first (ties by `id`). By default the list holds everything that hasn't ended yet plus anything that ended in the last 24 hours, so it shows what's coming up, what's on right now, and what happened yesterday. `?include_past=true` returns every event, however old, in the same order. Not paged: `{"items": [...]}`.

```json
{
  "items": [
    {
      "id": 4,
      "title": "Fall Clothing Drive",
      "description": "Two weeks of collecting gently used clothes for Nashville shelters.",
      "kind": "donation_drive",
      "status": "live",
      "is_live": true,
      "starts_at": "2026-10-14T14:00:00Z",
      "ends_at": "2026-10-28T22:00:00Z",
      "location_name": "Commons Center",
      "lat": 36.14155,
      "lng": -86.79725
    },
    {
      "id": 6,
      "title": "Fall Swap Day",
      "description": "Bring up to five clean items and leave with new favorites.",
      "kind": "swap_day",
      "status": "upcoming",
      "is_live": false,
      "starts_at": "2026-10-20T16:00:00Z",
      "ends_at": "2026-10-20T20:00:00Z",
      "location_name": "Alumni Lawn",
      "lat": 36.14605,
      "lng": -86.8019
    }
  ]
}
```

- `kind` is one of `swap_day`, `donation_drive`, `repair_workshop`. Treat an unknown value like `swap_day`.
- `status` is worked out from the server's clock when the response is built: `upcoming` before `starts_at`, `live` from `starts_at` until `ends_at`, `ended` after. `is_live` is `true` exactly when `status` is `live` (a convenience for the "Happening now" badge).
- `starts_at` and `ends_at` are UTC like every timestamp; the app shows them in the phone's time zone. `ends_at` is always after `starts_at`.
- Nullable: `description`, `lat`, `lng` (`lat` and `lng` are both set or both `null`). `location_name` is always a string, so the app can show it even without a pin.
- `include_past` takes `true` or `false` (default `false`); anything else is `400 bad_request`.
- Events are read-only for the app; the demo campus's come from the seed, with times relative to when it was seeded. Another campus usually has none, and gets `{"items": []}`.

### GET /donation-bins

Donation bins on the user's campus for the map (Tier 3), sorted by name (ties by `id`). Not paged:

```json
{
  "items": [
    {
      "id": 1,
      "name": "Commons Center bin",
      "description": "Inside the main doors, next to the mailroom.",
      "accepts": "Clean clothes, shoes tied in pairs, bags and belts",
      "hours": "7am to 11pm daily",
      "lat": 36.14142,
      "lng": -86.79748
    },
    {
      "id": 3,
      "name": "Branscomb Quad bin",
      "description": "Outdoor bin by the Branscomb Quad bike racks.",
      "accepts": "Clean clothes and linens, bagged",
      "hours": null,
      "lat": 36.1428,
      "lng": -86.8048
    }
  ]
}
```

- `lat` and `lng` are never `null` here (a bin is only useful on the map). Decode them as `Double`.
- Nullable: `description` (where exactly the bin is), `accepts` (what goes in it), `hours` (free text; `null` means no posted hours, like an outdoor bin).
- The campus map (I-28) shows these together with the meetup spots from `GET /meetup-spots` that have coordinates. Another campus usually has no bins and gets `{"items": []}`.
