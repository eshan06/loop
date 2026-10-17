"""Style it: two or three outfit ideas for a listing (POST /listings/{id}/style).

    ideas_for(db, listing) -> list[{"title", "description"}]     never raises

Ideas come from the text model (cohere.command-a-03-2025) prompted with the listing's
title, category, color and tags, and are cached in `listings.style_ideas` as

    {"basis": "<hash of title/category/color/tags>", "ideas": [...]}

so a repeat call is instant and an edit to those fields regenerates them. If the
model fails or takes longer than STYLE_TIMEOUT, the caller gets template ideas built
from the category and color instead; those are never cached, so the next call tries
the model again.

Quick check on the server (from backend/):
    .venv/bin/python -m app.style "Vintage denim jacket" outerwear "Light wash blue" denim,vintage
"""

from __future__ import annotations

import hashlib
import json
import logging
import sys
import time
from concurrent.futures import TimeoutError as FutureTimeout
from typing import Any

from pydantic import BaseModel, field_validator
from sqlalchemy.orm import Session

from . import ai
from .models import Listing

log = logging.getLogger("loop.style")

STYLE_TIMEOUT = 15.0  # seconds the endpoint gives the model before using templates (calls take ~3-7 s)
MIN_IDEAS, MAX_IDEAS = 2, 3
TITLE_MAX, DESCRIPTION_MAX = 40, 200


# --------------------------------------------------------------------------- validation


class StyleIdea(BaseModel):
    title: str
    description: str

    @field_validator("title", "description", mode="before")
    @classmethod
    def _text(cls, value: Any, info) -> str:
        cap = TITLE_MAX if info.field_name == "title" else DESCRIPTION_MAX
        text = ai._clean_str(value, 10_000)
        if not text:
            raise ValueError("empty")
        text = text.strip("\"'*#").strip()
        if info.field_name == "title":
            text = text.rstrip(".:!").strip()
        if len(text) > cap:  # cut at a word boundary
            text = text[:cap].rsplit(" ", 1)[0].rstrip(",;:-") + ("" if info.field_name == "title" else ".")
        if not text:
            raise ValueError("empty")
        return text


def validate_ideas(raw: Any) -> list[dict[str, str]]:
    """A list of ideas -> 2 or 3 clean ideas. Raises ValueError if fewer than 2 are usable."""
    if not isinstance(raw, list):
        raise ValueError("ideas is not a list")
    ideas: list[dict[str, str]] = []
    for item in raw:
        try:
            idea = StyleIdea.model_validate(item).model_dump()
        except Exception:  # noqa: BLE001 - skip a bad idea, keep the good ones
            continue
        if idea["title"].lower() not in (i["title"].lower() for i in ideas):
            ideas.append(idea)
    if len(ideas) < MIN_IDEAS:
        raise ValueError(f"only {len(ideas)} usable ideas")
    return ideas[:MAX_IDEAS]


def parse_reply(reply: str) -> list[dict[str, str]]:
    obj = ai.extract_json(reply)
    return validate_ideas(obj.get("ideas"))


# --------------------------------------------------------------------------- cache


def basis(title: str | None, category: str | None, color: str | None, tags: Any) -> str:
    """Hash of the fields the prompt uses; a cached entry is valid only while it matches."""
    clean_tags = [str(t).strip().lower() for t in (tags or []) if str(t).strip()]
    key = json.dumps([(title or "").strip(), category or "", (color or "").strip().lower(), clean_tags])
    return hashlib.sha1(key.encode()).hexdigest()[:16]


def listing_basis(listing: Listing) -> str:
    return basis(listing.title, listing.category, listing.color, listing.tags)


def cached(listing: Listing) -> list[dict[str, str]] | None:
    """The listing's cached ideas if present, current and well formed; else None."""
    entry = listing.style_ideas
    if not isinstance(entry, dict) or entry.get("basis") != listing_basis(listing):
        return None
    try:
        return validate_ideas(entry.get("ideas"))
    except ValueError:
        return None


def cache_entry(listing_or_basis: Listing | str, ideas: list[dict[str, str]]) -> dict:
    b = listing_or_basis if isinstance(listing_or_basis, str) else listing_basis(listing_or_basis)
    return {"basis": b, "ideas": ideas}


# --------------------------------------------------------------------------- model


def prompt(title: str, category: str | None, color: str | None, tags: Any) -> str:
    tag_text = ", ".join(str(t) for t in (tags or [])) or "none"
    return (
        "You give outfit ideas in Loop, an app where college students swap and give away "
        "clothes on their campus. A student is looking at this secondhand item:\n"
        f"- title: {title}\n"
        f"- category: {category or 'unknown'}\n"
        f"- color: {color or 'not given'}\n"
        f"- tags: {tag_text}\n"
        "Suggest 3 outfits built around this exact item, each with a clearly different vibe "
        "(for example relaxed, put-together, cozy, sporty, going out; pick what suits the item). "
        "Each one pairs it with 2 or 3 concrete everyday pieces named by type and color (like "
        "\"a gray hoodie\", \"black jeans\", \"white sneakers\") whose colors work with the "
        "item's color. Describe how this kind of item is actually worn (a hat goes on your head, "
        "shoes go with pants, a bag is carried). Casual, friendly college-student voice.\n"
        "Never mention brands, stores, prices or buying anything new. No emoji, no hashtags.\n"
        "Reply with ONLY one JSON object, no markdown and no other text:\n"
        '{"ideas": [{"title": string, "description": string}]}\n'
        "- title: 2 to 4 words in Title Case that name the look itself, like \"Weekend Layers\" "
        "or \"Black and Cream\". Avoid generic titles like \"Game Day Spirit\" or "
        "\"Casual Class Day\".\n"
        "- description: one sentence, at most 120 characters, like "
        "\"Over a gray hoodie with black jeans and white sneakers.\" Don't repeat the item's name; "
        "start with how to wear it."
    )


