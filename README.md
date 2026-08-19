# Nightshift for iOS

A native SwiftUI client for a [Nightshift](https://github.com/Jannehy/nightshift)
server. It talks to the same JSON API the web UI uses — no server changes
required.

## What it does

| Screen | Backed by |
|---|---|
| **Downloads** – paste a Spotify/SoundCloud/YouTube link, pick a Navidrome owner, toggle "keep in sync", watch the live log | `POST /download`, `GET /stream/<job_id>` (SSE), `GET /download-log`, `GET /api/queue`, `GET /nd-users` |
| **Search** – iTunes catalog as an artwork grid, 30 s previews, one-tap track or full-album download | `GET /api/search`, `POST /api/download-from-query`, `POST /api/download-album` |
| **Sync** – every playlist the nightly job maintains, grouped by source; admins set owner and visibility, owners remove their own | `GET/PATCH/DELETE /api/sync-playlists` |
| **Nightly** – schedule in plain language, manual run, its own live log | `POST /nightly`, `GET /nightly-status`, `GET /nightly-log` |
| **Settings** – account, password, user management, and a settings editor generated from whatever is in `config.yaml` | `GET/POST /api/config`, `POST /api/config/reset`, `/api/users*` |

Sign-in uses the Flask session cookie. Because the server marks the session
permanent, `URLSession`'s cookie store keeps you signed in across launches; the
password is kept in the Keychain so the app can re-authenticate silently when
the cookie does expire. The Sync tab is hidden when `sync.enabled` is off, the
owner picker when Navidrome is not configured, and the admin sections for
non-admin accounts — the app follows `/api/me`, same as the web UI.

Two live-log strategies, mirroring the web UI: while the app owns a job id it
reads the SSE stream, and after a cold start (or when a download was started
elsewhere) it falls back to polling the log endpoint.

German and English are included; the app follows the device language.

Two independent appearance settings: the **accent colour** (eight presets plus a
free colour picker) tints the whole UI including the launch mark, which is drawn
as vectors rather than shipped as an image. The **app icon** is a separate
setting, because iOS pops a system confirmation on every icon change and cannot
generate icons at runtime — each variant is a PNG in the bundle, declared under
`CFBundleAlternateIcons`. Both the icon PNGs and the launch mark's geometry come
from `Tools/make-icon.py` (`--alternates` writes the variants, `--swift` prints
the constants `NightshiftMark` draws from), so they cannot drift apart.

## Requirements

- macOS with **Xcode 15 or newer** — iOS apps cannot be compiled on Linux
- iOS 16.0 or newer on the device
- An Apple ID. A free one signs the app for 7 days at a time; the paid
  Developer Program gives a year and TestFlight.

## Building

```bash
brew install xcodegen        # once
cd nightshift-ios
xcodegen generate            # writes Nightshift.xcodeproj
open Nightshift.xcodeproj
```

Then in Xcode: select your team under *Signing & Capabilities*, pick your
iPhone, and hit Run.

Without XcodeGen: create a new iOS App project named `Nightshift`, delete the
generated `ContentView.swift` and `NightshiftApp.swift`, drag the `Sources` and
`Resources` folders in (*Create groups*), and set `Resources/Info.plist` as the
target's Info.plist file.

## Reaching the server

The app is built for a private network path — Tailscale, WireGuard or the LAN —
and speaks plain HTTP, so `Info.plist` carries an ATS exception
(`NSAllowsArbitraryLoads`). Bring the tunnel up before connecting.

On the first screen enter the host, e.g. `nightshift.tail1234.ts.net` or
`100.101.102.103`. A bare host gets `http://` and Nightshift's default port
`8765`; anything more explicit is taken as typed:

| Typed | Used |
|---|---|
| `nightshift.tail1234.ts.net` | `http://nightshift.tail1234.ts.net:8765` |
| `192.168.1.5:9000` | `http://192.168.1.5:9000` |
| `http://music.example.com` | `http://music.example.com` (port 80, no 8765 forced) |
| `https://music.example.com` | `https://music.example.com` (port 443) |
| `https://home.example.com/nightshift` | path prefix kept, for a server published under a subpath |

If you put an HTTPS reverse proxy in front of Nightshift, enter the full
`https://…` URL and the ATS exception in `Info.plist` can go.

Note that the server's own **setup wizard is web-only**. On a fresh server the
app links you to `/setup` in Safari; once an admin exists, sign in from the app.

## Distribution

The App Store is out (guideline 5.2.3 — apps must not offer to download media
from third-party services), so the app travels as source plus an IPA on the
releases page.

An IPA signed with your own account only installs on devices registered to it.
Everyone else re-signs it with their own Apple ID using AltStore or SideStore,
which is what the **AltStore source** is for:

```bash
Tools/build-ipa.sh
Tools/make-altstore-source.py build/Nightshift.ipa 1.0.0
```

The second command writes `altstore.json` with the IPA's exact byte size (which
AltStore checks) and keeps older versions listed so a downgrade stays possible.
Screenshots dropped into `docs/screenshots/` are picked up automatically and
served from the repository.
Commit it, attach `Nightshift.ipa` to the matching GitHub release, and people
add this URL as a source:

```
https://raw.githubusercontent.com/Jannehy/nightshift-ios/main/altstore.json
```

With a free Apple ID, AltStore-installed apps expire after 7 days and have to be
refreshed; a paid developer account stretches that to a year.

## Not included

- **Push notifications** when a download finishes. APNs needs a paid developer
  account and a server-side sender — Nightshift has no notification hook today.
- **A share extension** ("Share → Nightshift" from the Spotify app). The
  natural next step; it would post to `/download` with the shared URL.
- **The setup wizard**, deliberately — a one-time flow is not worth a native
  screen.
- Cancelling a running job: the server has no cancel endpoint. "Clear log" only
  detaches the view.

## Server requirements

Works against any Nightshift, but **1.3 or newer is recommended**: from that
version the download log is kept per user, and `/api/version` exists so the app
can identify the server before signing in. Against an older server the Settings
screen shows "older than 1.3" and warns that the download log is shared between
all users.

## Server-side suggestions

Not required for this client to work:

- `search.py`'s routes rely on the global access gate rather than carrying
  `@auth.login_required` themselves. It holds, but the decorator would make the
  intent explicit and survive a refactor of the gate.
