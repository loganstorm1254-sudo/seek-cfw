#!/bin/sh
# Unlock-friendly OTA (no systemd update-engine.service).
# Unlock's stock update-engine often cannot open file:// (exit 203).
# We download to /ota/v.ota, then serve it on 127.0.0.1 and flash via HTTP.
#
# Usage on robot:
#   sh unlock-ota.sh
#   sh unlock-ota.sh http://files.anki.org.uk/ota/latest
#   sh unlock-ota.sh flash-only    # use existing /ota/v.ota
set -e
URL="${1:-http://files.anki.org.uk/ota/latest}"
PORT=8765
unset SSL_CERT_FILE CURL_CA_BUNDLE 2>/dev/null || true
export SSL_CERT_FILE=
export CURL_CA_BUNDLE=

mount -o remount,rw / 2>/dev/null || true
mkdir -p /ota /cache /run/update-engine /run/vic-switchboard

if [ ! -x /usr/bin/curl.anki ]; then
  cp -L /usr/bin/curl /usr/bin/curl.anki 2>/dev/null || cp /usr/bin/curl /usr/bin/curl.anki
  chmod 755 /usr/bin/curl.anki
fi
CURL=/usr/bin/curl.anki

ENGINE=""
for e in /anki/bin/update-engine /anki/bin/update-engine.real; do
  [ -x "$e" ] || continue
  ENGINE="$e"
  break
done
if [ -z "$ENGINE" ]; then
  echo "FATAL: no /anki/bin/update-engine on this Unlock image."
  ls -la /anki/bin 2>/dev/null | head -40
  exit 1
fi

echo "OS: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "Engine: $ENGINE"
file "$ENGINE" 2>/dev/null || head -c 80 "$ENGINE" 2>/dev/null || true

SZ=0
[ -f /ota/v.ota ] && SZ=`stat -c %s /ota/v.ota 2>/dev/null || echo 0`

if [ "$URL" = "flash-only" ]; then
  if [ "$SZ" -lt 8000000 ]; then
    echo "No usable /ota/v.ota ($SZ). Pass a download URL instead."
    exit 1
  fi
  echo "Using existing /ota/v.ota ($SZ bytes)"
else
  echo "URL: $URL"
  if [ "$SZ" -ge 200000000 ]; then
    echo "Keeping existing /ota/v.ota ($SZ bytes) — already downloaded"
  else
    echo "Downloading to /ota/v.ota ..."
    rm -f /ota/v.ota
    $CURL -k -L --http1.1 -4 --fail -C - -o /ota/v.ota "$URL"
    SZ=`stat -c %s /ota/v.ota 2>/dev/null || echo 0`
    echo "Downloaded $SZ bytes"
  fi
fi

if [ "$SZ" -lt 8000000 ]; then
  echo "File too small — download failed"
  exit 1
fi

# Kill any old local servers
killall httpd 2>/dev/null || true
killall python 2>/dev/null || true
killall python3 2>/dev/null || true

start_local_http() {
  cd /ota || return 1
  if command -v busybox >/dev/null 2>&1; then
    busybox httpd -f -p "$PORT" -h /ota &
    echo $! > /run/update-engine/httpd.pid
    return 0
  fi
  if [ -x /usr/sbin/httpd ]; then
    /usr/sbin/httpd -f -p "$PORT" -h /ota &
    echo $! > /run/update-engine/httpd.pid
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -m http.server "$PORT" --bind 127.0.0.1 &
    echo $! > /run/update-engine/httpd.pid
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    python -m SimpleHTTPServer "$PORT" &
    echo $! > /run/update-engine/httpd.pid
    return 0
  fi
  return 1
}

echo "Starting local HTTP on 127.0.0.1:$PORT ..."
if ! start_local_http; then
  echo "No httpd/python — cannot serve local OTA on Unlock."
  exit 1
fi
sleep 1

LOCAL="http://127.0.0.1:${PORT}/v.ota"
echo "Probing $LOCAL ..."
CODE=`$CURL -k -s -o /dev/null -w '%{http_code}' --http1.1 -4 --max-time 10 -r 0-1023 "$LOCAL" 2>/dev/null || echo 000`
echo "local probe=$CODE"
if [ "$CODE" != "200" ] && [ "$CODE" != "206" ]; then
  echo "Local HTTP serve failed ($CODE)"
  killall httpd python python3 2>/dev/null || true
  exit 1
fi

export UPDATE_ENGINE_ENABLED=True
export UPDATE_ENGINE_ALLOW_DOWNGRADE=True
export UPDATE_ENGINE_URL="$LOCAL"
{
  echo UPDATE_ENGINE_ENABLED=True
  echo UPDATE_ENGINE_ALLOW_DOWNGRADE=True
  echo UPDATE_ENGINE_MAX_SLEEP=1
  printf 'UPDATE_ENGINE_URL=%s\n' "$LOCAL"
} >/run/vic-switchboard/update-engine.env 2>/dev/null || true

echo "Flashing $LOCAL (Unlock cannot use file:// — exit 203)..."
systemctl stop anki-robot.target 2>/dev/null || true
set +e
"$ENGINE" -v "$LOCAL"
EC=$?
set -e
echo "flash exit=$EC"

killall httpd python python3 2>/dev/null || true
[ -f /run/update-engine/httpd.pid ] && kill "$(cat /run/update-engine/httpd.pid)" 2>/dev/null || true

if [ "$EC" = 0 ]; then
  echo "Rebooting..."
  sync
  reboot
else
  echo "Flash failed (exit $EC). Error file:"
  cat /run/update-engine/error 2>/dev/null || true
  systemctl start anki-robot.target 2>/dev/null || true
  exit "$EC"
fi
