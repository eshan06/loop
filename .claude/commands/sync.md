---
description: Pull the latest main, read the other lane's log, and pick the next task
---

Run `bash scripts/sync.sh` from the repo root and read its output carefully.

Then:

1. If `docs/API.md` changed, list every change that affects code in this lane before doing anything else.
2. If the other lane's coord file has an open request addressed to this lane, list it and ask me whether to handle it now.
3. Look at this lane's open tasks in `PLAN.md`. Recommend the next one, skipping tasks marked `[!]` and tasks that depend on something the other lane hasn't shipped yet. Say what you'd do first.

Don't edit any files during `/sync`.
