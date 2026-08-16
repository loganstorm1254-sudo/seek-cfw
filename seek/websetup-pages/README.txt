Seek Web Setup — FAST install
=============================

EASIEST (Windows CMD) — PC serves OTA over LAN:
  powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://files.anki.org.uk/fast-ota.ps1 | iex"

If that 404s (Worker not updated yet), use:
  powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/websetup-pages/fast-ota.ps1 | iex"

Then: leave CMD open → Chrome Pages websetup → pair Vector → paste the LAN URL
it prints (or use Install from PC) → done in a few minutes on local Wi-Fi.

Pages zip: upload seek-websetup-pages.zip → hard refresh until UI seek24
Robot cloud URL (slow on hotspot): http://files.anki.org.uk/ota/latest
