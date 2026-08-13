#!/bin/sh
# Fix BLE websetup OTA (status 203) on a live Seek robot.
# Makes update-engine use a working curl + ALLOW_DOWNGRADE, and pass the URL
# as argv (more reliable than env alone).
#
# Run once from your PC:
#   ssh root@IP -i KEY "sh -s" < seek/scripts/fix-ble-ota.sh
# Or:
#   ssh root@IP -i KEY "curl -L -4 -o /tmp/fix-ble-ota.sh https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/scripts/fix-ble-ota.sh && sh /tmp/fix-ble-ota.sh"
set -e

mount -o remount,rw / 2>/dev/null || true
umount /usr/bin/curl 2>/dev/null || true
umount /usr/sbin/update-os 2>/dev/null || true

# Keep a real curl on /usr
if [ ! -x /usr/bin/curl.anki ]; then
  cp -L /usr/bin/curl /usr/bin/curl.anki 2>/dev/null || cp /usr/bin/curl /usr/bin/curl.anki
  chmod 755 /usr/bin/curl.anki
fi
cat > /usr/bin/curl << 'EOF'
#!/bin/sh
exec /usr/bin/curl.anki -L --http1.1 -4 --connect-timeout 30 "$@"
EOF
chmod 755 /usr/bin/curl

# Save real update-engine once
if [ ! -x /anki/bin/update-engine.real ]; then
  cp -a /anki/bin/update-engine /anki/bin/update-engine.real
fi

# Wrapper: BLE/systemd starts update-engine → we fix env and run real binary
cat > /anki/bin/update-engine << 'EOF'
#!/bin/bash
# Seek: BLE websetup OTA helper (avoids status 203 / bad URL)
mkdir -p /run/update-engine
{
  echo "wrapper start $(date)"
  echo "env URL=${UPDATE_ENGINE_URL-}"
  echo "args=$*"
} >> /run/update-engine/wrapper.log 2>&1

export UPDATE_ENGINE_ALLOW_DOWNGRADE=True
export UPDATE_ENGINE_ENABLED=True

URL="${UPDATE_ENGINE_URL-}"
# strip systemd quotes if present
URL="${URL%\"}"
URL="${URL#\"}"

# Prefer argv URL if systemd/env empty
if [ -z "$URL" ]; then
  for a in "$@"; do
    case "$a" in
      http://*|https://*) URL="$a" ;;
    esac
  done
fi

echo "using URL=$URL" >> /run/update-engine/wrapper.log 2>&1

# Probe once so we fail with a clear message
if [ -n "$URL" ]; then
  CODE=$(/usr/bin/curl.anki -s -o /dev/null -w '%{http_code}' --http1.1 -4 --max-time 25 -I "$URL" 2>/dev/null || echo 000)
  echo "probe=$CODE" >> /run/update-engine/wrapper.log 2>&1
  if [ "$CODE" != "200" ] && [ "$CODE" != "206" ] && [ "$CODE" != "301" ] && [ "$CODE" != "302" ]; then
    echo "failed to open URL (probe $CODE)" > /run/update-engine/error
    echo 203 > /run/update-engine/exit_code
    exit 203
  fi
  exec /anki/bin/update-engine.real -v "$URL"
fi

exec /anki/bin/update-engine.real "$@"
EOF
chmod 755 /anki/bin/update-engine

# Ensure update-os script is present for SSH installs too
if [ ! -f /data/update-os.sh ]; then
  curl -L -4 --max-time 60 -o /data/update-os.sh \
    https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/overlays/anki/wired/update-os.sh || true
  chmod 644 /data/update-os.sh 2>/dev/null || true
fi
touch /data/keep-update-os 2>/dev/null || true
if [ -f /data/update-os.sh ]; then
  printf '%s\n' '#!/bin/bash' 'exec /bin/bash /data/update-os.sh "$@"' >/usr/sbin/update-os
  chmod 755 /usr/sbin/update-os
fi

echo "OK — BLE websetup OTA fixed. Try Install again on the setup site."
echo "Log: /run/update-engine/wrapper.log"
