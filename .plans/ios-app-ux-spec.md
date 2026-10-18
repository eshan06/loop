# Loop iOS app: UX and visual design spec

Status: draft, from the design interview on 2026-10-17
Lane: `ios`
Scope: how the iOS app looks, feels, and behaves screen by screen. The API, data model, and task list are already defined in `docs/API.md`, `docs/ARCHITECTURE.md`, and `PLAN.md`. This spec only covers what those docs leave open, and it lists the contract changes the iOS lane needs.

---

## 1. Principles

1. **Apple-native first.** System font, system materials, SF Symbols, and standard controls. Loop should look like a well-made first-party app. That keeps design risk low and build speed high.
2. **Photos carry the color.** The interface is black and white. The clothing photos are the only colorful part of the screen.
3. **Make the demo path feel great.** Every decision below is weighed against the seven-step demo in `docs/FEATURES.md`. Moments judges see (scan, posting, the notification, completing an exchange, the leaderboard) get the polish budget.
4. **Never dead-end.** Every list has an empty state and an error state. Every AI call has a fallback. The whole app runs offline in mock mode.

---

## 2. Visual system (`DesignSystem/`)

### 2.1 Appearance
- **Light mode only.** Set `UIUserInterfaceStyle = Light` in Info.plist and `.preferredColorScheme(.light)` on the root view. We don't design or test dark mode.

### 2.2 Color
| Token | Value | Use |
| --- | --- | --- |
| `accent` | `Color.black` (`#000000`) | App tint, primary buttons, selected chips, tab selection |
| `background` | `systemBackground` (white) | Screens |
| `surface` | `secondarySystemBackground` | Cards, text fields, the banner |
| `textPrimary` | `label` | Text |
| `textSecondary` | `secondaryLabel` | Metadata |
| `hairline` | `separator` | Dividers |
| `success` | `systemGreen` | The "accepted" status, success states |
| `destructive` | `systemRed` | Decline, delete, report |
| `warning` | `systemOrange` | The "pending" status |

**Color budget:** system semantic colors (green, red, orange) for status, plus one brand accent, **Loop Lime `#C7E75A`** (update 2026-10-17). No color for share types, impact numbers, or badges. Impact and badges get their emphasis from type, weight, and motion.

**Loop Lime** is a controlled accent, not a theme. It is defined once, as `Theme.lime` in `DesignSystem/Theme.swift` (with `Theme.onLime`, near-black, for anything on top of it). Text and icons on lime are always near-black. It appears only in:
1. The raised Scan button in the tab bar.
2. The welcome and launch screens: a highlighter stroke behind the word "loop".
3. Publishing: the new card gets a lime "Just posted" tag for about 6 seconds (a tag only, no border around the photo).
4. Exchange completion: the checkmark disc.
5. "You" / "Yours" markers (leaderboard row, item cards, item detail).

Everything else stays as designed: black primary buttons, black selected chips, neutral gray capsules, and status colors that keep their system meaning (green accepted, red decline, orange pending). Don't use lime for body text, icons on the off-white page (contrast), tab selection, or impact statistics.

### 2.3 Type
- SF Pro (system) for everything, using Dynamic Type styles (`.largeTitle` … `.caption2`).
- **SF Pro Rounded** (`.fontDesign(.rounded)`) only for the wordmark and for large numbers (impact stats, counts, the leaderboard).
- Numbers use `.monospacedDigit()` wherever they animate.

### 2.4 Spacing, corner radius, elevation
- Spacing scale: 4, 8, 12, 16, 20, 24, 32. Screens have 16 pt side margins. The grid has a 12 pt gutter.
- Corner radius: 12 for cards and photos, 10 for text fields, a full capsule for chips and badges, and 20 for sheets (the system value).
- Use as few shadows as possible. Cards are flat on `surface`. Floating elements (the bottom CTA bar, the scan button) use `.ultraThinMaterial` or `.regularMaterial`.

