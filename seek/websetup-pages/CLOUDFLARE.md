# Cloudflare (files.anki.org.uk)

Paste [`worker-otas.js`](./worker-otas.js) into your Worker → Deploy (R2 binding **OTA**).

| URL | What |
|-----|------|
| https://files.anki.org.uk/ | Landing |
| https://files.anki.org.uk/setup | Seek Web Setup |
| https://files.anki.org.uk/files | White OTA directory listing |
| https://files.anki.org.uk/fast-ota.ps1 | Windows Fast OTA helper |
| https://files.anki.org.uk/fast-ota.bat | Double-click launcher |
| http://files.anki.org.uk/ota/latest | Robot download (HTTP) |

## Fast install for users (easy)

1. PC + Vector on the **same phone hotspot**
2. PowerShell on the PC:
   ```
   irm https://files.anki.org.uk/fast-ota.ps1 | iex
   ```
3. Chrome → https://files.anki.org.uk/setup → pair → paste the printed LAN URL → Install

Hard-refresh after Worker deploy (`Ctrl+Shift+R`). `/setup` should show **UI seek18**.
