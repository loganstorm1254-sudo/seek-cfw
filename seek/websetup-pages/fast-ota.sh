#!/usr/bin/env bash
# Seek Fast OTA — Mac/Linux. Same hotspot as Vector. No git clone required.
#   curl -fsSL https://files.anki.org.uk/fast-ota.sh | bash
set -euo pipefail
PORT="${SEEK_FAST_OTA_PORT:-8765}"
OTA_URL="${SEEK_OTA_URL:-http://files.anki.org.uk/ota/latest}"
DIR="${TMPDIR:-/tmp}/seek-fast-ota"
OTA="$DIR/latest.ota"
mkdir -p "$DIR"

lan_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
  fi
  if [[ -z "${ip:-}" ]] && command -v ifconfig >/dev/null 2>&1; then
    ip=$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}' | sed 's/addr://')
  fi
  if [[ -z "${ip:-}" ]]; then
    echo "No LAN IP found. Join this PC to the same phone hotspot as Vector." >&2
    exit 1
  fi
  echo "$ip"
}

echo ""
echo "=== Seek Fast OTA ==="
echo "PC downloads the OS image; Vector pulls it over hotspot Wi-Fi (fast)."
echo ""

NEED=1
if [[ -f "$OTA" ]]; then
  SZ=$(wc -c <"$OTA" | tr -d ' ')
  if [[ "$SZ" -gt 80000000 ]]; then
    NEED=0
    echo "Using cached file: $OTA ($SZ bytes)"
  fi
fi
if [[ "$NEED" = 1 ]]; then
  echo "Downloading Seek OS (~217 MB) to this PC…"
  echo "  $OTA_URL"
  curl -fL --http1.1 -o "$OTA" "$OTA_URL"
fi

IP=$(lan_ip)
ROBOT="http://${IP}:${PORT}/latest.ota"
echo ""
echo "READY — leave this terminal open."
echo "1. Chrome:  https://files.anki.org.uk/setup"
echo "2. Pair Vector (same hotspot as this PC)"
echo "3. Paste this into Fast install:"
echo ""
echo "   $ROBOT"
echo ""
if command -v pbcopy >/dev/null 2>&1; then echo -n "$ROBOT" | pbcopy || true; fi
if command -v xclip >/dev/null 2>&1; then echo -n "$ROBOT" | xclip -selection clipboard || true; fi

cd "$DIR"
echo "Serving $OTA on port $PORT … Ctrl+C to stop."
if command -v python3 >/dev/null 2>&1; then
  exec python3 -m http.server "$PORT" --bind 0.0.0.0
fi
if command -v python >/dev/null 2>&1; then
  exec python -m SimpleHTTPServer "$PORT"
fi
echo "Need python3 to serve the file." >&2
exit 1
