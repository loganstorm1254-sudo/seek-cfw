#!/usr/bin/env bash
# SeekOS update-os: download the .ota first (real progress), then flash from localhost.
# Stock update-engine HEAD-probes GitHub without -L and sits at 0%.

set -e
set -u

OTA_DIR=/data/ota
OTA_PORT=8765

function usage()
{
    echo "usage: update-os <url>"
    echo "  update-os https://github.com/USER/REPO/releases/download/vX/vicos-X.ota"
    exit 0
}

trap ctrl_c INT
function ctrl_c() {
    echo -e "\n\nStopping OS update..."
    systemctl -q stop update-engine || true
    exit 1
}

boost_cpu() {
    echo 1267200 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || true
    echo disabled > /sys/kernel/debug/msm_otg/bus_voting 2>/dev/null || true
    echo 0 > /sys/kernel/debug/msm-bus-dbg/shell-client/update_request 2>/dev/null || true
    echo 1 > /sys/kernel/debug/msm-bus-dbg/shell-client/mas 2>/dev/null || true
    echo 512 > /sys/kernel/debug/msm-bus-dbg/shell-client/slv 2>/dev/null || true
    echo 0 > /sys/kernel/debug/msm-bus-dbg/shell-client/ab 2>/dev/null || true
    echo 'active clk2 0 1 max 800000' > /sys/kernel/debug/rpm_send_msg/message 2>/dev/null || true
    echo 1 > /sys/kernel/debug/msm-bus-dbg/shell-client/update_request 2>/dev/null || true
}

header_length() {
    # Last Content-Length after redirects (GitHub 302 has none).
    curl -sIL --http1.1 -4 --max-time 15 "$1" 2>/dev/null \
        | awk 'BEGIN{IGNORECASE=1} /^Content-Length:/ {v=$2} END{gsub(/\r/,"",v); print v}' || true
}

serve_local_ota() {
    local file="$1"
    local name
    name="$(basename "$file")"
    mkdir -p "$OTA_DIR"
    if [ "$file" != "$OTA_DIR/$name" ]; then
        ln -sf "$file" "$OTA_DIR/$name"
    fi

    local probe="http://127.0.0.1:${OTA_PORT}/${name}"
    local cl=""
    cl="$(header_length "$probe" || true)"
    if [ -n "${cl:-}" ] && [ "$cl" -gt 1000 ] 2>/dev/null; then
        URL="$probe"
        return 0
    fi

    if command -v busybox >/dev/null 2>&1; then
        killall -q httpd 2>/dev/null || true
        busybox httpd -p "127.0.0.1:${OTA_PORT}" -h "$OTA_DIR" 2>/dev/null || \
            busybox httpd -p "${OTA_PORT}" -h "$OTA_DIR" 2>/dev/null || true
        sleep 1
        cl="$(header_length "$probe" || true)"
        if [ -n "${cl:-}" ] && [ "$cl" -gt 1000 ] 2>/dev/null; then
            URL="$probe"
            return 0
        fi
    fi

    if [ -d /etc/wired/webroot ]; then
        ln -sf "$OTA_DIR/$name" "/etc/wired/webroot/$name"
        URL="http://127.0.0.1:8080/${name}"
        return 0
    fi

    echo "Could not serve $file over local HTTP."
    exit 1
}

curl_get() {
    # HTTP/1.1 + IPv4 is much faster on Vector's old curl than GitHub HTTP/2.
    curl -fL --http1.1 -4 --retry 8 --retry-delay 3 --connect-timeout 20 --continue-at - --progress-bar -o "$2" "$1" \
        || curl -fL -4 --retry 8 --retry-delay 3 --connect-timeout 20 --progress-bar -o "$2" "$1"
}

download_remote() {
    local src="$1"
    local base
    systemctl -q stop update-engine || true
    boost_cpu
    base="$(basename "${src%%\?*}")"
    case "$base" in
        *.ota) ;;
        *) base="update.ota" ;;
    esac
    mkdir -p "$OTA_DIR"
    local dest="$OTA_DIR/$base"
    local expected=""
    expected="$(header_length "$src" || true)"

    if [ -f "$dest" ] && [ -n "${expected:-}" ] && [ "$(stat -c%s "$dest" 2>/dev/null || echo 0)" = "$expected" ]; then
        echo "Already have $dest ($expected bytes)"
    else
        echo "Downloading OS image (eyes stay on)..."
        echo "$src"
        rm -f "$dest"
        if ! curl_get "$src" "$dest"; then
            echo "Download failed."
            exit 1
        fi
    fi
    local got
    got="$(stat -c%s "$dest" 2>/dev/null || echo 0)"
    if [ "$got" -lt 1000000 ]; then
        echo "Download too small ($got bytes) — bad URL?"
        exit 1
    fi
    echo "Download complete ($got bytes). Flashing from localhost..."
    serve_local_ota "$dest"
}

