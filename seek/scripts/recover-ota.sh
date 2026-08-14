#!/bin/sh
# Unstick Vector stuck on the OTA face, install wrap v9.
# Keeps a large /ota/v.ota so a 92% download can resume/flash.
set -e
mount -o remount,rw / 2>/dev/null || true
killall -9 update-engine python httpd curl 2>/dev/null || true
SZ=0
[ -f /ota/v.ota ] && SZ=`stat -c %s /ota/v.ota 2>/dev/null || echo 0`
if [ "$SZ" -ge 8000000 ]; then
  echo "Keeping /ota/v.ota ($SZ bytes)"
else
  rm -f /ota/v.ota
fi
systemctl start anki-robot.target 2>/dev/null || true
systemctl restart vic-anim 2>/dev/null || true
echo "Face should return. Installing wrap v9..."
curl -k -L -4 --http1.1 --max-time 60 -o /tmp/f.sh \
  https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/scripts/fix-ble-ota.sh
sh /tmp/f.sh
if [ -x /anki/bin/update-engine.real ] && [ -f /ota/v.ota ]; then
  SZ=`stat -c %s /ota/v.ota 2>/dev/null || echo 0`
  if [ "$SZ" -ge 160000000 ]; then
    echo "Flashing existing /ota/v.ota ($SZ) via file://"
    /anki/bin/update-engine.real -v "file:///ota/v.ota"
  fi
fi
echo "RECOVER_OK"
