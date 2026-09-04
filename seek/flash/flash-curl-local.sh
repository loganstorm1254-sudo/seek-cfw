#!/bin/sh
# Viccyware/Unlock: curl can download GitHub; update-engine cannot (SSL).
# Download full OTA with curl -k to /ota (or /data if enough space), then
# flash inactive slot with unlock-manual-flash-v2.sh (no update-engine).
set -e

OTA_URL="${1:-https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.33d-recovery/vicos-3.0.1.33d.ota}"
BRANCH="cursor/head-only-ignore-body-7a4a"
RAW="https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/${BRANCH}"
MIN=200000000

mount -o remount,rw / 2>/dev/null || true
mkdir -p /data/ota /ota /data/seek 2>/dev/null || true

CURL=/usr/bin/curl
[ -x "$CURL" ] || CURL=/bin/curl
[ -x "$CURL" ] || { echo "ERROR: no curl"; exit 1; }

# Prefer /ota (often on rootfs). Need ~210MB free for the OTA.
mount -o remount,rw / 2>/dev/null || true
mkdir -p /ota /data/ota 2>/dev/null || true
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

echo "=== Seek curl-flash (bypass update-engine SSL) ==="
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
