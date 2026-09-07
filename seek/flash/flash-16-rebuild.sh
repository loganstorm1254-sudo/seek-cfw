#!/bin/sh
# One-shot: install error-safe update-os on a running robot, then flash 1.6-rebuild.
# Stay on charger. Use from SSH / real shell (not websetup terminal).
#
#   sh flash-16-rebuild.sh
#   sh flash-16-rebuild.sh <ota-url>
set -e

OTA_URL="${1:-https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v1.6.1.81d-errorsafe/vicos-1.6.1.81d.ota}"
BRANCH="cursor/16-rebuild-errorsafe-7a4a"
RAW="https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/${BRANCH}"

mount -o remount,rw / 2>/dev/null || true
mkdir -p /data/ota /data/seek /ota

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

echo "=== 1.6-rebuild safe flash ==="
echo "Current: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "OTA: $OTA_URL"

$CURL -k -L --http1.1 -4 -f -o /data/update-os.sh "${RAW}/seek/flash/update-os.sh"
$CURL -k -L --http1.1 -4 -f -o /data/unlock-manual-flash-v2.sh "${RAW}/seek/flash/unlock-manual-flash-v2.sh"
chmod 755 /data/update-os.sh /data/unlock-manual-flash-v2.sh

exec bash /data/update-os.sh "$OTA_URL"
