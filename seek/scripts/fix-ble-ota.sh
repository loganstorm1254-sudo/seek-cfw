#!/bin/sh
# Fix BLE websetup OTA (status 203) on a live Seek robot.
#
# Stock update-engine uses Python SSL against Cloudflare → 203
# (broken CA bundle). /data is often ~58MB, too small for a 171MB OTA.
#
# This wraps /anki/bin/update-engine: curl -k the OTA onto /ota (rootfs),
# serve it on 127.0.0.1, flash over HTTP (no TLS).
set -e

VERSION=4

mount -o remount,rw / 2>/dev/null || true
umount /usr/bin/curl 2>/dev/null || true
umount /usr/sbin/update-os 2>/dev/null || true
umount /anki/bin/update-engine 2>/dev/null || true

mkdir -p /ota /anki /run /run/update-engine /etc/systemd/system

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
if [ ! -x /usr/bin/curl.anki ]; then
  cp -L "$REALCURL" /usr/bin/curl.anki 2>/dev/null || cp "$REALCURL" /usr/bin/curl.anki
  chmod 755 /usr/bin/curl.anki
fi

cat > /usr/bin/curl << 'EOF'
#!/bin/sh
exec /usr/bin/curl.anki -k -L --http1.1 -4 --connect-timeout 30 "$@"
EOF
chmod 755 /usr/bin/curl

# Save original update-engine once (ELF or python — not our wrapper)
if [ ! -e /anki/bin/update-engine.real ] || grep -q 'Seek BLE OTA wrap' /anki/bin/update-engine.real 2>/dev/null; then
  if [ -e /anki/bin/update-engine ] && ! grep -q 'Seek BLE OTA wrap' /anki/bin/update-engine 2>/dev/null; then
    cp -a /anki/bin/update-engine /anki/bin/update-engine.real
    chmod 755 /anki/bin/update-engine.real
  fi
fi

# Wrapper lives in-place so BLE / vic-switchboard always hit it (no systemd unit required).
cat > /anki/bin/update-engine << 'EOF'
#!/bin/bash
# Seek BLE OTA wrap v4
mkdir -p /run/update-engine /ota
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

REAL=/anki/bin/update-engine.real
CURL=/usr/bin/curl.anki
[ -x "$CURL" ] || CURL=/usr/bin/curl
OTA=/ota/v.ota

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

NEED=1
if [ -f "$OTA" ]; then
  SZ=$(stat -c %s "$OTA" 2>/dev/null || echo 0)
  if [ "$SZ" -ge 8000000 ]; then
    echo "reusing existing $OTA ($SZ bytes)" >> "$LOG"
    NEED=0
  fi
fi

if [ "$NEED" = 1 ]; then
  echo "Downloading to $OTA ..." >> "$LOG"
  rm -f "$OTA"
  if ! "$CURL" -k -L --http1.1 -4 --retry 3 --connect-timeout 30 --max-time 1800 -o "$OTA" "$URL" >> "$LOG" 2>&1; then
    echo "download failed" > /run/update-engine/error
    echo 204 > /run/update-engine/exit_code
    echo "download failed" >> "$LOG"
    exit 204
  fi
fi
SZ=$(stat -c %s "$OTA" 2>/dev/null || echo 0)
echo "ota size $SZ bytes" >> "$LOG"
if [ "$SZ" -lt 8000000 ]; then
  echo "download too small ($SZ)" > /run/update-engine/error
  echo 204 > /run/update-engine/exit_code
  exit 204
fi

killall httpd 2>/dev/null || true
sleep 1
busybox httpd -p 127.0.0.1:8767 -h /ota 2>/dev/null || httpd -p 127.0.0.1:8767 -h /ota 2>/dev/null || true
sleep 1
echo "flashing local http://127.0.0.1:8767/v.ota" >> "$LOG"
exec "$REAL" -v "http://127.0.0.1:8767/v.ota"
EOF
chmod 755 /anki/bin/update-engine

# Persist tiny files on /data (survives reboot). OTA payload stays on /ota.
mkdir -p /data
cp -a /anki/bin/update-engine /data/update-engine-wrap 2>/dev/null || true
cp -a /anki/bin/update-engine.real /data/update-engine.real 2>/dev/null || true
chmod 755 /data/update-engine-wrap /data/update-engine.real 2>/dev/null || true

cat > /data/seek-ble-ota-apply.sh << 'EOF'
#!/bin/sh
mount -o remount,rw / 2>/dev/null || true
umount /anki/bin/update-engine 2>/dev/null || true
if [ -x /data/update-engine-wrap ]; then
  if grep -q 'Seek BLE OTA wrap' /anki/bin/update-engine 2>/dev/null; then
    exit 0
  fi
  mount --bind /data/update-engine-wrap /anki/bin/update-engine 2>/dev/null || \
    cp -a /data/update-engine-wrap /anki/bin/update-engine
fi
exit 0
EOF
chmod 755 /data/seek-ble-ota-apply.sh
cp -a /data/seek-ble-ota-apply.sh /anki/seek-ble-ota-apply.sh 2>/dev/null || true

cat > /etc/systemd/system/seek-ble-ota-fix.service << EOF
[Unit]
Description=Seek BLE OTA fix v${VERSION}
DefaultDependencies=no
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/data/seek-ble-ota-apply.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload 2>/dev/null || true
systemctl enable seek-ble-ota-fix.service 2>/dev/null || true

echo "OK - BLE OTA fix v${VERSION} (curl -k, OTA stored in /ota, in-place wrap)."
echo "Retry websetup Install. Log: /run/update-engine/wrapper.log"
ls -la /anki/bin/update-engine /anki/bin/update-engine.real /ota/v.ota 2>/dev/null || true
head -2 /anki/bin/update-engine
