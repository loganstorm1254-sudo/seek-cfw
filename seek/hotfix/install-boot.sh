#!/bin/sh
# Crypto OS boot: Samsung-style CRYPTO OS splash.
#
# WireOS leaves /persist/boot_anim.raw which OVERRIDES stock paths in bootAnim.
# That file must be removed (or replaced with the correct LCD size). Always
# installing 184x96 into /persist breaks Vector 2.0 (160x80) and can leave
# WireOS branding if the write fails.
set -e
HOTFIX_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$HOTFIX_DIR"

SANTEK_FRAME=$((184 * 96 * 2))
MIDAS_FRAME=$((160 * 80 * 2))

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

pick_persist_src() {
  # Prefer matching whatever WireOS left in /persist (frame size → LCD family).
  if [ -f /persist/boot_anim.raw ]; then
    sz=$(wc -c < /persist/boot_anim.raw)
    if [ $((sz % MIDAS_FRAME)) -eq 0 ] && [ $((sz % SANTEK_FRAME)) -ne 0 ]; then
      if [ -f "$HOTFIX_DIR/boot_anim_20.raw" ]; then
        echo "$HOTFIX_DIR/boot_anim_20.raw"
        return 0
      fi
    fi
    if [ $((sz % SANTEK_FRAME)) -eq 0 ]; then
      if [ -f "$HOTFIX_DIR/boot_anim.raw" ]; then
        echo "$HOTFIX_DIR/boot_anim.raw"
        return 0
      fi
    fi
  fi
  # No reliable size — do not write persist; stock paths are LCD-correct.
  echo ""
}

remount_rw

# Early boot splash (before Linux)
if [ -f "$HOTFIX_DIR/rampost" ]; then
  cat "$HOTFIX_DIR/rampost" > /usr/bin/rampost.cryptonew
  chmod 0755 /usr/bin/rampost.cryptonew
  mv -f /usr/bin/rampost.cryptonew /usr/bin/rampost
  echo "installed /usr/bin/rampost ($(wc -c < /usr/bin/rampost) bytes)"
fi

# Linux boot movie — stock paths (bootAnim picks by LCD type)
install_file "$HOTFIX_DIR/boot_anim.raw" \
  /anki/data/assets/cozmo_resources/config/engine/animations/boot_anim.raw
install_file "$HOTFIX_DIR/boot_anim_20.raw" \
  /anki/data/assets/cozmo_resources/config/engine/animations/boot_anim_20.raw

# Kill WireOS override so stock (correctly sized) paths are used.
# If remove fails, overwrite with a size-matched Crypto anim.
remount_rw
if [ -f /persist/boot_anim.raw ]; then
  old_sz=$(wc -c < /persist/boot_anim.raw)
  echo "found WireOS override /persist/boot_anim.raw ($old_sz bytes)"
  src="$(pick_persist_src)"
  rm -f /persist/boot_anim.raw 2>/dev/null || true
  if [ -f /persist/boot_anim.raw ]; then
    echo "WARN: could not delete /persist/boot_anim.raw — trying overwrite"
    if [ -n "$src" ] && [ -f "$src" ]; then
      install_file "$src" /persist/boot_anim.raw
    else
      echo "ERROR: cannot clear WireOS boot override" >&2
      exit 1
    fi
  else
    echo "removed WireOS /persist/boot_anim.raw (stock paths will be used)"
  fi
else
  echo "no /persist/boot_anim.raw (good — stock paths used)"
fi

echo "--- boot sources after install ---"
ls -la /persist/boot_anim.raw 2>/dev/null || echo "no /persist/boot_anim.raw (OK)"
ls -la /anki/data/assets/cozmo_resources/config/engine/animations/boot_anim.raw 2>/dev/null || true
ls -la /anki/data/assets/cozmo_resources/config/engine/animations/boot_anim_20.raw 2>/dev/null || true
ls -la /usr/bin/rampost 2>/dev/null || true

sync
echo CRYPTO_BOOT_OK
echo "Reboot now — expect black screen + white CRYPTO OS (not WireOS)"
