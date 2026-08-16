# Seek Web Setup

Open-source Vector setup without the phone app or an Anki account.
Chrome talks to the robot over BLE; the robot pulls the OS image over
**plain HTTP from this PC** (fast LAN). That avoids TLS status 203 and
is much faster than the robot downloading ~217 MB over a phone hotspot
(cellular is often 20–40 minutes; LAN is usually a few minutes).

Requires Node.js. Works on macOS, Windows, and Linux.

## One-time install

```bash
cd seek/websetup
npm install
node bin/seek-web-setup.js configure
node bin/seek-web-setup.js ota-sync
```

`ota-sync` downloads Seek OTAs from https://files.anki.org.uk into
`~/.seek-web-setup/firmware/seek/` (or `%USERPROFILE%\.seek-web-setup\...`).

## Daily usage (fast flash)

```bash
node bin/seek-web-setup.js serve
```

Chrome → **http://localhost:8000/**

1. Place Vector on the charger
2. Double-press the backpack button
3. Pair with Vector
4. Join Wi-Fi (**same hotspot/Wi-Fi as this PC**)
5. Pick **Seek OS (latest)** → Install

Robot URL looks like `http://192.168.x.x:8000/firmware/latest.ota`.

If you skip `ota-sync`, Install still works: this PC proxies the files
host while the robot only speaks LAN HTTP.

### Custom port

```bash
node bin/seek-web-setup.js serve -p 7010
```

## Hosted Pages (slower)

`../websetup-pages/` can be uploaded to Cloudflare Pages for the same
BLE UI. Public Install uses `http://files.anki.org.uk/ota/latest`, so
Vector downloads ~217 MB through the phone hotspot (often 20–40 min).

After uploading `seek-websetup-pages.zip`, confirm the page shows
**UI seek16** top-right. If you still see percent past 100%, Pages is
serving an old zip — redeploy and hard-refresh.
