Seek Web Setup — make BLE OTA actually work
============================================

Status 203 / cloud-with-! = Vector could not open the OTA URL.
Raw github.com links and long ?url= proxies often fail. Use short paths.

------------------------------------------------
Do this once (required)
------------------------------------------------

1) Cloudflare Worker (files host)
   - Paste worker-otas.js from this folder
   - Bindings → R2 bucket named exactly: OTA
   - Custom domain e.g. files.yourdomain.com
   - Best: upload .ota files under R2 prefix OTA/
     URL becomes: https://files.yourdomain.com/OTA/vicos-3.0.1.42d.ota
   - Worker also exposes GitHub releases as:
     https://files.yourdomain.com/g/3.0.1.42d/vicos-3.0.1.42d.ota

   Test on your PC:
     https://files.yourdomain.com/api/otas.json
   Test FROM THE ROBOT (SSH):
     curl -I https://files.yourdomain.com/OTA/vicos-3.0.1.42d.ota

2) Edit static/data/settings.json BEFORE uploading Pages:
   "otaListUrl": "https://files.yourdomain.com/api/otas.json"

3) Upload seek-websetup-pages.zip to Cloudflare Pages

4) Chrome + Bluetooth Present/Powered ✓
   Pair → Wi‑Fi → pick OTA → Install

Quick test without rebuilding:
  https://setup.yourdomain.com/?otaListUrl=https://files.yourdomain.com/api/otas.json

------------------------------------------------
If you still get status 203
------------------------------------------------
From SSH on Vector:
  curl -v -I https://YOUR-FILES-HOST/OTA/your.ota
If that fails, the robot cannot reach Cloudflare (DNS/Wi‑Fi/TLS).
Fix network first, or use SSH:
  update-os https://YOUR-FILES-HOST/OTA/your.ota

Based on https://github.com/digital-dream-labs/vector-web-setup (MIT)
