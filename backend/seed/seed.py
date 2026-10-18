"""Seed (or reset) the Vanderbilt demo campus.

Run on the server, from backend/:

    .venv/bin/python -m seed.seed            # wipe vanderbilt.edu and rebuild it
    .venv/bin/python -m seed.reset           # same thing (the S-25 "reset" command)
    .venv/bin/python -m seed.seed --check    # validate manifest + activity, touch nothing

or from the Mac: `bash scripts/reseed.sh`.

Idempotent: every run puts vanderbilt.edu back into the same state, with timestamps
relative to "now" so the demo always looks fresh. Other campuses (smoke.edu, ...)
are never touched.

What a run does, in one transaction:
1. Wipe the campus with SQL deletes (CLAUDE.md Gotcha: no ORM deletes of parents):
   its listings (cascading requests, messages, saves, reports), every photo,
   save, report, notification and badge of its users, its users that aren't
   seed accounts, its dorms, meetup spots, events and donation bins. Seed
   accounts keep their user row (same id, sessions still valid, so a logged-in
   phone stays logged in); their profile is reset.
2. Rebuild: dorms, meetup spots (with map coordinates), DONATION_BINS, EVENTS
   (times relative to the seed date, Nashville wall-clock), USERS, the listings
   in seed/photos/manifest.json (photos copied to MEDIA_DIR/seed/, cached "Style it" ideas from
   seed/style_ideas.json), then REQUESTS with MESSAGES and SAVES, and the
   notifications that activity would have sent (written by the same builders the
   API's event hooks use, app/notifications.py, back-dated with `at=`), and the
   badges it earned (app/badges.py check_badges, back-dated to when each goal was
   reached; their badge_earned notifications count as seen).
After the commit, photo files from the old state that the new state doesn't use
are deleted from MEDIA_DIR.

Request states follow the API rules (app/routers/requests.py): an accepted
request makes its listing `pending`, a completed one makes it `completed` with
`completed_at` set; pending requests only sit on `active` listings. No AI calls:
style ideas come from the snapshot in seed/style_ideas.json, which
`python -m seed.style_warm` (re)generates with the text model.
"""

from __future__ import annotations

import hashlib
import io
import json
import sys
from datetime import UTC, datetime, time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

from PIL import Image
from sqlalchemy import select, text, update
from sqlalchemy.orm import Session

from app.campus import DEFAULT_MEETUP_SPOTS
from app import badges
from app import notifications as notes
from app.config import settings
from app.db import SessionLocal, get_engine
from app.models import (
    Campus, DonationBin, Dorm, Event, Listing, MeetupSpot, Message, Notification, Photo,
    Request, Save, User, utcnow,
)
from app.routers.campus_life import EVENT_KINDS
from app.photos import MAX_SIDE, normalize_jpeg
from app.style import basis as style_basis
from app.style import validate_ideas

DOMAIN = "vanderbilt.edu"
CAMPUS_NAME = "Vanderbilt"
PHOTOS_DIR = Path(__file__).resolve().parent / "photos"
STYLE_FILE = Path(__file__).resolve().parent / "style_ideas.json"
MEDIA_SUBDIR = "seed"  # seed photos live in MEDIA_DIR/seed/, served at /media/seed/<file>
KINDS_BY_POSITION = ("front", "back", "label", "other", "other")

DORMS = (
    "Branscomb", "E. Bronson Ingram", "Hank Ingram", "Kissam",
    "Moore", "Rothschild", "Warren", "Zeppos",
)
MEETUP_SPOTS = DEFAULT_MEETUP_SPOTS + ("Commons Center", "Rand Dining Center", "Alumni Lawn")

# The first three are the demo accounts (IOS-1: the app's debug quick-login buttons).
# key = email local part; (name, dorm, class_year, top, bottom, shoe, days since sign-up)
USERS: dict[str, tuple] = {
    "jordan.park": ("Jordan Park", "Kissam", 2028, "M", "30", "9", 20),
    "sam.lee": ("Sam Lee", "Zeppos", 2027, "S", "28", "8.5", 19),
    "riley.chen": ("Riley Chen", "E. Bronson Ingram", 2027, "S", "26", "9", 18),
    "maya.johnson": ("Maya Johnson", "Warren", 2026, "M", "28", "8", 17),
    "ethan.brooks": ("Ethan Brooks", "Branscomb", 2029, "L", "32", "10.5", 16),
    "priya.nair": ("Priya Nair", "E. Bronson Ingram", 2027, "S", "26", "7", 16),
    "marcus.williams": ("Marcus Williams", "Moore", 2026, "L", "34", "11", 15),
    "olivia.martinez": ("Olivia Martinez", "Rothschild", 2028, "XS", "26", "8", 15),
    "noah.kim": ("Noah Kim", "Hank Ingram", 2029, "M", "30", "9.5", 14),
    "ava.thompson": ("Ava Thompson", "Zeppos", 2027, "S", "27", "7.5", 14),
    "leo.rossi": ("Leo Rossi", "Kissam", 2028, "L", "32", "10", 13),
}
DEMO_ACCOUNTS = tuple(f"{k}@{DOMAIN}" for k in list(USERS)[:3])

