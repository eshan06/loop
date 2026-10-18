# Live end-to-end run, 2026-10-17 (ios lane, Simulators)

Two Simulators against `http://163.192.218.131:8000`: iPhone 15 Pro = Jordan (owner), iPhone 15 = Sam (requester).
Driven by `ios/LoopUITests/LiveE2ETests.swift` (one phase per test, opt-in with `TEST_RUNNER_LOOP_E2E=<A-F>`);
state checked with `ios/Tools/live-state.py` (read-only). Start state was the clean S-25 seed.

| Phase | What | Result |
| --- | --- | --- |
| Raw `/scan` (curl, same 3 photos) | front + back + tag photo, `kinds=front,back,label`, on-device-style labels | 200 in 5.4 s, `source: "vision"`, "Levi's denim trucker jacket", outerwear, M, Light blue, Levi's, good, condition_note "light fading on seams", tags denim/trucker/jacket/light blue |
| A Jordan scan + post (in the app) | 3 photos from the library, real picker | Review in 3.0 s (app side), "Filled in by AI" banner, title "Classic Levi's denim trucker jacket", Levi's, Light blue, Outerwear, M, good. Posted as listing 1762, photos front/back/label. Closet Cleanout 10/10 earned at posting, `badge_earned` notification written. |
| B Sam request | search "jacket", top result is the new listing, Request + Send | request 999, status pending. Jordan's idle client moved on its own (bell 3 to 5, Requests 3 to 4). |
| C Jordan accept + write | accepted the Accept button in the jacket's row, sent a message | request 999 accepted, listing 1762 pending, the two Converse requests untouched. Sam got `request_accepted` and `new_message`. |
| D Sam reply | thread shows Jordan's message, Sam replied | both messages stored |
| E Jordan complete | Mark exchange done, confirm | request completed, listing completed. Celebration shows 0.4 kg, 3,135 L, 10 kg and "Badge unlocked: First Swap". |
| F Sam sees it | Requests row says Completed, thread, profile | First Swap earned, impact 0.44 kg / 3,135 L / 10.3 kg as `items_received` 1 |

Server numbers after the run: Jordan impact 1 shared (0.44 kg, 3,135 L, 10.3 kg CO2), First Swap + Closet Cleanout earned;
Sam 1 received, First Swap earned; campus 10 to 11 rehomed, top dorm E. Bronson Ingram to Kissam; leaderboard Kissam 3 alone at #1.
All match "Before the demo" in `coord/server.md`.

AI source: Oracle vision (`source: "vision"`) in the raw call. The app does not show `source`, only a banner for
`vision` or `labels` and a failure state for `none`, so the app run was identified as vision by its detailed fields and
the matching raw call, not by a flag. Not mock, not the fallback path. Two earlier app scans picked stock landscape
photos by mistake (test bug, fixed): the app showed "Couldn't fill this in automatically" and nothing was posted.

Not covered: banner animation (transient, missed by the screenshots), the thread's live "completed" poll while a thread
is open on Sam's side (needs a second exchange), a real camera, and `condition_note`: the app drops it, so listing 1762
has `condition_note: null` although the draft had one (IOS-3, not built).
