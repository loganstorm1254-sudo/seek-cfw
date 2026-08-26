#!/bin/sh
# SeekOS hotfix: DVT replicate OS look + suppress 898/899 (keep full motors).
set -e
cd "$(dirname "$0")"

mkdir -p /data/seek
rm -f /data/seek/head_only

install_bin() {
  dest="$1"
  src="$2"
  if [ ! -f "$dest" ]; then
    echo "missing $dest" >&2
    exit 1
  fi
  bak="${dest}.seekbak"
  if [ ! -f "$bak" ]; then
    cp -a "$dest" "$bak"
  fi
  cp "$src" "$dest"
  chown robot:anki "$dest" 2>/dev/null || true
  chmod 0755 "$dest"
}

mount -o remount,rw /anki 2>/dev/null || true
install_bin /anki/bin/vic-robot vic-robot
if [ -f vic-anim ]; then
  install_bin /anki/bin/vic-anim vic-anim
fi

mount -o remount,rw / 2>/dev/null || true
if [ -f /usr/bin/fault-code-handler ]; then
  if [ ! -f /usr/bin/fault-code-handler.seekbak ]; then
    cp -a /usr/bin/fault-code-handler /usr/bin/fault-code-handler.seekbak
  fi
  cp fault-code-handler /usr/bin/fault-code-handler
  chmod 0755 /usr/bin/fault-code-handler
fi
if [ -f /usr/bin/rampost ]; then
  if [ ! -f /usr/bin/rampost.seekbak ]; then
    cp -a /usr/bin/rampost /usr/bin/rampost.seekbak
  fi
  cp rampost /usr/bin/rampost
  chmod 0755 /usr/bin/rampost
fi

sync
systemctl daemon-reload 2>/dev/null || true
systemctl restart vic-robot
sleep 1
systemctl restart vic-engine 2>/dev/null || true
systemctl restart vic-anim 2>/dev/null || true
echo SEEK_HEADONLY_OK
