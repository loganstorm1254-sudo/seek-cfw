Seek Web Setup
==============

Online Pages (pairing / Wi-Fi only)
  Upload seek-websetup-pages.zip to Cloudflare Pages.
  settings.json otaListUrl: https://files.anki.org.uk/api/otas.json
  Worker: worker-otas.js  R2 binding OTA

OTA Install (avoids status 203)
  The online HTTPS URL cannot be opened by Vector (broken CA → 203).
  Same as original Vector Web Setup: serve OTAs over LAN HTTP from your PC.

  1. Install Node.js
  2. Double-click seek/websetup/serve.cmd
     or:  cd seek/websetup && node bin/seek-web-setup.js ota-sync && node bin/seek-web-setup.js serve
  3. Chrome → http://localhost:8000/
  4. Pair → Wi-Fi → pick OTA → Install

Robot fetches http://YOUR-PC-IP:8000/firmware/latest.ota (no TLS).
