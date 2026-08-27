#!/bin/sh
# Crypto OS boot: Samsung-style CRYPTO OS splash.
# WireOS uses /persist/boot_anim.raw which OVERRIDES the stock anim path —
# we must replace that or it keeps booting into WireOS branding.
set -e
HOTFIX_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$HOTFIX_DIR"

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
  cat "$src" > "${dest}.cryptonew"
  chmod 0644 "${dest}.cryptonew" 2>/dev/null || true
  mv -f "${dest}.cryptonew" "$dest"
  echo "installed $dest ($(wc -c < "$dest") bytes)"
}

remount_rw

# Early boot splash (before Linux)
if [ -f "$HOTFIX_DIR/rampost" ]; then
  cat "$HOTFIX_DIR/rampost" > /usr/bin/rampost.cryptonew
  chmod 0755 /usr/bin/rampost.cryptonew
  mv -f /usr/bin/rampost.cryptonew /usr/bin/rampost
  echo "installed /usr/bin/rampost"
fi

# Linux boot movie — stock paths
install_file "$HOTFIX_DIR/boot_anim.raw" \
  /anki/data/assets/cozmo_resources/config/engine/animations/boot_anim.raw
install_file "$HOTFIX_DIR/boot_anim_20.raw" \
  /anki/data/assets/cozmo_resources/config/engine/animations/boot_anim_20.raw

# WireOS override path (THIS is why it still said WireOS)
# Prefer 184x96; fall back to 160x80 if only that exists.
if [ -f "$HOTFIX_DIR/boot_anim.raw" ]; then
  install_file "$HOTFIX_DIR/boot_anim.raw" /persist/boot_anim.raw
elif [ -f "$HOTFIX_DIR/boot_anim_20.raw" ]; then
  install_file "$HOTFIX_DIR/boot_anim_20.raw" /persist/boot_anim.raw
fi

# Show what will play next boot
echo "--- boot sources ---"
ls -la /persist/boot_anim.raw 2>/dev/null || echo "no /persist/boot_anim.raw"
ls -la /anki/data/assets/cozmo_resources/config/engine/animations/boot_anim.raw 2>/dev/null || true
ls -la /usr/bin/rampost 2>/dev/null || true

sync
echo CRYPTO_BOOT_OK
echo "Reboot now to see CRYPTO OS (Samsung-style) boot"
