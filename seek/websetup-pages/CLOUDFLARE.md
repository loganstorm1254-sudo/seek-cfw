# Cloudflare (files.anki.org.uk)

Paste [`worker-otas.js`](./worker-otas.js) into your Worker → Deploy (R2 binding **OTA**).

| URL | What |
|-----|------|
| https://files.anki.org.uk/ | Landing |
| https://files.anki.org.uk/setup | Seek Web Setup (UI seek19) |
| https://files.anki.org.uk/files | White OTA directory listing |
| http://files.anki.org.uk/ota/latest | Robot download (HTTP) |

## Fast install (all on the site — no scripts)

1. Chrome → https://files.anki.org.uk/setup  
2. Pair Vector  
3. Connect Vector to **home Wi‑Fi** (not phone hotspot)  
4. Install **Seek OS (latest)**  
5. Wait for reboot  

Home Wi‑Fi uses your broadband. Phone hotspot uses cellular (~20–40 min for 217 MB).

Optional: Cloudflare Dashboard → Network → turn **HTTP/3** off for this zone (helps Vector’s old curl).

Hard-refresh after Worker deploy until `/setup` shows **UI seek19**.
