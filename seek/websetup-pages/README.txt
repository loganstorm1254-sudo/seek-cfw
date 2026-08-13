Seek Web Setup — auto OTA menu from R2
======================================

Upload .ota files to your R2 bucket under folder:

  OTA/
    vicos-3.0.1.42d.ota
    vicos-3.0.1.41d.ota
    ...

The setup site loads them automatically. No inventory edits each release.

------------------------------------------------
A) Worker (file host) — do once
------------------------------------------------
1. Cloudflare Worker (your file host) → replace code with worker-otas.js
   from this folder
2. Settings → Bindings → R2 bucket named exactly: OTA
3. Custom domain e.g. files.yourdomain.com  (or use workers.dev URL)
4. Test in browser:
   https://files.yourdomain.com/api/otas.json
   You should see JSON listing every .ota under OTA/

------------------------------------------------
B) Pages (setup GUI) — do once, then only upload OTAs
------------------------------------------------
1. Edit static/data/settings.json → set otaListUrl:

   "otaListUrl": "https://files.yourdomain.com/api/otas.json"

2. Cloudflare Pages → Upload this site → custom domain setup.yourdomain.com
3. Open https://setup.yourdomain.com in Chrome
4. Pair Vector → stack "seek" → pick an OTA from the auto list

------------------------------------------------
C) Every new release
------------------------------------------------
Only this:
  Upload vicos-x.y.z.ota into the R2 bucket folder OTA/

Refresh setup.yourdomain.com — it appears in the menu.

Based on https://github.com/digital-dream-labs/vector-web-setup (MIT)
