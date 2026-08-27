#!/bin/sh
# Unlock manual flash — BusyBox-safe for Vector (no GNU head/dd extras).
# Stay on charger.
#
#   sh unlock-manual-flash-v2.sh /data/ota/v.ota
set -e
OTA="${1:-/data/ota/v.ota}"
PAS=/anki/etc/ota.pas
ANKIDEV_B64='6YCZ5piv5LiA5YCL5a+G56K8'
TMP=/data/seek-flash

mount -o remount,rw / 2>/dev/null || true
mkdir -p "$TMP" /run/update-engine /data/ota

if [ ! -f "$OTA" ]; then
  echo "Missing $OTA"
  exit 1
fi

SZ=$(wc -c <"$OTA")
echo "OS now: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "OTA: $OTA ($SZ bytes)"
echo "temp: $TMP"
df -h /data /cache 2>/dev/null || true

# Reject truncated/corrupt OTA (full release is ~204MB).
MIN_OTA=200000000
if [ "$SZ" -lt "$MIN_OTA" ]; then
  echo "FATAL: OTA too small ($SZ bytes). Need complete ~204MB file."
  echo "Re-upload with recovery-chunk-upload.ps1 before flashing."
  exit 1
fi

if [ ! -s "$PAS" ]; then
  echo "Creating $PAS (ankidev)"
  echo "$ANKIDEV_B64" | base64 -d >"$PAS"
  chmod 644 "$PAS"
fi

BOOTCTL=""
for b in /bin/bootctl-anki /usr/bin/bootctl-anki /bin/bootctl; do
  if [ -x "$b" ]; then BOOTCTL="$b"; break; fi
done
if [ -z "$BOOTCTL" ]; then
  mkdir -p /mnt/sysa /mnt/sysb
  mount -t ext4 -o ro /dev/block/bootdevice/by-name/system_a /mnt/sysa 2>/dev/null || \
    mount -o ro /dev/block/bootdevice/by-name/system_a /mnt/sysa 2>/dev/null || true
  mount -t ext4 -o ro /dev/block/bootdevice/by-name/system_b /mnt/sysb 2>/dev/null || \
    mount -o ro /dev/block/bootdevice/by-name/system_b /mnt/sysb 2>/dev/null || true
  for b in /mnt/sysa/usr/bin/bootctl-anki /mnt/sysb/usr/bin/bootctl-anki \
           /mnt/sysa/bin/bootctl-anki /mnt/sysb/bin/bootctl-anki; do
    if [ -x "$b" ]; then BOOTCTL="$b"; break; fi
  done
fi
[ -n "$BOOTCTL" ] || { echo "FATAL: no bootctl"; exit 1; }

CMDLINE=$(cat /proc/cmdline)
SFX="_f"
for tok in $CMDLINE; do
  case "$tok" in
    androidboot.slot_suffix=*) SFX=${tok#androidboot.slot_suffix=} ;;
  esac
done
case "$SFX" in
  _a) CUR=a; TARGET=b ;;
  _b) CUR=b; TARGET=a ;;
  *) CUR=f; TARGET=a ;;
esac
echo "bootctl=$BOOTCTL slot current=$CUR target=$TARGET"

BOOT_DEV="/dev/block/bootdevice/by-name/boot_${TARGET}"
SYS_DEV="/dev/block/bootdevice/by-name/system_${TARGET}"
if [ ! -e "$BOOT_DEV" ]; then
  BOOT_DEV="/dev/block/bootdevice/by-name/boot_a"
  SYS_DEV="/dev/block/bootdevice/by-name/system_a"
fi
[ -e "$BOOT_DEV" ] && [ -e "$SYS_DEV" ] || {
  echo "FATAL: missing slot devices"
  ls -la /dev/block/bootdevice/by-name/ 2>/dev/null || true
  exit 1
}
echo "boot -> $BOOT_DEV"
echo "system -> $SYS_DEV"

echo "Reading manifest..."
MAN="$TMP/manifest.ini"
rm -f "$MAN"
tar -xOf "$OTA" manifest.ini >"$MAN"
[ -s "$MAN" ] || { echo "FATAL: could not read manifest.ini"; exit 1; }
cat "$MAN"

