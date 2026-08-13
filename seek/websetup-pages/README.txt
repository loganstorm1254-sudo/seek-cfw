Seek / Vector Web Setup — Cloudflare Pages zip
==============================================

Based on Digital Dream Labs vector-web-setup (MIT):
https://github.com/digital-dream-labs/vector-web-setup

This zip is static (no Node server). Upload it to Cloudflare Pages and
attach setup.YOURDOMAIN.com

------------------------------------------------
1) EDIT YOUR OTA URL (required)
------------------------------------------------
Open this file inside the zip (or after unzip):

  static/data/inventory.json

Change:

  https://FILES.YOURDOMAIN.com/vicos-3.0.1.42d.ota

to your real R2 / Worker file URL, for example:

  https://files.yourdomain.com/vicos-3.0.1.42d.ota
  or
  https://gentle-smoke-XXXX.workers.dev/vicos-3.0.1.42d.ota

Add more objects under "seek" for more OTAs.

------------------------------------------------
2) UPLOAD TO CLOUDFLARE PAGES
------------------------------------------------
1. Go to Cloudflare Dashboard
2. Workers & Pages → Create → Pages → Upload assets
3. Upload this whole folder (or the zip contents)
4. After deploy: Custom domains → add:

     setup.yourdomain.com

5. Wait until Active, open https://setup.yourdomain.com in Chrome

------------------------------------------------
3) USE IT
------------------------------------------------
- Chrome only (Web Bluetooth)
- Vector on charger
- Recovery / double-press as the page says
- Pair with Vector
- Choose stack "seek"
- Pick OTA → install

------------------------------------------------
4) NOTES
------------------------------------------------
- BLE requires https:// (Pages gives you that) or localhost
- OTAs must be direct https links (R2/Worker). GitHub release
  redirects often fail on the robot — use your files host.
- Account endpoints in settings.json are stock Anki keys for
  cloud authorize steps. OTA install in recovery mainly needs BLE + URL.

License: MIT (Digital Dream Labs). Seek packaging for Pages.
