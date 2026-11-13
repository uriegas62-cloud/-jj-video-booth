# J&J Video Booth — video guestbook + photo booth (iPad)

Guest flow: **Tap to Start → record a video message for the guest of honor → 1/3/4 photos → 4x6 prints on the Epson by itself → QR code / email to take their photo + video home.**
Every print also lands in **Tonight's Gallery** (on the iPad and on the web). The guest of honor gets a **private host gallery** with every video and photo, plus Download All.

## What's in here
| Folder | What it is |
|---|---|
| `App/` | The native iPad app (SwiftUI). Codemagic builds it — no Mac needed. |
| `project.yml` | XcodeGen project file (Codemagic turns it into the Xcode project). |
| `codemagic.yaml` | Build → TestFlight. Uses your existing `jj-apple` Codemagic key. |
| `web/` | Gallery website (guest link, tonight's gallery, host gallery). |
| `supabase/` | Database + the `vb-booth` function. **Already live** in your jjworkshop Supabase project. |

## Already done for you
- Supabase tables `vb_events`, `vb_sessions`, storage bucket `vb-media`, and the gallery functions are live (separate from your old booth tables).
- Edge function `vb-booth` is deployed and tested (signed uploads, finish, email).
- Netlify project **jj-video-booth** created → https://jj-video-booth.netlify.app (needs its first upload, step 3).
- Admin key (type it into the iPad's settings once): see the chat / ask Claude.

## Setup (one time)

### 1. GitHub
Done — code lives in `uriegas62-cloud/-jj-video-booth`.

### 2. Apple (same as last time, new bundle ID)
1. developer.apple.com → Identifiers → **+** → App ID → Bundle ID `com.jandjworkshop.videobooth`, name `J&J Video Booth`.
2. App Store Connect → Apps → **+** New App → iOS, name `J&J Video Booth`, that bundle ID, SKU `jjvideobooth`.

### 3. Gallery website
app.netlify.com → **jj-video-booth** → Deploys → drag the `web` folder onto the drop zone.

### 4. Email (Resend)
Supabase → jjworkshop project → Edge Functions → Secrets → add:
- `RESEND_API_KEY` = your Resend API key
- `BOOTH_FROM_EMAIL` = e.g. `J&J Photo Booth <booth@jandjworkshop.com>` (the domain must be verified in Resend)

### 5. Codemagic
Add application → pick the `jj-video-booth` repo → Start build with **J&J Video Booth (iOS → TestFlight)**. ~15–25 min.

### 6. iPad
1. TestFlight → install **J&J Video Booth** → allow Camera, Microphone, Local Network.
2. Hold the **top-right corner 2 seconds** → PIN **2580** (change it in settings).
3. Paste the admin key → **Create event** (name that prints on the photo, who it's for, date, host PIN) — or **Load my events** and tap one.
4. **Choose printer** → the Epson → **Test print**.
5. Copy the **Host video gallery** link and send it + the host PIN to the guest of honor.
6. Optional: **Print a gallery QR table sign**.
7. Turn on Guided Access (Settings › Accessibility) so guests can't leave the app.

## Night-of tips
- Epson: 4x6 photo paper in the photo tray, paper size set to 4x6 on the printer screen, same Wi-Fi as the iPad.
- Everything saves on the iPad first. If Wi-Fi drops, uploads and emails catch up later — leave the app open after the party until Settings › Uploads shows **0 waiting**.
- 720p video is the default (≈1 MB per second). 1080p looks sharper but uploads ~2x bigger.
