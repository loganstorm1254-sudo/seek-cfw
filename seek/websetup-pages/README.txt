Seek Web Setup (Cloudflare Pages) — FAST UI (old zip mechanism)
===============================================================

This zip is the same Direct Upload flow as before: static files on the
Cloudflare edge. That is what felt fast.

1. Download seek-websetup-pages.zip
2. Cloudflare → Workers & Pages → your Pages project → Upload assets
   (zip root must contain index.html)
3. Open the Pages URL (NOT files.anki.org.uk/setup)
4. Hard refresh until top-right shows: UI seek22

files.anki.org.uk is for OTA only:
  http://files.anki.org.uk/ota/latest

Optional (so /setup on files.anki.org.uk is fast again):
  A) Worker var WEBSETUP_PAGES_URL = your Pages URL  → /setup redirects
  B) Upload unzipped zip into R2 under websetup/     → /setup serves edge files

Do NOT use Worker → GitHub/jsDelivr UI proxy (removed; that was the slow path).

Install tip: Vector on home Wi-Fi, not phone hotspot.
Full OTA (~217 MB): vicos-3.0.1.64d.ota on R2 as latest.
