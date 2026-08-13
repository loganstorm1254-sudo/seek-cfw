#!/bin/sh
# Fix BLE websetup OTA (status 203) on a live Seek robot.
# BusyBox-safe: never overwrite a running binary (Text file busy) —
# write sidecars and bind-mount over the paths.
set -e

mount -o remount,rw / 2>/dev/null || true
umount /usr/bin/curl 2>/dev/null || true
umount /usr/sbin/update-os 2>/dev/null || true
umount /anki/bin/update-engine 2>/dev/null || true

mkdir -p /data /run

# --- curl HTTP/1.1 shim (bind-mount; don't clobber busy /usr/bin/curl) ---
if [ ! -x /data/curl.anki ]; then
  cp -L /usr/bin/curl /data/curl.anki 2>/dev/null || cp /usr/bin/curl /data/curl.anki
  chmod 755 /data/curl.anki
fi
# If /usr/bin/curl is already a script pointing at curl.anki, keep a real binary copy
if head -1 /data/curl.anki 2>/dev/null | grep -q '^#!'; then
  # bad copy — try curl.anki on /usr if present
  if [ -x /usr/bin/curl.anki ]; then
    cp -L /usr/bin/curl.anki /data/curl.anki
    chmod 755 /data/curl.anki
  fi
fi

cat > /data/curl-shim << 'EOF'
#!/bin/sh
REAL=/data/curl.anki
[ -x /usr/bin/curl.anki ] && REAL=/usr/bin/curl.anki
exec "$REAL" -L --http1.1 -4 --connect-timeout 30 "$@"
EOF
chmod 755 /data/curl-shim
mount --bind /data/curl-shim /usr/bin/curl 2>/dev/null || true

# --- save real update-engine once ---
if [ ! -x /data/update-engine.real ]; then
  # Prefer non-wrapper binary
  if [ -x /anki/bin/update-engine.real ]; then
    cp -a /anki/bin/update-engine.real /data/update-engine.real
  else
    cp -a /anki/bin/update-engine /data/update-engine.real
  fi
  chmod 755 /data/update-engine.real
fi

# --- update-engine wrapper (bind-mount) ---
cat > /data/update-engine-wrap << 'EOF'
#!/bin/bash
mkdir -p /run/update-engine
{
  echo "wrapper start $(date)"
  echo "env URL=${UPDATE_ENGINE_URL-}"
  echo "args=$*"
} >> /run/update-engine/wrapper.log 2>&1

export UPDATE_ENGINE_ALLOW_DOWNGRADE=True
export UPDATE_ENGINE_ENABLED=True

URL="${UPDATE_ENGINE_URL-}"
URL="${URL%\"}"
URL="${URL#\"}"

if [ -z "$URL" ]; then
  for a in "$@"; do
    case "$a" in
      http://*|https://*) URL="$a" ;;
    esac
  done
fi

echo "using URL=$URL" >> /run/update-engine/wrapper.log 2>&1

REAL=/data/update-engine.real
[ -x /anki/bin/update-engine.real ] && REAL=/anki/bin/update-engine.real

CURL=/data/curl.anki
[ -x /usr/bin/curl.anki ] && CURL=/usr/bin/curl.anki

if [ -n "$URL" ]; then
  CODE=$($CURL -s -o /dev/null -w '%{http_code}' --http1.1 -4 --max-time 25 -I "$URL" 2>/dev/null || echo 000)
  echo "probe=$CODE" >> /run/update-engine/wrapper.log 2>&1
  if [ "$CODE" != "200" ] && [ "$CODE" != "206" ] && [ "$CODE" != "301" ] && [ "$CODE" != "302" ]; then
    echo "failed to open URL (probe $CODE)" > /run/update-engine/error
    echo 203 > /run/update-engine/exit_code
    exit 203
  fi
  exec "$REAL" -v "$URL"
fi

exec "$REAL" "$@"
EOF
chmod 755 /data/update-engine-wrap
mount --bind /data/update-engine-wrap /anki/bin/update-engine

# --- update-os helper for SSH installs ---
if [ ! -f /data/update-os.sh ]; then
  /data/curl-shim -L -4 --max-time 60 -o /data/update-os.sh \
    https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/overlays/anki/wired/update-os.sh \
    || curl -L -4 --max-time 60 -o /data/update-os.sh \
    https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/overlays/anki/wired/update-os.sh \
    || true
  chmod 644 /data/update-os.sh 2>/dev/null || true
fi
touch /data/keep-update-os 2>/dev/null || true
if [ -f /data/update-os.sh ]; then
  printf '%s\n' '#!/bin/bash' 'exec /bin/bash /data/update-os.sh "$@"' >/data/update-os-wrap
  chmod 755 /data/update-os-wrap
  umount /usr/sbin/update-os 2>/dev/null || true
  # Prefer writing wrapper if possible; else bind
  if printf '%s\n' '#!/bin/bash' 'exec /bin/bash /data/update-os.sh "$@"' >/usr/sbin/update-os 2>/dev/null; then
    chmod 755 /usr/sbin/update-os
  else
    mount --bind /data/update-os-wrap /usr/sbin/update-os
  fi
fi

echo "OK — BLE websetup OTA fixed. Try Install again on the setup site."
echo "Log: /run/update-engine/wrapper.log"
mount | grep -E 'curl|update-engine|update-os' || true
