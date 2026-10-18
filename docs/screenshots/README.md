# Presentation screenshots

Real screenshots of the working Loop iOS app and web portal, for the architecture and technical presentation. Nothing here is mocked up or edited, apart from one crop and the lossless PNG optimization noted below.

## iOS (`ios/`)

iPhone 15 Pro Simulator, iOS 17.2, build 1.0 (3) with the approved black infinity Loop logo. Originals are still in `ios/Screenshots/`. "Live" means the app was running against the real server (`163.192.218.131:8000`, Oracle Cloud). "Mock" means the app's built-in sample data, which has placeholder art.

| File | Screen | Data |
| --- | --- | --- |
| `01-signin.png` | Sign-in with the infinity logo | n/a |
| `02-feed.png` | Campus feed | Live |
| `03-photo-picker.png` | Scan: choosing photos from the library | Mock |
| `04-ai-review.png` | AI-generated listing review ("Filled in by AI") | Live, Oracle vision model |
| `05-published-listing.png` | Published listing with the "Just posted" tag | Live |
| `06-item-detail.png` | Item detail | Live |
| `07-requests-inbox.png` | Requests inbox (incoming) with a new-request banner | Mock |
| `08-request-sent.png` | Request sent on an item | Live |
| `09-chat-accepted.png` | Chat inside an accepted request | Live |
| `10-chat-reply.png` | Chat after the reply | Live |
| `11-exchange-complete.png` | Exchange completion and badge | Live |
| `12-profile.png` | Profile, impact, badges | Live |
| `13-impact-leaderboard.png` | Impact statistics and dorm leaderboard | Live |
| `14-notification-banner.png` | In-app notification banner (new message) | Mock |
| `15-app-icon-home.png` | App icon on the home screen (cropped to the icon) | n/a |

Not available: the live camera view. The Simulator has no camera, so the scan step is shown through the photo picker.

## Web portal (`web/`)

Desktop captures are 1372x879 and mobile ones about 500 px wide (the narrowest the browser window allows), saved as JPEG exactly as captured. All are signed in as the demo account Jordan Park on the Vanderbilt campus, except the landing page and sign-in.

The production site is behind Vercel Authentication, so these were taken from a local production build (`npm run build` plus `vite preview`) of `web/` at commit `a5fa4a8`, the same code that was deployed. It talks to the same Oracle-hosted backend through the same `/api` proxy.

| File | Screen |
| --- | --- |
| `01-landing.jpg` | Landing page |
| `02-signin.jpg` | Sign in |
| `03-feed.jpg` | Campus feed |
| `04-listing-detail.jpg` | Listing detail |
| `05-requests-inbox.jpg` | Requests inbox |
| `06-profile.jpg` | Profile, impact and badges |
| `07-impact.jpg` | Impact |
| `08-leaderboard.jpg` | Dorm leaderboard |
| `09-notifications.jpg` | Notifications |
| `10-events.jpg` | Events |
| `11-campus-map.jpg` | Campus map: meetup spots and donation bins |
| `12-post-upload.jpg` | Post an item: photo upload step (empty) |
| `13-mobile-feed.jpg`, `14-mobile-listing-detail.jpg`, `15-mobile-leaderboard.jpg` | Mobile layout |

Not captured, because each needs a write to the shared demo server: the web scan in progress, the AI-generated review form, and an open chat thread (opening a chat marks messages read). The iOS set shows the equivalent AI review and chat screens.

## Notes

- The demo data reflects the last rehearsal on the live server, so the inbox and notifications list several repeated requests for the same jersey. A reseed (`scripts/reseed.sh`, server lane) restores the clean demo state.
- `ios/15-app-icon-home.png` is a crop of `ios/Screenshots/20-app-icon-home.png`, which also showed a test-runner app icon. iOS PNGs were re-saved with lossless optimization only.
