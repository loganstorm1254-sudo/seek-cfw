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

# If OTA already uploaded from PC, just flash.
if [ -s /data/ota/v.ota ] && [ "${1:-}" != "--download" ]; then
  if [ ! -f /data/unlock-manual-flash-v2.sh ]; then
    echo "Downloading flash script only..."
    CURL_DL=""
    for c in /usr/bin/curl.anki /usr/bin/curl /bin/curl; do
      [ -x "$c" ] && CURL_DL="$c" && break
    done
    if [ -n "$CURL_DL" ]; then
      "$CURL_DL" -k -L --http1.1 -4 -o /data/unlock-manual-flash-v2.sh \
        "${RAW}/seek/flash/unlock-manual-flash-v2.sh" || true
      chmod 755 /data/unlock-manual-flash-v2.sh 2>/dev/null || true
    fi
  fi
  if [ -f /data/unlock-manual-flash-v2.sh ]; then
    rm -f /data/unbrick 2>/dev/null || true
    exec sh /data/unlock-manual-flash-v2.sh /data/ota/v.ota
  fi
fi

CURL=""
for c in /usr/bin/curl /bin/curl; do
  if [ -x "$c" ] && ! head -n 1 "$c" 2>/dev/null | grep -q '^#!'; then
    CURL="$c"
    break
  fi
done
if [ -z "$CURL" ]; then
  echo "ERROR: no curl on robot — upload OTA from your PC instead:" >&2
  echo "  curl -L -o %TEMP%\\vicos-3.0.1.33d.ota https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.33d-recovery/vicos-3.0.1.33d.ota" >&2
  echo "  type %TEMP%\\vicos-3.0.1.33d.ota | ssh root@IP \"mkdir -p /data/ota && cat > /data/ota/v.ota\"" >&2
  echo "  type %TEMP%\\unlock-manual-flash-v2.sh | ssh root@IP \"cat > /data/unlock-manual-flash-v2.sh && chmod 755 /data/unlock-manual-flash-v2.sh\"" >&2
  echo "  ssh root@IP \"sh /data/unlock-manual-flash-v2.sh /data/ota/v.ota\"" >&2
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

echo "Downloading recovery script staging..."
if ! /usr/bin/curl.anki -k -L --http1.1 -4 --connect-timeout 60 -f -o /data/recovery-install.sh \
  "${RAW}/seek/flash/recovery-install.sh"; then
  echo "ERROR: could not download recovery-install.sh (no network or curl failed)" >&2
  exit 1
fi
chmod 755 /data/recovery-install.sh

# Clear recovery flag after successful flash (script reboots).
rm -f /data/unbrick 2>/dev/null || true

echo "Flashing inactive slot (keep charger connected)..."
sh /data/unlock-manual-flash-v2.sh "$OTA"
