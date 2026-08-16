# Seek Web Setup

## Fast install (easiest — no git, no Node)

1. Join your **PC** to the **same phone hotspot** as Vector  
2. On Windows, open **PowerShell** and paste:

```powershell
irm https://files.anki.org.uk/fast-ota.ps1 | iex
```

Or download and double-click: https://files.anki.org.uk/fast-ota.bat

3. Chrome → https://files.anki.org.uk/setup → pair Vector  
4. Paste the `http://192.168.…:8765/latest.ota` URL into **Fast install** → Install  

Mac/Linux:

```bash
curl -fsSL https://files.anki.org.uk/fast-ota.sh | bash
```

## Full local UI

```bash
cd seek/websetup
npm install
node bin/seek-web-setup.js serve
```

## Slow path

Cloudflare Install without Fast OTA makes Vector pull ~217 MB over cellular (often 20–40 min).
