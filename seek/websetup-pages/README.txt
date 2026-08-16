Seek Web Setup (Cloudflare Pages) — FAST UI
============================================

Upload seek-websetup-pages.zip to Cloudflare Pages (index.html at zip root).
That is the fast setup UI (static on the CF edge).

Do NOT rely on https://files.anki.org.uk/setup for day-to-day use — the
Worker pulls UI from GitHub/CDN and feels slow. files.anki.org.uk is for
OTA files: /ota/latest, /api/otas.json, /files.

After upload, hard-refresh until top-right shows: UI seek21

Install still sends Vector:
  http://files.anki.org.uk/ota/latest

settings.json already points otaListUrl at that host.

Full OTA (~217 MB, everything):
  https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.64d/vicos-3.0.1.64d.ota
Upload that to R2 so /ota/latest is current.

Wi-Fi tip: home Wi-Fi for Install, not phone hotspot.
