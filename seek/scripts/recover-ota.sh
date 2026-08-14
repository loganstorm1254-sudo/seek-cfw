#!/bin/sh
# Unstick Vector stuck on the OTA face, then reinstall BLE OTA wrap v7.
set -e
mount -o remount,rw / 2>/dev/null || true
killall -9 update-engine python httpd curl 2>/dev/null || true
rm -f /ota/v.ota
systemctl start anki-robot.target 2>/dev/null || true
systemctl restart vic-anim 2>/dev/null || true
echo "Face should return. Installing wrap..."
curl -k -L -4 --http1.1 --max-time 60 -o /tmp/f.sh \
  https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/scripts/fix-ble-ota.sh
sh /tmp/f.sh
echo "RECOVER_OK"
