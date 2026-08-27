#!/bin/sh
# Crypto OS boot-only: purple CRYPTO OS splash (rampost + boot movie).
set -e
HOTFIX_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$HOTFIX_DIR"

remount_rw() {
  mount -o remount,rw / 2>/dev/null || true
  mount -o remount,rw /anki 2>/dev/null || true
}

remount_rw

if [ -f "$HOTFIX_DIR/rampost" ]; then
  cat "$HOTFIX_DIR/rampost" > /usr/bin/rampost.seeknew
  chmod 0755 /usr/bin/rampost.seeknew
  mv -f /usr/bin/rampost.seeknew /usr/bin/rampost
  echo "installed rampost"
fi

for name in boot_anim.raw boot_anim_20.raw; do
  src="$HOTFIX_DIR/$name"
  dest="/anki/data/assets/cozmo_resources/config/engine/animations/$name"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dest")" 2>/dev/null || true
    cat "$src" > "${dest}.seeknew"
    mv -f "${dest}.seeknew" "$dest"
    echo "installed $name"
  fi
done

sync
echo CRYPTO_BOOT_OK
echo "Reboot to see purple CRYPTO OS splash"
