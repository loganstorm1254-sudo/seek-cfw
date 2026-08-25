# Seek Wi‑Fi Flash

Flash SeekOS over **Vector’s Wi‑Fi** from your PC. Upload your SSH key, enter his IP, pick a release — done.

Runs a tiny **local** server on your machine (SSH from the browser isn’t possible; this handles it for you).

## Download (no git)

**https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.17d-dvt/seek-wifi-flash.zip**

Unzip → `npm install` → `npm start` → http://127.0.0.1:3847

## Quick start

```bash
cd seek/wifi-flash
npm install
npm start
```

Open **http://127.0.0.1:3847**

1. PC on the **same Wi‑Fi** as Vector (not Vector’s hotspot unless that’s your setup)
2. Vector on **charger**
3. Pick release (auto-loaded from GitHub `*-dvt` tags)
4. Enter IP (e.g. `192.168.43.3`)
5. Upload **ssh_root_key** (your unlock private key)
6. **Flash from GitHub** — watch the log; ~5–10 min, eyes go dark, reboot

After reboot: `http://<vector-ip>:8080/dash.html`

## Why not the Cloudflare websetup?

Browsers **cannot SSH** to Vector. HTTPS pages also **block** `http://192.168.x.x` (mixed content), so “Wi‑Fi flash” from a hosted site fails. This tool runs on **localhost** and SSHs for you.

## Requirements

- Node.js 18+
- Unlocked Vector with SSH root + your key
- Same LAN as Vector
