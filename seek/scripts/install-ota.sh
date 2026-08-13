#!/usr/bin/env bash
# Short SeekOS OTA install. Streams from GitHub (no save to /data/ota).
# Usage: bash /data/u.sh [ota-url]
# BusyBox-safe (Vector).
set -e
set -u

URL="${1:-}"
if [ -z "$URL" ]; then
  URL=`curl -sL -4 --max-time 25 -H 'User-Agent: SeekOS' -H 'Accept: application/vnd.github+json' \
    https://api.github.com/repos/loganstorm1254-sudo/seek-cfw/releases/latest \
    | tr '"' '\n' | grep '/vicos-.*\.ota$' | grep '^https://' | sed -n '1p'`
fi
if [ -z "$URL" ]; then
  echo "No OTA URL"
  exit 1
fi

systemctl start anki-robot.target 2>/dev/null || true
sleep 3
umount /usr/bin/curl 2>/dev/null || true
umount /usr/sbin/update-os 2>/dev/null || true
mount -o remount,exec /run 2>/dev/null || true

CURL=curl
USE_RUN_PATH=0
if cp -L /usr/bin/curl /run/curl.real 2>/dev/null; then
  chmod 755 /run/curl.real
  if /run/curl.real -V >/dev/null 2>&1; then
    CURL=/run/curl.real
    printf '#!/bin/sh\nexec /run/curl.real -L --http1.1 -4 --connect-timeout 20 "$@"\n' >/run/curl-shim
    chmod 755 /run/curl-shim
    if /run/curl-shim -V >/dev/null 2>&1; then
      mount --bind /run/curl-shim /usr/bin/curl 2>/dev/null || true
      mkdir -p /run/bin
      cp /run/curl-shim /run/bin/curl
      chmod 755 /run/bin/curl
      USE_RUN_PATH=1
    fi
  fi
fi

case "$URL" in
  *github.com*)
    FINAL=`$CURL -sI --http1.1 -4 --max-time 20 "$URL" 2>/dev/null | grep -i '^location:' | sed -n '$p' | awk '{print $2}' | tr -d '\r'`
    [ -n "$FINAL" ] && URL="$FINAL"
    ;;
esac

echo "URL=$URL"
systemctl stop update-engine.timer update-engine 2>/dev/null || true
rm -rf /run/update-engine
mkdir -p /run/vic-switchboard /run/update-engine
{
  echo UPDATE_ENGINE_ENABLED=True
  echo UPDATE_ENGINE_MAX_SLEEP=1
  echo UPDATE_ENGINE_ALLOW_DOWNGRADE=True
  echo UPDATE_ENGINE_DEBUG=True
  printf 'UPDATE_ENGINE_URL=%s\n' "$URL"
  if [ "$USE_RUN_PATH" = "1" ]; then
    echo PATH=/run/bin:/usr/bin:/bin:/usr/sbin:/sbin
  fi
} >/run/vic-switchboard/update-engine.env
chown -R net:anki /run/vic-switchboard
systemctl reset-failed update-engine 2>/dev/null || true
systemctl start update-engine

echo "Waiting for download (Wi-Fi stays up)..."
W=0
while true; do
  if [ -f /run/update-engine/error ]; then
    E=`cat /run/update-engine/error`
    [ "$E" = "Unclean exit" ] || { echo "ERROR: $E"; systemctl start anki-robot.target; exit 1; }
  fi
  P=`cat /run/update-engine/progress 2>/dev/null || echo 0`
  echo "bytes $P"
  if [ "$P" -gt 1048576 ] 2>/dev/null; then
    break
  fi
  W=$((W+1))
  [ "$W" -gt 120 ] && { echo "Stuck at 0%"; systemctl stop update-engine; systemctl start anki-robot.target; exit 1; }
  sleep 2
done

echo "Stopping anki-robot (eyes dark)..."
systemctl stop anki-robot.target
echo 1267200 >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || true

while true; do
  if [ -f /run/update-engine/error ]; then
    E=`cat /run/update-engine/error`
    [ "$E" = "Unclean exit" ] || { echo "ERROR: $E"; systemctl start anki-robot.target; exit 1; }
  fi
  if [ -f /run/update-engine/progress ] && [ -f /run/update-engine/expected-size ]; then
    P=`cat /run/update-engine/progress`
    E=`cat /run/update-engine/expected-size`
    if [ -n "$P" ] && [ -n "$E" ] && [ "$E" != "0" ]; then
      echo "$((100 * P / E))%"
    fi
  fi
  if [ -f /run/update-engine/done ] && [ -f /run/update-engine/manifest.ini ]; then
    echo DONE
    sync
    reboot
    exit 0
  fi
  sleep 2
done
