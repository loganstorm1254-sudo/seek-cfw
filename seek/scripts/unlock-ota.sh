#!/bin/sh
# Unlock-friendly OTA (no systemd update-engine.service).
# Usage on robot:
#   sh unlock-ota.sh
#   sh unlock-ota.sh http://files.anki.org.uk/ota/latest
set -e
URL="${1:-http://files.anki.org.uk/ota/latest}"
unset SSL_CERT_FILE CURL_CA_BUNDLE 2>/dev/null || true
export SSL_CERT_FILE=
export CURL_CA_BUNDLE=

mount -o remount,rw / 2>/dev/null || true
mkdir -p /ota /cache /run/update-engine /run/vic-switchboard

if [ ! -x /usr/bin/curl.anki ]; then
  cp -L /usr/bin/curl /usr/bin/curl.anki 2>/dev/null || cp /usr/bin/curl /usr/bin/curl.anki
  chmod 755 /usr/bin/curl.anki
fi
CURL=/usr/bin/curl.anki

ENGINE=""
for e in /anki/bin/update-engine /anki/bin/update-engine.real; do
  [ -x "$e" ] || continue
  ENGINE="$e"
  break
done
if [ -z "$ENGINE" ]; then
  echo "FATAL: no /anki/bin/update-engine on this Unlock image."
  echo "Use BLE websetup instead, or flash via recovery."
  ls -la /anki/bin 2>/dev/null | head -40
  exit 1
fi

echo "OS: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "Engine: $ENGINE"
echo "URL: $URL"
echo "Downloading to /ota/v.ota (this is the slow step on hotspot)..."

rm -f /ota/v.ota
# Resume-friendly; show progress meter
$CURL -k -L --http1.1 -4 --fail -C - -o /ota/v.ota "$URL"
SZ=$(stat -c %s /ota/v.ota 2>/dev/null || wc -c </ota/v.ota)
echo "Downloaded $SZ bytes"
if [ "$SZ" -lt 8000000 ]; then
  echo "File too small — download failed"
  exit 1
fi

export UPDATE_ENGINE_ENABLED=True
export UPDATE_ENGINE_ALLOW_DOWNGRADE=True
export UPDATE_ENGINE_URL="file:///ota/v.ota"
echo "Flashing file:///ota/v.ota ..."
# Keep Wi-Fi alive briefly then stop robot services for flash
systemctl stop anki-robot.target 2>/dev/null || true
# Do NOT pass -v through logwrapper — Unlock's logwrapper treats it as its own flag.
# Run the engine directly (verbose on stdout is fine over SSH).
"$ENGINE" -v "file:///ota/v.ota"
EC=$?
echo "flash exit=$EC"
if [ "$EC" = 0 ]; then
  echo "Rebooting..."
  sync
  reboot
else
  echo "Flash failed — starting robot services again"
  systemctl start anki-robot.target 2>/dev/null || true
  exit "$EC"
fi
