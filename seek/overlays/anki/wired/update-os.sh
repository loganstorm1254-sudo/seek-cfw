#!/usr/bin/env bash
# WireOS-style: update-os <github-url>
# Streams the OTA (no save). BusyBox-safe. Forces HTTP/1.1 on /usr/bin/curl
# because Vector's curl hangs at 0% on GitHub CDN over HTTP/2.
set -e
set -u

function usage()
{
    echo "usage: update-os <url>"
    echo "  update-os https://github.com/USER/REPO/releases/download/vX/vicos-X.ota"
    exit 0
}

trap ctrl_c INT
function ctrl_c() {
    echo -e "\n\nStopping OS update..."
    systemctl -q stop update-engine.timer update-engine || true
    systemctl start anki-robot.target 2>/dev/null || true
    exit 1
}

BASE_URL=""
BASE_URL_LATEST=""
if [ -f /anki/etc/update-engine.env ]; then
    BASE_URL=`grep UPDATE_ENGINE_BASE_URL= /anki/etc/update-engine.env 2>/dev/null | awk -F= '{print $NF;}'`
    BASE_URL_LATEST=`grep UPDATE_ENGINE_BASE_URL_LATEST /anki/etc/update-engine.env 2>/dev/null | awk -F= '{print $NF;}'`
fi
if [ -z "${BASE_URL_LATEST}" ]; then
    BASE_URL_LATEST="${BASE_URL}"
fi
URL="${BASE_URL}full/lkg.ota"
if [ $# -gt 0 ]; then
    case "$1" in
	-h) usage ;;
	latest) URL="${BASE_URL}full/latest.ota" ;;
        delta-latest)
            URL="${BASE_URL_LATEST}diff/`getprop ro.anki.version | tr -d '[a-z]'`.ota"
            ;;
	lkg) ;;
	[0-9].[0-9].[0-9].[0-9]*) URL="${BASE_URL}full/$1.ota" ;;
	*) URL=$1 ;;
    esac
fi

# Unlock / minimal images often have no BASE_URL — require an explicit URL.
if [ -z "$URL" ] || [ "$URL" = "full/lkg.ota" ]; then
    echo "No OTA URL. Usage: update-os http://files.anki.org.uk/ota/latest"
    exit 1
fi

systemctl start anki-robot.target 2>/dev/null || true
sleep 2

# Tear down any broken curl bind-mounts from older Seek builds.
umount /usr/bin/curl 2>/dev/null || true
umount /usr/sbin/update-os 2>/dev/null || true

# Force HTTP/1.1 system-wide for update-engine (runs as user net).
# Do this on /usr (exec), never on noexec /data or /run.
# IMPORTANT: never `cat > /usr/bin/curl` while curl is executing — ETXTBSY
# ("Text file busy"). Unlink + recreate instead.
mount -o remount,rw / 2>/dev/null || true
if [ ! -x /usr/bin/curl.anki ]; then
    # Prefer real binary; skip if /usr/bin/curl is already our wrapper.
    if head -n 1 /usr/bin/curl 2>/dev/null | grep -q '^#!'; then
        echo "FATAL: /usr/bin/curl is a script but curl.anki is missing."
        exit 1
    fi
    cp -a /usr/bin/curl /usr/bin/curl.anki
    chmod 755 /usr/bin/curl.anki
fi
WRAP=/tmp/curl.seek.wrap.$$
cat > "$WRAP" << 'EOF'
#!/bin/sh
# SeekOS: Vector's stock curl stalls on GitHub CDN over HTTP/2.
# -k: many robots have a broken/missing CA bundle (curl exit 77).
exec /usr/bin/curl.anki -k -L --http1.1 -4 --connect-timeout 30 "$@"
EOF
chmod 755 "$WRAP"
# Kill holders, unlink busy inode, install fresh wrapper.
fuser -k /usr/bin/curl >/dev/null 2>&1 || true
sleep 0.3
rm -f /usr/bin/curl
cp "$WRAP" /usr/bin/curl
chmod 755 /usr/bin/curl
rm -f "$WRAP"

CURL_BIN=/usr/bin/curl.anki