# Requests. Times are hours before the seed runs. `events` sets the status:
#   pending:   no events
#   accepted:  accepted_h
#   completed: accepted_h, completed_h
# Messages: (sender "owner"|"requester", hours_ago, body). Read markers: `owner_read` /
# `requester_read` = how many of the messages (oldest first) that side has read;
# default all of them. A sender has always read their own messages up to the one
# they sent, so markers are given explicitly only where something is unread.
REQUESTS: list[dict] = [
    # --- Jordan (demo): an active chat with Sam on Jordan's pullover, Jordan has 1 unread.
    {"listing": "quarterzip", "requester": "sam.lee", "created_h": 30, "accepted_h": 26,
     "note": "Would you swap for my Breton striped top? Happy to throw in a coffee too.",
     "messages": [
         ("owner", 25.5, "Hey Sam! Yes, happy to swap. What size is the Breton?"),
         ("requester", 25, "It's an S but it runs roomy. Commons Center tomorrow?"),
         ("owner", 24.5, "Works for me. 4pm?"),
         ("requester", 0.4, "Perfect, see you at 4! I'll bring the Breton."),
     ],
     "owner_read": 3},
    # --- Jordan asked Riley for the Docs; Riley accepted, chat all read.
    {"listing": "docs", "requester": "jordan.park", "created_h": 50, "accepted_h": 46,
     "note": "These are exactly my size, would love them!",
     "messages": [
         ("owner", 45, "They're yours! Barely worn, just not my style anymore."),
         ("requester", 44, "Amazing, thank you!! Rand at noon on Friday?"),
         ("owner", 43, "See you at Rand Friday at noon."),
     ]},
    # --- Pending: three on Jordan's listings (incoming), one on Sam's.
    {"listing": "converse", "requester": "riley.chen", "created_h": 5,
     "note": "Are these still available? I'm a 9 too!"},
    {"listing": "converse", "requester": "ethan.brooks", "created_h": 2,
     "note": "Would you swap for my black puffer? It's an L."},
    {"listing": "cap", "requester": "maya.johnson", "created_h": 9,
     "note": "Love this cap! I can pick it up anytime this week."},
    {"listing": "sundress", "requester": "ava.thompson", "created_h": 3,
     "note": "This is so cute. Would you take my denim overall dress in a swap?"},
    # --- Completed over the last 7 days: 10 different owners (impact, leaderboard).
    {"listing": "maxidress", "requester": "olivia.martinez", "created_h": 170,
     "accepted_h": 168, "completed_h": 158, "note": "Obsessed with this dress!",
     "messages": [("owner", 167, "Yay! Alumni Lawn after my 2pm?"),
                  ("requester", 166.5, "Perfect, see you there.")]},
    {"listing": "jeans", "requester": "noah.kim", "created_h": 150, "accepted_h": 148,
     "completed_h": 140, "note": "I'm a 30 too. Could swap for a hoodie?"},
    {"listing": "leather", "requester": "priya.nair", "created_h": 130, "accepted_h": 128,
     "completed_h": 118, "note": "I've been looking for a jacket like this forever.",
     "messages": [("owner", 127, "It's yours! Commons at 6?"),
                  ("requester", 126, "See you at 6, thank you!")]},
    {"listing": "hiking", "requester": "leo.rossi", "created_h": 105, "accepted_h": 104,
     "completed_h": 96, "note": "Perfect for my Radnor Lake trips!"},
    {"listing": "duffel", "requester": "ethan.brooks", "created_h": 92, "accepted_h": 90,
     "completed_h": 84, "note": "Going home for fall break, this would be perfect."},
    {"listing": "trackpants", "requester": "riley.chen", "created_h": 80, "accepted_h": 78,
     "completed_h": 72, "note": "Need these for intramurals!",
     "messages": [("owner", 77, "They're yours. Student Union around 1?"),
                  ("requester", 76.5, "Great, thanks Sam!")]},
    {"listing": "chinos", "requester": "marcus.williams", "created_h": 66, "accepted_h": 64,
     "completed_h": 58, "note": "Need khakis for career fair next week."},
    {"listing": "shorts", "requester": "ava.thompson", "created_h": 54, "accepted_h": 52,
     "completed_h": 46, "note": "These are adorable, can I grab them?"},
    {"listing": "raincoat", "requester": "maya.johnson", "created_h": 34, "accepted_h": 33,
     "completed_h": 22, "note": "I don't own a rain jacket and it's been pouring."},
    {"listing": "belt", "requester": "sam.lee", "created_h": 20, "accepted_h": 19,
     "completed_h": 14, "note": "Exactly what I needed for my interview outfit!"},
]

