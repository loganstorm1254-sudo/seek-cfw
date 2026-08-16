#!/bin/sh
# Unlock-friendly OTA flash.
# Unlock ships a Python update-engine that:
#   - fails on file:// (exit 203)
#   - often fails if you pass -v on the CLI
#   - appends ?device=… query params (busybox httpd can 404 those)
# So: serve /ota/v.ota with a query-tolerant server, invoke via ENV URL.
#
#   sh unlock-ota.sh
#   sh unlock-ota.sh http://files.anki.org.uk/ota/latest
#   sh unlock-ota.sh flash-only
set -e
URL="${1:-http://files.anki.org.uk/ota/latest}"
PORT=8765
unset SSL_CERT_FILE CURL_CA_BUNDLE 2>/dev/null || true
export SSL_CERT_FILE=
export CURL_CA_BUNDLE=

mount -o remount,rw / 2>/dev/null || true
mkdir -p /ota /cache /run/update-engine /run/vic-switchboard

if [ ! -x /usr/bin/curl.anki ]; then
  cp -L /usr/bin/curl /usr/bin/curl.anki 2>/dev/null || cp /usr/bin/curl /usr/bin/curl.anki
  chmod 755 /usr/bin/curl.anki
fi
CURL=/usr/bin/curl.anki

ENGINE=/anki/bin/update-engine
if [ ! -x "$ENGINE" ]; then
  echo "FATAL: no $ENGINE"
  exit 1
fi

echo "OS: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "Engine: $ENGINE"
head -n 2 "$ENGINE" 2>/dev/null || true

SZ=0
[ -f /ota/v.ota ] && SZ=`stat -c %s /ota/v.ota 2>/dev/null || echo 0`

if [ "$URL" = "flash-only" ]; then
  if [ "$SZ" -lt 8000000 ]; then
    echo "No usable /ota/v.ota ($SZ)."
    exit 1
  fi
  echo "Using existing /ota/v.ota ($SZ bytes)"
else
  if [ "$SZ" -ge 200000000 ]; then
    echo "Keeping existing /ota/v.ota ($SZ bytes)"
  else
    echo "Downloading $URL → /ota/v.ota ..."
    rm -f /ota/v.ota
    $CURL -k -L --http1.1 -4 --fail -C - -o /ota/v.ota "$URL"
    SZ=`stat -c %s /ota/v.ota 2>/dev/null || echo 0`
    echo "Downloaded $SZ bytes"
  fi
fi
if [ "$SZ" -lt 8000000 ]; then
  echo "OTA too small"
  exit 1
fi

# Tiny Python HTTP server that IGNORES query strings (Unlock update-engine appends them).
cat > /run/update-engine/serve_ota.py << 'PY'
import sys
try:
    from BaseHTTPServer import HTTPServer, BaseHTTPRequestHandler
except ImportError:
    from http.server import HTTPServer, BaseHTTPRequestHandler
PORT = int(sys.argv[1])
PATH = sys.argv[2]
class H(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_head()
    def do_GET(self):
        f = self.send_head()
        if f:
            try:
                self.copyfile(f, self.wfile)
            finally:
                f.close()
    def send_head(self):
        import os, cgi
        # ignore ?query
        path = self.path.split("?", 1)[0]
        if path not in ("/", "/v.ota", "/latest.ota", "/ota/latest"):
            self.send_error(404)
            return None
        length = os.path.getsize(PATH)
        rng = self.headers.get("Range") or self.headers.get("range")
        start, end = 0, length - 1
        code = 200
        if rng and rng.startswith("bytes="):
            spec = rng[6:].split("-", 1)
            if spec[0]:
                start = int(spec[0])
            if len(spec) > 1 and spec[1]:
                end = int(spec[1])
            if end >= length:
                end = length - 1
            code = 206
        self.send_response(code)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if code == 206:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, length))
        self.end_headers()
        f = open(PATH, "rb")
        f.seek(start)
        # wrap to only send `end-start+1` bytes
        class Limited(object):
            def __init__(self, fp, n):
                self.fp, self.left = fp, n
            def read(self, amt=None):
                if self.left <= 0:
                    return b""
                if amt is None or amt > self.left:
                    amt = self.left
                data = self.fp.read(amt)
                self.left -= len(data)
                return data
            def close(self):
                self.fp.close()
        return Limited(f, end - start + 1)
    def copyfile(self, source, outputfile):
        while True:
            buf = source.read(64 * 1024)
            if not buf:
                break
            outputfile.write(buf)
    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))
HTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY

killall httpd python python3 2>/dev/null || true
sleep 0.5

PYBIN=""
for p in python python3; do
  if command -v "$p" >/dev/null 2>&1; then
    PYBIN="$p"
    break
  fi
done
if [ -z "$PYBIN" ]; then
  echo "No python on robot — cannot serve OTA for Unlock engine."
  exit 1
fi

echo "Starting query-tolerant HTTP on 127.0.0.1:$PORT via $PYBIN ..."
$PYBIN /run/update-engine/serve_ota.py "$PORT" /ota/v.ota >/run/update-engine/httpd.log 2>&1 &
HTTPD_PID=$!
echo "$HTTPD_PID" >/run/update-engine/httpd.pid
sleep 1

LOCAL="http://127.0.0.1:${PORT}/v.ota"
CODE=`$CURL -s -o /dev/null -w '%{http_code}' --http1.1 -4 --max-time 10 -r 0-1023 "$LOCAL?test=1" 2>/dev/null || echo 000`
echo "local probe (with query)=$CODE"
if [ "$CODE" != "200" ] && [ "$CODE" != "206" ]; then
  echo "Local serve failed. Log:"
  cat /run/update-engine/httpd.log 2>/dev/null || true
  kill "$HTTPD_PID" 2>/dev/null || true
  exit 1
fi

export UPDATE_ENGINE_ENABLED=True
export UPDATE_ENGINE_ALLOW_DOWNGRADE=True
export UPDATE_ENGINE_DEBUG=true
export UPDATE_ENGINE_URL="$LOCAL"
{
  echo UPDATE_ENGINE_ENABLED=True
  echo UPDATE_ENGINE_ALLOW_DOWNGRADE=True
  echo UPDATE_ENGINE_DEBUG=true
  echo UPDATE_ENGINE_MAX_SLEEP=1
  printf 'UPDATE_ENGINE_URL=%s\n' "$LOCAL"
} >/run/vic-switchboard/update-engine.env 2>/dev/null || true

echo "Flashing via ENV URL (no -v) — Unlock Python engine..."
systemctl stop anki-robot.target 2>/dev/null || true
set +e
# Critical: do NOT pass -v or URL on argv for Unlock Python engine.
"$ENGINE"
EC=$?
set -e
echo "flash exit=$EC"

kill "$HTTPD_PID" 2>/dev/null || true
killall httpd python python3 2>/dev/null || true

if [ "$EC" = 0 ]; then
  echo "Rebooting..."
  sync
  reboot
else
  echo "Flash failed (exit $EC)."
  cat /run/update-engine/error 2>/dev/null || true
  echo ""
  echo "Fallback: on your Windows PC run fast-ota.ps1, then on robot:"
  echo "  UPDATE_ENGINE_DEBUG=true UPDATE_ENGINE_ALLOW_DOWNGRADE=True UPDATE_ENGINE_ENABLED=True UPDATE_ENGINE_URL=http://PC_LAN_IP:8765/latest.ota /anki/bin/update-engine"
  systemctl start anki-robot.target 2>/dev/null || true
  exit "$EC"
fi
