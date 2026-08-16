# Cloudflare (files.anki.org.uk)

Paste [`worker-otas.js`](./worker-otas.js) → Deploy (R2 binding **OTA**).

## Full Seek on the site (no scripts)

1. Upload **vicos-3.0.1.64d.ota** to R2 (`OTA/`) so `/ota/latest` is the full ~217 MB build  
   https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.64d/vicos-3.0.1.64d.ota  
2. Chrome → https://files.anki.org.uk/setup (**UI seek21**)  
3. Pair → connect Vector to **home Wi‑Fi** → Install **Seek OS (latest)**  

Home Wi‑Fi = broadband (usually a few minutes).  
Phone hotspot = cellular (often 20–40 min for the same full file).

Optional: Cloudflare → Network → turn **HTTP/3** off for this zone.
