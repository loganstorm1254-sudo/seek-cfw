#!/bin/sh
# SeekOS hotfix: DVT replicate OS look + suppress 898/899 (keep full motors).
set -e
cd "$(dirname "$0")"

BACKUP_DIR=/data/seek/backups
mkdir -p /data/seek "$BACKUP_DIR"
rm -f /data/seek/head_only

remount_rw() {
  mount -o remount,rw / 2>/dev/null || true
  mount -o remount,rw /anki 2>/dev/null || true
}

backup_once() {
  name="$1"
  src="$2"
  bak="$BACKUP_DIR/$name"
  if [ ! -f "$bak" ] && [ -f "$src" ]; then
    cp -a "$src" "$bak"
  fi
}

install_bin() {
  dest="$1"
  src="$2"
  name="$(basename "$dest")"
  if [ ! -f "$dest" ]; then
    echo "missing $dest" >&2
    exit 1
  fi
  if [ ! -f "$src" ]; then
    echo "missing hotfix file $src" >&2
    exit 1
  fi
  backup_once "$name" "$dest"
  remount_rw
  if ! cp "$src" "$dest" 2>/dev/null; then
    remount_rw
    cp "$src" "$dest"
  fi
  chown robot:anki "$dest" 2>/dev/null || true
  chmod 0755 "$dest"
}

install_root_bin() {
  dest="$1"
  src="$2"
  name="$(basename "$dest")"
  backup_once "$name" "$dest"
  remount_rw
  cp "$src" "$dest"
  chmod 0755 "$dest"
}

remount_rw
install_bin /anki/bin/vic-robot vic-robot
if [ -f vic-anim ]; then
  install_bin /anki/bin/vic-anim vic-anim
fi

if [ -f /usr/bin/fault-code-handler ] && [ -f fault-code-handler ]; then
  install_root_bin /usr/bin/fault-code-handler fault-code-handler
fi
if [ -f /usr/bin/rampost ] && [ -f rampost ]; then
  install_root_bin /usr/bin/rampost rampost
fi

sync
systemctl daemon-reload 2>/dev/null || true
systemctl restart vic-robot
sleep 1
systemctl restart vic-engine 2>/dev/null || true
systemctl restart vic-anim 2>/dev/null || true
echo SEEK_HEADONLY_OK
