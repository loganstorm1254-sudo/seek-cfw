# Cloudflare — fast websetup (Pages zip = old mechanism)

The **Pages Direct Upload zip** is the fast UI. Static files on the edge.
The old Worker→GitHub/jsDelivr `/setup` path is removed (that felt slow).

## 1) Pages (do this)

1. Download `seek-websetup-pages.zip`
2. Cloudflare → **Workers & Pages** → Pages project → **Upload assets**
3. Open the **Pages URL**, hard-refresh until **UI seek22**

Install still uses: `http://files.anki.org.uk/ota/latest`

## 2) Worker (OTA only)

Paste `worker-otas.js` on **files.anki.org.uk** (R2 binding **OTA**).

Optional env var:
- `WEBSETUP_PAGES_URL` = `https://your-project.pages.dev`  
  → `/setup` redirects to Pages (so bookmarks still work)

Or upload unzipped zip into R2 under `websetup/` for edge-fast `/setup`.

## 3) R2 OTA file

Upload full build:
https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.65d/vicos-3.0.1.65d.ota
