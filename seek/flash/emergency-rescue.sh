#!/bin/sh
# Emergency recovery: run bootctl from mounted system image (needs /dev/block + libs).
set -e

MNT=/data/sysb
BC="$MNT/usr/bin/bootctl-anki"
LD="$MNT/lib/ld-linux.so.3"
LIBS="$MNT/usr/lib:$MNT/lib"

mount -o remount,rw / 2>/dev/null || true
mkdir -p "$MNT"
umount "$MNT" 2>/dev/null || true
mount -t ext4 -o ro /dev/block/bootdevice/by-name/system_b "$MNT"

if [ ! -f "$BC" ]; then
  umount "$MNT" 2>/dev/null || true
  mount -t ext4 -o ro /dev/block/bootdevice/by-name/system_a /data/sysa
  MNT=/data/sysa
  BC="$MNT/usr/bin/bootctl-anki"
  LD="$MNT/lib/ld-linux.so.3"
  LIBS="$MNT/usr/lib:$MNT/lib"
fi

[ -f "$BC" ] || { echo "FATAL: bootctl-anki missing"; exit 1; }
[ -f "$LD" ] || { echo "FATAL: ld-linux.so.3 missing"; exit 1; }

run_bc() {
  LD_LIBRARY_PATH="$LIBS" "$LD" --library-path "$LIBS" "$BC" "$@"
}

echo "=== Vector emergency rescue ==="
echo "cmdline: $(cat /proc/cmdline)"
echo ""
[ -f /data/ota/v.ota ] && echo "OTA bytes: $(wc -c </data/ota/v.ota)" || echo "OTA: missing"
echo ""

echo "Slot A:"
run_bc f status a || true
echo ""
echo "Slot B:"
run_bc f status b || true
echo ""

PICK=""
for s in a b; do
  ST=$(run_bc f status "$s" 2>/dev/null || true)
  echo "$ST" | grep -q 'bootable: 1' || continue
  if echo "$ST" | grep -q 'successful: 1'; then
    PICK="$s"
    break
  fi
  [ -z "$PICK" ] && PICK="$s"
done

if [ -z "$PICK" ]; then
  echo "WARNING: both slots show unbootable."
  echo "Will try slot B, then you may need a full re-flash."
  PICK=b
fi

echo "Removing /data/unbrick"
rm -f /data/unbrick
echo "Setting active slot: $PICK"
run_bc f set_active "$PICK"
sync
echo "Rebooting..."
sleep 2
reboot
