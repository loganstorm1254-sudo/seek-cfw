# Seek Web Setup

Open-source Vector setup without the phone app or an Anki account.
Chrome talks to the robot over BLE; the robot pulls the OS image over
**plain HTTP from this PC** (that is why stock Vector Web Setup works,
and why the online HTTPS site returns status 203).

Requires Node.js. Tested on Windows, macOS, and Linux.

## One-time install

1. Install [Node.js](https://nodejs.org/en/download/)
2. From this folder:

```
cd seek/websetup
npm install
node bin/seek-web-setup.js configure
node bin/seek-web-setup.js ota-sync
```

`ota-sync` downloads Seek OTAs from https://files.anki.org.uk into
`%USERPROFILE%\.seek-web-setup\firmware\seek\` (or `~/.seek-web-setup/...`).

## Daily usage

```
node bin/seek-web-setup.js serve
```

Chrome → **http://localhost:8000/**

1. Place Vector on the charger
2. Double-press the backpack button
3. Pair with Vector
4. Join Wi-Fi (same hotspot as this PC)
5. Pick the OTA (served as `http://YOUR-PC-IP:8000/firmware/...`)

BLE only works on `http://localhost` or `https://` sites. Use Chrome.

### Custom port

```
node bin/seek-web-setup.js serve -p 7010
```

### Windows

Double-click `serve.cmd` in this folder (runs sync then serve).

## Why not the online site?

`https://files.anki.org.uk/...` is fine for the browser. Vector's
update-engine cannot verify TLS (missing CA) and returns **203**.
This local server gives the robot `http://192.168.x.x:8000/firmware/latest.ota`
instead.

## Hosted Pages (optional)

`../websetup-pages/` can still be uploaded to Cloudflare Pages for pairing
and Wi-Fi only. For Install OTA, use this local server.
