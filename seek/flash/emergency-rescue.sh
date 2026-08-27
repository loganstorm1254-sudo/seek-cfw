#!/bin/sh
# Emergency slot rescue from recovery SSH. Safe to run multiple times.
# Keeps /data/unbrick so Vector returns to recovery if boot fails.
set -e

BOOTCTL=""
for b in /bin/bootctl-anki /usr/bin/bootctl-anki /bin/bootctl; do
  [ -x "$b" ] && BOOTCTL="$b" && break
done
[ -n "$BOOTCTL" ] || { echo "FATAL: no bootctl"; exit 1; }

mount -o remount,rw / 2>/dev/null || true
mkdir -p /data/ota /data/seek
touch /data/unbrick
sync

echo "=== Seek emergency rescue ==="
echo "cmdline: $(cat /proc/cmdline)"
echo ""
echo "Slot A:"
"$BOOTCTL" f status a || true
echo ""
echo "Slot B:"
"$BOOTCTL" f status b || true
echo ""

# Pick a bootable slot; prefer one marked successful.
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
  echo "WARNING: both slots show unbootable."
  echo "Trying slot B then slot A anyway..."
  PICK=b
fi

echo "Setting active slot: $PICK"
"$BOOTCTL" f set_active "$PICK"
sync

echo ""
echo "Rescue done. Rebooting to slot $PICK ..."
echo "If boot fails, hold back button -> recovery, SSH again."
sleep 2
reboot
