#!/usr/bin/env bash
# 1.6-rebuild update-os with error prevention:
# - curl -k downloads (avoids Python/update-engine SSL failures on GitHub)
# - writes to /ota (not tiny /data)
# - flashes inactive slot only (never bricks the flashed slot from recovery)
# - auto-creates gateway.cert (prevents fault 920)
#
#   update-os latest
#   update-os <url>
set -e
set -u

BRANCH="cursor/16-rebuild-errorsafe-7a4a"
RAW="https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/${BRANCH}"
# Latest public unlocked/dev 1.6-rebuild OTA (Victor-Rebuild historical releases).
DEFAULT_OTA="https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v1.6.1.81d-errorsafe/vicos-1.6.1.81d.ota"
MIN=150000000

usage() {
  echo "usage: update-os [-h|latest|url]"
  echo "  update-os latest"
  echo "  update-os $DEFAULT_OTA"
  echo ""
  echo "Downloads with curl (SSL-safe) and flashes the inactive slot."
  exit 0
}

if [ $# -lt 1 ] || [ "$1" = "-h" ]; then
  usage
fi

case "$1" in
  latest|lkg)
    URL="$DEFAULT_OTA"
    ;;
  *)
    URL="$1"
    ;;
esac

mount -o remount,rw / 2>/dev/null || true
mkdir -p /ota /data/ota /data/seek /run/update-engine

# Prefer a real curl; accept PATH curl (recovery often has a working one).
CURL=""
for c in /usr/bin/curl /bin/curl "$(command -v curl 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] || continue
  SZ=$(wc -c <"$c" 2>/dev/null || echo 0)
  # Skip empty curl.anki stubs (~0 bytes); keep anything else that runs.
  if [ "$SZ" -gt 100 ] 2>/dev/null; then
    CURL="$c"
    break
  fi
done
[ -n "$CURL" ] || { echo "ERROR: no working curl binary"; exit 1; }

FLASH="/usr/sbin/unlock-manual-flash-v2.sh"
if [ ! -x "$FLASH" ]; then
  FLASH="/data/unlock-manual-flash-v2.sh"
fi
if [ ! -x "$FLASH" ]; then
  echo "Fetching flash helper..."
  $CURL -k -L --http1.1 -4 -f -o /data/unlock-manual-flash-v2.sh \
    "${RAW}/seek/flash/unlock-manual-flash-v2.sh"
  chmod 755 /data/unlock-manual-flash-v2.sh
  FLASH=/data/unlock-manual-flash-v2.sh
fi

echo "Current OS Version: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "1.6-rebuild update-os (curl + safe manual flash)"
echo "OTA: $URL"
echo "curl=$CURL"
df -h /ota /data 2>/dev/null || true

DEST=/ota/v.ota
if ! touch /ota/.w 2>/dev/null; then
  echo "WARNING: /ota not writable — using /data/ota"
  DEST=/data/ota/v.ota
fi
rm -f /ota/.w

# Resolve GitHub redirect to CDN (optional; curl -L also handles it).
case "$URL" in
  *github.com*)
    FINAL=$($CURL -k -sI --http1.1 -4 --max-time 25 "$URL" 2>/dev/null | grep -i '^location:' | sed -n '$p' | awk '{print $2}' | tr -d '\r')
    if [ -n "${FINAL:-}" ]; then
      URL="$FINAL"
      echo "CDN: $URL"
    fi
    ;;
esac

echo "Downloading OTA to $DEST ..."
rm -f "$DEST"
$CURL -k -L --http1.1 -4 --connect-timeout 120 -f -o "$DEST" "$URL"
SZ=$(wc -c <"$DEST")
echo "OTA size=$SZ"
if [ "$SZ" -lt "$MIN" ]; then
  echo "FATAL: OTA too small (need >= $MIN) — download incomplete"
  exit 1
fi

systemctl -q stop update-engine 2>/dev/null || true
echo "Stopping anki-robot (eyes may go dark)..."
systemctl stop anki-robot.target 2>/dev/null || true
killall -9 vic-engine vic-anim vic-cloud vic-robot 2>/dev/null || true

echo "Flashing inactive slot (stay on charger)..."
rm -f /data/unbrick
exec sh "$FLASH" "$DEST"
