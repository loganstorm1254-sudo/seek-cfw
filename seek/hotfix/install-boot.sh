#!/bin/sh
# DVT boot: authentic Anki proprietary splash + clear WireOS persist override.
set -e
HOTFIX_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$HOTFIX_DIR"

SANTEK_FRAME=$((184 * 96 * 2))
MIDAS_FRAME=$((160 * 80 * 2))

log() { echo "seek-boot: $*"; }

remount_rw() {
  mount -o remount,rw / 2>/dev/null || true
  mount -o remount,rw /anki 2>/dev/null || true
  mount -o remount,rw /persist 2>/dev/null || true
}

install_file() {
  src="$1"
  dest="$2"
  [ -f "$src" ] || return 0
  mkdir -p "$(dirname "$dest")" 2>/dev/null || true
  cp -f "$src" "${dest}.cryptonew"
  chmod 0644 "${dest}.cryptonew" 2>/dev/null || true
  mv -f "${dest}.cryptonew" "$dest"
  log "installed $dest ($(wc -c < "$dest") bytes)"
}

remount_rw

if [ -f "$HOTFIX_DIR/rampost" ]; then
  remount_rw
  if [ -f /usr/bin/rampost ] || [ -L /usr/bin/rampost ]; then
    if cp -f "$HOTFIX_DIR/rampost" /usr/bin/rampost.cryptonew 2>/dev/null; then
      chmod 0755 /usr/bin/rampost.cryptonew
      mv -f /usr/bin/rampost.cryptonew /usr/bin/rampost
      log "installed /usr/bin/rampost"
    else
      log "WARN: could not replace /usr/bin/rampost"
    fi
  else
    if cp -f "$HOTFIX_DIR/rampost" /usr/bin/rampost 2>/dev/null; then
      chmod 0755 /usr/bin/rampost
      log "installed /usr/bin/rampost (new)"
    else
      log "WARN: no /usr/bin/rampost on rootfs (initramfs-only) — boot movie still applied"
    fi
  fi
fi

install_file "$HOTFIX_DIR/boot_anim.raw" \
  /anki/data/assets/cozmo_resources/config/engine/animations/boot_anim.raw
install_file "$HOTFIX_DIR/boot_anim_20.raw" \
  /anki/data/assets/cozmo_resources/config/engine/animations/boot_anim_20.raw

remount_rw
if [ -f /persist/boot_anim.raw ]; then
  old_sz=$(wc -c < /persist/boot_anim.raw)
  log "found WireOS override /persist/boot_anim.raw ($old_sz bytes)"
  rm -f /persist/boot_anim.raw 2>/dev/null || true
  if [ -f /persist/boot_anim.raw ]; then
    match=""
    if [ $((old_sz % MIDAS_FRAME)) -eq 0 ] && [ $((old_sz % SANTEK_FRAME)) -ne 0 ]; then
      match="$HOTFIX_DIR/boot_anim_20.raw"
    elif [ $((old_sz % SANTEK_FRAME)) -eq 0 ]; then
      match="$HOTFIX_DIR/boot_anim.raw"
    fi
    if [ -n "$match" ] && [ -f "$match" ]; then
      install_file "$match" /persist/boot_anim.raw
    else
      echo "ERROR: cannot clear WireOS boot override" >&2
      exit 1
    fi
  else
    log "removed WireOS /persist/boot_anim.raw"
  fi
else
  log "no /persist/boot_anim.raw (good)"
fi

sync
echo DVT_BOOT_OK
