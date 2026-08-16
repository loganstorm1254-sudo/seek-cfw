Seek Web Setup (Cloudflare Pages)
=================================

Everyone uses this site over BLE. Nobody needs SSH.

Vector cannot verify HTTPS (status 203). Chrome talks to this site over
HTTPS; Install tells the robot to fetch **http://** (no TLS).

http://files.anki.org.uk/ota/latest  already returns HTTP 200 (no redirect).

------------------------------------------------
Speed (read this)
------------------------------------------------
Cloudflare Pages + phone hotspot pulls ~217 MB over cellular. That often
takes **20–40 minutes**. The percent bar lying past 100% is an old UI bug —
real size is ~217 MB; leave it alone until reboot.

**Fast path (~2–5 min):** run local Seek Web Setup on a Mac/PC joined to
the **same** hotspot as Vector:

  cd seek/websetup
  npm install
  node bin/seek-web-setup.js ota-sync
  node bin/seek-web-setup.js serve

Chrome → http://localhost:8000/ → pair → Install.
Robot URL looks like http://192.168.x.x:8000/firmware/latest.ota (LAN).

------------------------------------------------
What other people do (public Pages)
------------------------------------------------
1. Open the Seek Web Setup Pages site in Chrome.
2. Confirm the top-right badge says **UI seek16** (if not, redeploy the zip).
3. Pair Vector over Bluetooth, join the phone hotspot.
4. Choose **Seek OS (latest)** → Install.
5. Leave the page open. Wait for reboot. Do not tap Try Again.

The robot downloads: http://files.anki.org.uk/ota/latest

SeekOS 3.0.1.44d and later ship the BLE wrap + HTTP fallback inside the
OTA, so later updates work the same with no extra steps.

------------------------------------------------
Worker (required for the robot to pull)
------------------------------------------------
Paste the CURRENT worker-otas.js, bind R2 as OTA, Deploy.
The file MUST define function otaResponse. A broken Worker returns
1101 and Vector never downloads anything — the bar stays at 0%.

/api/otas.json includes url (https) and robotUrl (http).

------------------------------------------------
Pages
------------------------------------------------
settings.json:
  "otaListUrl": "https://files.anki.org.uk/api/otas.json"

Upload seek-websetup-pages.zip (index.html at the zip root).
Hard-refresh Chrome. You MUST see **UI seek16** top-right and
script rts.seek16.js in DevTools → Network.

Do NOT enable a Cloudflare "Always Use HTTPS" rule on /ota* or /dl*
or the robot will follow the redirect and 203 again.

After every Pages zip upload, confirm Install shows:
  URL: http://files.anki.org.uk/ota/latest
(not https).

------------------------------------------------
Maintainer recovery (optional, not for users)
------------------------------------------------
SSH wrap is only for a robot that already has a stuck local /ota/v.ota.
Public installs never use it.
