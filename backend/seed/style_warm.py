"""(Re)generate the "Style it" snapshot for the demo listings: seed/style_ideas.json.

Run on the server, from backend/ (it calls the text model, about 2 s per listing):

    .venv/bin/python -m seed.style_warm           # only listings with no current ideas
    .venv/bin/python -m seed.style_warm --force   # regenerate every listing

Then copy the file back to the Mac and commit it (or commit on the server), so
seed.py bakes the ideas into `listings.style_ideas` on every reseed without calling
the AI. An entry stays current while its listing's title, category, color and tags
in manifest.json are unchanged (the "basis" hash); seed.py skips stale entries.
"""

from __future__ import annotations

import json
import sys
import time

from app import style
from seed.seed import STYLE_FILE, item_basis, load_manifest

RETRIES = 2


def main(argv: list[str]) -> int:
    force = "--force" in argv[1:]
    listings = load_manifest()
    snapshot: dict[str, dict] = {}
    if STYLE_FILE.is_file():
        snapshot = json.loads(STYLE_FILE.read_text()).get("listings", {})
    keys = {item["key"] for item in listings}
    snapshot = {k: v for k, v in snapshot.items() if k in keys}  # drop removed listings

    made = failed = 0
    for item in listings:
        b = item_basis(item)
        current = snapshot.get(item["key"], {}).get("basis") == b
        if current and not force:
            continue
        for attempt in range(1, RETRIES + 1):
            start = time.monotonic()
            try:
                ideas = style.generate(item["title"], item["category"], item.get("color"),
                                       item.get("tags"), timeout=30)
            except Exception as exc:  # noqa: BLE001
                print(f"  {item['key']}: attempt {attempt} failed: {exc}")
                continue
            snapshot[item["key"]] = {"basis": b, "ideas": ideas}
            made += 1
            print(f"  {item['key']}: {len(ideas)} ideas in {time.monotonic() - start:.1f}s "
                  f"({', '.join(i['title'] for i in ideas)})")
            # Write after each one so an interrupted run keeps its progress.
            ordered = {i["key"]: snapshot[i["key"]] for i in listings if i["key"] in snapshot}
            STYLE_FILE.write_text(json.dumps({"listings": ordered}, indent=2, ensure_ascii=False) + "\n")
            break
        else:
            failed += 1

    have = sum(1 for item in listings if snapshot.get(item["key"], {}).get("basis") == item_basis(item))
    print(f"generated {made}, failed {failed}; {have}/{len(listings)} listings have current ideas "
          f"in {STYLE_FILE}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
