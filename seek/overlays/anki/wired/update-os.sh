#!/usr/bin/env bash
# Seek update-os: curl downloads GitHub OTA (SSL-safe), then flashes inactive slot.
# Stock Viccyware update-os / update-engine fail GitHub SSL — do not use them.
#
#   update-os <url>
#   bash /data/update-os.sh <url>
set -e
set -u

BRANCH="cursor/head-only-ignore-body-7a4a"
RAW="https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/${BRANCH}"
DEFAULT_OTA="https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.33d-recovery/vicos-3.0.1.33d.ota"
MIN=200000000

usage() {
  echo "usage: update-os <url>"
  echo "  update-os $DEFAULT_OTA"
  exit 0
}

if [ $# -lt 1 ] || [ "$1" = "-h" ]; then
  usage
fi
URL="$1"

mount -o remount,rw / 2>/dev/null || true
mkdir -p /ota /data/ota /data/seek /run/update-engine

# Real curl only (skip empty/broken curl.anki stubs).
CURL=""
for c in /usr/bin/curl /bin/curl; do
  if [ -x "$c" ]; then
    SZ=$(wc -c <"$c" 2>/dev/null || echo 0)
    if [ "$SZ" -gt 1000 ] 2>/dev/null; then
      CURL="$c"
      break
    fi
  fi
done
[ -n "$CURL" ] || { echo "ERROR: no working curl binary"; exit 1; }

echo "Current OS Version: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "Seek update-os (curl + manual flash)"
echo "OTA: $URL"
df -h /ota /data 2>/dev/null || true

if ! touch /ota/.w 2>/dev/null; then
  echo "ERROR: /ota not writable — remount / rw failed?"
  exit 1
fi
rm -f /ota/.w

echo "Fetching flash helper..."
$CURL -k -L --http1.1 -4 -f -o /data/unlock-manual-flash-v2.sh \
  "${RAW}/seek/flash/unlock-manual-flash-v2.sh"
chmod 755 /data/unlock-manual-flash-v2.sh

# Resolve GitHub redirect to CDN (optional; curl -L handles it on download).
case "$URL" in
  *github.com*)
    FINAL=$($CURL -k -sI --http1.1 -4 --max-time 25 "$URL" 2>/dev/null | grep -i '^location:' | sed -n '$p' | awk '{print $2}' | tr -d '\r')
    if [ -n "${FINAL:-}" ]; then
      URL="$FINAL"
      echo "CDN: $URL"
    fi
    ;;
esac

echo "Downloading OTA to /ota/v.ota (~204MB)..."
rm -f /ota/v.ota
$CURL -k -L --http1.1 -4 --connect-timeout 120 -f -o /ota/v.ota "$URL"
SZ=$(wc -c </ota/v.ota)
echo "OTA size=$SZ"
if [ "$SZ" -lt "$MIN" ]; then
  echo "FATAL: OTA too small (need >= $MIN)"
  exit 1
fi

echo "Stopping anki-robot (eyes may go dark)..."
systemctl stop anki-robot.target 2>/dev/null || true
killall -9 vic-engine vic-anim vic-cloud vic-robot 2>/dev/null || true

echo "Flashing inactive slot (stay on charger)..."
rm -f /data/unbrick
exec sh /data/unlock-manual-flash-v2.sh /ota/v.ota