# Local file already on robot (Seek dash upload → 127.0.0.1:8765/v.ota).
# Never delete /data/ota/v.ota — older scripts did, then cloud-with-! failed.
case "$URL" in
  http://127.0.0.1:*|http://localhost:*)
    if [ ! -f /data/ota/v.ota ]; then
      echo "Local OTA missing: /data/ota/v.ota"
      exit 1
    fi
    echo "Current OS Version: `getprop ro.anki.version 2>/dev/null || echo unknown`"
    echo "Flashing local uploaded OTA:"
    echo "$URL"
    ;;
  *)
    # Resolve GitHub 302 → CDN 200 URL (update-engine --fail dies on redirects).
    case "$URL" in
      *github.com*)
        FINAL=`$CURL_BIN -k -sI --http1.1 -4 --max-time 25 "$URL" 2>/dev/null | grep -i '^location:' | sed -n '$p' | awk '{print $2}' | tr -d '\r'`
        if [ -n "$FINAL" ]; then
          URL="$FINAL"
        fi
        ;;
    esac

    echo "Current OS Version: `getprop ro.anki.version 2>/dev/null || echo unknown`"
    echo "Installing OS update from:"
    echo "$URL"

    # Prove the CDN actually streams before we hand it to update-engine.
    echo "Probing download..."
    CODE=`$CURL_BIN -k -s -o /dev/null -w '%{http_code}' --http1.1 -4 --max-time 40 -r 0-1048575 "$URL" 2>/dev/null || echo 000`
    echo "probe=$CODE"
    if [ "$CODE" != "200" ] && [ "$CODE" != "206" ]; then
        echo "CDN probe failed ($CODE). Bring Wi-Fi back and retry."
        systemctl start anki-robot.target 2>/dev/null || true
        exit 1
    fi
    ;;
esac

systemctl -q stop update-engine.timer update-engine 2>/dev/null || true
rm -rf /run/update-engine
mkdir -p /run/vic-switchboard /run/update-engine /ota /cache
{
  echo UPDATE_ENGINE_ENABLED=True
  echo UPDATE_ENGINE_MAX_SLEEP=1
  echo UPDATE_ENGINE_ALLOW_DOWNGRADE=True
  echo UPDATE_ENGINE_DEBUG=True
  printf 'UPDATE_ENGINE_URL=%s\n' "$URL"
} >/run/vic-switchboard/update-engine.env
# Unlock may not have net:anki — ignore chown failures.
chown -R net:anki /run/vic-switchboard 2>/dev/null || true

# Max CPU for the transfer; keep anki-robot UP so Wi-Fi stays alive.
echo 1267200 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || true

export UPDATE_ENGINE_ENABLED=True
export UPDATE_ENGINE_ALLOW_DOWNGRADE=True
export UPDATE_ENGINE_MAX_SLEEP=1
export UPDATE_ENGINE_URL="$URL"
export SSL_CERT_FILE=
export CURL_CA_BUNDLE=
unset SSL_CERT_FILE CURL_CA_BUNDLE 2>/dev/null || true

ENGINE=""
for e in /anki/bin/update-engine /anki/bin/update-engine.real /usr/bin/update-engine; do
  if [ -x "$e" ] && ! head -n 1 "$e" 2>/dev/null | grep -q 'Seek BLE OTA wrap'; then
    ENGINE="$e"
    break
  fi
done
# Prefer wrap if present (downloads to /ota then flashes) — works on Unlock.
if [ -x /anki/bin/update-engine ] && grep -q 'Seek BLE OTA wrap' /anki/bin/update-engine 2>/dev/null; then
  ENGINE=/anki/bin/update-engine
elif [ -x /data/update-engine-wrap ]; then
  ENGINE=/data/update-engine-wrap
elif [ -z "$ENGINE" ] && [ -x /anki/bin/update-engine ]; then
  ENGINE=/anki/bin/update-engine
fi

if [ -z "$ENGINE" ]; then
  echo "No /anki/bin/update-engine on this robot (Unlock missing binary?)."
  echo "Falling back: download OTA to /ota/v.ota then you need update-engine to flash."
  echo "Downloading to /ota/v.ota ..."
  $CURL_BIN -k -L --http1.1 -4 --fail -o /ota/v.ota "$URL"
  ls -la /ota/v.ota
  echo "Downloaded, but cannot flash without update-engine binary."
  exit 1
fi

USE_SYSTEMD=0
if systemctl cat update-engine.service >/dev/null 2>&1; then
  USE_SYSTEMD=1
fi

if [ "$USE_SYSTEMD" = 1 ]; then
  systemctl reset-failed update-engine 2>/dev/null || true
  systemctl start update-engine
else
  # Unlock 0.9.x: no update-engine.service — run the binary directly.
  echo "Unlock/no-systemd mode: running $ENGINE directly"
  echo starting > /run/update-engine/phase
  (
    # Never put -v before BINARY via logwrapper — Unlock logwrapper claims -v.
    "$ENGINE" -v "$URL"
    echo $? > /run/update-engine/exit_code
    touch /run/update-engine/done
  ) &
  ENGINE_PID=$!
  echo "update-engine pid=$ENGINE_PID"