# Saved listings: (user, listing key, hours ago). Jordan (demo) has 3 so the Saved tab has items.
SAVES: list[tuple[str, str, float]] = [
    ("jordan.park", "puffer", 12),
    ("jordan.park", "woolcoat", 30),
    ("jordan.park", "flannel", 40),
    ("sam.lee", "skirt", 6),
    ("riley.chen", "cableknit", 20),
]

# ---- Campus map and events (S-27) ----
# Approximate spots on Vanderbilt's campus in Nashville (WGS84). Every seeded meetup spot
# gets coordinates; a new campus's default spots have none (null lat/lng).
CAMPUS_BOUNDS = ((36.1380, 36.1520), (-86.8100, -86.7940))  # (lat min/max, lng min/max)
SPOT_COORDS: dict[str, tuple[float, float]] = {
    "Main Library entrance": (36.145020, -86.800560),  # Central Library, 21st Ave side
    "Student Union": (36.146700, -86.802950),          # Sarratt Student Center
    "Main Dining Hall": (36.148900, -86.804300),       # The Kitchen at Kissam
    "Campus Center": (36.144700, -86.802700),
    "Commons Center": (36.141550, -86.797250),
    "Rand Dining Center": (36.146450, -86.803550),
    "Alumni Lawn": (36.146050, -86.801900),
}

# (name, description, accepts, hours or None, lat, lng)
DONATION_BINS: list[tuple] = [
    ("Commons Center bin", "Inside the main doors, next to the mailroom.",
     "Clean clothes, shoes tied in pairs, bags and belts", "7am to 11pm daily",
     36.141420, -86.797480),
    ("Sarratt Student Center bin", "Ground floor by the post office.",
     "Clean clothes, coats, shoes in pairs", "8am to midnight daily",
     36.146820, -86.802780),
    ("Branscomb Quad bin", "Outdoor bin by the Branscomb Quad bike racks.",
     "Clean clothes and linens, bagged", None,
     36.142800, -86.804800),
    ("Kissam Quad bin", "Under the archway between Warren and Moore.",
     "Clean clothes, shoes in pairs", None,
     36.149200, -86.804000),
]

# Event times are Nashville wall-clock: (days from the seed date, "HH:MM").
EVENT_TZ = "America/Chicago"
EVENTS: list[dict] = [
    {"kind": "donation_drive", "title": "Fall Clothing Drive",
     "description": "Two weeks of collecting gently used clothes for Nashville shelters. "
                    "Drop items in any campus donation bin or at the Commons Center table.",
     "start": (-3, "09:00"), "end": (11, "17:00"),
     "location_name": "Commons Center", "spot": "Commons Center"},
    {"kind": "swap_day", "title": "Kissam Quad Pop-up Swap",
     "description": "A quick evening swap on the quad. Bring a piece, take a piece.",
     "start": (-2, "16:00"), "end": (-2, "19:00"),
     "location_name": "Kissam Quad", "spot": "Main Dining Hall"},
    {"kind": "swap_day", "title": "Fall Swap Day",
     "description": "The big one: bring up to five clean items and leave with new favorites. "
                    "Racks by category, a fitting tent, free coffee, and everything left over "
                    "goes to the Fall Clothing Drive.",
     "start": (3, "11:00"), "end": (3, "15:00"),
     "location_name": "Alumni Lawn", "spot": "Alumni Lawn"},
    {"kind": "repair_workshop", "title": "Mend It: Sewing and Repair Workshop",
     "description": "Learn to sew on buttons, patch jeans and fix hems. Machines, thread and "
                    "snacks provided; bring something that needs fixing.",
     "start": (7, "18:00"), "end": (7, "20:00"),
     "location_name": "Rand Hall, Room 208", "spot": "Rand Dining Center"},
]

# Notifications: request ones (received/accepted/declined) newer than this many hours
# stay unread; older ones count as seen. new_message ones are unread exactly when the
# recipient has unread messages on that chat (the read markers above).
UNREAD_WITHIN_H = 6
REQUEST_TYPES = ("request_received", "request_accepted", "request_declined")

