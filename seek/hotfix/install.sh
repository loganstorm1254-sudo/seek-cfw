#!/bin/sh
# Crypto OS hotfix: WireOS look + Crypto branding + 898/899 skip (full motors).
set -e
HOTFIX_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$HOTFIX_DIR"

BACKUP_DIR=/data/seek/backups
mkdir -p /data/seek "$BACKUP_DIR"
rm -f /data/seek/head_only

remount_rw() {
  mount -o remount,rw / 2>/dev/null || true
  mount -o remount,rw /anki 2>/dev/null || true
  mount -o remount,rw /persist 2>/dev/null || true
}

same_file() {
  a="$1"
  b="$2"
  [ -f "$a" ] && [ -f "$b" ] || return 1
  [ "$(stat -c '%d:%i' "$a" 2>/dev/null)" = "$(stat -c '%d:%i' "$b" 2>/dev/null)" ]
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
  name="$(basename "$dest")"
  src="$HOTFIX_DIR/$name"
  if [ ! -f "$dest" ]; then
    echo "missing $dest" >&2
    exit 1
  fi
  if [ ! -f "$src" ]; then
    echo "missing hotfix file $src" >&2
    exit 1
  fi
  if same_file "$src" "$dest"; then
    echo "skip $name (already installed)"
    return 0
  fi
  backup_once "$name" "$dest"
  remount_rw
  tmp="${dest}.seeknew"
  cat "$src" > "$tmp"
  chmod 0755 "$tmp"
  chown robot:anki "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$dest"
}

install_root_bin() {
  dest="$1"
  name="$(basename "$dest")"
  src="$HOTFIX_DIR/$name"
  if [ ! -f "$src" ]; then
    return 0
  fi
  if same_file "$src" "$dest"; then
    echo "skip $name (already installed)"
    return 0
  fi
  backup_once "$name" "$dest"
  remount_rw
  tmp="${dest}.seeknew"
  cat "$src" > "$tmp"
  chmod 0755 "$tmp"
  mv -f "$tmp" "$dest"
}

install_lights() {
  src="$HOTFIX_DIR/backpackLightsWireOS"
  dest="/anki/data/assets/cozmo_resources/config/engine/lights/backpackLightsWireOS"
  if [ ! -d "$src" ]; then
    return 0
  fi
  remount_rw
  mkdir -p "$dest"
  cp -a "$src/." "$dest/"
  echo "installed WireOS backpack lights"
}

install_boot_anim() {
  # bootAnim prefers /persist/boot_anim.raw over stock paths. WireOS leaves that
  # file; always writing 184x96 there breaks 160x80 displays. Clear the override
  # so LCD-correct stock paths (boot_anim.raw / boot_anim_20.raw) are used.
  SANTEK_FRAME=$((184 * 96 * 2))
  MIDAS_FRAME=$((160 * 80 * 2))
  remount_rw
  for name in boot_anim.raw boot_anim_20.raw; do
    src="$HOTFIX_DIR/$name"
    dest="/anki/data/assets/cozmo_resources/config/engine/animations/$name"
    if [ ! -f "$src" ]; then
      continue
    fi
    mkdir -p "$(dirname "$dest")" 2>/dev/null || true
    cat "$src" > "${dest}.seeknew"
    mv -f "${dest}.seeknew" "$dest"
    echo "installed $name ($(wc -c < "$dest") bytes)"
  done
  if [ -f /persist/boot_anim.raw ]; then
    old_sz=$(wc -c < /persist/boot_anim.raw)
    echo "found WireOS override /persist/boot_anim.raw ($old_sz bytes) — removing"
    rm -f /persist/boot_anim.raw 2>/dev/null || true
    if [ -f /persist/boot_anim.raw ]; then
      echo "WARN: delete failed — overwriting with size-matched Crypto anim"
      src=""
      if [ $((old_sz % MIDAS_FRAME)) -eq 0 ] && [ $((old_sz % SANTEK_FRAME)) -ne 0 ]; then
        src="$HOTFIX_DIR/boot_anim_20.raw"
      elif [ $((old_sz % SANTEK_FRAME)) -eq 0 ]; then
        src="$HOTFIX_DIR/boot_anim.raw"
      fi
      if [ -n "$src" ] && [ -f "$src" ]; then
        cat "$src" > /persist/boot_anim.raw.seeknew
        mv -f /persist/boot_anim.raw.seeknew /persist/boot_anim.raw
        echo "installed /persist/boot_anim.raw from $(basename "$src")"
      else
        echo "ERROR: could not clear WireOS /persist/boot_anim.raw" >&2
        exit 1
      fi
    else
      echo "removed WireOS /persist/boot_anim.raw"
    fi
  else
    echo "no /persist/boot_anim.raw (stock paths used)"
  fi
}

remount_rw
install_bin /anki/bin/vic-robot
if [ -f "$HOTFIX_DIR/vic-anim" ]; then
  install_bin /anki/bin/vic-anim
fi
install_root_bin /usr/bin/fault-code-handler
install_root_bin /usr/bin/rampost
install_lights
install_boot_anim

rm -f /data/data/enableankilights 2>/dev/null || true

sync
systemctl daemon-reload 2>/dev/null || true
systemctl restart vic-robot
sleep 1
systemctl restart vic-engine 2>/dev/null || true
systemctl restart vic-anim 2>/dev/null || true
echo CRYPTO_OS_OK