# Parse without head (BusyBox head is broken/limited on some builds)
ini_get() {
  section="$1"
  key="$2"
  awk -F= -v sec="$section" -v key="$key" '
    $0 == "[" sec "]" { insec=1; next }
    /^\[/ { insec=0 }
    insec && $1 == key { print $2; exit }
  ' "$MAN"
}

ENC=$(ini_get BOOT encryption)
COMP=$(ini_get BOOT compression)
BOOT_BYTES=$(ini_get BOOT bytes)
SYS_ENC=$(ini_get SYSTEM encryption)
SYS_COMP=$(ini_get SYSTEM compression)
SYS_BYTES=$(ini_get SYSTEM bytes)

echo "BOOT enc=$ENC comp=$COMP bytes=$BOOT_BYTES"
echo "SYSTEM enc=$SYS_ENC comp=$SYS_COMP bytes=$SYS_BYTES"

[ "$ENC" = "1" ] || [ "$ENC" = "0" ] || { echo "FATAL: bad BOOT encryption='$ENC'"; exit 1; }
[ -n "$COMP" ] && [ -n "$BOOT_BYTES" ] || { echo "FATAL: bad BOOT parse"; exit 1; }
[ -n "$SYS_ENC" ] && [ -n "$SYS_COMP" ] && [ -n "$SYS_BYTES" ] || { echo "FATAL: bad SYSTEM parse"; exit 1; }

decode_pipe() {
  enc="$1"; comp="$2"
  if [ "$enc" = "1" ] && [ "$comp" = "gz" ]; then
    openssl enc -d -aes-256-ctr -md md5 -pass "file:$PAS" 2>/dev/null | gunzip
  elif [ "$enc" = "1" ]; then
    openssl enc -d -aes-256-ctr -md md5 -pass "file:$PAS" 2>/dev/null
  elif [ "$comp" = "gz" ]; then
    gunzip
  else
    cat
  fi
}

systemctl stop anki-robot.target 2>/dev/null || true
killall -9 vic-engine vic-anim vic-cloud vic-robot 2>/dev/null || true

echo "Marking slot $TARGET unbootable..."
"$BOOTCTL" "$CUR" set_unbootable "$TARGET" 2>/dev/null || true

BOOT_STAGE="$TMP/boot.img"
rm -f "$BOOT_STAGE"
echo "Streaming boot decode..."
tar -xOf "$OTA" apq8009-robot-boot.img.gz | decode_pipe "$ENC" "$COMP" >"$BOOT_STAGE"
BST=$(wc -c <"$BOOT_STAGE")
echo "boot staging size=$BST (expect ~$BOOT_BYTES)"
if [ "$BST" -lt 1000000 ]; then
  echo "FATAL: boot decode failed (check openssl + ota.pas)"
  ls -la "$PAS"
  od -Ax -tx1 "$PAS" | sed -n '1,2p'
  exit 1
fi

echo "Writing boot (${BST} bytes)..."
# Numeric bs only — BusyBox often rejects 1M / conv=
dd if="$BOOT_STAGE" of="$BOOT_DEV" bs=1048576
sync
rm -f "$BOOT_STAGE"

echo "Streaming system decode+write (several minutes)..."
tar -xOf "$OTA" apq8009-robot-sysfs.img.gz | decode_pipe "$SYS_ENC" "$SYS_COMP" | dd of="$SYS_DEV" bs=1048576
sync

echo "Setting active slot $TARGET ..."
"$BOOTCTL" "$CUR" set_active "$TARGET"

# Lock the OTHER slot only. When booting recovery (CUR=f), f aliases to slot a —
# locking CUR would mark the slot we just flashed unbootable and brick reboot.
if [ "$CUR" = "f" ]; then
  case "$TARGET" in
    a) LOCK=b ;;
    b) LOCK=a ;;
    *) LOCK=b ;;
  esac
else
  LOCK="$CUR"
fi
echo "Locking fallback slot $LOCK (not the flashed slot $TARGET)..."
"$BOOTCTL" "$CUR" set_unbootable "$LOCK" 2>/dev/null || true
mkdir -p /data/seek
touch /data/seek/slot_lock
sync
rm -rf "$TMP"

echo ""
echo "FLASH OK — rebooting. Keep charger connected."
sleep 2
reboot