LISTING_FIELDS = ("title", "category", "size", "color", "brand", "condition",
                  "condition_note", "description", "tags", "share_type")


# --------------------------------------------------------------------------- data checks


def on_campus(lat: float, lng: float) -> bool:
    (lat_lo, lat_hi), (lng_lo, lng_hi) = CAMPUS_BOUNDS
    return lat_lo <= lat <= lat_hi and lng_lo <= lng <= lng_hi


def event_times(ev: dict, now: datetime) -> tuple[datetime, datetime]:
    """(starts_at, ends_at) as naive UTC whole seconds, from the Nashville wall-clock spec."""
    try:
        tz = ZoneInfo(EVENT_TZ)
    except Exception:  # no tz database: Central Daylight Time is close enough for a demo
        tz = timezone(timedelta(hours=-5))
    today = now.replace(tzinfo=UTC).astimezone(tz).date()

    def at(spec: tuple[int, str]) -> datetime:
        days, hhmm = spec
        local = datetime.combine(today + timedelta(days=days), time.fromisoformat(hhmm), tz)
        return local.astimezone(UTC).replace(tzinfo=None, microsecond=0)

    return at(ev["start"]), at(ev["end"])


def check_places(now: datetime) -> dict[str, int]:
    """Validate spot coordinates, bins and events; returns event counts by status at `now`."""
    assert set(SPOT_COORDS) == set(MEETUP_SPOTS), \
        f"SPOT_COORDS must cover exactly MEETUP_SPOTS: {set(SPOT_COORDS) ^ set(MEETUP_SPOTS)}"
    for name, (lat, lng) in SPOT_COORDS.items():
        assert on_campus(lat, lng), f"spot {name!r} is off campus: {lat}, {lng}"
    assert len({b[0] for b in DONATION_BINS}) == len(DONATION_BINS) >= 3, "3+ uniquely named bins"
    for name, desc, accepts, hours, lat, lng in DONATION_BINS:
        assert on_campus(lat, lng), f"bin {name!r} is off campus: {lat}, {lng}"
        assert len(name) <= 120 and len(desc or "") <= 500 and len(accepts or "") <= 200 \
            and len(hours or "") <= 80, f"bin {name!r}: text too long"
    counts = {"upcoming": 0, "live": 0, "ended": 0}
    for ev in EVENTS:
        assert ev["kind"] in EVENT_KINDS, f"event {ev['title']!r}: bad kind {ev['kind']!r}"
        assert ev["spot"] in SPOT_COORDS, f"event {ev['title']!r}: unknown spot {ev['spot']!r}"
        assert len(ev["title"]) <= 120 and len(ev["description"]) <= 2000 \
            and len(ev["location_name"]) <= 120, f"event {ev['title']!r}: text too long"
        start, end = event_times(ev, now)
        assert start < end, f"event {ev['title']!r} ends before it starts"
        counts["upcoming" if now < start else "live" if now < end else "ended"] += 1
    assert counts["upcoming"] >= 2 and counts["live"] >= 1 and counts["ended"] >= 1, \
        f"events need 2+ upcoming, 1+ live, 1+ ended: {counts}"
    assert {"swap_day", "donation_drive", "repair_workshop"} <= {e["kind"] for e in EVENTS}
    return counts


def load_manifest() -> list[dict]:
    listings = json.loads((PHOTOS_DIR / "manifest.json").read_text())["listings"]
    keys = [item["key"] for item in listings]
    dupes = {k for k in keys if keys.count(k) > 1}
    assert not dupes, f"duplicate listing keys: {dupes}"
    for item in listings:
        where = f"manifest listing {item.get('key')!r}"
        assert item["owner"] in USERS, f"{where}: unknown owner {item['owner']!r}"
        assert item["meetup_spot"] in MEETUP_SPOTS, f"{where}: unknown spot {item['meetup_spot']!r}"
        assert 1 <= len(item["photos"]) <= 5, f"{where}: needs 1 to 5 photos"
        for name in item["photos"]:
            assert (PHOTOS_DIR / name).is_file(), f"{where}: missing photo {name}"
        assert item["category"] in ("tops", "bottoms", "outerwear", "dresses", "shoes",
                                    "accessories", "bags"), f"{where}: bad category"
        assert item["condition"] in ("new", "like_new", "good", "worn"), f"{where}: bad condition"
        assert item["share_type"] in ("swap", "free", "donate"), f"{where}: bad share_type"
        note = item.get("condition_note")
        assert note is None or (1 <= len(note) <= 140 and note == note.strip()
                                and not note.endswith(".")), f"{where}: condition_note"
        assert not (note and item["condition"] == "new"), f"{where}: a new item has no condition_note"
        assert 1 <= len(item["title"]) <= 120, f"{where}: title length"
        assert len(item["tags"]) <= 10 and all(len(t) <= 30 for t in item["tags"]), f"{where}: tags"
        assert item["hours_ago"] > 0, f"{where}: hours_ago must be > 0"
    return listings


