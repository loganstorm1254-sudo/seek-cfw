#!/bin/sh
# ONE command for SeekOS OTA. BusyBox-safe.
# curl -L -4 -o /data/u.sh THIS_URL && sh /data/u.sh
set -e

OTA_URL="${1:-}"
RAW=https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/overlays/anki/wired/update-os.sh

curl -L -4 --max-time 60 -o /data/update-os.sh "$RAW"
chmod 644 /data/update-os.sh
touch /data/keep-update-os
umount /usr/sbin/update-os 2>/dev/null || true
mount -o remount,rw / 2>/dev/null || true
printf '%s\n' '#!/bin/bash' 'exec /bin/bash /data/update-os.sh "$@"' >/usr/sbin/update-os
chmod 755 /usr/sbin/update-os

if [ -z "$OTA_URL" ]; then
  OTA_URL=`curl -sL -4 --max-time 25 -H 'User-Agent: SeekOS' -H 'Accept: application/vnd.github+json' \
    https://api.github.com/repos/loganstorm1254-sudo/seek-cfw/releases/latest \
    | tr '"' '\n' | grep '/vicos-.*\.ota$' | grep '^https://' | sed -n '1p'`
fi
[ -n "$OTA_URL" ] || { echo "No OTA URL"; exit 1; }

exec update-os "$OTA_URL"
