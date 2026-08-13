#!/bin/sh
# Fix BLE websetup OTA (status 203) on a live Seek robot.
# Strategy: download the OTA with a known-good curl to /data/ota/v.ota,
# then run real update-engine against http://127.0.0.1:8766/v.ota
# (Vector's updater often can't open Cloudflare URLs directly → 203).
#
# Also: many Seek robots have a broken CA store (curl exit 77). We use -k.
# Bind-mounts die on reboot — this installs a oneshot that re-applies them.
set -e

VERSION=3

mount -o remount,rw / 2>/dev/null || true
umount /usr/bin/curl 2>/dev/null || true
umount /usr/sbin/update-os 2>/dev/null || true
umount /anki/bin/update-engine 2>/dev/null || true

mkdir -p /data /data/ota /run /run/update-engine /etc/systemd/system

# Real curl binary on /data (never overwrite busy /usr/bin/curl)
pick_curl() {
  for c in /usr/bin/curl.anki /bin/curl /usr/bin/curl; do
    if [ -x "$c" ] && ! head -1 "$c" 2>/dev/null | grep -q '^#!'; then
      echo "$c"
      return 0
    fi
  done
  echo /usr/bin/curl
}
REALCURL=$(pick_curl)
cp -L "$REALCURL" /data/curl.anki 2>/dev/null || cp "$REALCURL" /data/curl.anki
chmod 755 /data/curl.anki

# -k: Vector CA bundle is often missing/broken (curl: 77)
cat > /data/curl-shim << 'EOF'
#!/bin/sh
exec /data/curl.anki -k -L --http1.1 -4 --connect-timeout 30 "$@"
EOF
chmod 755 /data/curl-shim

# Save real update-engine once (must be ELF, not a script)
if [ ! -x /data/update-engine.real ] || head -1 /data/update-engine.real 2>/dev/null | grep -q '^#!'; then
  umount /anki/bin/update-engine 2>/dev/null || true
  SRC=/anki/bin/update-engine
  [ -x /anki/bin/update-engine.real ] && SRC=/anki/bin/update-engine.real
  cp -a "$SRC" /data/update-engine.real
  chmod 755 /data/update-engine.real
fi

# Wrapper: BLE starts update-engine.service → we download then flash local
cat > /data/update-engine-wrap << 'EOF'
#!/bin/bash
mkdir -p /run/update-engine /data/ota
LOG=/run/update-engine/wrapper.log
echo "wrapper start $(date)" >> "$LOG"
echo "env URL=${UPDATE_ENGINE_URL-}" >> "$LOG"
echo "args=$*" >> "$LOG"

export UPDATE_ENGINE_ALLOW_DOWNGRADE=True
export UPDATE_ENGINE_ENABLED=True

URL="${UPDATE_ENGINE_URL-}"
URL="${URL%\"}"
URL="${URL#\"}"
if [ -z "$URL" ]; then
  for a in "$@"; do
    case "$a" in
      http://*|https://*) URL="$a" ;;
    esac
  done
fi
echo "using URL=$URL" >> "$LOG"

REAL=/data/update-engine.real
CURL=/data/curl.anki

# Already a local flash URL — just run engine
case "$URL" in
  http://127.0.0.1:*|http://localhost:*)
    exec "$REAL" -v "$URL"
    ;;
esac

if [ -z "$URL" ]; then
  echo "no URL" > /run/update-engine/error
  echo 203 > /run/update-engine/exit_code
  exit 203
fi

echo "Downloading to /data/ota/v.ota ..." >> "$LOG"
rm -f /data/ota/v.ota
# -k: broken CA store on many Vectors (curl 77)
if ! "$CURL" -k -L --http1.1 -4 --retry 3 --connect-timeout 30 --max-time 1800 -o /data/ota/v.ota "$URL" >> "$LOG" 2>&1; then
  echo "download failed" > /run/update-engine/error
  echo 204 > /run/update-engine/exit_code
  echo "download failed" >> "$LOG"
  exit 204