def item_basis(item: dict) -> str:
    return style_basis(item["title"], item["category"], item.get("color"), item.get("tags"))


def load_style(listings: list[dict]) -> dict[str, dict]:
    """listing key -> cache entry {"basis", "ideas"} for listings whose snapshot entry is
    current (an edited title/category/color/tags makes it stale, so it's skipped)."""
    if not STYLE_FILE.is_file():
        return {}
    snapshot = json.loads(STYLE_FILE.read_text())["listings"]
    out = {}
    for item in listings:
        entry = snapshot.get(item["key"])
        if entry and entry.get("basis") == item_basis(item):
            out[item["key"]] = {"basis": entry["basis"], "ideas": validate_ideas(entry["ideas"])}
    return out


def request_status(r: dict) -> str:
    if "completed_h" in r:
        return "completed"
    return "accepted" if "accepted_h" in r else "pending"


def check_activity(listings: list[dict]) -> dict[str, str]:
    """Validate REQUESTS/SAVES against the API's state rules; returns listing key -> status."""
    by_key = {item["key"]: item for item in listings}
    status = {key: "active" for key in by_key}
    for r in REQUESTS:
        item = by_key.get(r["listing"])
        assert item, f"request on unknown listing {r['listing']!r}"
        assert r["requester"] in USERS, f"unknown requester {r['requester']!r}"
        assert r["requester"] != item["owner"], f"{r['listing']}: owner can't request own listing"
        times = [item["hours_ago"], r["created_h"], r.get("accepted_h"), r.get("completed_h")]
        times = [t for t in times if t is not None]
        assert times == sorted(times, reverse=True), f"{r['listing']}: events out of order"
        st = request_status(r)
        if st != "pending":
            assert status[r["listing"]] == "active", f"{r['listing']}: two accepted/completed requests"
            status[r["listing"]] = "pending" if st == "accepted" else "completed"
        if r.get("messages"):
            assert st != "pending", f"{r['listing']}: chat only after accept"
            last = r.get("completed_h", 0)
            for _, h, body in r["messages"]:
                assert r["accepted_h"] >= h >= last and 1 <= len(body) <= 1000, \
                    f"{r['listing']}: message time/body"
    for r in REQUESTS:
        if request_status(r) == "pending":
            assert status[r["listing"]] == "active", \
                f"{r['listing']}: pending request on a listing that isn't active"
    for user, key, hours in SAVES:
        assert user in USERS and key in by_key and by_key[key]["owner"] != user, f"bad save {key}"
        assert 0 < hours < by_key[key]["hours_ago"], f"save of {key} before it was posted"
    unread = expected_unread(by_key)
    assert 2 <= unread.get("jordan.park", 0) <= 4, f"Jordan should have 2-4 unread notifications: {unread}"
    progress = expected_badges(by_key)["jordan.park"]
    goals = {r.id: r.goal for r in badges.RULES}
    assert any(n >= goals[b] for b, n in progress.items()), f"Jordan needs an earned badge: {progress}"
    assert any(0 < n < goals[b] for b, n in progress.items()), f"Jordan needs a badge in progress: {progress}"
    pairs = [(u, k) for u, k, _ in SAVES]
    assert len(pairs) == len(set(pairs)), "duplicate save"
    assert sum(u == "jordan.park" for u, _ in pairs) >= 2, "Jordan's Saved tab needs 2+ items"
    return status


def expected_unread(by_key: dict[str, dict]) -> dict[str, int]:
    """Unread notifications per user that build() should leave (mirrors its rules)."""
    out: dict[str, int] = {}
    for r in REQUESTS:
        owner = by_key[r["listing"]]["owner"]
        if "accepted_h" not in r and r["created_h"] < UNREAD_WITHIN_H:
            out[owner] = out.get(owner, 0) + 1  # request_received, not yet acted on
        if r.get("accepted_h", UNREAD_WITHIN_H) < UNREAD_WITHIN_H:
            out[r["requester"]] = out.get(r["requester"], 0) + 1  # request_accepted
        msgs = r.get("messages", [])
        for side, user in (("owner", owner), ("requester", r["requester"])):
            read_n = r.get(f"{side}_read", len(msgs))
            if any(s != side for s, _, _ in msgs[read_n:]):
                out[user] = out.get(user, 0) + 1  # one collapsed new_message
    return out


