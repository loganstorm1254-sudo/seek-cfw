Seek Web Setup on Cloudflare
============================

Primary host: https://files.anki.org.uk/

Chrome uses HTTPS for the UI. Install tells Vector to fetch
http://files.anki.org.uk/ota/latest (plain HTTP — Vector cannot do TLS).

Deploy steps: see CLOUDFLARE.md
  1) Paste worker-otas.js into your files.anki.org.uk Worker + Deploy
  2) Upload UI to R2 under websetup/ (deploy-cloudflare.mjs --ui-only)
  3) Open https://files.anki.org.uk/ — top-right must say UI seek16

OTA list: https://files.anki.org.uk/api/otas.json
settings.json already points otaListUrl there.

Hotspot downloads of ~217 MB often take 20–40 minutes. That is expected.
Do not tap Try Again while bytes are still climbing.

Optional alternate: upload seek-websetup-pages.zip to a Pages project.
Prefer files.anki.org.uk so UI + OTA stay on one Cloudflare deploy.

Do NOT enable Always Use HTTPS on /ota* or /dl*.
