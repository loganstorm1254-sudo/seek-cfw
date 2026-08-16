# Seek Web Setup

All on the website — no scripts required.

## Fast path

1. Chrome → https://files.anki.org.uk/setup  
2. Pair Vector over Bluetooth  
3. Join **home Wi‑Fi** (not a phone hotspot)  
4. Install **Seek OS (latest)**  
5. Leave the tab open until Vector reboots  

## Why hotspot feels slow

Vector downloads ~217 MB from Cloudflare. On a phone hotspot that traffic
goes through cellular. On home Wi‑Fi it uses your broadband.

## Local optional tools

`fast-ota.ps1` / `node bin/seek-web-setup.js serve` still exist for advanced
LAN installs, but normal users only need the site + home Wi‑Fi.
