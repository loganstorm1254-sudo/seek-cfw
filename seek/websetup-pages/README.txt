Seek Web Setup (Cloudflare Pages)
=================================

Vector cannot verify HTTPS (status 203). This site lists OTAs over HTTPS
in Chrome, but Install tells the robot to fetch **http://** (no TLS).

http://files.anki.org.uk/ota/latest  already returns HTTP 200 (no redirect).

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

Zip the websetup-pages folder (index.html at the zip root) and upload.
Hard-refresh Chrome so rts.js?v=seek9 loads.

Robot downloads: http://files.anki.org.uk/dl/... or
http://files.anki.org.uk/ota/latest

Do NOT enable a Cloudflare "Always Use HTTPS" rule on /ota* or /dl*
or the robot will follow the redirect and 203 again.

------------------------------------------------
Robot wrap v8 (SSH once)
------------------------------------------------
Unstick the update face, then install the wrap that downloads over HTTP
to /ota/v.ota and writes BLE progress files:

ssh ... root@ROBOT "curl -k -L -4 -o /tmp/r.sh https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/scripts/recover-ota.sh && sh /tmp/r.sh"

Want: FACE / OK - BLE OTA fix v8