fi
SZ=$(stat -c %s /data/ota/v.ota 2>/dev/null || echo 0)
echo "downloaded $SZ bytes" >> "$LOG"
if [ "$SZ" -lt 8000000 ]; then
  echo "download too small ($SZ)" > /run/update-engine/error
  echo 204 > /run/update-engine/exit_code
  exit 204
fi

# Local HTTP for update-engine (no Cloudflare)
killall httpd 2>/dev/null || true
busybox httpd -p 127.0.0.1:8766 -h /data/ota 2>/dev/null || httpd -p 127.0.0.1:8766 -h /data/ota 2>/dev/null || true
sleep 1
echo "flashing local http://127.0.0.1:8766/v.ota" >> "$LOG"
exec "$REAL" -v "http://127.0.0.1:8766/v.ota"
EOF
chmod 755 /data/update-engine-wrap

# update-os for SSH / otaFromUrl — fetch with -k; keep existing if fetch fails
if [ ! -f /data/update-os.sh ] || ! grep -q 'http1.1\|-k' /data/update-os.sh 2>/dev/null; then
  /data/curl.anki -k -L --http1.1 -4 --max-time 60 -o /data/update-os.sh \
    https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/overlays/anki/wired/update-os.sh || true
  chmod 644 /data/update-os.sh 2>/dev/null || true
fi
# Ensure -k is present even on older cached update-os.sh
if [ -f /data/update-os.sh ] && ! grep -q -- ' -k ' /data/update-os.sh 2>/dev/null; then
  sed -i 's|exec /usr/bin/curl.anki -L|exec /usr/bin/curl.anki -k -L|g' /data/update-os.sh 2>/dev/null || true
fi
touch /data/keep-update-os 2>/dev/null || true
printf '%s\n' '#!/bin/bash' 'exec /bin/bash /data/update-os.sh "$@"' >/data/update-os-wrap
chmod 755 /data/update-os-wrap

# Boot-safe apply: rebind after every reboot
cat > /data/seek-ble-ota-apply.sh << 'EOF'
#!/bin/sh
# Re-apply Seek BLE OTA fix after boot (bind-mounts do not persist).
mount -o remount,rw / 2>/dev/null || true
umount /usr/bin/curl 2>/dev/null || true
umount /usr/sbin/update-os 2>/dev/null || true
umount /anki/bin/update-engine 2>/dev/null || true
[ -x /data/curl-shim ] && mount --bind /data/curl-shim /usr/bin/curl 2>/dev/null || true
[ -x /data/update-engine-wrap ] && mount --bind /data/update-engine-wrap /anki/bin/update-engine 2>/dev/null || true
if [ -f /data/update-os.sh ]; then
  if printf '%s\n' '#!/bin/bash' 'exec /bin/bash /data/update-os.sh "$@"' >/usr/sbin/update-os 2>/dev/null; then
    chmod 755 /usr/sbin/update-os
  else
    [ -x /data/update-os-wrap ] && mount --bind /data/update-os-wrap /usr/sbin/update-os 2>/dev/null || true
  fi
fi
exit 0
EOF
chmod 755 /data/seek-ble-ota-apply.sh

cat > /etc/systemd/system/seek-ble-ota-fix.service << EOF
[Unit]
Description=Seek BLE OTA fix (curl/update-engine bind mounts) v${VERSION}
DefaultDependencies=no
After=local-fs.target
Before=update-engine.service update-engine.timer

[Service]
Type=oneshot
ExecStart=/data/seek-ble-ota-apply.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload 2>/dev/null || true
systemctl enable seek-ble-ota-fix.service 2>/dev/null || true
/data/seek-ble-ota-apply.sh

echo "OK — BLE OTA fix v${VERSION} installed (download→local flash, -k TLS, survives reboot)."
echo "Log: /run/update-engine/wrapper.log"
mount | grep -E 'curl|update-engine' || true
ls -la /data/curl.anki /data/update-engine.real /data/update-engine-wrap /data/seek-ble-ota-apply.sh
systemctl is-enabled seek-ble-ota-fix.service 2>/dev/null || true
