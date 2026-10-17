---
description: Log what this lane just did, update PLAN.md, commit, and push
---

Read this machine's lane from `.lane` (`ios` or `server`). Only edit files that belong to that lane, as listed in `CLAUDE.md`.

1. Add a new entry at the top of the Log section in `coord/<lane>.md`, dated today, with up to five short lines:
   - Done: tasks finished since the last entry, by ID.
   - Now: what's next.
   - Needs: new requests for the other lane. Also add each one under "Open requests" with the next free ID.
   - Contract: (server lane only) any change to `docs/API.md`. Also add it under "Contract changes".
   - Heads-up: anything that could break the other lane, like a renamed field, a server restart, or new seed data.
   Leave out any line that has nothing in it.
2. If the other lane answered one of this lane's requests, move it to "Closed requests" with a short note.
3. In `PLAN.md`, update the status marks on this lane's tasks only (`I-` for ios, `S-` for server). Don't touch the other lane's lines.
4. (server lane only) If the server's API URL, the vision model check, or the demo accounts changed, update "Server status" in `coord/server.md`.
5. Show me the diff, then commit with a message that starts with the lane, like `ios: feed filters (I-11)`. Don't add a `Co-Authored-By` line or a "Generated with Claude Code" line.
6. Run `git pull --rebase`, then `git push`. If the push is rejected, pull with rebase again and retry. If there's a conflict in a file this lane doesn't own, stop and tell me rather than resolving it.
