# Cloudflare (files.anki.org.uk)

Paste [`worker-otas.js`](./worker-otas.js) into your Worker → Deploy (R2 binding **OTA**).

Then:

| URL | What |
|-----|------|
| https://files.anki.org.uk/ | Landing — two choices |
| https://files.anki.org.uk/setup | Seek Web Setup (UI seek16) |
| https://files.anki.org.uk/files | White OTA directory listing |
| http://files.anki.org.uk/ota/latest | Robot download (HTTP) |

Hard-refresh after deploy (`Ctrl+Shift+R`).
