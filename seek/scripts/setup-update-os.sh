#!/bin/sh
# One-time: install WireOS-style `update-os <url>` on a live robot.
# BusyBox-safe. Does not flash an OTA.
set -e
curl -L -4 --max-time 60 -o /data/update-os.sh \
  https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/overlays/anki/wired/update-os.sh
chmod 644 /data/update-os.sh
touch /data/keep-update-os
umount /usr/sbin/update-os 2>/dev/null || true
mount -o remount,rw / 2>/dev/null || true
printf '%s\n' '#!/bin/bash' 'exec /bin/bash /data/update-os.sh "$@"' >/usr/sbin/update-os
chmod 755 /usr/sbin/update-os
echo "OK — use: update-os <github-ota-url>"
