#!/bin/sh
# DVT hotfix: Anki DVT look + green CCIS info + 898/899 skip (full motors).
set -e
HOTFIX_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$HOTFIX_DIR"

BACKUP_DIR=/data/seek/backups
mkdir -p /data/seek "$BACKUP_DIR"
rm -f /data/seek/head_only

log() { echo "seek: $*"; }

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
  path="$2"
  bak="$BACKUP_DIR/$name"
  if [ ! -f "$bak" ] && [ -f "$path" ]; then
    cp -a "$path" "$bak" 2>/dev/null || true
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
    log "skip $name (already installed)"
    return 0
  fi
  backup_once "$name" "$dest"
  remount_rw
  tmp="${dest}.seeknew"
  cp -f "$src" "$tmp"
  chmod 0755 "$tmp"
  chown robot:anki "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$dest"
  log "installed $dest"
}

install_root_bin_optional() {
  dest="$1"
  name="$(basename "$dest")"
  src="$HOTFIX_DIR/$name"
  if [ ! -f "$src" ]; then
    log "skip $name (not in hotfix)"
    return 0
  fi
  if same_file "$src" "$dest"; then
    log "skip $name (already installed)"
    return 0
  fi
  remount_rw
  backup_once "$name" "$dest"
  if [ -f "$dest" ] || [ -L "$dest" ]; then
    tmp="${dest}.seeknew"
    if cp -f "$src" "$tmp" 2>/dev/null; then
      chmod 0755 "$tmp"
      mv -f "$tmp" "$dest"
      log "installed $dest"
      return 0
    fi
  else
    if cp -f "$src" "$dest" 2>/dev/null; then
      chmod 0755 "$dest"
      log "installed $dest (new)"
      return 0
    fi
  fi
  log "WARN: could not install $name -> $dest (ok if initramfs-only)"
  return 0
}

install_lights() {
  src="$HOTFIX_DIR/backpackLightsAnki"
  dest="/anki/data/assets/cozmo_resources/config/engine/lights/backpackLightsAnki"
  if [ ! -d "$src" ]; then
    return 0
  fi
  remount_rw
  mkdir -p "$dest"
  cp -a "$src/." "$dest/"
  # Force Anki green lights path
  rm -f /data/data/enableankilights 2>/dev/null || true
  touch /data/data/enableankilights 2>/dev/null || true
  log "installed Anki green backpack lights"
}

install_boot_anim() {
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
    cp -f "$src" "${dest}.seeknew"
    mv -f "${dest}.seeknew" "$dest"
    log "installed $name ($(wc -c < "$dest") bytes)"
  done
  if [ -f /persist/boot_anim.raw ]; then
    old_sz=$(wc -c < /persist/boot_anim.raw)
    log "found WireOS override /persist/boot_anim.raw ($old_sz bytes) — removing"
    rm -f /persist/boot_anim.raw 2>/dev/null || true
    if [ -f /persist/boot_anim.raw ]; then
      match=""
      if [ $((old_sz % MIDAS_FRAME)) -eq 0 ] && [ $((old_sz % SANTEK_FRAME)) -ne 0 ]; then
        match="$HOTFIX_DIR/boot_anim_20.raw"
      elif [ $((old_sz % SANTEK_FRAME)) -eq 0 ]; then
        match="$HOTFIX_DIR/boot_anim.raw"
      fi
      if [ -n "$match" ] && [ -f "$match" ]; then
        cp -f "$match" /persist/boot_anim.raw.seeknew
        mv -f /persist/boot_anim.raw.seeknew /persist/boot_anim.raw
        log "overwrote /persist/boot_anim.raw with DVT anim"
      else
        echo "ERROR: could not clear WireOS /persist/boot_anim.raw" >&2
        exit 1
      fi
    else
      log "removed WireOS /persist/boot_anim.raw"
    fi
  else
    log "no /persist/boot_anim.raw (stock paths used)"
  fi
}

remount_rw
log "hotfix dir=$HOTFIX_DIR (DVT)"

install_boot_anim
install_lights

install_bin /anki/bin/vic-robot
if [ -f "$HOTFIX_DIR/vic-anim" ]; then
  install_bin /anki/bin/vic-anim
fi
install_root_bin_optional /usr/bin/fault-code-handler
install_root_bin_optional /usr/bin/rampost

sync
systemctl daemon-reload 2>/dev/null || true
systemctl restart vic-robot
sleep 1
systemctl restart vic-engine 2>/dev/null || true
systemctl restart vic-anim 2>/dev/null || true

if [ -f "$HOTFIX_DIR/seek-slot-lock.sh" ]; then
  cp -f "$HOTFIX_DIR/seek-slot-lock.sh" /data/seek/seek-slot-lock.sh
  chmod 0755 /data/seek/seek-slot-lock.sh
  sh /data/seek/seek-slot-lock.sh || true
fi
echo DVT_OK
log "reboot for DVT splash; double-click+lift → green info; backpack cycles screens"
