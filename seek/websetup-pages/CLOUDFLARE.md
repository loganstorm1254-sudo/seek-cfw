# Cloudflare — fast websetup (Pages zip)

The **zip on Cloudflare Pages** is the fast UI (static files on the edge).
Serving `/setup` from the Worker via GitHub/jsDelivr is slower — don’t use that for the UI.

## 1) Pages (websetup UI) — do this

1. Download `seek-websetup-pages.zip` from this folder / the PR / release  
2. Cloudflare Dashboard → **Workers & Pages** → your **Pages** project  
3. **Upload assets** / replace deployment with the zip  
   - Zip root must contain `index.html` (not a nested folder)  
4. Hard refresh the Pages URL (`Ctrl+Shift+R`)  
5. Confirm top-right **UI seek21**

That site talks BLE; Install still tells Vector to fetch:
`http://files.anki.org.uk/ota/latest`

## 2) Worker (OTA files only)

Keep the Worker on **files.anki.org.uk** for `/ota/latest`, `/api/otas.json`, `/dl/…`, `/files`.  
Paste current `worker-otas.js` if needed. R2 binding name: **OTA**.

Upload full OTA to R2:
https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.64d/vicos-3.0.1.64d.ota

## 3) Optional: landing on files.anki.org.uk

Worker `/` can stay as a small landing that links to your **Pages** websetup URL.
If Worker `/setup` feels slow, open the Pages URL instead.
