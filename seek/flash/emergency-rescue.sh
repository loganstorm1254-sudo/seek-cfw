#!/bin/sh
# Emergency slot rescue from recovery SSH. Finds bootctl on a system slot image.
set -e

mount -o remount,rw / 2>/dev/null || true
mkdir -p /data/ota /data/seek /mnt/sysa /mnt/sysb
touch /data/unbrick
sync

find_bootctl() {
  for b in /bin/bootctl-anki /usr/bin/bootctl-anki /bin/bootctl; do
    [ -x "$b" ] && echo "$b" && return 0
  done
  for mnt in /mnt/sysa /mnt/sysb; do
    for b in "$mnt/usr/bin/bootctl-anki" "$mnt/bin/bootctl-anki"; do
      [ -x "$b" ] && echo "$b" && return 0
    done
  done
  return 1
}

mount_system_slots() {
  umount /mnt/sysa 2>/dev/null || true
  umount /mnt/sysb 2>/dev/null || true
  mount -t ext4 -o ro /dev/block/bootdevice/by-name/system_a /mnt/sysa 2>/dev/null || \
    mount -o ro /dev/block/bootdevice/by-name/system_a /mnt/sysa 2>/dev/null || true
  mount -t ext4 -o ro /dev/block/bootdevice/by-name/system_b /mnt/sysb 2>/dev/null || \
    mount -o ro /dev/block/bootdevice/by-name/system_b /mnt/sysb 2>/dev/null || true
}

echo "=== Seek emergency rescue ==="
echo "cmdline: $(cat /proc/cmdline)"
echo ""
echo "Files:"
ls -la /data/ota/v.ota /data/unbrick /data/unlock-manual-flash-v2.sh 2>/dev/null || true
[ -f /data/ota/v.ota ] && echo "OTA bytes: $(wc -c </data/ota/v.ota)" || echo "OTA: missing"
echo ""

mount_system_slots
BOOTCTL="$(find_bootctl || true)"
if [ -z "$BOOTCTL" ]; then
  echo "ERROR: bootctl-anki not found even after mounting system_a/system_b."
  echo "Try normal reboot (keeps recovery if boot fails):"
  echo "  rm -f /data/unbrick; reboot"
  exit 1
fi
echo "bootctl: $BOOTCTL"
echo ""

echo "Slot A:"
"$BOOTCTL" f status a || true
echo ""
echo "Slot B:"
"$BOOTCTL" f status b || true
echo ""

PICK=""
for s in a b; do
  ST=$("$BOOTCTL" f status "$s" 2>/dev/null || true)
  echo "$ST" | grep -q 'bootable: 1' || continue
  if echo "$ST" | grep -q 'successful: 1'; then
    PICK="$s"
    break
  fi
  [ -z "$PICK" ] && PICK="$s"
done

if [ -z "$PICK" ]; then
  echo "Both slots look unbootable. Trying slot B..."
  PICK=b
fi

echo "Setting active slot: $PICK"
"$BOOTCTL" f set_active "$PICK"
sync

echo ""
echo "Rebooting to slot $PICK (recovery flag kept at /data/unbrick)..."
sleep 2
reboot
