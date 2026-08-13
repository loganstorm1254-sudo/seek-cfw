Seek / Vector Web Setup — Cloudflare Pages
==========================================

Based on: https://github.com/digital-dream-labs/vector-web-setup (MIT)

------------------------------------------------
1) ADD / EDIT OTAs (multi-select menu)
------------------------------------------------
Edit:

  static/data/inventory.json

Each entry under "seek" is one row in the OTA menu.
With 2+ entries, users get a picker. With 1 entry, it auto-starts.

Example:

{
  "seek": [
    {
      "url": "https://files.yourdomain.com/vicos-3.0.1.42d.ota",
      "name": "SeekOS 3.0.1.42d (latest)",
      "checksum": ""
    },
    {
      "url": "https://files.yourdomain.com/vicos-3.0.1.41d.ota",
      "name": "SeekOS 3.0.1.41d",
      "checksum": ""
    },
    {
      "url": "https://files.yourdomain.com/vicos-3.0.1.40d.ota",
      "name": "SeekOS 3.0.1.40d",
      "checksum": ""
    }
  ]
}

Replace FILES.YOURDOMAIN.com with your real R2 / Worker host.
Upload each .ota file to that host with the same filename.

------------------------------------------------
2) UPLOAD TO CLOUDFLARE PAGES
------------------------------------------------
1. Workers & Pages → Create → Pages → Upload assets
2. Upload these files (folder contents)
3. Custom domains → setup.yourdomain.com
4. Open https://setup.yourdomain.com in Chrome

------------------------------------------------
3) USE IT
------------------------------------------------
Chrome + Bluetooth PC
Vector on charger → recovery / double-press as shown
Pair with Vector → stack "seek" → pick an OTA from the menu → install

------------------------------------------------
4) NOTES
------------------------------------------------
Use direct https OTA links (R2/Worker), not GitHub release redirects.
BLE requires https (Pages) or localhost.
