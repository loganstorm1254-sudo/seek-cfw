#!/bin/sh
# Recovery / bricked-slot install: download full Seek OTA and flash INACTIVE slot.
# Stay on charger. Run as root via SSH from recovery menu.
#
#   sh recovery-install.sh
#   sh recovery-install.sh https://github.com/.../vicos-3.0.1.33d.ota
set -e

OTA_URL="${1:-https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.33d-recovery/vicos-3.0.1.33d.ota}"
OTA="/data/ota/v.ota"
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
if [ -z "$CURL" ]; then
  echo "ERROR: no curl on robot" >&2
  exit 1
fi
if [ ! -x /usr/bin/curl.anki ]; then
  cp -a "$CURL" /usr/bin/curl.anki
  chmod 755 /usr/bin/curl.anki
fi

echo "=== Seek recovery install ==="
echo "OS now: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "OTA: $OTA_URL"

echo "Downloading OTA..."
/usr/bin/curl.anki -k -L --http1.1 -4 --connect-timeout 120 -o "$OTA" "$OTA_URL"
[ -s "$OTA" ] || { echo "ERROR: OTA download failed" >&2; exit 1; }
echo "OTA size: $(wc -c <"$OTA") bytes"

echo "Downloading flash script..."
/usr/bin/curl.anki -k -L --http1.1 -4 -o /data/unlock-manual-flash-v2.sh \
  "${RAW}/seek/flash/unlock-manual-flash-v2.sh"
chmod 755 /data/unlock-manual-flash-v2.sh

# Clear recovery flag after successful flash (script reboots).
rm -f /data/unbrick 2>/dev/null || true

echo "Flashing inactive slot (keep charger connected)..."
sh /data/unlock-manual-flash-v2.sh "$OTA"
