#!/usr/bin/env bash
# SeekOS full-image installer. Run on a computer on the same Wi-Fi as Vector.
# Vector cannot pull GitHub OTAs (stuck at 0%) — this downloads here, then copies over LAN.
#
# One command:
#   curl -fsSL https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/install-ota.sh | bash -s -- 192.168.42.209 "$HOME/Downloads/ssh_root_key.txt"
set -euo pipefail

IP="${1:-${SEEK_IP:-192.168.42.209}}"
KEY="${2:-${SEEK_KEY:-$HOME/Downloads/ssh_root_key.txt}}"
REPO="loganstorm1254-sudo/seek-cfw"
FALLBACK_URL="https://github.com/${REPO}/releases/download/v3.0.1.38d/vicos-3.0.1.38d.ota"
FALLBACK_NAME="vicos-3.0.1.38d.ota"

if [[ ! -f "$KEY" ]]; then
    echo "SSH key not found: $KEY" >&2
    exit 1
fi

SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o BatchMode=yes)
SCP=(scp -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o BatchMode=yes)

echo "Finding latest SeekOS .ota on GitHub..."
NAME=""
URL=""
API_JSON="$(curl -fsSL -A seek-install-ota "https://api.github.com/repos/${REPO}/releases?per_page=15" || true)"
if [[ -n "$API_JSON" ]]; then
    # First vicos-*.ota asset across recent releases.
    URL="$(printf '%s' "$API_JSON" | tr ',' '\n' | grep -o 'https://github.com/[^"]*/vicos-[^"]*\.ota' | head -n1 || true)"
    if [[ -n "$URL" ]]; then
        NAME="$(basename "$URL")"
    fi
fi
if [[ -z "$URL" ]]; then
    URL="$FALLBACK_URL"
    NAME="$FALLBACK_NAME"
fi

LOCAL="${TMPDIR:-/tmp}/$NAME"
echo "Downloading $NAME on this computer (not the robot)..."
echo "$URL"
curl -fL --progress-bar -o "$LOCAL" "$URL"
echo "Preparing Vector $IP ..."
"${SSH[@]}" "root@$IP" 'mkdir -p /data/ota; systemctl stop update-engine || true'
echo "Copying over Wi-Fi..."
"${SCP[@]}" "$LOCAL" "root@$IP:/data/ota/$NAME"
echo "Flashing from localhost. Eyes will go dark; Vector reboots when done."
"${SSH[@]}" "root@$IP" "set -e
mkdir -p /data/ota
if grep -q serve_local_ota /usr/sbin/update-os 2>/dev/null; then
  update-os /data/ota/$NAME
elif curl -sI --max-time 3 http://127.0.0.1:8765/$NAME 2>/dev/null | grep -qi content-length; then
  systemctl stop update-engine || true
  update-os http://127.0.0.1:8765/$NAME
elif busybox httpd -p 127.0.0.1:8765 -h /data/ota 2>/dev/null; then
  systemctl stop update-engine || true
  update-os http://127.0.0.1:8765/$NAME
else
  ln -sf /data/ota/$NAME /etc/wired/webroot/vicos.ota
  systemctl stop update-engine || true
  update-os http://127.0.0.1:8080/vicos.ota
fi"
echo "Done. Wait for Vector to boot."
