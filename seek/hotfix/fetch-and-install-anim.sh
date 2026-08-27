#!/bin/sh
# Download seek-anim-menu.tgz and run install-anim.sh.
# Works on WireOS (no curl.anki yet) and Seek.
set -e

URL="${1:-https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/head-only-ignore-body-7a4a/seek/hotfix/seek-anim-menu.tgz}"
DEST=/data/seek-anim-menu.tgz

mount -o remount,rw / 2>/dev/null || true
mkdir -p /data/seek

# Find a real curl binary (not a broken wrapper script).
CURL=""
for c in /usr/bin/curl /bin/curl; do
  if [ -x "$c" ] && ! head -n 1 "$c" 2>/dev/null | grep -q '^#!'; then
    CURL="$c"
    break
  fi
done

if [ -z "$CURL" ]; then
  echo "ERROR: no curl binary on robot." >&2
  echo "Download on your PC, then pipe to Vector:" >&2
  echo "  type seek-anim-menu.tgz | ssh root@IP \"cat > /data/seek-anim-menu.tgz\"" >&2
  exit 1
fi

if [ ! -x /usr/bin/curl.anki ]; then
  cp -a "$CURL" /usr/bin/curl.anki
  chmod 755 /usr/bin/curl.anki
fi

echo "Fetching $URL ..."
/usr/bin/curl.anki -k -L --http1.1 -4 --connect-timeout 60 -o "$DEST" "$URL"
[ -s "$DEST" ] || { echo "ERROR: download failed (empty file)" >&2; exit 1; }

cd /data
tar xzf seek-anim-menu.tgz
sh install-anim.sh
