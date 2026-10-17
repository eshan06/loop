# Server lane log

Only the server machine (the one with the OCI account) edits this file. The iOS lane reads it after every pull.

Add new log entries at the top of the Log section, newest first. Keep each entry short. `/handoff` writes them for you.

## Server status

- API base URL: not deployed yet
- Vision model (`cohere.command-a-vision`) available on our account: not checked yet
- Demo accounts: not seeded yet

Keep this block current. It's the first thing the iOS lane looks at.

## Contract changes

Every change to `docs/API.md` gets a line here: what changed and whether the iOS lane needs to update anything.

None yet.

## Open requests to the iOS lane

Give each request an ID (`SRV-1`, `SRV-2`, ...). Move it to "Closed requests" once the iOS lane answers in `coord/ios.md`.

None yet.

## Closed requests

None yet.

## Log

### 2026-10-17 — lane created
- Now: nothing in progress. Start with Phase 0 in `PLAN.md`.
