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

BASE_URL=`grep UPDATE_ENGINE_BASE_URL= /anki/etc/update-engine.env | awk -F= '{print $NF;}'`
BASE_URL_LATEST=`grep UPDATE_ENGINE_BASE_URL_LATEST /anki/etc/update-engine.env | awk -F= '{print $NF;}'`
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

systemctl start anki-robot.target 2>/dev/null || true
sleep 2

# Tear down any broken curl bind-mounts from older Seek builds.
umount /usr/bin/curl 2>/dev/null || true
umount /usr/sbin/update-os 2>/dev/null || true

# Force HTTP/1.1 system-wide for update-engine (runs as user net).
# Do this on /usr (exec), never on noexec /data or /run.
mount -o remount,rw / 2>/dev/null || true
if [ ! -x /usr/bin/curl.anki ]; then
    cp -L /usr/bin/curl /usr/bin/curl.anki 2>/dev/null || cp /usr/bin/curl /usr/bin/curl.anki
    chmod 755 /usr/bin/curl.anki
fi
cat > /usr/bin/curl << 'EOF'
#!/bin/sh
# SeekOS: Vector's stock curl stalls on GitHub CDN over HTTP/2.
exec /usr/bin/curl.anki -L --http1.1 -4 --connect-timeout 30 "$@"
EOF
chmod 755 /usr/bin/curl

CURL_BIN=/usr/bin/curl.anki

# Resolve GitHub 302 → CDN 200 URL (update-engine --fail dies on redirects).
case "$URL" in
  *github.com*)
    FINAL=`$CURL_BIN -sI --http1.1 -4 --max-time 25 "$URL" 2>/dev/null | grep -i '^location:' | sed -n '$p' | awk '{print $2}' | tr -d '\r'`
    if [ -n "$FINAL" ]; then
      URL="$FINAL"
    fi
    ;;
esac

echo "Current OS Version: `getprop ro.anki.version`"
echo "Installing OS update from:"
echo "$URL"

# Prove the CDN actually streams before we hand it to update-engine.
echo "Probing download..."
CODE=`$CURL_BIN -s -o /dev/null -w '%{http_code}' --http1.1 -4 --max-time 40 -r 0-1048575 "$URL" 2>/dev/null || echo 000`
echo "probe=$CODE"
if [ "$CODE" != "200" ] && [ "$CODE" != "206" ]; then
    echo "CDN probe failed ($CODE). Bring Wi-Fi back and retry."
    systemctl start anki-robot.target 2>/dev/null || true
    exit 1
fi

systemctl -q stop update-engine.timer update-engine || true
rm -rf /run/update-engine
mkdir -p /run/vic-switchboard /run/update-engine
{
  echo UPDATE_ENGINE_ENABLED=True
  echo UPDATE_ENGINE_MAX_SLEEP=1
  echo UPDATE_ENGINE_ALLOW_DOWNGRADE=True
  echo UPDATE_ENGINE_DEBUG=True
  printf 'UPDATE_ENGINE_URL=%s\n' "$URL"
} >/run/vic-switchboard/update-engine.env
chown -R net:anki /run/vic-switchboard

# Max CPU for the transfer; keep anki-robot UP so Wi-Fi stays alive.
echo 1267200 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || true

systemctl reset-failed update-engine || true
systemctl start update-engine

echo "Downloading (eyes stay on until data moves)..."
WAIT=0
LAST=0
STALL=0
while true; do
    if [ -f /run/update-engine/error ]; then
	ERRORMSG=`cat /run/update-engine/error`
	if [ "$ERRORMSG" != "Unclean exit" ]; then
	    echo "Error updating OS: $ERRORMSG"
            systemctl start anki-robot.target || true
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
    if [ "$PROGRESS" -gt 5242880 ] 2>/dev/null; then
        # Enough data flowing — safe to free CPU for the flash.
        if systemctl is-active --quiet anki-robot.target 2>/dev/null; then
            echo "Stopping anki-robot.target... (eyes will go dark)"
            systemctl stop anki-robot.target || true
        fi
    fi
    if [ "$PROGRESS" -eq "$LAST" ] 2>/dev/null; then
        STALL=$((STALL+1))
    else
        STALL=0
        LAST=$PROGRESS
    fi
    # If we never leave 0% for 2 minutes, abort cleanly.
    if [ "$PROGRESS" -eq 0 ] 2>/dev/null && [ "$STALL" -gt 60 ]; then
        echo "Stuck at 0%. CDN stream stalled."
        systemctl -q stop update-engine || true
        systemctl start anki-robot.target || true
        exit 1
    fi
    if [ -f /run/update-engine/done ]; then
        if [ ! -f /run/update-engine/manifest.ini ]; then
            echo "Did not flash (stale done flag). Not rebooting."
            rm -f /run/update-engine/done
            systemctl start anki-robot.target || true
            exit 1
        fi
        break
    fi
    WAIT=$((WAIT+1))
    if [ "$WAIT" -gt 3600 ]; then
        echo "Timed out. Not rebooting."
        systemctl start anki-robot.target || true
        exit 1
    fi
    sleep 2
done

echo -e "\n\nRebooting....."
sleep 2
sync
reboot & exit
