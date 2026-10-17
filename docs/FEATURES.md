# Features

Loop is a college-only clothing exchange. Students scan an item, AI writes the listing, and other students on the same campus can request it as a swap, take it for free, or the owner can donate it.

The mission behind it: keep clothes out of landfills, make clothes cheaper for students, and get a circular clothing economy going on campus.

Features are split into three tiers. Tier 1 has to work end to end before anyone starts Tier 2. Each feature lists what the iOS lane builds and what the server lane builds; the task IDs point to `PLAN.md`.

## Tier 1: the core demo

### Sign-in and profile
- Sign in with a .edu email. Anything else is rejected with a clear message.
- The campus comes from the email domain, so a `vanderbilt.edu` address lands you in the Vanderbilt feed.
- Profile setup: name, photo, class year, dorm, and usual sizes (top, bottom, shoe).
- iOS: I-8. Server: S-8, S-9.

Sign-in is demo-grade. There's no email verification code; entering a valid .edu address logs you in.

### Scan to listing
- Camera flow with three guided shots: front, back, and the label. Upload from the photo library also works.
- AI fills in title, category, size, color, brand, condition, a short description, and search tags.
- Every field stays editable before posting.
- The owner picks a share type (Swap, Free, or Donate) and a meetup spot from a fixed list for their campus.
- If the AI call fails or times out, the form opens empty instead of blocking the user.
- iOS: I-9, I-10. Server: S-9, S-10.

### Feed
- Two-column grid of listings from your campus only.
- Filter chips for share type, plus category and size filters.
- Search across title, brand, and tags.
- Pull to refresh.
- iOS: I-11. Server: S-11.

### Item detail
- Photo carousel, the AI tags as chips, condition, size, and meetup spot.
- Owner card with name, dorm, and how many items they've shared.
- Request button. It changes to "Requested" once you've sent one.
- iOS: I-12. Server: S-11.

### Requests and chat
- Send a request with an optional note.
- The owner accepts or declines. Accepting one request declines the rest on that listing.
- An accepted request opens a chat thread. The app polls for new messages every 3 seconds while the chat is open.
- Either person can mark the exchange done, which moves the listing to Completed and counts toward impact.
- iOS: I-13, I-14. Server: S-12, S-13.

### Profile
- My listings, with Active and Completed tabs.
- Edit or delete a listing.
- iOS: I-15. Server: S-11.

### Seed data
- 30 to 40 listings with real photos of the team's clothes, spread across dorms and share types, so the feed looks alive.
- Three demo accounts for the live demo.
- Server: S-15.

## Tier 2: what makes it impressive

### Impact tracker
- Each completed exchange adds an estimate of textile kept out of landfill, water saved, and CO₂ avoided, looked up by category.
- Personal totals on the profile and an Impact screen. Campus totals for the week on a banner at the top of the feed.
- The per-category numbers come from one published source, cited in a comment next to the table, so the team can answer if a judge asks where they're from.
- iOS: I-18. Server: S-17.

### Saved items
- Heart on feed cards and item detail, and a Saved tab.
- iOS: I-19. Server: S-18.

### Similar items
- A row of similar listings on item detail, matched by shared tags and category.
- iOS: I-20. Server: S-19.

### Style it
- A button on item detail. The text model suggests two or three outfit ideas built around the item.
- iOS: I-21. Server: S-20.

### Dorm leaderboard
- Dorms ranked by items shared this week.
- iOS: I-22. Server: S-21.

### Badges
- First Swap: completed one exchange.
- Giving Back: donated five items.
- Closet Cleanout: listed ten items.
- Shown on the profile, earned ones in color and the rest grayed out.
- iOS: I-23. Server: S-22.

### Notifications
- In-app only, no push. A bell with an unread count and a list.
- Events: someone requested your item, your request was accepted or declined, a new message, a badge earned.
- iOS: I-24. Server: S-23.

### Report a listing
- A report button on item detail. Three reports hide the listing.
- iOS: I-25. Server: S-24.

## Tier 3: only if there's time

- Campus map of donation bins and meetup spots (I-28).
- Swap Day events tab (I-29, S-27).
- Onboarding carousel that explains the mission (I-30).
- A short condition note from the vision model, like "light fading at the cuffs" (S-28).

## Demo path

This is the run the team rehearses, and it's what "integration works" means at sync point C. It needs two phones signed in as two different demo accounts.

1. Phone 1 signs in with a .edu email and lands on the campus feed.
2. Phone 1 taps Scan, photographs a real jacket (front, back, label), and the AI fills in the listing.
3. Phone 1 fixes one field, picks Swap and a meetup spot, and posts. The jacket appears at the top of the feed.
4. Phone 2 finds the jacket through search, opens it, and sends a request.
5. Phone 1 gets the notification, accepts, and the two phones exchange a chat message.
6. Phone 1 marks the exchange done. The impact numbers and the feed banner update.
7. Close on the dorm leaderboard and a badge on the profile.
