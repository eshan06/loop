"""The one command before a demo (S-25): put the demo campus back to its clean state.

Run on the server from backend/ (or from the Mac: `bash scripts/reseed.sh`):

    .venv/bin/python -m seed.reset           # reseed + clean up + summary + check
    .venv/bin/python -m seed.reset --check   # validate the seed data and check the live
                                             # demo campus is still clean; changes nothing

A full run:
1. Reseeds vanderbilt.edu (seed/seed.py: wipe the campus, rebuild it, timestamps relative
   to now).
2. Deletes the scratch campuses in SCRATCH_CAMPUSES (smoke.edu, smokeother.edu: the smoke test's
   throwaway users) with SQL deletes that cascade: listings (requests, messages, saves,
   reports), users (sessions, photos, notifications, badges), then the campus row (spots,
   dorms, events, bins). The next smoke run's first login recreates the campus.
3. Deletes orphan uploads: files directly in MEDIA_DIR named like app/photos.py names
   them (32 hex chars + .jpg) that no `photos` row points at and that are older than
   ORPHAN_MIN_AGE_S (so an upload in flight is never touched). Nothing else in
   MEDIA_DIR is ever deleted here (seed photos in MEDIA_DIR/seed/ are seed.py's job).
4. Prints a short summary and runs the live check (the same one `--check` runs).

Idempotent: a second run leaves the same state (new ids and "now", same story).
"""

from __future__ import annotations

import re
import subprocess
import sys
import time
from datetime import timedelta
from pathlib import Path

from sqlalchemy import String, cast, func, or_, select, text
from sqlalchemy.orm import Session

from app import badges
from app.db import SessionLocal, get_engine
from app.models import Campus, Listing, Notification, Photo, Request, User, utcnow
from app.routers.stats import dorm_board
from seed import seed

SCRATCH_CAMPUSES = ("smoke.edu", "smokeother.edu")  # scripts/smoke.sh's throwaway campuses
GENERATED_NAME = re.compile(r"^[0-9a-f]{32}\.jpg$")  # app/photos.py save_photo
ORPHAN_MIN_AGE_S = 600
STALE_AFTER_H = 24  # the leaderboard tie and "live" events drift after about a day


# --------------------------------------------------------------------------- clean up


def purge_campus(db: Session, domain: str) -> dict[str, int] | None:
    """Delete a scratch campus and everything on it. None if it doesn't exist."""
    cid = db.scalar(text("SELECT id FROM campuses WHERE email_domain = :d"), {"d": domain})
    if cid is None:
        return None
    p = {"c": cid}
    counts = {
        "users": db.scalar(text("SELECT COUNT(*) FROM users WHERE campus_id = :c"), p),
        "listings": db.scalar(text("SELECT COUNT(*) FROM listings WHERE campus_id = :c"), p),
    }
    # listings.campus_id and users.campus_id don't cascade, so children first.
    db.execute(text("DELETE FROM listings WHERE campus_id = :c"), p)
    db.execute(text("DELETE FROM users WHERE campus_id = :c"), p)
    db.execute(text("DELETE FROM campuses WHERE id = :c"), p)
    return counts


def orphan_files(db: Session) -> tuple[list[Path], int]:
    """(generated upload files no photos row uses and old enough to delete, how many
    generated files are in use)."""
    root = seed.media_dir()
    if not root.is_dir():
        return [], 0
    referenced = set(db.scalars(select(Photo.path)))
    cutoff = time.time() - ORPHAN_MIN_AGE_S
    orphans, in_use = [], 0
    for f in root.iterdir():
        if not (f.is_file() and not f.is_symlink() and GENERATED_NAME.match(f.name)):
            continue
        if f.name in referenced:
            in_use += 1
        elif f.stat().st_mtime < cutoff:
            orphans.append(f)
    return orphans, in_use


# --------------------------------------------------------------------------- check


