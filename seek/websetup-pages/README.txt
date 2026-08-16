Seek Web Setup (Cloudflare Pages)
=================================

Everyone uses this site over BLE. Nobody needs SSH.

Vector cannot verify HTTPS (status 203). Chrome talks to this site over
HTTPS; Install tells the robot to fetch **http://** (no TLS).

http://files.anki.org.uk/ota/latest  already returns HTTP 200 (no redirect).

------------------------------------------------
What other people do
------------------------------------------------
1. Open the Seek Web Setup Pages site in Chrome.
2. Pair Vector over Bluetooth, join the phone hotspot.
3. Choose **Seek OS (latest)** → Install.
4. Leave the page open. The bar often freezes during flash — wait for
   Vector to reboot (a few minutes). Do not tap Try Again.

The robot downloads: http://files.anki.org.uk/ota/latest

For a **faster** first flash (especially stock Unlock), run the local
Mac/PC server instead so the robot pulls over LAN HTTP — see
`../websetup/README.md`.

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
Hard-refresh Chrome so rts.js?v=seek15 loads.

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
