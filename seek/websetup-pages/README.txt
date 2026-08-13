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

------------------------------------------------
Robot offline / SSH timeout / curl (77)
------------------------------------------------
Phone hotspots renumber Vectors; SSH often times out. Broken CA → curl 77.

From Windows PowerShell (PC on same hotspot as Vector):

  cd path\to\seek-cfw\seek\scripts
  powershell -ExecutionPolicy Bypass -File .\fix-ble-ota.ps1 -Scan

Or one IP:

  powershell -ExecutionPolicy Bypass -File .\fix-ble-ota.ps1 -Key C:\Users\Logan\Downloads\ssh_root_key.txt -Ip 192.168.43.130

This scp's the fix (robot never curls GitHub). Fix survives reboot.

If SSH never answers: reboot Vector on charger → rejoin hotspot via BLE websetup →
open http://ROBOT_IP → Install OTA (file upload), or re-run the .ps1 with the new IP.

After fix: Install https://files.anki.org.uk/ota/latest from websetup.
