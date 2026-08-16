# Cloudflare deploy (Seek Web Setup + OTA)

Your OTA host is already Cloudflare: **https://files.anki.org.uk**

This makes the **same host** serve Seek Web Setup (seek16), so you do not
depend on a separate Pages project staying in sync.

## What you do (about 5 minutes)

### 1) Paste the Worker

1. Cloudflare Dashboard → **Workers & Pages** → your Worker for `files.anki.org.uk`
2. Edit code → replace with `seek/websetup-pages/worker-otas.js` from this repo
3. Confirm R2 binding name is still **`OTA`**
4. **Save and Deploy**

### 2) Upload the UI into R2

Put the websetup files under prefix **`websetup/`** in that same R2 bucket.

**Option A — script (recommended)**

```bash
export CLOUDFLARE_API_TOKEN=...          # Workers Scripts + R2 Edit
export SEEK_R2_BUCKET=YOUR_BUCKET_NAME  # bucket bound as OTA
node seek/websetup-pages/deploy-cloudflare.mjs --ui-only
```

**Option B — dashboard**

R2 → your OTA bucket → Upload:
- `websetup/index.html`
- `websetup/static/...` (keep folder structure from `seek/websetup-pages/`)

Do **not** upload `seek-websetup-pages.zip` or `worker-otas.js` into R2.

### 3) Verify

Chrome → **https://files.anki.org.uk/**

- Top-right badge: **UI seek16**
- Pair Vector → Install → URL line: `http://files.anki.org.uk/ota/latest` (http, not https)

If you still see percent past 100% or no **UI seek16**, the UI upload did not land — redo step 2 and hard-refresh.

## Pages project (optional)

You can still upload `seek-websetup-pages.zip` to a Cloudflare Pages project.
Prefer **https://files.anki.org.uk/** so UI + OTA stay on one deploy.

## Rules that keep Vector working

- Do **not** enable Always Use HTTPS on `/ota*` or `/dl*`
- Robot must receive **http://** OTA URLs (status 203 = HTTPS)
- Full Seek OS is ~217 MB; on a phone hotspot expect ~20–40 min. Leave it alone until reboot.

## After every websetup change

1. Paste updated `worker-otas.js` (if Worker changed)
2. Re-run `deploy-cloudflare.mjs --ui-only`
3. Confirm **UI seek16** (or newer) on https://files.anki.org.uk/