def generate(title: str, category: str | None, color: str | None, tags: Any,
             timeout: float = STYLE_TIMEOUT) -> list[dict[str, str]]:
    """Ideas from the text model. Raises on failure, bad JSON or timeout."""
    text = prompt(title, category, color, tags)
    future = ai._pool.submit(ai.text_chat, text, 500, 0.8)
    try:
        reply = future.result(timeout=timeout)
    except FutureTimeout as exc:
        raise TimeoutError(f"style: no reply after {timeout:.0f}s") from exc
    return parse_reply(reply)


# --------------------------------------------------------------------------- templates

# Used only when the model fails, so the sheet is never empty. {it} is "the <color>
# <item>", e.g. "the light wash blue jacket" ("the jacket" without a color).
_TEMPLATES: dict[str, list[tuple[str, str]]] = {
    "tops": [
        ("Easy Class Fit", "Tuck {it} into light-wash jeans and finish with white sneakers."),
        ("Layered Up", "Wear it under an open flannel with black jeans and canvas high-tops."),
        ("Game Day Ready", "Pair it with denim shorts, a ball cap and clean low-top sneakers."),
    ],
    "bottoms": [
        ("Everyday Campus", "Pair {it} with a plain white tee and white sneakers."),
        ("Cozy Library Night", "Go with an oversized gray hoodie and comfy slip-on shoes."),
        ("Night Out", "Dress them up with a fitted black top and simple ankle boots."),
    ],
    "outerwear": [
        ("Weekend Layers", "Throw {it} over a gray hoodie with black jeans and white sneakers."),
        ("Clean Lines", "Layer it over a white tee with dark straight-leg jeans and boots."),
        ("Career Fair Ready", "Wear it over a button-down with chinos and loafers."),
    ],
    "dresses": [
        ("Sunny Afternoon", "Wear {it} with white sneakers and a denim jacket."),
        ("Cooler Days", "Layer it with black tights, a chunky cardigan and ankle boots."),
        ("Night Out", "Add strappy sandals, small hoops and a mini shoulder bag."),
    ],
    "shoes": [
        ("Everyday Rotation", "Wear {it} with straight-leg jeans and a crewneck sweatshirt."),
        ("Off to Class", "Go with relaxed chinos, a plain tee and a canvas backpack."),
        ("Weekend Mode", "Pair them with shorts or joggers and a cozy oversized hoodie."),
    ],
    "accessories": [
        ("Finishing Touch", "Add {it} to a white tee and jeans to pull the look together."),
        ("Cozy Layers", "Pair it with a neutral sweater, dark jeans and boots."),
        ("Game Day", "Style it with a team tee, denim shorts and clean sneakers."),
    ],
    "bags": [
        ("Daily Carry", "Take {it} to class with jeans, a crewneck and sneakers."),
        ("Weekend Errands", "Pair it with leggings, an oversized hoodie and slides."),
        ("Night Out", "Go with a black top, straight-leg jeans and ankle boots."),
    ],
}
_ITEM_NAME = {"tops": "top", "bottoms": "bottoms", "outerwear": "jacket", "dresses": "dress",
              "shoes": "shoes", "accessories": "piece", "bags": "bag"}


def template_ideas(category: str | None, color: str | None) -> list[dict[str, str]]:
    rows = _TEMPLATES.get(category or "", _TEMPLATES["tops"])
    color_text = " ".join((color or "").lower().split())
    it = " ".join(["the", color_text, _ITEM_NAME.get(category or "", "piece")]).replace("  ", " ")
    out = [{"title": title, "description": desc.format(it=it)} for title, desc in rows]
    return validate_ideas(out)


# --------------------------------------------------------------------------- endpoint helper


def ideas_for(db: Session, listing: Listing) -> list[dict[str, str]]:
    """Cached ideas, else fresh ones from the model (cached), else templates (not cached)."""
    hit = cached(listing)
    if hit is not None:
        return hit
    start = time.monotonic()
    b = listing_basis(listing)
    try:
        ideas = generate(listing.title, listing.category, listing.color, listing.tags)
    except Exception as exc:  # noqa: BLE001 - any failure means "use the templates"
        log.warning("style: listing %s failed after %.1fs: %s", listing.id,
                    time.monotonic() - start, ai._describe(exc))
        return template_ideas(listing.category, listing.color)
    log.info("style: listing %s ok in %.1fs", listing.id, time.monotonic() - start)
    # Last write wins if two calls race; both wrote valid ideas for the same basis.
    if listing_basis(listing) == b:
        listing.style_ideas = cache_entry(b, ideas)
        db.commit()
    return ideas


# --------------------------------------------------------------------------- CLI


def _main(argv: list[str]) -> int:
    title = argv[1] if len(argv) > 1 else "Vintage denim trucker jacket"
    category = argv[2] if len(argv) > 2 else "outerwear"
    color = argv[3] if len(argv) > 3 else "Light wash blue"
    tags = argv[4].split(",") if len(argv) > 4 else ["denim", "vintage"]
    start = time.monotonic()
    print(json.dumps(generate(title, category, color, tags), indent=2))
    print(f"{time.monotonic() - start:.1f}s")
    print(json.dumps(template_ideas(category, color), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
