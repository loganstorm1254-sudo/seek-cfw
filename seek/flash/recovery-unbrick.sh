#!/bin/sh
# Unbrick Vector when both A/B slots are marked unbootable.
# Needs /data/bootctl-anki (patched, with set_bootable) uploaded from PC first.
set -e

mount -o remount,rw / 2>/dev/null || true

if [ ! -x /data/bootctl-anki ]; then
  echo "ERROR: upload bootctl first:"
  echo "  scp -O ... seek/flash/bin/bootctl-anki-arm root@IP:/data/bootctl-anki"
  echo "  ssh ... chmod 755 /data/bootctl-anki"
  exit 1
fi

BC=/data/run-bootctl.sh
cat >"$BC" <<'EOS'
#!/bin/sh
MNT=/data/sysb
BC=/data/bootctl-anki
mkdir -p "$MNT"
umount "$MNT" 2>/dev/null || true
mount -t ext4 -o ro /dev/block/bootdevice/by-name/system_b "$MNT" 2>/dev/null || true
LD="$MNT/lib/ld-linux.so.3"
LIBS="$MNT/usr/lib:$MNT/lib"
[ -f "$LD" ] || LD="$MNT/usr/lib/ld-linux.so.3"
LD_LIBRARY_PATH="$LIBS" "$LD" --library-path "$LIBS" "$BC" "$@"
EOS
chmod 755 "$BC"

echo "=== Unbrick both slots ==="
sh "$BC" f status a || true
echo "---"
sh "$BC" f status b || true
echo ""
echo "Clearing unbootable on A and B..."
sh "$BC" f set_bootable a || true
sh "$BC" f set_bootable b || true
echo ""
sh "$BC" f status a || true
echo "---"
sh "$BC" f status b || true
echo ""

PICK=b
STB=$(sh "$BC" f status b 2>/dev/null || true)
STA=$(sh "$BC" f status a 2>/dev/null || true)
echo "$STB" | grep -q 'successful: 1' && PICK=b
echo "$STA" | grep -q 'successful: 1' && PICK=a

echo "Removing /data/unbrick"
rm -f /data/unbrick
echo "Setting active slot $PICK"
sh "$BC" f set_active "$PICK"
sync
echo "Rebooting..."
sleep 2
reboot