### 2.5 Components
- **`ShareTypeCapsule`**: a neutral capsule with text only (`Swap`, `Free`, `Donate`): `.caption.weight(.semibold)`, `surface` fill, `textPrimary`. No icons and no color.
- **`YoursCapsule`**: the same shape with the label `Yours`, in Loop Lime with near-black text (`TagCapsule(lime: true)`). It sits next to the share-type capsule on my own cards.
- **`StatusPill`** for request status: `pending` orange, `accepted` green, `declined` and `cancelled` gray, `completed` black. A tinted fill at 15% opacity with full-color text.
- **`CachedImage`**: see §9.2.
- **`EmptyState`**: an SF Symbol, a one-line title, a one-line body, and an optional button. Wraps `ContentUnavailableView`.
- **`ErrorState`**: shows `error.message` from the API and a Retry button.
- **`Toast`**: a top-aligned material capsule that disappears after 2.5 s. Used for small confirmations.
- **`InAppBanner`**: a notification banner that slides down from the top, styled like a push notification (see §8.2).
- **`PrimaryButton`**: a full-width black capsule with white text, 50 pt tall. It shows a loading state with a spinner.

### 2.6 Wordmark and icon
- Wordmark (final, typography-first): lowercase **"loop."** in SF Pro Rounded Bold, near-black `Theme.ink` (#191919) in the app, with no glyph. On the welcome and launch screens a Loop Lime highlighter sits behind it.
- App icon: the same "loop." in Loop Lime on a solid #191919 square: no symbol, gradient, shadow or border. `ios/Tools/make-app-icon.swift` renders the 1024 px PNG (no alpha) into the asset catalog.
- Launch background is the warm off-white #FAF8F4, so launch flows into the welcome screen with no white flash.
- Welcome screen text is `Theme.ink`; secondary copy and placeholders use `Theme.inkSecondary` / `Theme.inkPlaceholder` (about 7:1 and 4.5:1). Buttons stay black with white text.

### 2.7 Copy tone
Friendly, short, and about campus. Use the user's dorm or campus where we have it.
- Empty feed: "Nothing here yet. Be the first to share something from Kissam." with a Scan button.
- Empty Saved: "Tap the heart on anything you like." with no button.
- Empty incoming requests: "No requests yet. Listings with good photos get noticed faster."
- Error messages: always `error.message` from the server as written. Don't write your own.

---

## 3. App structure and navigation

### 3.1 Tab bar
`Feed · Saved · [Scan] · Requests · Profile`

- **Scan** is a raised black circular button (about 56 pt, white `camera.fill`) that sits over the center of the tab bar. It opens the scan flow as a `fullScreenCover`. It isn't a real tab, so it never becomes "selected".
- Build the tab bar with a custom overlay on a standard `TabView`, with a placeholder middle tab that can't be selected. This keeps system tab behavior and state.
- **Requests** tab badge: the number of requests that need action or have unread messages. It comes from the notifications poll (§8.1).
- The impact screen, leaderboard, and badges live inside Profile, and also open from the feed banner (§6).

### 3.2 Navigation and routing
- Each tab has a `NavigationStack` with a typed `path` (`[Route]`).
- `Route` cases: `listing(id)`, `thread(requestID)`, `impact`, `notifications`, `editListing(id)`, `incomingRequests(listingID)`.
- A shared `@Observable Router` owns the selected tab and every tab's path. `Router.open(_ notification:)` switches to the right tab and pushes the right route. The bell, the in-app banner, and other deep links all use it.
  - `request_received` → Requests tab → `thread(requestID)`
  - `request_accepted`, `request_declined`, `new_message` → Requests tab → `thread(requestID)`
  - `badge_earned` → Profile tab → scrolls to badges

### 3.3 Motion and haptics (native, purposeful)
- Card → detail: `.navigationTransition(.zoom(sourceID:in:))` on iOS 18, a standard push on iOS 17 (guard with `if #available`).
- The heart uses `.symbolEffect(.bounce)` when saved. The bell uses `.symbolEffect(.bounce)` when the unread count goes up.
- Numbers use `.contentTransition(.numericText())` for the impact count-up and the unread counts.
- Use default springs (`.snappy` or `.smooth`) and no custom curves.
- Haptics with `.sensoryFeedback`:
  - `.success`: post a listing, accept a request, complete an exchange
  - `.impact(.light)`: save or unsave, take a shot
  - `.warning`: AI failure, an error
  - `.selection`: chip and filter changes

### 3.4 iOS version
The test phones' iOS versions aren't known yet. **Deployment target: iOS 17.**

Update 2026-10-17: the iOS Mac runs macOS 13.7, so the newest Xcode it can run is **15.2 (iOS 17.2 SDK)**. iOS 18 APIs can't compile at all, even behind `#available`, so the zoom transition (§3.3) and `.navigationSubtitle` are dropped: card → detail is a standard push, and the campus name sits in the leading toolbar slot. Folder-synced groups need Xcode 16, so `ios/Loop.xcodeproj` is generated from `ios/project.yml` with XcodeGen (`bash ios/generate.sh`) and committed.

---

## 4. Sign-in and profile setup (I-8)

### 4.1 Sign-in screen
- The wordmark is centered in the top third, with one line under it: "Swap, give, and donate clothes on your campus."
- One email field (`.keyboardType(.emailAddress)`, `.textContentType(.emailAddress)`, no autocapitalization) and a `PrimaryButton` "Continue".
- The app checks the email ends in `.edu` before sending, and the server checks again. Either way, the error appears inline under the field in red, using the server's `message` when there is one.
- **DEBUG builds only:** a row of three quick-login buttons for the demo accounts, under the button. They don't appear in release builds.
- No onboarding carousel (Tier 3 I-30 is out of scope).

### 4.2 Profile setup (when `is_new == true`)
One scrolling `Form`:
- An avatar circle with a "Add photo" `PhotosPicker`. Uploads with `POST /photos` (`kind=avatar`), then `PATCH /me` with `avatar_photo_id`.
- Name (required).
- Class year: a `Picker` covering the current year to current year + 4.
- **Dorm: a `Picker` from `GET /dorms`** (contract v1 added it; the API wins over the earlier plan for a hardcoded list). If the list is empty, a text field. The mock list below lives in `Mocks/dorms.json`. The leaderboard groups by the exact dorm string, so free text is out. Draft list (**verify against the official Vanderbilt housing list before shipping**, and send the final list to the server lane so the seed data uses the same spellings, see IOS-4):
  - The Commons: Crawford, Gillette, Hank Ingram, Memorial, Murray, North, East, Stambaugh, Sutherland, West
  - Kissam
  - E. Bronson Ingram
  - Warren, Moore
  - Rothschild, Nicholas S. Zeppos (shown as "Zeppos")
  - Highland Quad, Branscomb, Carmichael Towers, McGill, Lewis
  - Off campus
- Sizes: top (XS–XXL), bottom (waist 24–40), shoe (5–14 in half sizes), using the same vocabulary as §5.4.
- "Done" button → `PATCH /me` → the feed.

### 4.3 Sign out
In Profile → the gear icon → a settings sheet: "Sign out" (destructive) clears the token in the Keychain and the session store, and returns to sign-in.

---

## 5. Scan → Review → Post (I-9, I-10)

This is the core of the demo. The flow is a `fullScreenCover` with an internal `NavigationStack`: **Camera → Review**.

### 5.1 Camera (custom AVFoundation, one continuous flow)
- A full-screen `AVCaptureSession` preview. The top bar has a close (✕) button and a step label: **"Front"**, then **"Back"**, then **"Label"**.
- A light guide overlay for each step: a rounded-rectangle frame for front and back, and a smaller frame with the hint "Get the tag in frame" for the label.
- The bottom has a shutter, a **photo library button** on the left (a `PhotosPicker` with a single selection that fills the current step), and a strip of three slots on the right that fill with thumbnails as shots are taken.
- **Auto-advance:** after each capture (or library pick), the slot fills with a light haptic and the label moves to the next step. There is no checklist screen in between.
- Tap a filled thumbnail to retake that shot. That jumps back to that step.
- **Skipping:**
  - Front is required. There's no skip button on that step.
  - Back has a plain "Skip" button.
  - On the label step, Skip opens a short confirmation: "The label helps us read the brand and size. Skip anyway?" with the options **Take label photo** and **Skip**.
- When the last required step is done, go straight to Review. That's after the label shot, or after you skip the label.
- If camera permission is denied: an empty state with "Open Settings" and a "Choose from library" fallback that uses the same per-step flow.
- In the simulator (no camera): only the library button is active.

### 5.2 Work started at capture
As soon as each photo is captured, a background task does two things:
1. **Resize** the photo: longest side 1600 px, JPEG quality 0.8.
2. **Run on-device Vision** (`VNClassifyImageRequest`, keeping the top 5 labels with confidence ≥ 0.3; plus `VNRecognizeTextRequest` on the label photo). The results become the `labels` field.

The app **always** sends `labels` to `POST /scan`. The server ignores them when the vision model works. This is the cheap insurance from `docs/ARCHITECTURE.md`. The helper lives in `Features/Scan/OnDeviceLabeler.swift`.

### 5.3 Review screen
Review **opens right away**, and `POST /scan` runs while it's on screen.

Layout, top to bottom:
1. A horizontal row of the 1 to 3 captured photos (from local images, so they show at once).
2. **The AI banner** (one banner, no marks on individual fields), in one of four states:
   - Loading: a shimmering line, "Reading your photos…"
   - `source: vision` or `labels`: "Filled in by AI. Check before posting." with a `sparkles` symbol.
   - `source: none`, or the request failed: "Couldn't fill this in automatically." plus a **Try again** button. Try again calls `/scan` again with the same images. Meanwhile the fields unlock and stay empty, so the user can keep going by hand.
3. **AI fields**: title, category, size, color, brand, condition, description, tags. **While loading, they show as skeletons (`.redacted(reason: .placeholder)` plus a shimmer) and are locked.** When the draft arrives, they fill in with a short cross-fade and unlock.
4. **Fields the user fills in** (editable during loading): **share type** (a segmented `Swap / Free / Donate` control, no default, required) and **meetup spot** (a `Picker` from `GET /meetup-spots`, loaded when the scan flow opens, required).
5. The `PrimaryButton` **Post**, at the bottom in a material bar. It's disabled until the required fields are filled: title, category, condition, share type, meetup spot, and at least one photo.

Field controls:
- Title: a text field. Description: a multi-line `TextField(axis: .vertical)`.
- Category: a menu `Picker` with the 7 enum values, using human-readable labels.
- Condition: a segmented control for `New / Like new / Good / Worn`.
- Size: see §5.4.
- Tags: editable chips with an "add tag" field. Tap × to remove a tag.
- Condition note (Tier 3, S-28): if the server returns one, show it as read-only secondary text under Condition, like "Light fading at the cuffs". It's hidden when it's null. Needs IOS-3.

Photos from a scan are saved on the server even when the AI fails, so `photo_ids` from the scan response always go into `POST /listings`. If the `/scan` request **itself** failed (a network error), there are no photo IDs. Try again resends everything. If Post is tapped with no photo IDs, upload each image with `POST /photos` first.

### 5.4 Size picker by category
| Category | Options |
| --- | --- |
| tops, outerwear, dresses | XS, S, M, L, XL, XXL |
| bottoms | 24–40 (waist) and XS–XXL |
| shoes | 5–14 in half sizes |
| accessories, bags | One size |

- If the AI's `size` exactly matches an option, that option is selected. If not, the picker shows **"Other: <AI value>"** as a selected custom option, so nothing is lost. Choosing "Other…" opens a text field.
- Changing the category resets the size only when the current size isn't valid for the new category.
- The same vocabulary drives the feed's size filter, which keeps exact-match filtering reliable.

### 5.5 After posting
1. `POST /listings` → 201.
2. The cover dismisses, the app switches to the **Feed** tab, scrolls to the top, and **inserts the new card at the top** with a scale-and-fade animation and a `.success` haptic.
3. The feed store inserts the returned `Listing` into its cache right away, without waiting for a refresh.

---

## 6. Feed (I-11)

### 6.1 Header
- A large title, "Feed", with the campus name as a subtitle (`.navigationSubtitle` on iOS 18; on iOS 17, a caption line in the first row).
- A toolbar **bell** (`bell` / `bell.badge`) with the unread count. It pushes `notifications`.
- `.searchable` in the navigation bar. Search waits 300 ms after typing stops and sends `q`.

### 6.2 Filter row
One horizontal chip row: **All · Swap · Free · Donate · [Filters ⌄]**
- The share-type chips choose one at a time. The selected chip is black with white text, and the others are `surface`.
- **Filters** opens a medium-detent sheet with a category grid (choose one, or none) and a size picker that changes with the category (§5.4). "Clear" and "Show results" buttons.
- When filters are on, the chip reads "Filters · 2".

### 6.3 Campus banner (the first grid row, full width, scrolls away)
- `GET /impact/campus`: "**86** items rehomed this week · **61 kg** kept out of landfill", and "Kissam leads" under it.
- Tap it → **Impact screen** (§10.2), the same screen Profile opens. It's one of the two ways to reach the leaderboard.
- Hidden when filters or search are active.

### 6.4 Grid
- A two-column `LazyVGrid` with **uniform 4:5 photos** (`aspectFill`, clipped, 12 pt radius).
- Under the photo: the **title** (one line, `.subheadline.weight(.medium)`), then **size** and the **share-type capsule** in one row. On my own listings, a **Yours** capsule sits next to the share-type capsule.
- A heart button in the top-right corner of the photo, on a small material circle. It's hidden on my own cards.
- **Paging:** load the first page with `limit=50` and no more. Seed data is 30 to 40 listings. Pull to refresh reloads the page.
- States: skeleton cards on the first load; `EmptyState` (§2.7); `ErrorState` with Retry.

---

## 7. Item detail (I-12, plus Tier 2 I-19, I-20, I-21, I-25)

### 7.1 Layout
- A **full-bleed paged carousel** (`TabView(.page)`, 4:5) under a transparent nav bar, with page dots. Nav bar buttons sit on material circles: back, heart, and an overflow `…` menu.
- Info section: the title (`.title2.bold`), then a row with the share-type capsule, size, and condition. Then color and brand, the description, tag chips, and the meetup spot (`mappin` plus the name).
- An owner card: avatar, name, dorm, and "Shared N items".
- **Style it** button (secondary, `sparkles`): see §7.3.
- **Similar items**: a horizontal row of small cards from `GET /listings/{id}/similar`. The row is hidden when there are no results.

### 7.2 Sticky bottom bar (material)
For someone else's listing:
- `my_request_status == null` and the listing is active: **Request** (a `PrimaryButton`) opens a sheet with an optional note. The note field is empty with placeholder text, has a 280-character counter, and a Send button. After it sends: a `.success` haptic, the bar changes to **Requested** (disabled, gray), and a toast says "Request sent".
- `pending`: "Requested", disabled, with a "Cancel request" text button.
- `accepted`: "Open chat" → `thread(requestID)`.
- The listing isn't active: "No longer available", disabled.

For my own listing:
- **Edit** (secondary) → `editListing(id)`, which reuses the Review form without AI and calls `PATCH /listings/{id}`.
- **"N requests"** (primary) → `incomingRequests(listingID)`. N is counted on the phone from incoming requests filtered to this listing (needs IOS-2). Hidden when N is 0.

### 7.3 Style it
- The button opens a **medium-detent sheet** that shows 2 or 3 skeleton cards while `POST /listings/{id}/style` runs.
- Each card: the idea title (`.headline`) and its description.
- On a 502 `ai_unavailable` error: close the sheet and show the toast "Style ideas aren't available right now."

### 7.4 Overflow menu
- Someone else's listing: **Report** → a `confirmationDialog` with three reasons: "Not clothing", "Inappropriate", "Spam". → `POST /listings/{id}/report` → the toast "Thanks, we'll take a look."
- My own listing: **Mark as exchanged** (only when there's an accepted request; it goes to that thread) and **Delete** (a destructive confirmation → `DELETE` → pop the screen and remove the listing from every cache).

---

## 8. Notifications (I-24)

### 8.1 Polling
- `NotificationStore` polls `GET /notifications?limit=20` **every 5 seconds while the app is in the foreground and signed in**. It pauses on `scenePhase != .active`.
- It drives the bell count (`unread`) and the Requests tab badge (unread notifications of the request and message types).
- A new item is one whose `id` is greater than the highest ID already seen. The first poll after launch only sets that starting point and shows no banners.

### 8.2 In-app banner
- For each new notification, a top banner slides down (material, rounded, with an SF Symbol for its type, `title`, and `body`). It stays up for 4 seconds and can be swiped up to dismiss.
- Tap it → `Router.open(notification)`, and mark it read.
- If the user is already in the thread the notification is about, don't show a `new_message` banner.
- Several new notifications at once: show the newest one, with "+2 more" when there are others.

### 8.3 Notification list
- Pushed from the bell. Rows: an icon, the title, the body, and a relative time. Unread rows have a dot.
- Opening the list calls `POST /notifications/read {"all": true}` after 1 second.
- Tapping a row → `Router.open`.

---

## 9. Requests and chat (I-13, I-14)

### 9.1 Requests tab
- A segmented control: **Incoming | Outgoing** (`GET /me/requests?role=…`).
- **Grouped by status:**
  - Incoming: **Needs response** (pending) · **Active** (accepted) · **Past** (declined, completed, cancelled)
  - Outgoing: **Waiting** (pending) · **Active** (accepted) · **Past**
- Row: the item thumbnail, the item title, the other person's name and dorm, a `StatusPill`, an unread dot when `unread_messages > 0`, and a relative time.
- Pending incoming rows have inline **Accept** (black) and **Decline** (text, red) buttons, so the owner can act without opening the thread.
- `incomingRequests(listingID)` reuses this list, filtered to one listing.
- Pull to refresh. Also refreshes whenever the tab appears and when a request-type notification arrives.

### 9.2 Thread screen (one screen for the request and its chat)
- **Header card** (pinned to the top): the item thumbnail and title, the other person, a `StatusPill`, and context actions:
  - Owner, pending: **Accept** / **Decline**
  - Either person, accepted: **Mark exchange done** (prominent and black, see §9.3)
  - Requester, pending or accepted: "Cancel request" (text, in the overflow menu)
- **Body**: the requester's note is shown first as a styled bubble labeled "Request note". Then the messages, my bubbles in black on the right and theirs in `surface` on the left, grouped by sender, with timestamps between groups when more than 10 minutes pass.
- **Composer**: a multi-line text field and a send button. It's **disabled with the hint "Chat opens once the request is accepted"** until the status is `accepted`. Once the request is completed or cancelled, it's replaced by a status note.
- **Polling, every 3 seconds while the thread is visible:**
  - `GET /requests/{id}/messages?after_id=<last>` adds new messages.
  - `GET /requests/{id}` (needs **IOS-1**) refreshes the status, so the screen updates live when the other phone accepts, declines, completes, or cancels.
- **Sending is optimistic:** the bubble appears right away, slightly faded. Once `POST` returns, it becomes the server's message (matched by body and timing, then swapped for the real ID). If sending fails, the bubble turns red with "Tap to retry".
- The list scrolls to the bottom when the screen opens and when a new message arrives, but only if the user was already near the bottom.

### 9.3 Mark exchange done: the celebration
1. Tap **Mark exchange done** → a confirmation dialog: "Mark this exchange as done? This moves the item to Completed."
2. Before calling `POST /requests/{id}/complete`, take a snapshot of `GET /me/badges` and `GET /impact/me`. Use the cached copies if they were fetched in the last 60 seconds.
3. Once the call succeeds, fetch both again and compare them with the snapshot.
4. Show a **full-screen celebration** as a `fullScreenCover` on white:
   - "Exchange complete" in a large title.
   - The listing's own impact (`listing.impact`), counting up from 0 with `.numericText()` in large SF Rounded numbers: **textile kg · water L · CO₂ kg**. Each has a relatable comparison (§10.3).
   - If any badge went from not earned to earned: a badge card that flips in, black-filled, with "Badge unlocked: First Swap".
   - A `.success` haptic. A "Done" button closes the screen and goes back to the thread.
5. **The other phone:** when the thread's status poll sees `accepted → completed` and this user didn't tap the button, it shows **the same celebration** (with the same badge comparison). So both phones celebrate on stage within about 3 seconds.
6. Invalidate the feed banner, the profile impact strip, and the listing caches so they refetch.

---

## 10. Profile, impact, leaderboard, badges (I-15, I-18, I-22, I-23)

### 10.1 Profile tab
From the top:
1. **Header**: avatar, name, dorm, class year, and a gear icon (the settings sheet: edit profile, sign out).
2. **Impact strip**: three compact stats (textile kg · water L · CO₂ kg) from `GET /impact/me`. Tap it → the Impact screen.
3. **Badges row**: a horizontal row of all badges from `GET /me/badges`. Earned badges are a black-filled circle with a white glyph. Unearned ones are an outlined gray circle with a gray glyph. Tap one → a small popover with its description and the date it was earned.
   - Glyphs: First Swap `arrow.2.squarepath`, Giving Back `heart`, Closet Cleanout `hanger`.
4. **My listings**: a segmented control, **Active | Completed** (`GET /me/listings?status=…`), and the same 4:5 grid as the feed. Tap a card → detail, which has the owner controls (§7.2).

### 10.2 Impact screen
It opens from both the Profile impact strip and the feed banner, and it's the same screen either way.
1. **You**: three large SF Rounded numbers with units and comparisons, plus "Items shared N · received M".
2. **Your campus this week** (`GET /impact/campus`): items rehomed, the three totals, the top dorm.
3. **Dorm leaderboard** (`GET /leaderboard/dorms`): ranked rows with the rank in SF Rounded, the dorm, and the item count with a thin black bar scaled to the leader's count. **The user's dorm row is highlighted** (a `surface` fill and bold text). This is where the demo ends (step 7).

### 10.3 Relatable comparisons
Shown under each impact number. **Every comparison factor must cite a published source in a code comment**, the same rule as `impact.py`. Starting figures, to be checked:
- Water: "≈ N showers", using about 65 L per shower (EPA WaterSense: an average US shower is 2.1 gal/min × 8 min ≈ 17 gal).
- CO₂: "≈ N miles not driven", using about 0.4 kg CO₂ per mile (EPA: a typical passenger vehicle emits about 400 g/mile).
- Textile: "≈ N T-shirts", using about 0.2 kg per T-shirt (check the source).
Round to whole numbers and hide the comparison when it rounds to 0.

---

## 11. Saved tab (I-19)
- `GET /me/saved`, using the same grid as the feed. Pull to refresh. Empty state per §2.7.
- `SavedStore` holds the set of saved listing IDs, so toggling the heart anywhere (feed, detail, similar items) updates every view at once. Toggles are optimistic (`PUT` / `DELETE /listings/{id}/save`) and roll back with a toast if the call fails.

---

## 12. Engineering architecture

### 12.1 State: hybrid
Global `@Observable` stores, injected with `.environment`:
- `SessionStore`: token (in the Keychain), current `User`, sign-in and sign-out.
- `ListingCache`: `[Int: Listing]`, the source of truth for any listing shown on screen. Feed, detail, saved, and profile read from it, so edits, deletes, and status changes show up everywhere.
- `SavedStore`: saved IDs (§11).
- `NotificationStore`: polling, unread count, the banner queue (§8).
- `Router`: tabs and paths (§3.2).

Each screen has its own `@Observable` view model for everything else (feed query and filters, scan and review form, thread polling, the requests list).

### 12.2 Images
`CachedImage(url:targetSize:)`: a small custom view, no packages.
- An `NSCache<NSURL, UIImage>` in memory, holding images already **downsampled** to the target pixel size with ImageIO (`CGImageSourceCreateThumbnailAtIndex`). Grid thumbnails are about 400 px.
- `URLCache.shared` enlarged to 50 MB in memory and 300 MB on disk, for the raw bytes.
- A `surface`-colored placeholder with a short fade-in when the image loads.
- Local `UIImage`s (scan captures) are passed in directly.

### 12.3 Networking and mocks
- `APIClient`: one `async throws` function per endpoint. `APIError` carries the server's `code` and `message`.
- `APIConfig.useMocks` switches between `LiveTransport` and **`MockTransport`, which is a stateful in-memory backend**:
  - Startup data comes from the JSON files in `ios/Loop/Mocks/` (which match the examples in `docs/API.md`).
  - Mutations really change the state: posting adds to the feed; requests move through pending, accepted, and completed; accepting declines the other requests on that listing; chat messages are stored, and a canned reply from the other user arrives about 2 seconds later; completing adds to impact and can award the First Swap badge; saves and reports work.
  - `/scan` waits 2.5 seconds, then returns the draft fixture with `source: vision`.
  - Mock notifications are generated for request, accept, and message events, so the banner and bell work offline.
  - Goal: **the whole demo path works on one phone with `useMocks = true`**, as the last-resort fallback.
- Put a short delay (300 ms) on every mock response so loading states are visible during development.

### 12.4 Folder layout
As in `docs/ARCHITECTURE.md`, plus:
```
DesignSystem/  Tokens.swift, Components/ (ShareTypeCapsule, StatusPill, CachedImage, Toast, InAppBanner, EmptyState, PrimaryButton, LoopGlyph)
Core/          Router.swift, Stores/ (Session, ListingCache, Saved, Notification)
Features/Scan/ CameraView, CameraController (AVFoundation), OnDeviceLabeler, ReviewView, SizeVocabulary
Features/Celebration/
Config/        APIConfig.swift, Campus.swift (Vanderbilt dorms)
```

---

## 13. Contract requests for the server lane

Update 2026-10-17: contract v1 (frozen by the server lane) already has `GET /requests/{id}`, `pending_request_count` and `accepted_request_id` on Listing, `GET /me/unread`, and `GET /dorms`, so IOS-1 and IOS-2 below aren't needed. The app counts "N requests" from `pending_request_count`. The open requests in `coord/ios.md` are renumbered: demo accounts, size vocabulary, and the Tier 3 condition note.

The original list:

| ID | Ask | Why |
| --- | --- | --- |
| **IOS-1** | Add `GET /requests/{id}` that returns one Request (only the two people on it can read it). | The thread polls it every 3 s to see live status changes (accepted, declined, completed, cancelled) on both phones (§9.2, §9.3). |
| **IOS-2** | Add an optional `listing_id` query parameter to `GET /me/requests`. | The "N requests" button on my own listing, and the per-listing incoming list (§7.2). The app counts them itself. |
| **IOS-3** | (Tier 3, S-28) Add a nullable `condition_note` string to `ScanDraft`, `Listing`, and the POST/PATCH listing bodies. | Show the vision model's condition note on Review and detail (§5.3). |
| **IOS-4** | Use the exact Vanderbilt dorm spellings in `Config/Campus.swift` for seed users, and the size vocabulary in §5.4 for seed listing sizes. Ask the vision prompt to return sizes in that vocabulary. | Leaderboard grouping and the exact-match size filter depend on matching strings. |

---

## 14. Process note: Git

This machine works on **feature branches with PRs into `main`** (currently `feature/frontend`). That conflicts with the "both lanes push to `main` all day" rule in `CLAUDE.md`. Changing it is a decision for both lanes. Raise it with the server lane, then update `CLAUDE.md` and `/handoff` to match. Until then, merge PRs often so the server lane sees iOS progress in `coord/ios.md`. Also create `.lane` with `echo ios > .lane`.

---

## 15. Out of scope
- Dark mode.
- Onboarding carousel (I-30), campus map (I-28), Swap Day events (I-29).
- Push notifications (APNs).
- Paging the feed beyond the first 50 listings.
- Any brand color beyond Loop Lime (see §2.2) and the system semantic colors.

## 16. Open items to verify
- The final Vanderbilt dorm list (§4.2).
- The sources and factors for the relatable comparisons (§10.3).
- The OS versions on the demo phones (the zoom transition needs iOS 18; everything else works on iOS 17).
- Whether `cohere.command-a-vision` is available (S-3). If it isn't, the `labels` path in §5.2 becomes the main path, so test that the on-device labels it produces are good.
