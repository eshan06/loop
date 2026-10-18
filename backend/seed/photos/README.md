# Seed photos: swapping in the team's real photos

The photos in this folder are placeholders from Wikimedia Commons (see `ATTRIBUTION.md`).
Each seed listing in `manifest.json` names its photo files here. To use the team's own
photos, replace them listing by listing with the steps below. You can swap some and keep
the rest; nothing else in the app changes.

## 1. Take and name the photos

- One item per listing, up to 5 photos: front first (the feed card), then back, label,
  and any others. Plain background, item centered, good light, portrait or square.
- JPEG only (`.jpg`), at most 5 MB each, shortest side at least 300 px. Up to 1600 px on
  the longest side is ideal; larger photos are fine, the seed downscales them (and fixes
  phone rotation from EXIF).
- Name files after the listing's `key`, lowercase, no spaces: `denimjacket.jpg`,
  `denimjacket-back.jpg`, `denimjacket-label.jpg`. To keep a listing's key and just
  replace its photo, overwrite the file with the same name (the seed gives every version
  a new URL, so phones never show a cached old photo).

## 2. Update `manifest.json`

For each listing you replace, edit its entry so the text matches the real item:

| Field | Rules |
| --- | --- |
| `key` | Unique. Don't rename keys used in `REQUESTS` or `SAVES` in `seed.py` (or update those too). |
| `photos` | File names in this folder, in order front, back, label, other. 1 to 5. |
| `owner` | A seed account: the part of the email before `@vanderbilt.edu` (`USERS` in `seed.py`). |
| `title` | 1 to 120 characters. |
| `category` | `tops`, `bottoms`, `outerwear`, `dresses`, `shoes`, `accessories` or `bags`. |
| `size` | The docs/API.md "Sizes" vocabulary for the category: `XS` to `XXL`; bottoms a waist `24` to `40` (or a letter); shoes `5` to `14` in halves (`9.5`); accessories and bags `One size`. |
| `color`, `brand` | Short text, or `null`. |
| `condition` | `new`, `like_new`, `good` or `worn`. |
| `condition_note` | The visible wear, lowercase start, no period, at most 140 characters (`"light pilling under the arms"`). `null` for a `new` item or when there's nothing to say. |
| `share_type` | `swap`, `free` or `donate`. |
| `tags` | Up to 10, each at most 30 characters. |
| `description` | Up to 2000 characters, in the owner's voice. |
| `meetup_spot` | One of `MEETUP_SPOTS` in `seed.py`. |
| `hours_ago` | When it was posted, hours before the reseed. Must be older than any request on it. |

Shortcut for the text: scan the item in the app (any account) and copy what the AI
fills in, including the condition note. The reseed wipes that scan afterwards.

Then delete the replaced placeholder file and its row in `ATTRIBUTION.md` (photos you
took yourselves need no attribution).

Keep the demo story intact (`seed.py`, "The live demo"; `--check` enforces it):
Jordan must keep 6 listings, and at most 3 active listings may mention "jacket" in the
title, brand or tags, so the jacket scanned live tops the search.

## 3. Check, regenerate style ideas, reseed

The Mac has no Python 3.12, so these run on the server. From the repo root on the Mac:

```bash
git add backend/seed/photos && git commit -m "server: real seed photos (S-25)" && git pull --rebase && git push
bash scripts/deploy.sh
ssh -i ~/.ssh/loop-key.pem opc@163.192.218.131
cd ~/loop/backend
.venv/bin/python -m seed.seed --check       # every file exists, JPEG, <= 5 MB, sizes, story
.venv/bin/python -m seed.style_warm         # "Style it" ideas for listings whose title,
                                            # category, color or tags changed (about 2 s each)
exit
```

`--check` lists the listings whose style ideas are stale; `style_warm` regenerates just
those (`--force` redoes all). Copy the result back, commit it, and undo the server's
local copy so the next deploy can pull:

```bash
scp -i ~/.ssh/loop-key.pem opc@163.192.218.131:loop/backend/seed/style_ideas.json backend/seed/
ssh -i ~/.ssh/loop-key.pem opc@163.192.218.131 'git -C ~/loop checkout backend/seed/style_ideas.json'
git add backend/seed/style_ideas.json && git commit -m "server: style ideas for the real photos (S-25)" && git pull --rebase && git push
bash scripts/deploy.sh
bash scripts/reseed.sh            # reseed + clean up + check; must end with "check ok"
bash scripts/smoke.sh             # the demo section checks photos load and ideas are cached
bash scripts/reseed.sh            # smoke leaves smoke.edu data behind; this clears it
```
