#!/bin/sh
# curl can download GitHub; stock update-engine often cannot (SSL).
# Download full OTA with curl -k to /ota, then flash inactive slot.
set -e

OTA_URL="${1:-https://github.com/Victor-Rebuild/1.6-rebuild-historical-releases/releases/download/1.6.1.007X/vicos-1.6.1.0079d.ota}"
BRANCH="cursor/16-rebuild-errorsafe-7a4a"
RAW="https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/${BRANCH}"
MIN=150000000

mount -o remount,rw / 2>/dev/null || true
mkdir -p /data/ota /ota /data/seek 2>/dev/null || true

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
[ -n "$CURL" ] || { echo "ERROR: no working curl"; exit 1; }

DEST=/ota/v.ota
FREE_K=$(df -k /ota 2>/dev/null | awk 'NR==2{print $4}')
if [ -z "$FREE_K" ] || [ "$FREE_K" -lt 220000 ]; then
  echo "WARNING: /ota free=${FREE_K:-?}K (need ~220000K). Trying anyway."
fi
if ! touch /ota/.w 2>/dev/null; then
  echo "ERROR: /ota not writable. df:"
  df -h / /ota /data /cache 2>/dev/null || true
  exit 1
fi
rm -f /ota/.w

echo "=== 1.6-rebuild curl-flash (bypass update-engine SSL) ==="
echo "curl=$CURL"
echo "dest=$DEST"
df -h /ota /data /cache 2>/dev/null || true

echo "Downloading flash script..."
$CURL -k -L --http1.1 -4 -f -o /data/unlock-manual-flash-v2.sh \
  "${RAW}/seek/flash/unlock-manual-flash-v2.sh"
chmod 755 /data/unlock-manual-flash-v2.sh

echo "Downloading OTA (~204MB) — several minutes..."
rm -f "$DEST"
$CURL -k -L --http1.1 -4 --connect-timeout 120 -f -o "$DEST" "$OTA_URL"
SZ=$(wc -c <"$DEST")
echo "OTA size=$SZ"
[ "$SZ" -ge "$MIN" ] || { echo "FATAL: OTA too small"; exit 1; }

echo "Flashing inactive slot (stay on charger)..."
rm -f /data/unbrick
exec sh /data/unlock-manual-flash-v2.sh "$DEST"
