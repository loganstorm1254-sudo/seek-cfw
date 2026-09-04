#!/bin/sh
# Quick vic-anim hotfix: double-click backpack opens CCIS menu again.
set -e
HOTFIX_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$HOTFIX_DIR"

BACKUP_DIR=/data/seek/backups
mkdir -p /data/seek "$BACKUP_DIR"

remount_rw() {
  mount -o remount,rw / 2>/dev/null || true
  mount -o remount,rw /anki 2>/dev/null || true
}

same_file() {
  a="$1"
  b="$2"
  [ -f "$a" ] && [ -f "$b" ] || return 1
  [ "$(stat -c '%d:%i' "$a" 2>/dev/null)" = "$(stat -c '%d:%i' "$b" 2>/dev/null)" ]
}

dest=/anki/bin/vic-anim
src="$HOTFIX_DIR/vic-anim"
bak="$BACKUP_DIR/vic-anim"

[ -f "$dest" ] || { echo "missing $dest" >&2; exit 1; }
[ -f "$src" ] || { echo "missing $src" >&2; exit 1; }

if same_file "$src" "$dest"; then
  echo "skip vic-anim (already installed)"
else
  if [ ! -f "$bak" ]; then
    cp -a "$dest" "$bak"
  fi
  remount_rw
  tmp="${dest}.seeknew"
  cat "$src" > "$tmp"
  chmod 0755 "$tmp"
  chown robot:anki "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$dest"
fi

sync
systemctl restart vic-anim 2>/dev/null || true

if [ -f "$HOTFIX_DIR/seek-slot-lock.sh" ]; then
  cp -f "$HOTFIX_DIR/seek-slot-lock.sh" /data/seek/seek-slot-lock.sh
  chmod 0755 /data/seek/seek-slot-lock.sh
  sh /data/seek/seek-slot-lock.sh || true
fi
echo SEEK_ANIM_MENU_OK
