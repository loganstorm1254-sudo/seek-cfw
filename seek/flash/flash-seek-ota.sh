#!/bin/sh
# Install Seek update-os helper, then flash latest OTA.
#   sh flash-seek-ota.sh
#   sh flash-seek-ota.sh <ota-url>
set -e

OTA_URL="${1:-https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.33d-recovery/vicos-3.0.1.33d.ota}"
BRANCH="cursor/head-only-ignore-body-7a4a"
RAW="https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/${BRANCH}"

mount -o remount,rw / 2>/dev/null || true
mkdir -p /data/ota /data/seek /ota

CURL=/usr/bin/curl
[ -x "$CURL" ] || CURL=/bin/curl
[ -x "$CURL" ] || { echo "ERROR: no curl"; exit 1; }

echo "=== Seek full OTA flash ==="
echo "Current: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "OTA: $OTA_URL"

$CURL -k -L --http1.1 -4 -f -o /data/update-os.sh \
  "${RAW}/seek/overlays/anki/wired/update-os.sh"
chmod 755 /data/update-os.sh

# Optional: expose as update-os on PATH for this session
ln -sf /data/update-os.sh /data/update-os 2>/dev/null || true

exec bash /data/update-os.sh "$OTA_URL"
