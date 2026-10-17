# Architecture

Loop has three parts: the iOS app, a FastAPI backend on an OCI compute instance, and a MySQL HeatWave database. The backend is the only thing that talks to the database and to OCI Generative AI.

```
 iPhone (SwiftUI app)
    │  HTTPS or HTTP + JSON, bearer token
    ▼
 OCI compute instance (Oracle Linux 9)
    FastAPI on port 8000, run by systemd as `loop-api`
    photos on local disk, served at /media
    │                         │
    │ private network         │ OCI SDK, us-chicago-1
    ▼                         ▼
 MySQL HeatWave           OCI Generative AI
 (private IP only)        cohere.command-a-vision   reads scan photos
                          cohere.command-a-03-2025  writes "Style it" ideas
```

## Who can reach what

Only the server lane's Mac has OCI credentials. It holds `~/.oci/config` and the API signing key, and so does the compute instance, so the backend can call Generative AI.

The iOS lane needs nothing from OCI. It only needs the API base URL, which the server lane keeps current under "Server status" in `coord/server.md`. Until the server is up, the app runs on mock data.

Nobody else needs the OCI console. If something on the server breaks, the iOS lane writes a request in `coord/ios.md` and the server lane fixes it.

## iOS app

SwiftUI, iOS 17+, no third-party packages.

```
ios/Loop/
  Config/        APIConfig.swift: base URL and the useMocks switch
  Models/        Codable structs matching docs/API.md
  Networking/    APIClient: one async function per endpoint, mock or live
  Mocks/         one JSON file per endpoint, copied from docs/API.md
  DesignSystem/  colors, type, spacing, reusable components
  Features/      Onboarding, Feed, Scan, Review, Detail, Requests, Chat, Profile, Impact, ...
```

Every screen gets its data through `APIClient`, never `URLSession` directly, so flipping `useMocks` switches the whole app between mock and live.

Photos are resized on the phone before upload: longest side 1600 px, JPEG quality 0.8.

The fallback scan path (below) uses Apple's Vision framework to classify the photo on the device. Build it as a small helper in `Features/Scan/` even if the vision model works, because it's cheap insurance.

## Backend

Python 3.12, FastAPI, Uvicorn, SQLAlchemy 2, `mysql-connector-python`, and the `oci` SDK.

```
backend/
  app/
    main.py        app setup, routers, /media static files, error handler
    config.py      reads settings from .env
    db.py          engine and session
    models.py      SQLAlchemy tables
    schemas.py     Pydantic request and response models (match docs/API.md)
    auth.py        token lookup dependency
    ai.py          vision scan, fallback, Style it
    impact.py      per-category impact table, with its source cited
    routers/       auth, me, photos, scan, listings, requests, messages, social, stats
  migrations/      plain SQL files, run in order
  seed/            seed.py and the seed photos
  requirements.txt
  .env.example
```

Errors go through one handler that returns the shape in `docs/API.md`, so the app can always show `error.message`.

## Data model

MySQL tables. Every table has an integer `id` primary key unless noted, and `created_at`.

```
campuses        name, email_domain (unique)
users           campus_id, email (unique), name, dorm, class_year,
                size_top, size_bottom, size_shoe, avatar_photo_id
sessions        token (primary key), user_id
photos          owner_id, listing_id (null until posted), kind, path
meetup_spots    campus_id, name
listings        owner_id, campus_id, title, category, size, color, brand,
                `condition`, description, tags (JSON), share_type, status,
                meetup_spot_id, style_ideas (JSON, cached), updated_at
requests        listing_id, requester_id, note, status, updated_at, completed_at,
                owner_last_read_id, requester_last_read_id
messages        request_id, sender_id, body
saves           user_id + listing_id (primary key)
reports         listing_id, reporter_id, reason, unique (listing_id, reporter_id)
notifications   user_id, type, title, body, request_id, listing_id, read_at
user_badges     user_id + badge_id (primary key), earned_at
```

`condition` is a reserved word in MySQL, so quote it with backticks in raw SQL.

Some numbers are computed when asked for instead of stored:

- Impact: completed requests joined to listings, with each listing's category looked up in `impact.py`.
- `items_shared`: the owner's listings with status `completed`.
- Leaderboard: completed requests in the last 7 days, grouped by the owner's dorm.
- Badges: checked whenever a request completes or a listing is created. New ones get a row in `user_badges` and a notification.
- Unread messages: messages with an ID above the reader's `*_last_read_id` on the request.

## Auth

Demo-grade, on purpose. `POST /auth/login` checks that the email ends in `.edu`, finds or creates the campus from the domain, finds or creates the user, and returns a random token stored in `sessions`. There are no passwords and no email codes. Every other route looks up the token and gets the user and campus from it, and every query filters by that campus.

## The scan pipeline

`POST /scan` saves the photos first, then tries to fill in the draft.

