# Loop

Loop is an iOS app for college students to swap, give away and donate clothes on their own campus. Built by team Stacked (Yusung, Ji Ting) for an Oracle Cloud hackathon.

This README covers the backend: the server behind the app. It's a FastAPI app on an Oracle Cloud VM, backed by MySQL HeatWave, and it calls Oracle's Generative AI service to turn clothing photos into listings.

## Oracle Cloud services we use

| OCI service | AWS equivalent | What it does for Loop |
| --- | --- | --- |
| **Generative AI** | Bedrock | Reads clothing photos (`cohere.command-a-vision`) and writes "Style it" outfit ideas (`cohere.command-a-03-2025`). Region: `us-chicago-1`. |
| **MySQL HeatWave** | RDS / Aurora MySQL | The database. Private IP only, so only the VM can reach it. |
| **Compute** | EC2 | One Oracle Linux 9 VM that runs the API under systemd as `loop-api`. |
| **Virtual Cloud Network** | VPC + security groups | Networking. Port 8000 is open for the API. |
| **Resource Manager** | CloudFormation | The starter-kit stack that created the VM, network and database. |
| **IAM** | IAM | API signing keys, so the server can call Generative AI. |

## How a scan works

1. The app uploads 1 to 3 photos (front, back, label) to `POST /scan`.
2. The server saves the photos first, so they're never lost. Then it shrinks them and sends them to `cohere.command-a-vision`.
3. The prompt asks for one JSON object with these fields: title, category, size, color, brand, condition, tags and a short wear note.
4. The server cleans up the reply:
   - it strips the code fences the model likes to add;
   - it maps sizes onto the app's list, so "Large" becomes `L` and "W32 L30" becomes `32`;
   - any value that doesn't fit becomes `null`.
5. If the vision model fails, the app's on-device labels (from Apple's Vision framework) go to the text model instead. If that fails too, or the whole thing takes longer than 20 seconds, the user gets a blank form and fills it in by hand.

A scan usually takes 3 to 4 seconds end to end. All of the AI code lives in `backend/app/ai.py`.

"Style it" (`backend/app/style.py`) uses the text model to suggest 2 or 3 outfits for an item. It saves the result on the listing, so later taps are instant. Every demo listing ships with pre-made ideas, so the demo never waits on the AI.

## What's in `backend/`

```
app/
  main.py           app setup, routers, /media, error handlers
  config.py         settings, read from backend/.env
  db.py             SQLAlchemy engine and sessions
  models.py         one model per table
  schemas.py        Pydantic request and response shapes
  serializers.py    builds every JSON object the API returns
  errors.py         the {"error": {code, message}} shape
  auth.py           bearer token -> current user
  ai.py             OCI Generative AI calls and scan parsing
  style.py          "Style it"
  photos.py         upload checks, resizing, saving
  impact.py         per-item textile, water and CO2 numbers, with sources
  badges.py         badge rules
  notifications.py  notification builders
  events.py         hooks that fire on request and message events
  campus.py         campus lookup and default meetup spots
  paging.py         limit/offset paging
  routers/          one file per area: auth, me, photos, scan, listings,
                    requests, messages, notifications, stats, spots, campus_life
migrations/         plain SQL, applied in order by migrate.py
seed/               demo campus data, photos and the reset script
```

The full API contract is in [`docs/API.md`](docs/API.md). It covers every endpoint, object and error code.

## Impact numbers

Each item's impact comes from one row per category in `backend/app/impact.py`:

- **Footprint per kilogram:** WRAP (2017), *Valuing Our Clothes*, 23.2 kg CO2e and 7,060 L of water per kg of clothing.
- **Garment weights:** Sandin et al. (2019), *Environmental assessment of Swedish clothing consumption*.

The full citations are in the file. Neither source covers shoes or bags, so those reuse the jeans and jacket weights. The file says so.

## Running it

### On the server (the normal way)

Push to `main`, then deploy from your Mac:

```
bash scripts/deploy.sh
```

This pulls on the VM, installs requirements, runs migrations, restarts `loop-api` and checks `/health`. The API is down for a couple of seconds during the restart.

The API lives at `http://163.192.218.131:8000`. Check that it's up with:

```
curl http://163.192.218.131:8000/health
```

To read the logs on the VM:

```
sudo journalctl -u loop-api -n 100 --no-pager
```

### Locally

You need Python 3.12. The MySQL driver won't import on 3.15. You also need a filled-in `backend/.env` (copy `backend/.env.example`).

The database only has a private IP, so open a tunnel first:

```
bash scripts/db-tunnel.sh
```

It uses port 3307 if 3306 is taken. Then start the API:

```
cd backend
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python migrate.py
uvicorn app.main:app --reload --port 8000
```

## Demo data

The seed builds a fake Vanderbilt campus:

- 11 students across 8 dorms;
- 39 listings with photos;
- a week of finished swaps;
- chats, notifications and badges;
- Swap Day events and donation bins on the map.

The demo accounts are `jordan.park@vanderbilt.edu` (Phone 1) and `sam.lee@vanderbilt.edu` (Phone 2). Riley Chen is a third demo account. There are no passwords: any `.edu` email logs in.

Before every demo, and after every rehearsal, run:

```
bash scripts/reseed.sh
```

It resets the demo campus to the same clean state, clears out test data and checks the result. Run it within a day or two of presenting. The leaderboard only counts the last 7 days, and events are scheduled relative to the reset, so old data goes stale.

To check the demo campus without changing anything:

```
bash scripts/reseed.sh --check
```

The listing photos are openly licensed Wikimedia Commons placeholders, with credits in `backend/seed/photos/ATTRIBUTION.md`. To use your own photos, follow `backend/seed/photos/README.md`.

## Testing

```
bash scripts/smoke.sh
```

This runs about 790 end-to-end checks against the live server. They cover every endpoint, the error codes and the full request → accept → chat → complete flow. Test users go on a throwaway `smoke.edu` campus, and the demo campus is only read, never changed.

## Secrets

`backend/.env` holds the database password. It is git-ignored and exists only on the VM and on the server lane's Mac. `backend/.env.example` lists the same keys with blank values.

OCI API keys live in `~/.oci/` on the VM and on the Mac, never in the repo. The iOS app never talks to Oracle directly: every AI call goes through this server.
