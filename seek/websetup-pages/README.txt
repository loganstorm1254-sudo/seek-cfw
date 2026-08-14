Seek Web Setup (Cloudflare Pages)
=================================

Vector cannot verify HTTPS (status 203). This site lists OTAs over HTTPS
in Chrome, but Install tells the robot to fetch **http://** (no TLS).

http://files.anki.org.uk/ota/latest  already returns HTTP 200 (no redirect).

------------------------------------------------
Worker
------------------------------------------------
Paste worker-otas.js, bind R2 as OTA, Deploy.
/api/otas.json includes url (https) and robotUrl (http).

------------------------------------------------
Pages
------------------------------------------------
settings.json:
  "otaListUrl": "https://files.anki.org.uk/api/otas.json"

Upload seek-websetup-pages.zip
Chrome → pair → Wi-Fi → Install

Robot downloads: http://files.anki.org.uk/dl/seek-os-3.01.42d.ota
(or http://files.anki.org.uk/ota/latest)

Do NOT enable a Cloudflare "Always Use HTTPS" rule on /ota* or /dl*
or the robot will follow the redirect and 203 again.