def expected_badges(by_key: dict[str, dict]) -> dict[str, dict[str, int]]:
    """user -> badge id -> progress the seeded activity gives (mirrors app/badges.py)."""
    out = {u: {r.id: 0 for r in badges.RULES} for u in USERS}
    for item in by_key.values():
        out[item["owner"]]["closet_cleanout"] += 1
    for r in REQUESTS:
        if request_status(r) != "completed":
            continue
        item = by_key[r["listing"]]
        out[item["owner"]]["first_swap"] += 1
        out[r["requester"]]["first_swap"] += 1
        if item["share_type"] == "donate":
            out[item["owner"]]["giving_back"] += 1
    return out


def expected_earned(by_key: dict[str, dict]) -> dict[str, set[str]]:
    goals = {r.id: r.goal for r in badges.RULES}
    return {u: {b for b, n in p.items() if n >= goals[b]}
            for u, p in expected_badges(by_key).items()}


def unread_by_user(db: Session, users: dict[str, User]) -> dict[str, int]:
    return {k: db.query(Notification).filter(Notification.user_id == u.id,
                                             Notification.read_at.is_(None)).count()
            for k, u in users.items()}


# --------------------------------------------------------------------------- wipe


def wipe_campus(db: Session, campus_id: int) -> set[str]:
    """Delete the campus's data (keeping seed users' rows). Returns old photo paths."""
    p = {"c": campus_id}
    users_q = "SELECT id FROM users WHERE campus_id = :c"
    old_paths = set(db.scalars(text(f"SELECT path FROM photos WHERE owner_id IN ({users_q})"), p))
    # Listings first: cascades requests -> messages, saves, reports; unlinks photos.
    db.execute(text("DELETE FROM listings WHERE campus_id = :c"), p)
    for table in ("photos", "saves", "reports", "notifications"):
        col = "owner_id" if table == "photos" else ("reporter_id" if table == "reports" else "user_id")
        db.execute(text(f"DELETE FROM {table} WHERE {col} IN ({users_q})"), p)
    db.execute(text(f"DELETE FROM user_badges WHERE user_id IN ({users_q})"), p)
    # Requests/messages by campus users on other campuses can't exist (campus scoping),
    # but clear them anyway so the user delete below can't trip over anything.
    db.execute(text(f"DELETE FROM requests WHERE requester_id IN ({users_q})"), p)
    seed_emails = [f"{k}@{DOMAIN}" for k in USERS]
    params = {f"e{i}": e for i, e in enumerate(seed_emails)}
    in_list = ", ".join(f":e{i}" for i in range(len(seed_emails)))
    db.execute(text(f"DELETE FROM users WHERE campus_id = :c AND email NOT IN ({in_list})"),
               {**p, **params})
    db.execute(text("DELETE FROM dorms WHERE campus_id = :c"), p)
    db.execute(text("DELETE FROM meetup_spots WHERE campus_id = :c"), p)
    db.execute(text("DELETE FROM events WHERE campus_id = :c"), p)
    db.execute(text("DELETE FROM donation_bins WHERE campus_id = :c"), p)
    return old_paths


# --------------------------------------------------------------------------- build


def media_dir() -> Path:
    return Path(settings.media_dir).expanduser()


def store_photo(name: str) -> str:
    """Copy a seed photo into MEDIA_DIR/seed/ (normalized if needed); returns its path."""
    data = (PHOTOS_DIR / name).read_bytes()
    with Image.open(io.BytesIO(data)) as img:
        ok_as_is = (img.format == "JPEG" and img.mode == "RGB" and max(img.size) <= MAX_SIDE
                    and img.getexif().get(0x0112, 1) == 1)
    if not ok_as_is:
        data = normalize_jpeg(data)
    # Content hash in the name: a replaced photo gets a new URL, so no stale app caches.
    rel = f"{MEDIA_SUBDIR}/{Path(name).stem}-{hashlib.sha1(data).hexdigest()[:10]}.jpg"
    dest = media_dir() / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        dest.write_bytes(data)
    return rel


