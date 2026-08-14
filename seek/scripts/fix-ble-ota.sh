#!/bin/sh
# Fix BLE websetup OTA (status 203/204) on a live Seek robot.
#
# Stock update-engine uses TLS against Cloudflare → 203.
# /data is often ~58MB, too small for a 171MB OTA — store payload on /ota.
# BLE on old OS execs: /anki/bin/update-engine <url>
# BLE on new OS writes UPDATE_ENGINE_URL into an env file (no argv).
set -e

VERSION=5

mount -o remount,rw / 2>/dev/null || true
umount /usr/bin/curl 2>/dev/null || true
umount /usr/sbin/update-os 2>/dev/null || true
umount /anki/bin/update-engine 2>/dev/null || true

mkdir -p /ota /anki /data /run /run/update-engine /etc/systemd/system

pick_curl() {
  for c in /usr/bin/curl.anki /bin/curl /usr/bin/curl; do
    if [ -x "$c" ] && ! head -n 1 "$c" 2>/dev/null | grep -q '^#!'; then
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

if [ ! -e /anki/bin/update-engine.real ] || grep -q 'Seek BLE OTA wrap' /anki/bin/update-engine.real 2>/dev/null; then
  if [ -e /anki/bin/update-engine ] && ! grep -q 'Seek BLE OTA wrap' /anki/bin/update-engine 2>/dev/null; then
    cp -a /anki/bin/update-engine /anki/bin/update-engine.real
    chmod 755 /anki/bin/update-engine.real
  fi
fi

cat > /anki/bin/update-engine << 'EOF'
#!/bin/sh
# Seek BLE OTA wrap v5
mkdir -p /run/update-engine /ota
LOG=/run/update-engine/wrapper.log
echo "wrapper v5 start" >> "$LOG"
echo "env URL=${UPDATE_ENGINE_URL-}" >> "$LOG"
echo "args=$*" >> "$LOG"

export UPDATE_ENGINE_ALLOW_DOWNGRADE=True
export UPDATE_ENGINE_ENABLED=True

URL="${UPDATE_ENGINE_URL-}"
URL=`echo "$URL" | tr -d '"'`

if [ -z "$URL" ]; then
  for a in "$@"; do
    case "$a" in
      http://*|https://*) URL="$a" ;;
    esac
  done
fi

if [ -z "$URL" ]; then
  for f in /run/vic-switchboard/update-engine.env /run/update-engine-oneshot.env; do
    if [ -f "$f" ]; then
      U=`grep UPDATE_ENGINE_URL= "$f" 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d '"'`
      if [ -n "$U" ]; then
        URL="$U"
      fi
    fi
  done
fi

OTA=/ota/v.ota
SZ=0
[ -f "$OTA" ] && SZ=`stat -c %s "$OTA" 2>/dev/null || echo 0`

# Already have a full OTA on disk — flash it (website 203 with empty URL).
if [ -z "$URL" ] && [ "$SZ" -ge 8000000 ]; then
  URL="http://127.0.0.1:8767/v.ota"
  echo "no URL from BLE; reusing $OTA ($SZ)" >> "$LOG"
fi

if [ -z "$URL" ]; then
  URL="https://files.anki.org.uk/ota/latest"
  echo "defaulting URL=$URL" >> "$LOG"
fi

echo "using URL=$URL" >> "$LOG"

REAL=/anki/bin/update-engine.real
[ -x /data/update-engine.real ] && REAL=/data/update-engine.real
CURL=/usr/bin/curl.anki
[ -x "$CURL" ] || CURL=/usr/bin/curl

NEED=1
case "$URL" in
  http://127.0.0.1:*|http://localhost:*) NEED=0 ;;
esac
if [ "$SZ" -ge 8000000 ]; then
  echo "reusing existing $OTA ($SZ)" >> "$LOG"
  NEED=0
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

SZ=`stat -c %s "$OTA" 2>/dev/null || echo 0`
echo "ota size $SZ" >> "$LOG"
if [ "$SZ" -lt 8000000 ]; then
  echo "download too small ($SZ)" > /run/update-engine/error
  echo 204 > /run/update-engine/exit_code
  exit 204
fi

# BusyBox: -p PORT (IP:PORT is flaky on old httpd)
killall httpd 2>/dev/null || true
sleep 1
busybox httpd -p 8767 -h /ota >> "$LOG" 2>&1 || httpd -p 8767 -h /ota >> "$LOG" 2>&1 || true
sleep 1
CODE=`"$CURL" -k -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8767/v.ota 2>/dev/null || echo 000`
echo "local probe=$CODE" >> "$LOG"
if [ "$CODE" != "200" ] && [ "$CODE" != "206" ]; then
  echo "local httpd not serving OTA ($CODE)" > /run/update-engine/error
  echo 204 > /run/update-engine/exit_code
  exit 204
fi

echo "flashing local http://127.0.0.1:8767/v.ota" >> "$LOG"
exec "$REAL" -v "http://127.0.0.1:8767/v.ota"
EOF
chmod 755 /anki/bin/update-engine

cp -a /anki/bin/update-engine /data/update-engine-wrap 2>/dev/null || true
cp -a /anki/bin/update-engine.real /data/update-engine.real 2>/dev/null || true
chmod 755 /data/update-engine-wrap /data/update-engine.real 2>/dev/null || true

cat > /data/seek-ble-ota-apply.sh << 'EOF'
#!/bin/sh
mount -o remount,rw / 2>/dev/null || true
umount /anki/bin/update-engine 2>/dev/null || true
if [ -x /data/update-engine-wrap ]; then
  if grep -q 'Seek BLE OTA wrap v5' /anki/bin/update-engine 2>/dev/null; then
    exit 0
  fi
  cp -a /data/update-engine-wrap /anki/bin/update-engine
  chmod 755 /anki/bin/update-engine
fi
exit 0
EOF
chmod 755 /data/seek-ble-ota-apply.sh
sh /data/seek-ble-ota-apply.sh

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

echo "OK - BLE OTA fix v${VERSION}"
ls -la /anki/bin/update-engine /anki/bin/update-engine.real /ota/v.ota 2>/dev/null || true
grep 'Seek BLE OTA wrap' /anki/bin/update-engine
