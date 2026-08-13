#!/bin/sh
# Fast Seek update: replace /usr/bin/wired + /etc/wired/webroot only.
# No full OTA, no reboot. Eyes stay on.
# usage: update-seek <url-to-seek-wired.tgz>
set -e

URL="${1:-}"
if [ -z "$URL" ] || [ "$URL" = "-h" ] || [ "$URL" = "--help" ]; then
    echo "usage: update-seek <url>"
    echo "example: update-seek https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.38d/seek-wired.tgz"
    exit 0
fi

TMP=/tmp/seek-wired-update
TGZ=/tmp/seek-wired.tgz
rm -rf "$TMP" "$TGZ"
mkdir -p "$TMP"

echo "Downloading Seek (wired only, not a full OS)..."
echo "$URL"
fetch_ok=0
if command -v curl >/dev/null 2>&1; then
    if curl -fL --progress-bar -o "$TGZ" "$URL"; then
        fetch_ok=1
    fi
fi
if [ "$fetch_ok" -eq 0 ] && command -v wget >/dev/null 2>&1; then
    if wget -O "$TGZ" "$URL"; then
        fetch_ok=1
    fi
fi
if [ "$fetch_ok" -eq 0 ]; then
    echo "Need curl or wget to download."
    exit 1
fi

echo "Unpacking..."
tar -C "$TMP" -xzf "$TGZ"
# tarball may be seek-wired/wired or just wired
BIN=""
ROOT=""
if [ -f "$TMP/seek-wired/wired" ]; then
    BIN="$TMP/seek-wired/wired"
    ROOT="$TMP/seek-wired/webroot"
elif [ -f "$TMP/wired" ]; then
    BIN="$TMP/wired"
    ROOT="$TMP/webroot"
else
    echo "Bad tarball: no wired binary"
    exit 1
fi
if [ ! -d "$ROOT" ]; then
    echo "Bad tarball: no webroot"
    exit 1
fi

echo "Restarting wired (dashboard)..."
systemctl stop wired || true
cp "$BIN" /usr/bin/wired
chmod 0755 /usr/bin/wired
rm -rf /etc/wired/webroot
cp -a "$ROOT" /etc/wired/webroot
install_helper() {
    dest="$1"
    shift
    for src in "$@"; do
        if [ -f "$src" ]; then
            cp "$src" "$dest"
            chmod 0755 "$dest"
            return 0
        fi
    done
    return 0
}
install_helper /usr/sbin/update-seek \
    "$TMP/seek-wired/update-seek" "$TMP/update-seek" \
    "$TMP/seek-wired/update-seek.sh" "$TMP/update-seek.sh"
install_helper /usr/sbin/update-os \
    "$TMP/seek-wired/update-os" "$TMP/update-os" \
    "$TMP/seek-wired/update-os.sh" "$TMP/update-os.sh"
sync
systemctl start wired
rm -rf "$TMP" "$TGZ"
echo "Seek updated. No reboot. Hard-refresh the dashboard."
