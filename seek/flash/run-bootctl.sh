#!/bin/sh
# Run bootctl in recovery: prefer /data/bootctl-anki, else mounted system libs.
set -e

MNT=/data/sysb
BC=""
LD=""
LIBS=""

if [ -x /data/bootctl-anki ]; then
  BC=/data/bootctl-anki
  mkdir -p "$MNT"
  umount "$MNT" 2>/dev/null || true
  mount -t ext4 -o ro /dev/block/bootdevice/by-name/system_b "$MNT" 2>/dev/null || true
  LD="$MNT/lib/ld-linux.so.3"
  LIBS="$MNT/usr/lib:$MNT/lib"
  if [ ! -f "$LD" ]; then
    LD="$MNT/usr/lib/ld-linux.so.3"
  fi
else
  mkdir -p "$MNT"
  umount "$MNT" 2>/dev/null || true
  mount -t ext4 -o ro /dev/block/bootdevice/by-name/system_b "$MNT"
  BC="$MNT/usr/bin/bootctl-anki"
  LD="$MNT/lib/ld-linux.so.3"
  LIBS="$MNT/usr/lib:$MNT/lib"
  if [ ! -f "$LD" ]; then
    LD="$MNT/usr/lib/ld-linux.so.3"
  fi
fi

[ -f "$BC" ] || { echo "FATAL: bootctl not found"; exit 1; }
[ -f "$LD" ] || { echo "FATAL: dynamic linker not found"; exit 1; }

export LD_LIBRARY_PATH="$LIBS"
exec "$LD" --library-path "$LIBS" "$BC" "$@"
