# Fix Seek Web Setup on Cloudflare (one paste)

Your OTA host already works: `http://files.anki.org.uk/ota/latest`

The **Install UI** was not on that host yet. Do this once:

## Paste the Worker (required)

1. Open [Cloudflare Dashboard](https://dash.cloudflare.com) → **Workers & Pages**
2. Open the Worker attached to **files.anki.org.uk**
3. **Edit code** → select all → delete
4. Paste the full contents of  
   [`seek/websetup-pages/worker-otas.js`](https://github.com/loganstorm1254-sudo/seek-cfw/blob/cursor/seek-web-dashboard-f1f4/seek/websetup-pages/worker-otas.js)
5. Confirm R2 binding is still named **`OTA`**
6. **Save and Deploy**

## Verify (30 seconds)

Chrome → **https://files.anki.org.uk/**

- Top-right: **UI seek16**
- Pair Vector → choose **Seek OS (latest)** → Install
- URL line must say: `http://files.anki.org.uk/ota/latest` (http, not https)

If you still see “Index of /” with only `OTA/`, the Worker paste did not deploy — repeat step 6.

## Notes

- Hotspot download of ~217 MB often takes **20–40 minutes**. Leave it alone; do not tap Try Again.
- Optional later: upload UI into R2 (`websetup/`) with `deploy-cloudflare.mjs` so the Worker does not need GitHub/jsDelivr.
- Do **not** enable Always Use HTTPS on `/ota*` or `/dl*`.