resolve_url() {
    local src="$1"
    case "$src" in
        http://127.0.0.1/*|http://localhost/*|http://[::1]/*)
            URL="$src"
            ;;
        http://*|https://*)
            download_remote "$src"
            ;;
        /*)
            [ -f "$src" ] || { echo "No such file: $src"; exit 1; }
            serve_local_ota "$src"
            ;;
        *)
            if [ -f "$src" ]; then
                serve_local_ota "$(pwd)/$src"
            else
                URL="$src"
            fi
            ;;
    esac
}

BASE_URL=`grep UPDATE_ENGINE_BASE_URL= /anki/etc/update-engine.env | awk -F= '{print $NF;}'`
BASE_URL_LATEST=`grep UPDATE_ENGINE_BASE_URL_LATEST /anki/etc/update-engine.env | awk -F= '{print $NF;}'`
if [ -z "${BASE_URL_LATEST}" ]; then
    BASE_URL_LATEST="${BASE_URL}"
fi
URL="${BASE_URL}full/lkg.ota"
if [ $# -gt 0 ]; then
    case "$1" in
	-h)
	    usage
	    ;;
	latest)
	    URL="${BASE_URL}full/latest.ota"
	    ;;
        delta-latest)
            URL="${BASE_URL_LATEST}diff/`getprop ro.anki.version | tr -d '[a-z]'`.ota"
            ;;
	lkg)
	    ;;
	[0-9].[0-9].[0-9].[0-9]*)
	    URL="${BASE_URL}full/$1.ota"
	    ;;
	*)
	    resolve_url "$1"
	    ;;
    esac
fi

# Remote Anki/GitHub URLs still need a local copy so update-engine doesn't hang at 0%.
case "$URL" in
    http://127.0.0.1/*|http://localhost/*|file:*)
        ;;
    http://*|https://*)
        download_remote "$URL"
        ;;
esac

systemctl -q stop update-engine || true
rm -rf /run/update-engine
boost_cpu

echo "Current OS Version: `getprop ro.anki.version`"

mkdir -p /run/vic-switchboard /run/update-engine
echo "UPDATE_ENGINE_ENABLED=True" > /run/vic-switchboard/update-engine.env
echo "UPDATE_ENGINE_MAX_SLEEP=1" >> /run/vic-switchboard/update-engine.env
echo "UPDATE_ENGINE_ALLOW_DOWNGRADE=True" >> /run/vic-switchboard/update-engine.env
echo "UPDATE_ENGINE_URL=$URL" >> /run/vic-switchboard/update-engine.env
echo "UPDATE_ENGINE_DEBUG=True" >> /run/vic-switchboard/update-engine.env
chown -R net:anki /run/vic-switchboard

systemctl reset-failed update-engine || true
systemctl start update-engine
sleep 1
if ! systemctl is-active --quiet update-engine && [ ! -f /run/update-engine/manifest.ini ]; then
    echo "update-engine did not start."
    cat /run/update-engine/error 2>/dev/null || true
    systemctl status update-engine --no-pager || true
    exit 1
fi

echo "Stopping anki-robot.target... (eyes will go dark)"
systemctl stop anki-robot.target

echo -e "Installing from:\n$URL"

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
            echo "update-engine said done but did not flash (stale flag). Not rebooting."
            rm -f /run/update-engine/done
            exit 1
        fi
        CODE=`cat /run/update-engine/exit_code 2>/dev/null || true`
        if [ -z "$CODE" ]; then
            sleep 1
            CODE=`cat /run/update-engine/exit_code 2>/dev/null || echo 0`
        fi
        if [ "$CODE" != "0" ]; then
            echo "update-engine failed (exit $CODE). Not rebooting."
            exit 1
        fi
        break
    fi
    if [ "$WAIT" -gt 3600 ]; then
        echo "Timed out waiting for the flash. Not rebooting."
        exit 1
    fi
done

echo -e "\n\nRebooting....."
sleep 2
sync
reboot & exit
