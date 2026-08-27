#!/bin/sh
# One command: flash latest full Seek OTA to inactive slot (running OS).
#   curl -fsSL .../flash-seek-ota.sh | ssh root@IP sh
set -e

OTA_URL="${1:-https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.33d-recovery/vicos-3.0.1.33d.ota}"
BRANCH="cursor/head-only-ignore-body-7a4a"
RAW="https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/${BRANCH}"

mount -o remount,rw / 2>/dev/null || true
mkdir -p /data/ota /data/seek

CURL=""
for c in /usr/bin/curl /bin/curl; do
  if [ -x "$c" ] && ! head -n 1 "$c" 2>/dev/null | grep -q '^#!'; then
    CURL="$c"
    break
  fi
done
[ -n "$CURL" ] || { echo "ERROR: no curl"; exit 1; }

if [ ! -x /usr/bin/curl.anki ]; then
  cp -a "$CURL" /usr/bin/curl.anki
  chmod 755 /usr/bin/curl.anki
fi

echo "=== Seek full OTA flash ==="
echo "Current: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "OTA: $OTA_URL"

/usr/bin/curl.anki -k -L --http1.1 -4 -f -o /data/update-os.sh \
  "${RAW}/seek/overlays/anki/wired/update-os.sh"
chmod 644 /data/update-os.sh

exec bash /data/update-os.sh "$OTA_URL"