Main path, when `cohere.command-a-vision` is available on our account:

1. Base64-encode the photos and send them in one chat request to the vision model. It only works with the Cohere V2 chat format.
2. The prompt asks for a single JSON object with exactly the ScanDraft keys, the allowed values for `category` and `condition`, and `null` for anything the model can't see.
3. Strip any code fences from the reply, parse it, and validate it with the Pydantic `ScanDraft` model. Values outside the enums become `null`.
4. Return the draft with `source: "vision"`.

To get the call right quickly, open the Generative AI Playground, select the vision model, attach a photo, and use View code → Python. That gives the exact client, request classes, and endpoint for our region. The `cohere[oci]` Python package (its `OciClientV2`) is another way to call the same model.

Fallback path, when the vision model isn't available or fails:

1. The app sends `labels`: the top labels from Apple's Vision classifier, plus any text it read off the label photo.
2. The backend sends those words to `cohere.command-a-03-2025` with the same JSON prompt.
3. Return the draft with `source: "labels"`.

If both fail, or the AI takes longer than 20 seconds, return an all-`null` draft with `source: "none"`. The photos are already saved, so the user just fills in the form.

"Style it" uses the text model with the listing's title, category, color, and tags, asks for two or three outfit ideas as JSON, and caches the result in `listings.style_ideas`.

## Impact numbers

`impact.py` has one row per category: kilograms of textile, liters of water, and kilograms of CO₂ for a typical item. Take every number from one published source and cite it in a comment above the table. Judges at a social-good hackathon may ask where the numbers come from, and "we made them up" loses points.

## Photos

Saved to `MEDIA_DIR` on the server's disk and served by FastAPI at `/media/<file>`. URLs in responses are built from `PUBLIC_BASE_URL`. For a demo this is enough. OCI Object Storage is a stretch goal, not a requirement.

## OCI setup

The starter kit stack already created the network, the compute instance, and MySQL HeatWave. What's left for the server lane:

Open the port. Add an ingress rule for TCP 8000 from `0.0.0.0/0` to the public subnet's security list, then open it on the instance:

```
sudo firewall-cmd --add-port=8000/tcp --permanent
sudo firewall-cmd --reload
```

Reach MySQL from the Mac. The database has only a private IP, so tunnel through the instance and point `DB_HOST` at `127.0.0.1`:

```
ssh -i key.pem -N -L 3306:<mysql-private-ip>:3306 opc@<server-ip>
```

If the Mac already runs MySQL on 3306, use `-L 3307:...` and `DB_PORT=3307`.

Run the API on the instance with systemd. Save this as `/etc/systemd/system/loop-api.service`:

```
[Unit]
Description=Loop API
After=network.target

[Service]
User=opc
WorkingDirectory=/home/opc/loop/backend
EnvironmentFile=/home/opc/loop/backend/.env
ExecStart=/home/opc/loop/backend/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

Then `sudo systemctl daemon-reload && sudo systemctl enable --now loop-api`. If it fails with status `203/EXEC`, SELinux is likely blocking the venv in the home directory. Run the app in `tmux` for the hackathon instead of fighting it.

Deploy by pulling on the instance. The repo is public, so no credentials are needed:

```
cd ~/loop && git pull && sudo systemctl restart loop-api
```

## HTTPS and iOS

iOS refuses plain `http://` connections unless the app opts out, and the server starts out as plain HTTP on a bare IP address. Two ways around it:

1. Fastest: in the app target's Info settings, add App Transport Security Settings → Allow Arbitrary Loads = YES. Fine for a hackathon build; don't ship it.
2. Cleaner: put Caddy in front of the API with a hostname from sslip.io (an address like `<ip-with-dashes>.sslip.io` resolves to the IP inside it). Caddy gets a real certificate automatically. This needs ports 80 and 443 open in the security list and `firewalld`.

Start with option 1. Switch to option 2 only if there's time.

## Environment variables

`backend/.env` on each machine that runs the API. Never commit it. `backend/.env.example` lists the same keys with blank values.

```
DB_HOST=
DB_PORT=3306
DB_USER=
DB_PASSWORD=
DB_NAME=loop
OCI_CONFIG_PROFILE=DEFAULT
OCI_REGION=us-chicago-1
OCI_COMPARTMENT_ID=
GENAI_VISION_MODEL=cohere.command-a-vision
GENAI_TEXT_MODEL=cohere.command-a-03-2025
MEDIA_DIR=/home/opc/loop-media
PUBLIC_BASE_URL=
```

## If something breaks during the demo

- The server keeps running under systemd, so it doesn't depend on anyone's laptop being open.
- `seed/reset.py` puts the database back to the clean demo state in one command.
- A screen recording of the full demo path is the backup if the venue Wi-Fi fails.
- As a last resort, `useMocks = true` runs the whole app offline on mock data.
