#!/bin/sh
# Fix BLE websetup OTA (status 203/204) on a live Seek robot.
#
# Stock update-engine uses TLS against Cloudflare → 203.
# /data is often ~58MB, too small for a 171MB OTA — store payload on /ota.
#
# v9: resume stalled downloads, flash file:///ota/v.ota (no second HTTP pull).
# The 92% freeze was wrap finishing the download then hanging while
# update-engine.real re-downloaded the same file via Python httpd.
set -e

VERSION=9

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
# Seek BLE OTA wrap v9
mkdir -p /run/update-engine /ota
LOG=/run/update-engine/wrapper.log
echo "wrapper v9 start $(date 2>/dev/null || true)" >> "$LOG"
echo "env URL=${UPDATE_ENGINE_URL-}" >> "$LOG"
echo "args=$*" >> "$LOG"

export UPDATE_ENGINE_ALLOW_DOWNGRADE=True
export UPDATE_ENGINE_ENABLED=True

URL="${UPDATE_ENGINE_URL-}"
URL=`echo "$URL" | tr -d '"'`

if [ -z "$URL" ]; then
  for a in "$@"; do
    case "$a" in
      http://*|https://*|file://*) URL="$a" ;;
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

case "$URL" in
  https://files.anki.org.uk/*|https://*.anki.org.uk/*)
    URL=`echo "$URL" | sed 's|^https://|http://|'`
    echo "rewrote to HTTP $URL" >> "$LOG"
    ;;
esac

OTA=/ota/v.ota
SZ=0
[ -f "$OTA" ] && SZ=`stat -c %s "$OTA" 2>/dev/null || echo 0`

if [ -z "$URL" ] && [ "$SZ" -ge 8000000 ]; then
  URL="file://$OTA"
  echo "no URL from BLE; flashing existing $OTA ($SZ)" >> "$LOG"
fi

if [ -z "$URL" ]; then
  URL="http://files.anki.org.uk/ota/latest"
  echo "defaulting URL=$URL" >> "$LOG"
fi

echo "using URL=$URL" >> "$LOG"

REAL=/anki/bin/update-engine.real
[ -x /data/update-engine.real ] && REAL=/data/update-engine.real
if [ ! -x "$REAL" ] || grep -q 'Seek BLE OTA wrap' "$REAL" 2>/dev/null; then
  echo "missing update-engine.real" >> "$LOG"
  echo "missing update-engine.real" > /run/update-engine/error
  echo 203 > /run/update-engine/exit_code
  exit 203
fi
CURL=/usr/bin/curl.anki
[ -x "$CURL" ] || CURL=/usr/bin/curl

NEED=1
case "$URL" in
  http://127.0.0.1:*|http://localhost:*|file://*) NEED=0 ;;
esac

echo 180000000 > /run/update-engine/expected-size
echo "$SZ" > /run/update-engine/progress
rm -f /run/update-engine/error /run/update-engine/done /run/update-engine/exit_code

if [ "$NEED" = 1 ]; then
  echo download > /run/update-engine/phase
  # Keep a partial /ota/v.ota and resume. Do not delete a 90%+ download.
  if [ "$SZ" -lt 8000000 ]; then
    rm -f "$OTA"
    SZ=0
  fi
  TRIES=0
  CR=1
  while [ "$TRIES" -lt 8 ]; do
    TRIES=`expr "$TRIES" + 1`
    echo "curl try $TRIES size=$SZ" >> "$LOG"
    "$CURL" -k -L --http1.1 -4 --fail --connect-timeout 20 --retry 0 \
      --speed-limit 2048 --speed-time 45 -C - -o "$OTA" "$URL" >> "$LOG" 2>&1 &
    CPID=$!
    TICK=0
    while kill -0 "$CPID" 2>/dev/null; do
      NOW=`stat -c %s "$OTA" 2>/dev/null || echo 0`
      echo "$NOW" > /run/update-engine/progress
      TICK=`expr "$TICK" + 1`
      if [ `expr "$TICK" % 5` -eq 0 ]; then
        echo "progress $NOW bytes" >> "$LOG"
      fi
      sleep 1
    done
    wait "$CPID"
    CR=$?
    SZ=`stat -c %s "$OTA" 2>/dev/null || echo 0`
    echo "$SZ" > /run/update-engine/progress
    echo "try $TRIES done rc=$CR size=$SZ" >> "$LOG"
    if [ "$CR" = 0 ] && [ "$SZ" -ge 8000000 ]; then
      break
    fi
    sleep 3
  done
  if [ "$CR" != 0 ] || [ "$SZ" -lt 8000000 ]; then
    echo "download failed" > /run/update-engine/error
    echo 204 > /run/update-engine/exit_code
    echo "download failed rc=$CR size=$SZ" >> "$LOG"
    exit 204
  fi
fi

SZ=`stat -c %s "$OTA" 2>/dev/null || echo 0`
echo "$SZ" > /run/update-engine/progress
echo "$SZ" > /run/update-engine/expected-size
echo "ota size $SZ" >> "$LOG"
if [ "$SZ" -lt 8000000 ]; then
  echo "download too small ($SZ)" > /run/update-engine/error
  echo 204 > /run/update-engine/exit_code
  exit 204
fi

killall httpd 2>/dev/null || true
killall python 2>/dev/null || true

echo flash > /run/update-engine/phase
cp -f "$LOG" /data/update-engine-wrapper.log 2>/dev/null || true
echo "flashing file://$OTA via $REAL" >> "$LOG"
echo "flashing file://$OTA via $REAL" >> /data/update-engine-wrapper.log
# Do NOT HTTP-serve and re-download. That is what froze the bar at ~92%.
exec "$REAL" -v "file://$OTA"
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
  if grep -q 'Seek BLE OTA wrap v9' /anki/bin/update-engine 2>/dev/null; then
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
