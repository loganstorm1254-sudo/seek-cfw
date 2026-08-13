Seek Web Setup — make BLE OTA actually work
============================================

Vector’s updater cannot follow GitHub redirects (that’s the cloud-with-!).
OTAs must be served as a direct HTTP 200 with Content-Length.

------------------------------------------------
Do this once (required)
------------------------------------------------

1) Cloudflare Worker (files host)
   - Create/edit Worker, paste worker-otas.js from this folder
   - Bindings → R2 bucket named exactly: OTA
   - Custom domain e.g. files.yourdomain.com  (or use *.workers.dev)
   - Optional: upload .ota files under R2 prefix OTA/
   - Worker also lists GitHub Seek releases and serves them via /fetch
     (so BLE install works without uploading to R2)

   Test:
     https://files.yourdomain.com/api/otas.json
   You should see JSON with "seek": [ { "url": "...", "name": "vicos-….ota" } ]

2) Edit static/data/settings.json BEFORE uploading Pages:

   "otaListUrl": "https://files.yourdomain.com/api/otas.json"

   (replace with YOUR real Worker/files URL)

3) Cloudflare Pages → Upload this whole folder (or the zip)
   Custom domain e.g. setup.yourdomain.com

4) Chrome on a PC with working Bluetooth:
   https://setup.yourdomain.com
   Pair Vector → Wi‑Fi → pick an OTA → Install

Quick test without rebuilding the zip:
  https://setup.yourdomain.com/?otaListUrl=https://files.yourdomain.com/api/otas.json

------------------------------------------------
Every new release
------------------------------------------------
Upload vicos-x.y.z.ota into R2 folder OTA/
  OR just publish a GitHub release — Worker /api/otas.json picks it up via /fetch

------------------------------------------------
If BLE still fails
------------------------------------------------
- chrome://bluetooth-internals/#adapter → Present + Powered must be ✓
- Do NOT use raw github.com download links for BLE
- Downgrading (e.g. 42d → 1d) may need SSH:
    update-os https://…/vicos-3.0.1.1d.ota

Based on https://github.com/digital-dream-labs/vector-web-setup (MIT)
