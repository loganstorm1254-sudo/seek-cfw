# Seek Web Setup

Chrome ↔ Vector over BLE. For a **fast** flash, the robot must pull the
~217 MB OTA over **LAN HTTP from this PC** (same hotspot) — not through
the phone’s cellular link to Cloudflare (that is often 20–40 minutes).

## Fast install (recommended)

```bash
cd seek/websetup
npm install   # once
node bin/seek-web-setup.js fast-ota
```

Windows: double-click `fast-ota.cmd`.

It prints something like `http://192.168.x.x:8765/latest.ota`.

1. Join this PC to the **same hotspot** as Vector
2. Chrome → https://files.anki.org.uk/setup → pair
3. Paste that URL into **Fast install** → Install

## Full local UI (also fast)

```bash
node bin/seek-web-setup.js ota-sync
node bin/seek-web-setup.js serve
```

Chrome → http://localhost:8000/

## Cloudflare-only (slow)

Using Install with `http://files.anki.org.uk/ota/latest` makes Vector
download ~217 MB via cellular. Expect 20–40 minutes. Prefer Fast install.
