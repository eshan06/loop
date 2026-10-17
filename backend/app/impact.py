"""Per-item impact estimate by category: the `impact` object on a Listing, and
the totals behind GET /impact/me and GET /impact/campus.

Where the numbers come from (S-17)
==================================

Each category's estimate is  typical garment mass  x  footprint per kg of clothing.
The footprint per kg is from ONE source (WRAP); the masses are from a second
(Mistra Future Fashion / RISE), because WRAP publishes footprints per tonne, not
per-garment weights.

[1] Footprint per kg of clothing:
    WRAP (2017). "Valuing Our Clothes: the cost of UK fashion". WRAP (Waste and
    Resources Action Programme), UK. July 2017.
    https://www.wrap.ngo/sites/default/files/2020-10/WRAP-valuing-our-clothes-the-cost-of-uk-fashion_WRAP.pdf
    Page 11, Table 3 "Changes in the carbon, water, and process waste footprints
    (per tonne) of UK clothing in active use in 2012 and 2016", 2016 column:
        Carbon  23.2 tonnes CO2e per tonne of clothing  ->  23.2 kg CO2e per kg
        Water   7,060 m3 per tonne of clothing           ->  7,060 litres per kg
    These are whole-life-cycle averages (fibre, processing, manufacture, use,
    end of life) for clothing in use in the UK. (The same table is repeated as
    Table 6 on page 26.)

[2] Typical garment masses:
    Sandin, G., Roos, S., Spak, B., Zamani, B. & Peters, G. (2019).
    "Environmental assessment of Swedish clothing consumption - six garments,
    sustainable futures". Mistra Future Fashion report 2019:05, RISE AB /
    Chalmers University of Technology. ISBN 978-91-89049-05-5.
    https://research.chalmers.se/publication/514322
    (full text: https://research.chalmers.se/publication/514322/file/514322_Fulltext.pdf)
    Printed page 28 (PDF page 26), Table 3.1 "Key modelling parameters for
    the garments selected for the LCA study", row "mass" (measured retail example items):
        T-shirt 110 g, jeans 477 g, dress 478 g, jacket 444 g, socks 43 g.

Mapping to our categories (API.md enum):
    tops         T-shirt 110 g                                         [2]
    bottoms      jeans 477 g                                           [2]
    dresses      dress 478 g                                           [2]
    outerwear    jacket 444 g                                          [2]
    accessories  socks 43 g (smallest garment in [2]; a scarf, hat or belt is
                 also a small item)                                    [2]
    shoes        ASSUMPTION, neither source covers footwear: jeans mass
                 (477 g) as a stand-in for a pair of shoes.
    bags         ASSUMPTION, neither source covers bags: jacket mass (444 g,
                 woven synthetic with zips, the closest construction).
The footprint factors in [1] are for clothing, so applying them to shoes and
bags is an approximation too.

Worked example, tops: 0.110 kg x 23.2 = 2.55 kg CO2e; 0.110 kg x 7,060 = 777 L.

What this means: the footprint of making, using and disposing of one typical
new item of that category, which is what a reused item can stand in for. It is
an estimate for a demo, not an LCA of the specific item. Nothing here is
invented; the two assumptions above are the only numbers not read straight
from a table.
"""

from __future__ import annotations

from collections.abc import Iterable

# [1] WRAP 2017, Table 3, 2016 column.
CO2E_KG_PER_KG = 23.2
WATER_L_PER_KG = 7060.0

# [2] Sandin et al. 2019, Table 3.1 masses, in kg (see the mapping above).
_TSHIRT, _JEANS, _DRESS, _JACKET, _SOCKS = 0.110, 0.477, 0.478, 0.444, 0.043
MASS_KG_BY_CATEGORY: dict[str, float] = {
    "tops": _TSHIRT,
    "bottoms": _JEANS,
    "dresses": _DRESS,
    "outerwear": _JACKET,
    "accessories": _SOCKS,
    "shoes": _JEANS,  # assumption: no footwear mass in either source
    "bags": _JACKET,  # assumption: no bag mass in either source
}
_DEFAULT_MASS = _TSHIRT  # unknown category (shouldn't happen: the API validates the enum)

# category -> (textile_kg, water_l, co2_kg) for one typical item, unrounded.
IMPACT_BY_CATEGORY: dict[str, tuple[float, float, float]] = {
    cat: (kg, kg * WATER_L_PER_KG, kg * CO2E_KG_PER_KG) for cat, kg in MASS_KG_BY_CATEGORY.items()
}
_DEFAULT = (_DEFAULT_MASS, _DEFAULT_MASS * WATER_L_PER_KG, _DEFAULT_MASS * CO2E_KG_PER_KG)


def _raw(category: str | None) -> tuple[float, float, float]:
    return IMPACT_BY_CATEGORY.get(category or "", _DEFAULT)


def _rounded(textile: float, water: float, co2: float) -> dict[str, float]:
    return {"textile_kg": round(textile, 2), "water_l": round(water), "co2_kg": round(co2, 1)}


def impact_for(category: str | None) -> dict[str, float]:
    """{"textile_kg", "water_l", "co2_kg"} for one item of this category."""
    return _rounded(*_raw(category))


def impact_total(categories: Iterable[str | None]) -> dict[str, float]:
    """Summed impact for a list of item categories (one entry per item), rounded once."""
    textile = water = co2 = 0.0
    for category in categories:
        t, w, c = _raw(category)
        textile, water, co2 = textile + t, water + w, co2 + c
    return _rounded(textile, water, co2)