fi

# Local upload flash: Wi‑Fi not required — free CPU immediately.
case "$URL" in
  http://127.0.0.1:*|http://localhost:*)
    echo "Stopping anki-robot.target... (eyes will go dark)"
    systemctl stop anki-robot.target 2>/dev/null || true
    ;;
esac

echo "Downloading (eyes stay on until data moves)..."
WAIT=0
LAST=0
STALL=0
while true; do
    if [ -f /run/update-engine/error ]; then
	ERRORMSG=`cat /run/update-engine/error`
	if [ "$ERRORMSG" != "Unclean exit" ]; then
	    echo "Error updating OS: $ERRORMSG"
            systemctl start anki-robot.target 2>/dev/null || true
	    exit 1
	fi
    fi
    PROGRESS=0
    EXPECTED=0
    if [ -f /run/update-engine/progress ]; then
        PROGRESS=`cat /run/update-engine/progress 2>/dev/null || echo 0`
    fi
    if [ -f /run/update-engine/expected-size ]; then
        EXPECTED=`cat /run/update-engine/expected-size 2>/dev/null || echo 0`
    fi
    if [ -n "$PROGRESS" ] && [ -n "$EXPECTED" ] && [ "$EXPECTED" != "0" ]; then
        PCT=$(( 100 * PROGRESS / EXPECTED ))
        echo "Updating ( ${PCT}% ) ${PROGRESS}/${EXPECTED}"
    else
        echo "bytes ${PROGRESS}"
    fi
    case "$URL" in
      http://127.0.0.1:*|http://localhost:*) ;;
      *)
        if [ "$PROGRESS" -gt 5242880 ] 2>/dev/null; then
            # Enough data flowing — safe to free CPU for the flash.
            if systemctl is-active --quiet anki-robot.target 2>/dev/null; then
                echo "Stopping anki-robot.target... (eyes will go dark)"
                systemctl stop anki-robot.target 2>/dev/null || true
            fi
        fi
        ;;
    esac
    if [ "$PROGRESS" -eq "$LAST" ] 2>/dev/null; then
        STALL=$((STALL+1))
    else
        STALL=0
        LAST=$PROGRESS
    fi
    # If we never leave 0% for 2 minutes, abort cleanly.
    if [ "$PROGRESS" -eq 0 ] 2>/dev/null && [ "$STALL" -gt 60 ]; then
        echo "Stuck at 0%. CDN stream stalled."
        systemctl -q stop update-engine 2>/dev/null || true
        kill "$ENGINE_PID" 2>/dev/null || true
        systemctl start anki-robot.target 2>/dev/null || true
        exit 1
    fi
    if [ -f /run/update-engine/done ]; then
        if [ ! -f /run/update-engine/manifest.ini ] && [ "$USE_SYSTEMD" = 1 ]; then
            echo "Did not flash (stale done flag). Not rebooting."
            rm -f /run/update-engine/done
            systemctl start anki-robot.target 2>/dev/null || true
            exit 1
        fi
        # Direct mode: wait for background engine to exit.
        if [ "$USE_SYSTEMD" != 1 ] && [ -n "${ENGINE_PID:-}" ]; then
          wait "$ENGINE_PID" 2>/dev/null || true
          EC=`cat /run/update-engine/exit_code 2>/dev/null || echo 1`
          if [ "$EC" != "0" ]; then
            echo "update-engine exited $EC"
            systemctl start anki-robot.target 2>/dev/null || true
            exit "$EC"
          fi
        fi
        break
    fi
    # Direct mode: process exited without done flag
    if [ "$USE_SYSTEMD" != 1 ] && [ -n "${ENGINE_PID:-}" ]; then
      if ! kill -0 "$ENGINE_PID" 2>/dev/null; then
        wait "$ENGINE_PID" 2>/dev/null || true
        EC=`cat /run/update-engine/exit_code 2>/dev/null || echo 1`
        if [ "$EC" = "0" ]; then
          break
        fi
        echo "update-engine exited $EC"
        cat /run/update-engine/error 2>/dev/null || true
        systemctl start anki-robot.target 2>/dev/null || true
        exit "$EC"
      fi
    fi
    WAIT=$((WAIT+1))
    if [ "$WAIT" -gt 3600 ]; then
        echo "Timed out. Not rebooting."
        systemctl start anki-robot.target 2>/dev/null || true
        exit 1
    fi
    sleep 2
done

echo -e "\n\nRebooting....."
sleep 2
sync
reboot & exit