def build(db: Session, campus: Campus, listings: list[dict], status: dict[str, str],
          now: datetime, style: dict[str, dict]) -> set[str]:
    """Insert the demo campus. Returns the photo paths it uses."""
    def ago(hours: float) -> datetime:
        return (now - timedelta(hours=hours)).replace(microsecond=0)

    db.add_all(Dorm(campus_id=campus.id, name=n, created_at=ago(24 * 30)) for n in DORMS)
    spots = {n: MeetupSpot(campus_id=campus.id, name=n, lat=SPOT_COORDS[n][0],
                           lng=SPOT_COORDS[n][1], created_at=ago(24 * 30))
             for n in MEETUP_SPOTS}
    db.add_all(spots.values())
    db.add_all(
        DonationBin(campus_id=campus.id, name=name, description=desc, accepts=accepts,
                    hours=hours, lat=lat, lng=lng, created_at=ago(24 * 30))
        for name, desc, accepts, hours, lat, lng in DONATION_BINS
    )
    for ev in EVENTS:
        starts, ends = event_times(ev, now)
        lat, lng = SPOT_COORDS[ev["spot"]]
        db.add(Event(campus_id=campus.id, kind=ev["kind"], title=ev["title"],
                     description=ev["description"], starts_at=starts, ends_at=ends,
                     location_name=ev["location_name"], lat=lat, lng=lng,
                     created_at=ago(24 * 14)))

    existing = {u.email: u for u in db.scalars(select(User).where(User.campus_id == campus.id))}
    users: dict[str, User] = {}
    for key, (name, dorm, year, top, bottom, shoe, days) in USERS.items():
        email = f"{key}@{DOMAIN}"
        user = existing.get(email) or User(email=email, campus_id=campus.id)
        user.name, user.dorm, user.class_year = name, dorm, year
        user.size_top, user.size_bottom, user.size_shoe = top, bottom, shoe
        user.avatar_photo_id = None
        user.listings_created = sum(item["owner"] == key for item in listings)
        user.created_at = ago(24 * days)
        db.add(user)
        users[key] = user
    db.flush()

    used_paths: set[str] = set()
    rows: dict[str, Listing] = {}
    completed_at: dict[str, datetime] = {
        r["listing"]: ago(r["completed_h"]) for r in REQUESTS if "completed_h" in r
    }
    for item in listings:
        created = ago(item["hours_ago"])
        listing = Listing(
            owner_id=users[item["owner"]].id, campus_id=campus.id,
            status=status[item["key"]], meetup_spot_id=spots[item["meetup_spot"]].id,
            created_at=created, updated_at=completed_at.get(item["key"], created),
            style_ideas=style.get(item["key"]),
            **{f: item.get(f) for f in LISTING_FIELDS},
        )
        db.add(listing)
        rows[item["key"]] = listing
    db.flush()

    for item in listings:
        listing = rows[item["key"]]
        for pos, name in enumerate(item["photos"]):
            rel = store_photo(name)
            used_paths.add(rel)
            db.add(Photo(owner_id=listing.owner_id, listing_id=listing.id, position=pos,
                         kind=KINDS_BY_POSITION[pos], path=rel, created_at=listing.created_at))

    for r in REQUESTS:
        listing = rows[r["listing"]]
        events = [r["created_h"], r.get("accepted_h"), r.get("completed_h")]
        req = Request(
            listing_id=listing.id, requester_id=users[r["requester"]].id, note=r.get("note"),
            status=request_status(r), created_at=ago(r["created_h"]),
            completed_at=ago(r["completed_h"]) if "completed_h" in r else None,
        )
        req.owner_last_read_id = req.requester_last_read_id = 0
        db.add(req)
        db.flush()
        # Replay the activity through the notification builders, in order, as the API would.
        notes.request_received(db, req, at=ago(r["created_h"]))
        if "accepted_h" in r:
            notes.request_accepted(db, req, at=ago(r["accepted_h"]))
        msgs = []
        for side, hours, body in r.get("messages", []):
            sender = listing.owner_id if side == "owner" else req.requester_id
            msg = Message(request_id=req.id, sender_id=sender, body=body, created_at=ago(hours))
            db.add(msg)
            db.flush()
            msgs.append(msg)
            events.append(hours)
            if side == "owner":  # a sender has read up to their own message
                req.owner_last_read_id = msg.id
            else:
                req.requester_last_read_id = msg.id
            notes.new_message(db, msg, req, at=ago(hours))
        ids = [m.id for m in msgs]
        owner_n = r.get("owner_read", len(ids))
        requester_n = r.get("requester_read", len(ids))
        req.owner_last_read_id = ids[owner_n - 1] if owner_n else 0
        req.requester_last_read_id = ids[requester_n - 1] if requester_n else 0
        # Whoever has read the whole chat has also seen its new_message notifications.
        for uid, marker in ((listing.owner_id, req.owner_last_read_id),
                            (req.requester_id, req.requester_last_read_id)):
            if all(m.id <= marker for m in msgs if m.sender_id != uid):
                notes.mark_read(db, uid, req.id, ("new_message",), at=now)
        # updated_at: the latest event (accept/complete/message), like the API leaves it.
        req.updated_at = ago(min(h for h in events if h is not None))

    # Older request notifications count as seen.
    db.flush()
    db.execute(
        update(Notification)
        .where(Notification.user_id.in_([u.id for u in users.values()]),
               Notification.type.in_(REQUEST_TYPES), Notification.read_at.is_(None),
               Notification.created_at < ago(UNREAD_WITHIN_H))
        .values(read_at=now)
        .execution_options(synchronize_session=False)
    )

    for user_key, listing_key, hours in SAVES:
        db.add(Save(user_id=users[user_key].id, listing_id=rows[listing_key].id,
                    created_at=ago(hours)))
    db.flush()

    # Badges the activity earned, dated when each goal was reached; already seen.
    got = {k: set(badges.check_badges(db, u, at=now, backdate=True)) for k, u in users.items()}
    want_badges = expected_earned({i["key"]: i for i in listings})
    assert got == want_badges, f"badges {got} != expected {want_badges}"
    db.execute(
        update(Notification)
        .where(Notification.user_id.in_([u.id for u in users.values()]),
               Notification.type == "badge_earned", Notification.read_at.is_(None))
        .values(read_at=now)
        .execution_options(synchronize_session=False)
    )
    print(f"badges: {sum(map(len, got.values()))} earned, "
          f"jordan.park {sorted(got['jordan.park'])}")

    unread = {k: n for k, n in unread_by_user(db, users).items() if n}
    want = {k: n for k, n in expected_unread({i["key"]: i for i in listings}).items() if n}
    assert unread == want, f"unread notifications {unread} != expected {want}"
    print(f"notifications: {db.query(Notification).filter(Notification.user_id.in_([u.id for u in users.values()])).count()} written, unread {unread}")
    return used_paths


