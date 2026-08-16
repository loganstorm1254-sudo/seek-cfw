#!/bin/sh
# Seek BLE OTA wrap v11 (shipped in the OTA — no SSH).
# Public websetup only starts /anki/bin/update-engine <url>. This wrap:
#   - remounts root rw and prefers /ota or /cache for the payload
#   - rewrites https://*.anki.org.uk → http:// (Vector cannot verify TLS)
#   - downloads with resume + parallel ranges when possible, then flashes file://
#   - grows expected-size if the file passes a stale size guess (no 193/171)
#   - otherwise execs the streaming C++ engine (no second HTTP pull)
# Periodic auto-update (no URL) is passed through. Do not default to /ota/latest.
mount -o remount,rw / 2>/dev/null || true
mkdir -p /run/update-engine /data /ota /cache
LOG=/run/update-engine/wrapper.log
echo "wrapper v11 start $(date 2>/dev/null || true)" >> "$LOG"
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

# Default ~Seek cloudless OTA size; HEAD may replace this.
EXPECT=230000000
probe_expect() {
  HURL="$1"
  case "$HURL" in
    http://*|https://*) ;;
    *) return 0 ;;
  esac
  CL=`curl -k -sIL --http1.1 -4 --max-time 12 --connect-timeout 8 "$HURL" 2>/dev/null \
    | tr -d '\r' | awk 'tolower($0) ~ /^content-length:/ { v=$2 } END { print v }'`
  case "$CL" in
    ''|*[!0-9]*) ;;
    *)
      if [ "$CL" -ge 8000000 ]; then
        EXPECT="$CL"
      fi
      ;;
  esac
}

# Pick a writable dir with enough free space for the OTA (+ margin).
# /data is often ~58MB on Unlock — too small. Prefer /ota (root) or /cache.
OTA=
ota_pick() {
  NEED_KB=`expr "$EXPECT" / 1024 + 20480`
  for d in /ota /cache /data/ota; do
    mkdir -p "$d" 2>/dev/null || continue
    touch "$d/.seek-write" 2>/dev/null || continue
    rm -f "$d/.seek-write"
    AVAIL=`df -P "$d" 2>/dev/null | awk 'NR==2 { print $4 }'`
    [ -n "$AVAIL" ] || continue
    EXIST=0
    [ -f "$d/v.ota" ] && EXIST=`stat -c %s "$d/v.ota" 2>/dev/null || echo 0`
    if [ "$EXIST" -ge 8000000 ] || [ "$AVAIL" -ge "$NEED_KB" ]; then
      OTA="$d/v.ota"
      echo "ota path $OTA avail_kb=$AVAIL need_kb=$NEED_KB exist=$EXIST" >> "$LOG"
      return 0
    fi
    echo "skip $d avail_kb=$AVAIL need_kb=$NEED_KB" >> "$LOG"
  done
  return 1
}

SZ=0
[ -n "$OTA" ] && [ -f "$OTA" ] && SZ=`stat -c %s "$OTA" 2>/dev/null || echo 0`

# BLE sometimes starts the engine with no URL. Flash a complete local payload.
if [ -z "$URL" ] || [ "$URL" = "auto" ]; then
  for d in /ota /cache /data/ota; do
    if [ -f "$d/v.ota" ]; then
      TSZ=`stat -c %s "$d/v.ota" 2>/dev/null || echo 0`
      if [ "$TSZ" -ge 8000000 ]; then
        OTA="$d/v.ota"
        SZ="$TSZ"
        URL="file://$OTA"
        echo "no BLE URL; flashing existing $OTA ($SZ)" >> "$LOG"
        break
      fi
    fi
  done
  if [ -z "$URL" ] || [ "$URL" = "auto" ]; then
    echo "no URL; passing through to real engine" >> "$LOG"
    cp -f "$LOG" /data/update-engine-wrapper.log 2>/dev/null || true
    exec "$REAL" "$@"
  fi
fi

echo "using URL=$URL" >> "$LOG"
probe_expect "$URL"
echo "expect $EXPECT" >> "$LOG"

NEED=1
case "$URL" in
  http://127.0.0.1:*|http://localhost:*|file://*) NEED=0 ;;
esac

ble_progress_init() {
  echo "$EXPECT" > /run/update-engine/expected-size
  echo "${1:-0}" > /run/update-engine/progress
  echo download > /run/update-engine/phase
  rm -f /run/update-engine/error /run/update-engine/done /run/update-engine/exit_code
}

