# Seek Web Setup

Browser-based installer for **SeekOS DVT** on Vector 1.0 — like [vector-web-setup](https://github.com/digital-dream-labs/vector-web-setup), but the OTA is pulled from **GitHub Releases** (no local firmware folder).

Deploy **`public/`** to Cloudflare Pages (or any static HTTPS host).

## Download setup folder (.zip)

**Direct download (Cloudflare / self-host without git):**

https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.17d-dvt/seek-websetup.zip

Unzip and upload the contents to Cloudflare Pages, or open `index.html` via a local HTTPS server (BLE needs Chrome + HTTPS or localhost).

The site also shows this link in the header after load.

## Auto-update releases

On load, the setup page calls the **GitHub Releases API** for tags containing `-dvt`, fills the **OS release** dropdown (latest first), and uses the selected `.ota` for BLE / Wi‑Fi / SSH paths. Click **Check for updates** to refresh.

Edit `public/config.json` only for repo name, tag filter, zip URL, and offline `fallbackRelease`.

## Cloudflare Pages

1. **Workers & Pages → Create → Pages → Connect to Git** → `loganstorm1254-sudo/seek-cfw`
2. **Build settings**
   - Build command: `cd seek/websetup && npm install && ./build.sh`
   - Build output directory: `seek/websetup/public`
3. Deploy. Your site is `https://<project>.pages.dev`

Or **Direct Upload**: run `./build.sh` locally, upload `public/` as a folder.

## Update OTA version

Edit `public/config.json`:

- `otaUrl` — GitHub release `.ota` URL  
- `otaSize` — byte size (flash script verifies this)  
- `otaSha256` — optional reference  
- `flashScriptUrl` — `unlock-manual-flash-v2.sh` on the same release  

Then commit, push, and redeploy.

## Install paths

| Tab | When to use |
| --- | --- |
| **Bluetooth (Chrome)** | First install or no SSH. Pair → Wi‑Fi → robot downloads OTA from GitHub over BLE/Wi‑Fi. |
| **Wi‑Fi upgrade** | Already on Seek; same Wi‑Fi as Vector. Calls `:8080/api/mods/SeekDashboard/otaFromUrl`. |
| **SSH one-liner** | Windows + SSH key; copy/paste into CMD. |

## Build locally

```bash
cd seek/websetup
npm install
./build.sh
npx --yes serve public   # http://localhost:3000 — BLE needs Chrome + localhost is OK
```

## Third-party code

- `vendor/rts-js/` — fork of [digital-dream-labs/vector-web-setup](https://github.com/digital-dream-labs/vector-web-setup) RTS/BLE stack (MIT). See `vendor/NOTICE.md`.
