Seek Web Setup — R2 OTA list only
=================================

/api/otas.json lists ONLY .ota files you uploaded to R2.
It does not pull GitHub releases.

------------------------------------------------
Worker (files.anki.org.uk)
------------------------------------------------
1. Paste worker-otas.js into the Worker, Deploy
2. R2 binding name: OTA
3. Upload files under folder OTA/  (avoid spaces in names if you can)
     OTA/vicos-3.0.1.42d.ota

Test:
  https://files.anki.org.uk/api/otas.json
Should show only your R2 files.

------------------------------------------------
Pages (setup site)
------------------------------------------------
settings.json:
  "otaListUrl": "https://files.anki.org.uk/api/otas.json"

Upload seek-websetup-pages.zip to Pages.
Chrome → pair → Wi‑Fi → pick OTA → Install

Tip: rename "seek os 3.01.42d.ota" to vicos-3.0.1.42d.ota (no spaces).