def _jacket_hits(db: Session, campus_id: int) -> int:
    pattern = f"%{seed.DEMO_SEARCH}%"
    return db.scalar(
        select(func.count(Listing.id)).where(
            Listing.campus_id == campus_id, Listing.status == "active",
            or_(func.lower(Listing.title).like(pattern), func.lower(Listing.brand).like(pattern),
                func.lower(cast(Listing.tags, String)).like(pattern)))
    )


def live_check(db: Session) -> list[str]:
    """Is the live demo campus in its seeded state? Returns problems (empty = clean).
    Read-only."""
    problems: list[str] = []
    listings = seed.load_manifest()
    by_key = {i["key"]: i for i in listings}
    status = seed.check_activity(listings)

    campus = db.scalar(select(Campus).where(Campus.email_domain == seed.DOMAIN))
    if campus is None:
        return [f"{seed.DOMAIN} doesn't exist: run the reseed"]
    users = {u.email.split("@")[0]: u for u in
             db.scalars(select(User).where(User.campus_id == campus.id))}
    if set(users) != set(seed.USERS):
        problems.append(f"users: extra {sorted(set(users) - set(seed.USERS))}, "
                        f"missing {sorted(set(seed.USERS) - set(users))}")
    p1, p2 = users.get(seed.DEMO_PHONE_1), users.get(seed.DEMO_PHONE_2)
    if p1 is None or p2 is None:
        return problems + ["a demo phone account is missing"]

    # Phone 1 signed up USERS[...][6] days before the seed ran.
    seeded_at = p1.created_at + timedelta(days=seed.USERS[seed.DEMO_PHONE_1][6])
    age_h = (utcnow() - seeded_at).total_seconds() / 3600
    if age_h > STALE_AFTER_H:
        problems.append(f"seeded {age_h:.0f} h ago (> {STALE_AFTER_H} h): reseed before the demo")

    have = dict(db.execute(select(Listing.status, func.count()).where(Listing.campus_id == campus.id)
                           .group_by(Listing.status)).all())
    want = {s: list(status.values()).count(s) for s in set(status.values())}
    if have != want:
        problems.append(f"listings by status {have} != seeded {want} (someone posted or traded)")

    b1 = {b["id"]: b for b in badges.badges_for(db, p1)}
    b2 = {b["id"]: b for b in badges.badges_for(db, p2)}
    goal = b1["closet_cleanout"]["goal"]
    if b1["closet_cleanout"]["progress"] != goal - 1 or b1["closet_cleanout"]["earned_at"]:
        problems.append(f"Phone 1 Closet Cleanout is {b1['closet_cleanout']['progress']}/{goal}, "
                        f"not {goal - 1}/{goal}")
    for who, b in (("Phone 1", b1), ("Phone 2", b2)):
        if b["first_swap"]["earned_at"]:
            problems.append(f"{who} already has First Swap")

    pair = db.scalar(
        select(func.count(Request.id)).join(Listing, Listing.id == Request.listing_id).where(
            or_((Listing.owner_id == p1.id) & (Request.requester_id == p2.id),
                (Listing.owner_id == p2.id) & (Request.requester_id == p1.id))))
    if pair:
        problems.append(f"{pair} request(s) between the demo phones already")

    board = [(r.dorm, r.items_shared) for r in dorm_board(db, campus.id)]
    want_board = seed.board_order(seed.expected_board(by_key))
    if board != want_board:
        problems.append(f"leaderboard {board[:3]} != seeded {want_board[:3]}")

    hits = _jacket_hits(db, campus.id)
    if hits > 3:
        problems.append(f"{hits} active listings match {seed.DEMO_SEARCH!r} (want <= 3)")

    want_unread = {k: n for k, n in seed.expected_unread(by_key).items() if n}
    unread = {k: n for k, n in seed.unread_by_user(db, users).items() if n}
    if unread.get(seed.DEMO_PHONE_1) != want_unread.get(seed.DEMO_PHONE_1):
        problems.append(f"Phone 1 has {unread.get(seed.DEMO_PHONE_1, 0)} unread notifications, "
                        f"seeded {want_unread.get(seed.DEMO_PHONE_1, 0)}")

    root = seed.media_dir()
    paths = db.scalars(select(Photo.path).join(User, User.id == Photo.owner_id)
                       .where(User.campus_id == campus.id)).all()
    missing = [p for p in paths if not (root / p).is_file()]
    if missing:
        problems.append(f"{len(missing)} demo photo files missing on disk, e.g. {missing[0]}")
    return problems


