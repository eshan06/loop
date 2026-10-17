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
   seed accounts, its dorms and meetup spots. Seed accounts keep their user
   row (same id, sessions still valid, so a logged-in phone stays logged in);
   their profile is reset.
2. Rebuild: dorms, meetup spots, USERS, the listings in seed/photos/manifest.json
   (photos copied to MEDIA_DIR/seed/), then REQUESTS with MESSAGES and SAVES.
After the commit, photo files from the old state that the new state doesn't use
are deleted from MEDIA_DIR.

Request states follow the API rules (app/routers/requests.py): an accepted
request makes its listing `pending`, a completed one makes it `completed` with
`completed_at` set; pending requests only sit on `active` listings. No AI calls.
"""

from __future__ import annotations

import hashlib
import io
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path

from PIL import Image
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from app.campus import DEFAULT_MEETUP_SPOTS
from app.config import settings
from app.db import SessionLocal, get_engine
from app.models import (
    Campus, Dorm, Listing, MeetupSpot, Message, Photo, Request, Save, User, utcnow,
)
from app.photos import MAX_SIDE, normalize_jpeg

DOMAIN = "vanderbilt.edu"
CAMPUS_NAME = "Vanderbilt"
PHOTOS_DIR = Path(__file__).resolve().parent / "photos"
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

# Saved listings: (user, listing key, hours ago)
SAVES: list[tuple[str, str, float]] = [
    ("jordan.park", "puffer", 12),
    ("jordan.park", "woolcoat", 30),
    ("jordan.park", "flannel", 40),
    ("sam.lee", "skirt", 6),
    ("riley.chen", "cableknit", 20),
]

LISTING_FIELDS = ("title", "category", "size", "color", "brand", "condition",
                  "description", "tags", "share_type")


# --------------------------------------------------------------------------- data checks


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
        assert 1 <= len(item["title"]) <= 120, f"{where}: title length"
        assert len(item["tags"]) <= 10 and all(len(t) <= 30 for t in item["tags"]), f"{where}: tags"
        assert item["hours_ago"] > 0, f"{where}: hours_ago must be > 0"
    return listings


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
    for user, key, _ in SAVES:
        assert user in USERS and key in by_key and by_key[key]["owner"] != user, f"bad save {key}"
    return status


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
          now: datetime) -> set[str]:
    """Insert the demo campus. Returns the photo paths it uses."""
    def ago(hours: float) -> datetime:
        return (now - timedelta(hours=hours)).replace(microsecond=0)

    db.add_all(Dorm(campus_id=campus.id, name=n, created_at=ago(24 * 30)) for n in DORMS)
    spots = {n: MeetupSpot(campus_id=campus.id, name=n, created_at=ago(24 * 30))
             for n in MEETUP_SPOTS}
    db.add_all(spots.values())

    existing = {u.email: u for u in db.scalars(select(User).where(User.campus_id == campus.id))}
    users: dict[str, User] = {}
    for key, (name, dorm, year, top, bottom, shoe, days) in USERS.items():
        email = f"{key}@{DOMAIN}"
        user = existing.get(email) or User(email=email, campus_id=campus.id)
        user.name, user.dorm, user.class_year = name, dorm, year
        user.size_top, user.size_bottom, user.size_shoe = top, bottom, shoe
        user.avatar_photo_id = None
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
        db.add(req)
        db.flush()
        msgs = []
        for side, hours, body in r.get("messages", []):
            sender = listing.owner_id if side == "owner" else req.requester_id
            msg = Message(request_id=req.id, sender_id=sender, body=body, created_at=ago(hours))
            db.add(msg)
            db.flush()
            msgs.append(msg)
            events.append(hours)
        ids = [m.id for m in msgs]
        owner_n = r.get("owner_read", len(ids))
        requester_n = r.get("requester_read", len(ids))
        req.owner_last_read_id = ids[owner_n - 1] if owner_n else 0
        req.requester_last_read_id = ids[requester_n - 1] if requester_n else 0
        # updated_at: the latest event (accept/complete/message), like the API leaves it.
        req.updated_at = ago(min(h for h in events if h is not None))

    for user_key, listing_key, hours in SAVES:
        db.add(Save(user_id=users[user_key].id, listing_id=rows[listing_key].id,
                    created_at=ago(hours)))
    db.flush()
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
    counts = {s: list(status.values()).count(s) for s in ("active", "pending", "completed")}
    print(f"manifest ok: {len(listings)} listings {counts}, {len(USERS)} users, "
          f"{len(REQUESTS)} requests, {len(SAVES)} saves")
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
        used = build(db, campus, listings, status, utcnow())
        db.commit()
        campus_id = campus.id

    seed_dir = media_dir() / MEDIA_SUBDIR
    stale = {f"{MEDIA_SUBDIR}/{p.name}" for p in seed_dir.glob("*") if p.is_file()}
    removed = remove_files((old_paths | stale) - used)
    print(f"seeded {DOMAIN} (campus {campus_id}): {len(DORMS)} dorms, {len(MEETUP_SPOTS)} spots, "
          f"{len(used)} photos in {seed_dir}, removed {removed} old files")
    print("demo accounts: " + ", ".join(DEMO_ACCOUNTS))
    return 0


def main(argv: list[str]) -> int:
    return run(check_only="--check" in argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