def remove_files(paths: set[str]) -> int:
    root = media_dir().resolve()
    removed = 0
    for rel in paths:
        target = (root / rel).resolve()
        if target.is_relative_to(root) and target.is_file():
            target.unlink()
            removed += 1
    return removed


# --------------------------------------------------------------------------- main


def run(check_only: bool = False) -> int:
    listings = load_manifest()
    status = check_activity(listings)
    style = load_style(listings)
    counts = {s: list(status.values()).count(s) for s in ("active", "pending", "completed")}
    print(f"manifest ok: {len(listings)} listings {counts}, {len(USERS)} users, "
          f"{len(REQUESTS)} requests, {len(SAVES)} saves, "
          f"{len(style)}/{len(listings)} with style ideas")
    print(f"unread notifications expected: {expected_unread({i['key']: i for i in listings})}")
    print(f"badges expected for jordan.park: {expected_badges({i['key']: i for i in listings})['jordan.park']}")
    places = check_places(utcnow())
    print(f"map ok: {len(SPOT_COORDS)} spots with coordinates, {len(DONATION_BINS)} bins; "
          f"events {places}")
    missing = [item["key"] for item in listings if item["key"] not in style]
    if missing:
        print("  no current style ideas (run `python -m seed.style_warm`): " + ", ".join(missing))
    if check_only:
        return 0

    with SessionLocal(bind=get_engine()) as db:
        campus = db.scalar(select(Campus).where(Campus.email_domain == DOMAIN).with_for_update())
        if campus is None:
            campus = Campus(name=CAMPUS_NAME, email_domain=DOMAIN)
            db.add(campus)
            db.flush()
        campus.name = CAMPUS_NAME
        old_paths = wipe_campus(db, campus.id)
        used = build(db, campus, listings, status, utcnow(), style)
        db.commit()
        campus_id = campus.id

    seed_dir = media_dir() / MEDIA_SUBDIR
    stale = {f"{MEDIA_SUBDIR}/{p.name}" for p in seed_dir.glob("*") if p.is_file()}
    removed = remove_files((old_paths | stale) - used)
    print(f"seeded {DOMAIN} (campus {campus_id}): {len(DORMS)} dorms, {len(MEETUP_SPOTS)} spots, "
          f"{len(DONATION_BINS)} donation bins, {len(EVENTS)} events, "
          f"{len(used)} photos in {seed_dir}, removed {removed} old files")
    print("demo accounts: " + ", ".join(DEMO_ACCOUNTS))
    return 0


def main(argv: list[str]) -> int:
    return run(check_only="--check" in argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