def summary(db: Session) -> list[str]:
    out = []
    campus = db.scalar(select(Campus).where(Campus.email_domain == seed.DOMAIN))
    rows = db.execute(text(
        "SELECT c.email_domain, (SELECT COUNT(*) FROM users u WHERE u.campus_id = c.id), "
        "(SELECT COUNT(*) FROM listings l WHERE l.campus_id = c.id) FROM campuses c "
        "ORDER BY c.email_domain")).all()
    out.append("campuses: " + "; ".join(f"{d} {u} users {n} listings" for d, u, n in rows))
    if campus is not None:
        board = dorm_board(db, campus.id)
        out.append("leaderboard: " + ", ".join(f"#{r.rank} {r.dorm} {r.items_shared}"
                                               for r in board[:4]) + ", ...")
        for key in (seed.DEMO_PHONE_1, seed.DEMO_PHONE_2):
            u = db.scalar(select(User).where(User.email == f"{key}@{seed.DOMAIN}"))
            if u is None:
                continue
            bs = ", ".join(f"{b['name']} {b['progress']}/{b['goal']}" for b in badges.badges_for(db, u))
            unread = db.scalar(select(func.count(Notification.id)).where(
                Notification.user_id == u.id, Notification.read_at.is_(None)))
            out.append(f"{key}: {bs}; {unread} unread")
    root = seed.media_dir()
    files = [f for f in root.rglob("*") if f.is_file()] if root.is_dir() else []
    out.append(f"media: {len(files)} files, {sum(f.stat().st_size for f in files) / 2**20:.1f} MB "
               f"in {root}")
    try:
        head = subprocess.run(["git", "log", "-1", "--format=%h %s"], capture_output=True,
                              text=True, cwd=Path(__file__).resolve().parent, timeout=5).stdout.strip()
        out.append(f"server code: {head}")
    except Exception:  # noqa: BLE001
        pass
    return out


def check(db: Session) -> int:
    problems = live_check(db)
    if problems:
        print("CHECK FAILED: the demo campus isn't in its seeded state:")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"check ok: {seed.DOMAIN} matches the seed (badges, leaderboard, inbox, search, photos)")
    return 0


# --------------------------------------------------------------------------- main


def main(argv: list[str]) -> int:
    if "--check" in argv[1:]:
        print("== seed data")
        seed.run(check_only=True)
        print("== live demo campus")
        with SessionLocal(bind=get_engine()) as db:
            for line in summary(db):
                print(f"  {line}")
            return check(db)

    print("== reseed")
    seed.run()

    print("== clean up")
    with SessionLocal(bind=get_engine()) as db:
        for domain in SCRATCH_CAMPUSES:
            gone = purge_campus(db, domain)
            print(f"  {domain}: " + (f"deleted {gone['users']} users, {gone['listings']} listings"
                                     if gone else "nothing to delete"))
        db.commit()
        orphans, in_use = orphan_files(db)
        freed = 0
        for f in orphans:
            freed += f.stat().st_size
            f.unlink()
        print(f"  media: deleted {len(orphans)} orphan uploads ({freed / 2**20:.1f} MB), "
              f"{in_use} uploads in use kept")

    print("== summary")
    with SessionLocal(bind=get_engine()) as db:
        for line in summary(db):
            print(f"  {line}")
        return check(db)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
