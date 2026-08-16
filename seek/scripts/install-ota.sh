#!/bin/sh
# ONE command on the robot (or via SSH from your PC):
#   curl -kfsSL .../install-ota.sh | sh
#   curl -kfsSL .../install-ota.sh | sh -s -- http://files.anki.org.uk/ota/latest
set -e
unset SSL_CERT_FILE CURL_CA_BUNDLE || true
export SSL_CERT_FILE=
export CURL_CA_BUNDLE=

RAW=https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/overlays/anki/wired/update-os.sh
curl -k -L -4 --http1.1 --max-time 60 -o /data/update-os.sh "$RAW"
chmod 644 /data/update-os.sh
touch /data/keep-update-os
umount /usr/sbin/update-os 2>/dev/null || true
mount -o remount,rw / 2>/dev/null || true
printf '%s\n' '#!/bin/bash' 'exec /bin/bash /data/update-os.sh "$@"' >/usr/sbin/update-os
chmod 755 /usr/sbin/update-os

OTA_URL="${1:-}"
if [ -z "$OTA_URL" ]; then
  # Prefer robot-friendly plain HTTP (no TLS).
  OTA_URL="http://files.anki.org.uk/ota/latest"
fi
echo "update-os → $OTA_URL"
exec update-os "$OTA_URL"