if [ "$NEED" = 1 ] && ! ota_pick; then
  echo "/ota|/cache not usable; streaming $URL" >> "$LOG"
  ble_progress_init 0
  cp -f "$LOG" /data/update-engine-wrapper.log 2>/dev/null || true
  exec "$REAL" -v "$URL"
fi

# Local file:// flash path (already downloaded).
case "$URL" in
  file://*)
    OTA=`echo "$URL" | sed 's|^file://||'`
    ;;
esac

CURL=/usr/bin/curl.anki
[ -x "$CURL" ] || CURL=/usr/bin/curl

[ -z "$OTA" ] && OTA=/ota/v.ota
SZ=0
[ -f "$OTA" ] && SZ=`stat -c %s "$OTA" 2>/dev/null || echo 0`
ble_progress_init "$SZ"

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
    echo "curl try $TRIES size=$SZ expect=$EXPECT" >> "$LOG"
    # Prefer multi-range pull (often 2–4× on phone hotspots / Wi-Fi).
    # Falls back to single resume curl if ranges fail.
    PARALLEL_OK=0
    if [ "$SZ" -eq 0 ] && [ "$EXPECT" -ge 16000000 ]; then
      PARTS=4
      CHUNK=`expr "$EXPECT" / "$PARTS"`
      PI=0
      PIDS=""
      FAIL=0
      while [ "$PI" -lt "$PARTS" ]; do
        START=`expr "$PI" \* "$CHUNK"`
        if [ "$PI" -eq `expr "$PARTS" - 1` ]; then
          END=`expr "$EXPECT" - 1`
        else
          END=`expr "$START" + "$CHUNK" - 1`
        fi
        PART="$OTA.p$PI"
        rm -f "$PART"
        echo "range $PI bytes=$START-$END" >> "$LOG"
        "$CURL" -k -L --http1.1 -4 --fail --connect-timeout 20 --retry 2 \
          -r "$START-$END" -o "$PART" "$URL" >> "$LOG" 2>&1 &
        PIDS="$PIDS $!"
        PI=`expr "$PI" + 1`
      done
      for P in $PIDS; do
        if ! wait "$P"; then
          FAIL=1
        fi
      done
      if [ "$FAIL" = 0 ]; then
        rm -f "$OTA"
        PI=0
        while [ "$PI" -lt "$PARTS" ]; do
          cat "$OTA.p$PI" >> "$OTA" || FAIL=1
          rm -f "$OTA.p$PI"
          PI=`expr "$PI" + 1`
        done
      else
        PI=0
        while [ "$PI" -lt "$PARTS" ]; do
          rm -f "$OTA.p$PI"
          PI=`expr "$PI" + 1`
        done
      fi
      SZ=`stat -c %s "$OTA" 2>/dev/null || echo 0`
      echo "$SZ" > /run/update-engine/progress
      echo "$EXPECT" > /run/update-engine/expected-size
      if [ "$FAIL" = 0 ] && [ "$SZ" -ge 8000000 ]; then
        PARALLEL_OK=1
        CR=0
        echo "parallel download ok size=$SZ" >> "$LOG"
      else
        echo "parallel download failed; single resume" >> "$LOG"
        rm -f "$OTA"
        SZ=0
      fi
    fi
    if [ "$PARALLEL_OK" = 0 ]; then
      "$CURL" -k -L --http1.1 -4 --fail --connect-timeout 20 --retry 2 \
        -C - -o "$OTA" "$URL" >> "$LOG" 2>&1 &
      CPID=$!
      TICK=0
      while kill -0 "$CPID" 2>/dev/null; do
        NOW=`stat -c %s "$OTA" 2>/dev/null || echo 0`
        if [ "$NOW" -gt "$EXPECT" ]; then
          EXPECT=`expr "$NOW" + 2097152`
        fi
        echo "$NOW" > /run/update-engine/progress
        echo "$EXPECT" > /run/update-engine/expected-size
        TICK=`expr "$TICK" + 1`
        if [ `expr "$TICK" % 5` -eq 0 ]; then
          echo "progress $NOW / $EXPECT bytes" >> "$LOG"
        fi
        sleep 1
      done
      wait "$CPID"
      CR=$?
      SZ=`stat -c %s "$OTA" 2>/dev/null || echo 0`
      echo "$SZ" > /run/update-engine/progress
      echo "try $TRIES done rc=$CR size=$SZ" >> "$LOG"
    fi
    if [ "$CR" = 0 ] && [ "$SZ" -ge 8000000 ]; then
      break
    fi
    sleep 3
  done
  if [ "$CR" != 0 ] || [ "$SZ" -lt 8000000 ]; then
    echo "download failed; streaming $URL" >> "$LOG"
    ble_progress_init 0
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
