"""Per-item impact estimate by category: the `impact` object on a Listing.

PROVISIONAL (added with S-11 so Listing has an `impact` object): rough typical
item weights times rough per-kg water and CO2 factors. S-17 replaces this table
with numbers from one published source, cited here, keeping `impact_for()`'s
signature so the Listing serializer doesn't change.
"""

from __future__ import annotations

# category -> (textile_kg, water_l, co2_kg) for one typical item.
IMPACT_BY_CATEGORY: dict[str, tuple[float, float, float]] = {
    "tops": (0.25, 2700, 5.0),
    "bottoms": (0.6, 7500, 12.0),
    "outerwear": (1.0, 10000, 20.0),
    "dresses": (0.4, 4000, 8.0),
    "shoes": (0.9, 4000, 14.0),
    "accessories": (0.15, 1000, 2.5),
    "bags": (0.5, 3000, 8.0),
}
_DEFAULT = (0.4, 4000, 8.0)


def impact_for(category: str | None) -> dict[str, float]:
    """{"textile_kg", "water_l", "co2_kg"} for one item of this category."""
    textile, water, co2 = IMPACT_BY_CATEGORY.get(category or "", _DEFAULT)
    return {"textile_kg": round(textile, 2), "water_l": round(water), "co2_kg": round(co2, 1)}
