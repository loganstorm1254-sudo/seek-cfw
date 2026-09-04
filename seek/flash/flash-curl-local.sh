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

CURL=""
for c in /usr/bin/curl /bin/curl; do
  if [ -x "$c" ] && [ "$(wc -c <"$c" 2>/dev/null || echo 0)" -gt 1000 ] && ! head -n 1 "$c" 2>/dev/null | grep -q '^#!'; then
    CURL="$c"
    break
  fi
done
[ -n "$CURL" ] || { echo "ERROR: no working curl"; exit 1; }

# Prefer /ota for ~204MB; fall back only if huge free space on /data
DEST=""
if mkdir -p /ota 2>/dev/null && touch /ota/.w 2>/dev/null; then
  rm -f /ota/.w
  DEST=/ota/v.ota
elif [ "$(df -k /data 2>/dev/null | awk 'NR==2{print $4}')" -gt 220000 ] 2>/dev/null; then
  DEST=/data/ota/v.ota
else
  echo "ERROR: need writable /ota (or 220MB free on /data). df:"
  df -h /ota /data /cache 2>/dev/null || true
  exit 1
fi

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
