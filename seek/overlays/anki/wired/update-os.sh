#!/usr/bin/env bash
# Same command as WireOS: update-os <github-url>
# Streams from the URL (no copy to /data). Fixes GitHub HEAD/0% via a curl shim.

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

# GitHub on Vector's old curl is dead-slow over HTTP/2. Force HTTP/1.1 like it used to.
# /data is noexec. Some robots also mount /run noexec — remount exec before using /run.
umount /usr/bin/curl 2>/dev/null || true
mount -o remount,exec /run 2>/dev/null || true

CURL_BIN=/usr/bin/curl
if cp -L /usr/bin/curl /run/curl.real 2>/dev/null || cp /usr/bin/curl /run/curl.real 2>/dev/null; then
    chmod 0755 /run/curl.real
    if /run/curl.real -V >/dev/null 2>&1; then
        CURL_BIN=/run/curl.real
        cat > /run/curl-shim << 'EOF'
#!/bin/sh
exec /run/curl.real -L --http1.1 -4 --connect-timeout 20 "$@"
EOF
        chmod 0755 /run/curl-shim
        if /run/curl-shim -V >/dev/null 2>&1; then
            mount --bind /run/curl-shim /usr/bin/curl 2>/dev/null || true
            mkdir -p /run/bin
            cp /run/curl-shim /run/bin/curl
            chmod 0755 /run/bin/curl
            USE_RUN_PATH=1
        fi
    fi
fi

# Do not save the OTA on Vector. Follow GitHub's 302 so update-engine
# streams a 200 URL (its --fail flag dies on the redirect).
case "$URL" in
  *github.com*|*githubusercontent.com*)
    FINAL=`$CURL_BIN -sI --http1.1 -4 --max-time 20 "$URL" 2>/dev/null | grep -i '^location:' | tail -1 | awk '{print $2}' | tr -d '\r'`
    if [ -z "$FINAL" ]; then
      FINAL=`$CURL_BIN -sI -4 --max-time 20 "$URL" 2>/dev/null | grep -i '^location:' | tail -1 | awk '{print $2}' | tr -d '\r'`
    fi
    if [ -n "$FINAL" ]; then
      URL="$FINAL"
    fi
    ;;
esac

systemctl -q stop update-engine.timer update-engine || true
rm -rf /run/update-engine

echo "Current OS Version: `getprop ro.anki.version`"

mkdir -p /run/vic-switchboard /run/update-engine
echo "UPDATE_ENGINE_ENABLED=True" > /run/vic-switchboard/update-engine.env
echo "UPDATE_ENGINE_MAX_SLEEP=1" >> /run/vic-switchboard/update-engine.env
echo "UPDATE_ENGINE_ALLOW_DOWNGRADE=True" >> /run/vic-switchboard/update-engine.env
printf 'UPDATE_ENGINE_URL=%s\n' "$URL" >> /run/vic-switchboard/update-engine.env
echo "UPDATE_ENGINE_DEBUG=True" >> /run/vic-switchboard/update-engine.env
if [ "${USE_RUN_PATH:-0}" = "1" ]; then
    echo "PATH=/run/bin:/usr/bin:/bin:/usr/sbin:/sbin" >> /run/vic-switchboard/update-engine.env
fi
chown -R net:anki /run/vic-switchboard

systemctl reset-failed update-engine || true
systemctl start update-engine
sleep 5

echo "Stopping anki-robot.target... (eyes will go dark)"
systemctl stop anki-robot.target

echo 1267200 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || true

echo
echo -e "Installing OS update from:\n$URL"

echo -e -n "\r."
DOTS=1
UPDATE_VERSION=""
WAIT=0
while true ; do
    sleep 1
    WAIT=$((WAIT+1))
    if [ -z "${UPDATE_VERSION}" -a -f /run/update-engine/manifest.ini ]; then
	UPDATE_VERSION=`grep update_version /run/update-engine/manifest.ini | awk -F= '{print $NF;}' || true`
    fi
    if [ -f /run/update-engine/progress -a -f /run/update-engine/expected-size ] ; then
	PROGRESS=`cat /run/update-engine/progress`
	EXPECTED=`cat /run/update-engine/expected-size`
        if [ -n "$PROGRESS" -a -n "$EXPECTED" ] && [ "$EXPECTED" != "0" ]; then
	    PCT=$(( 100 * $PROGRESS / $EXPECTED ))
	    echo -e -n "\rUpdating to ${UPDATE_VERSION} ( ${PCT}% )"
        fi
    else
	for ((i=0;i<$DOTS;i++)); do
	    echo -n "."
	done
	DOTS=$((DOTS+1))
    fi
    if [ -f /run/update-engine/error ]; then
	ERRORMSG=`cat /run/update-engine/error`
	if [ "$ERRORMSG" != "Unclean exit" ]; then
	    echo "Error updating OS: $ERRORMSG"
	    exit 1
	fi
    fi
    if [ -f /run/update-engine/done ]; then
        if [ ! -f /run/update-engine/manifest.ini ]; then
            echo "Did not flash (stale done flag). Not rebooting."
            rm -f /run/update-engine/done
            exit 1
        fi
        break
    fi
    if [ "$WAIT" -gt 3600 ]; then
        echo "Timed out. Not rebooting."
        exit 1
    fi
done

echo -e "\n\nRebooting....."
sleep 2
sync
reboot & exit
