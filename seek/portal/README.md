# Seek portal (host this yourself)

A small website you host. On your phone you enter **Vector’s IP** and the **Wi‑Fi name (SSID)**. It then opens the Seek dashboard **on your site** (same origin), so mobile browsers work — including HTTPS.

## 1. Run it

```bash
cd seek/portal
npm install
npm start
```

Listens on port **8787** (or `$PORT`). Put it behind Caddy/nginx/Cloudflare for HTTPS.

Example Caddy:

```
seek.yourdomain.com {
    reverse_proxy 127.0.0.1:8787
}
```

## 2. Point Vector at it (needed if the site is on the internet)

A VPS cannot reach `192.168.x.x`. Vector must connect **out**:

1. Install SeekOS **38d+** on the robot  
2. Open Seek on the robot IP once (PC is fine)  
3. **Look → Portal URL** → `wss://seek.yourdomain.com/vector` → Save  
4. Wait until it says **Portal connected**

If you host the portal **on the same Wi‑Fi** as Vector (home PC / Pi), you can skip this — the server talks to `:8080` directly.

## 3. Phone

1. Join the **same Wi‑Fi as Vector**  
2. Open `https://seek.yourdomain.com`  
3. IP = Vector’s LAN IP (example `192.168.42.209`)  
4. SSID = that Wi‑Fi’s name  
5. **Open Seek**

SSID must match what Vector reports (stops random people on the internet from guessing an IP).

## Security

Anyone who knows the IP **and** SSID can control that robot through your site. Don’t publish the URL widely. Add your own login in front if you need it.
