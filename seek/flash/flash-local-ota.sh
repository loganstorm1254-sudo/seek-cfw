#!/bin/sh
# Flash OTA already on robot at /data/ota/v.ota (upload from PC via pipe).
#   sh /data/flash-local-ota.sh
set -e
OTA="/data/ota/v.ota"
mount -o remount,rw / 2>/dev/null || true
mkdir -p /data/ota /data/seek
if [ ! -s "$OTA" ]; then
  echo "ERROR: missing $OTA" >&2
  echo "Upload from PC:" >&2
  echo "  type vicos-3.0.1.33d.ota | ssh root@IP \"cat > /data/ota/v.ota\"" >&2
  exit 1
fi
echo "OTA ready: $(wc -c <"$OTA") bytes"
if [ ! -x /data/unlock-manual-flash-v2.sh ]; then
  echo "ERROR: missing /data/unlock-manual-flash-v2.sh — pipe it from PC first" >&2
  exit 1
fi
rm -f /data/unbrick 2>/dev/null || true
sh /data/unlock-manual-flash-v2.sh "$OTA"
