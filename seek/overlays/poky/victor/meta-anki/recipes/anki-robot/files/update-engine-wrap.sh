#!/bin/sh
# Seek BLE OTA wrap v9 (shipped in the OTA — no SSH).
# Public websetup only starts /anki/bin/update-engine <url>. This wrap:
#   - rewrites https://*.anki.org.uk → http:// (Vector cannot verify TLS)
#   - if /ota is large enough, downloads with resume then flashes file://
#   - otherwise execs the streaming C++ engine (no second HTTP pull)
# Periodic auto-update (no URL) is passed through. Do not default to /ota/latest.
mkdir -p /run/update-engine /data
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
      http://*|https://*|file://*|auto) URL="$a" ;;
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
  https://*.anki.org.uk/*|https://anki.org.uk/*)
    URL=`echo "$URL" | sed 's|^https://|http://|'`
    echo "rewrote to HTTP $URL" >> "$LOG"
    ;;
esac

REAL=/anki/bin/update-engine.real
[ -x /data/update-engine.real ] && REAL=/data/update-engine.real
if [ ! -x "$REAL" ] || grep -q 'Seek BLE OTA wrap' "$REAL" 2>/dev/null; then
  echo "missing update-engine.real" >> "$LOG"
  echo "missing update-engine.real" > /run/update-engine/error
  echo 203 > /run/update-engine/exit_code
  exit 203
fi

OTA=/ota/v.ota
SZ=0
[ -f "$OTA" ] && SZ=`stat -c %s "$OTA" 2>/dev/null || echo 0`

# BLE sometimes starts the engine with no URL. Flash a complete local payload.
if [ -z "$URL" ] || [ "$URL" = "auto" ]; then
  if [ "$SZ" -ge 8000000 ]; then
    URL="file://$OTA"
    echo "no BLE URL; flashing existing $OTA ($SZ)" >> "$LOG"
  else
    echo "no URL; passing through to real engine" >> "$LOG"
    cp -f "$LOG" /data/update-engine-wrapper.log 2>/dev/null || true
    exec "$REAL" "$@"
  fi
fi

echo "using URL=$URL" >> "$LOG"

NEED=1
case "$URL" in
  http://127.0.0.1:*|http://localhost:*|file://*) NEED=0 ;;
esac

ota_usable() {
  mkdir -p /ota 2>/dev/null || return 1
  touch /ota/.seek-write 2>/dev/null || return 1
  rm -f /ota/.seek-write
  AVAIL=`df -P /ota 2>/dev/null | awk 'NR==2 { print $4 }'`
  [ -n "$AVAIL" ] || return 1
  # df -P is KB. Need ~200MB free (or a large in-progress file).
  if [ "$SZ" -ge 8000000 ]; then
    return 0
  fi
  [ "$AVAIL" -ge 200000 ]
}

if [ "$NEED" = 1 ] && ! ota_usable; then
  echo "/ota not usable; streaming $URL" >> "$LOG"
  echo 180000000 > /run/update-engine/expected-size
  echo 0 > /run/update-engine/progress
  echo download > /run/update-engine/phase
  rm -f /run/update-engine/error /run/update-engine/done /run/update-engine/exit_code
  cp -f "$LOG" /data/update-engine-wrapper.log 2>/dev/null || true
  exec "$REAL" -v "$URL"
fi

CURL=/usr/bin/curl.anki
[ -x "$CURL" ] || CURL=/usr/bin/curl

echo 180000000 > /run/update-engine/expected-size
echo "$SZ" > /run/update-engine/progress
rm -f /run/update-engine/error /run/update-engine/done /run/update-engine/exit_code

if [ "$NEED" = 1 ]; then
  echo download > /run/update-engine/phase
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
    echo "download failed; streaming $URL" >> "$LOG"
    echo download > /run/update-engine/phase
    cp -f "$LOG" /data/update-engine-wrapper.log 2>/dev/null || true
    exec "$REAL" -v "$URL"
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
exec "$REAL" -v "file://$OTA"
