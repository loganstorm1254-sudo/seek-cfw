#!/usr/bin/env bash
# SeekOS update-os: flash a full OTA from a local file (or a LAN URL).
# Vector cannot pull GitHub release assets at a usable speed — the stock
# updater HEAD-probes without -L, never gets Content-Length, and sits at 0%.

set -e
set -u

OTA_DIR=/data/ota
OTA_PORT=8765

function usage()
{
    echo "usage: update-os [-h|lkg|latest|version|url|file]"
    echo "-h                   This message"
    echo "lkg                  Update to Last Known Good OS (default) via full OTA"
    echo "latest               Update to latest OS via full OTA"
    echo "version              Like 1.2.1.2210 - Update to a specific version via full OTA"
    echo "delta-latest         Update to latest OS via delta OTA (may not work)"
    echo "url                  http://laptop:5555/os.ota  (LAN) or a local path"
    echo "file                 /data/ota/vicos-3.0.1.38d.ota"
    echo ""
    echo "Do not pass a GitHub https URL. Download the .ota on your PC, copy it"
    echo "to the robot over LAN, then point update-os at the local file:"
    echo "  scp -i KEY vicos-3.0.1.38d.ota root@VECTOR_IP:/data/ota/"
    echo "  ssh ... update-os /data/ota/vicos-3.0.1.38d.ota"
    echo ""
    echo "The robot reboots when the flash finishes."
    echo ""
    exit 0
}

trap ctrl_c INT

function ctrl_c() {
    echo -e "\n\nStopping OS update and exiting..."
    systemctl -q stop update-engine
    exit 1
}

header_length() {
    # $1 = URL. Prints Content-Length or empty.
    curl -sI -L --max-time 8 "$1" 2>/dev/null \
        | awk 'BEGIN{IGNORECASE=1} /^Content-Length:/ {gsub(/\r/,""); print $2; exit}'
}

serve_local_ota() {
    # $1 = absolute path to .ota. Sets URL to a loopback http URL.
    local file="$1"
    local name
    name="$(basename "$file")"
    mkdir -p "$OTA_DIR"
    if [ "$file" != "$OTA_DIR/$name" ]; then
        ln -sf "$file" "$OTA_DIR/$name"
    fi

    local probe="http://127.0.0.1:${OTA_PORT}/${name}"
    local cl

    # Prefer an already-running local server (Seek wired :8765 or busybox httpd).
    cl="$(header_length "$probe" || true)"
    if [ -n "${cl:-}" ] && [ "$cl" -gt 1000 ] 2>/dev/null; then
        URL="$probe"
        echo "Serving OTA from $file via $URL (${cl} bytes)"
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
            echo "Serving OTA from $file via busybox httpd $URL (${cl} bytes)"
            return 0
        fi
    fi

    # Last resort: dashboard FileServer on :8080 (works on 38d, no extra binary).
    if [ -d /etc/wired/webroot ]; then
        ln -sf "$OTA_DIR/$name" "/etc/wired/webroot/$name"
        probe="http://127.0.0.1:8080/${name}"
        cl="$(header_length "$probe" || true)"
        if [ -n "${cl:-}" ] && [ "$cl" -gt 1000 ] 2>/dev/null; then
            URL="$probe"
            echo "Serving OTA from $file via dashboard $URL (${cl} bytes)"
            return 0
        fi
    fi

    echo "Could not serve $file over local HTTP (need busybox httpd or wired :8080)."
    exit 1
}

resolve_url() {
    local src="$1"
    local base
    case "$src" in
        http://127.0.0.1/*|http://localhost/*|http://[::1]/*)
            URL="$src"
            return 0
            ;;
        http://*|https://*)
            base="$(basename "${src%%\?*}")"
            case "$src" in
                *github.com*|*githubusercontent.com*)
                    if [ -f "$OTA_DIR/$base" ]; then
                        echo "GitHub URLs stall on Vector. Using local $OTA_DIR/$base instead."
                        serve_local_ota "$OTA_DIR/$base"
                        return 0
                    fi
                    echo "Vector cannot download GitHub OTAs at a usable speed (stuck at 0%)."
                    echo "On your PC, download the .ota in a browser, then copy it over LAN:"
                    echo "  scp -i KEY $base root@VECTOR_IP:$OTA_DIR/$base"
                    echo "  ssh ... update-os $OTA_DIR/$base"
                    exit 1
                    ;;
            esac
            URL="$src"
            return 0
            ;;
        /*)
            if [ ! -f "$src" ]; then
                echo "No such file: $src"
                exit 1
            fi
            serve_local_ota "$src"
            return 0
            ;;
        *)
            if [ -f "$src" ]; then
                serve_local_ota "$(pwd)/$src"
                return 0
            fi
            URL="$src"
            return 0
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

# Always kill a hung updater first (GitHub HEAD can sit forever at 0%).
systemctl -q stop update-engine || true

echo "Current OS Version: `getprop ro.anki.version`"

mkdir -p /run/vic-switchboard

echo "UPDATE_ENGINE_ENABLED=True" > /run/vic-switchboard/update-engine.env
echo "UPDATE_ENGINE_MAX_SLEEP=1" >> /run/vic-switchboard/update-engine.env
echo "UPDATE_ENGINE_ALLOW_DOWNGRADE=True" >> /run/vic-switchboard/update-engine.env
echo "UPDATE_ENGINE_URL=$URL" >> /run/vic-switchboard/update-engine.env
echo "UPDATE_ENGINE_DEBUG=True" >> /run/vic-switchboard/update-engine.env

chown -R net:anki /run/vic-switchboard

systemctl restart update-engine

echo "Stopping anki-robot.target... (eyes will go dark)"
systemctl stop anki-robot.target

echo "Upping CPU+RAM frequencies..."
echo 1267200 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
echo disabled > /sys/kernel/debug/msm_otg/bus_voting  # This prevents USB from pinning RAM to 400MHz
echo 0 > /sys/kernel/debug/msm-bus-dbg/shell-client/update_request
echo 1 > /sys/kernel/debug/msm-bus-dbg/shell-client/mas
echo 512 > /sys/kernel/debug/msm-bus-dbg/shell-client/slv
echo 0 > /sys/kernel/debug/msm-bus-dbg/shell-client/ab
echo active clk2 0 1 max 800000 > /sys/kernel/debug/rpm_send_msg/message # Max RAM freq in KHz = 400MHz
echo 1 > /sys/kernel/debug/msm-bus-dbg/shell-client/update_request

echo

echo -e "Installing OS update from:\n$URL"

echo -e -n "\r."
DOTS=1
UPDATE_VERSION=""
while [[ ! -f /run/update-engine/done ]] ; do
    sleep 1
    if [ -z "${UPDATE_VERSION}" -a -f /run/update-engine/manifest.ini ]; then
	UPDATE_VERSION=`grep update_version /run/update-engine/manifest.ini | awk -F= '{print $NF;}'`
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
	    echo "Error updating OS . $ERRORMSG"
	    exit 1
	fi
    fi

done

echo -e "\n\nRebooting....."

sleep 2
sync
reboot & exit
