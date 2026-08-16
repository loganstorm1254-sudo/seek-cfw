#!/bin/sh
# Unlock manual flash — Unlock's Python /anki/bin/update-engine is a stub
# (exits 0 and does nothing). This decrypts Seek ankidev OTA and writes slots.
#
# DANGER: stay on charger. Wrong flash can brick. Uses existing /ota/v.ota.
#
#   sh unlock-manual-flash.sh
#   sh unlock-manual-flash.sh /ota/v.ota
set -e
OTA="${1:-/ota/v.ota}"
WORK=/ota/seek-flash
PAS=/anki/etc/ota.pas
# Public ankidev passphrase used by Seek/Wire-style ankidev=1 OTAs (in repo as ota.pas).
ANKIDEV_B64='6YCZ5piv5LiA5YCL5a+G56K8'

mount -o remount,rw / 2>/dev/null || true
mkdir -p "$WORK" /run/update-engine /ota

if [ ! -f "$OTA" ]; then
  echo "Missing $OTA"
  exit 1
fi
SZ=$(stat -c %s "$OTA" 2>/dev/null || wc -c <"$OTA")
if [ "$SZ" -lt 8000000 ]; then
  echo "OTA too small ($SZ)"
  exit 1
fi

echo "OS now: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "OTA: $OTA ($SZ bytes)"

# Ensure ankidev passphrase exists for encrypted Seek OTAs
if [ ! -s "$PAS" ]; then
  echo "Creating $PAS (ankidev)"
  printf '%s' "$ANKIDEV_PAS" >"$PAS"
  chmod 644 "$PAS"
fi

BOOTCTL=""
for b in /bin/bootctl-anki /usr/bin/bootctl-anki /bin/bootctl; do
  if [ -x "$b" ]; then BOOTCTL="$b"; break; fi
done
if [ -z "$BOOTCTL" ]; then
  echo "FATAL: no bootctl-anki/bootctl"
  exit 1
fi
echo "bootctl: $BOOTCTL"

# Parse current slot from cmdline
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
echo "slot current=$CUR target=$TARGET"

BOOT_DEV="/dev/block/bootdevice/by-name/boot_${TARGET}"
SYS_DEV="/dev/block/bootdevice/by-name/system_${TARGET}"
if [ "$TARGET" = "a" ] && [ ! -e "$BOOT_DEV" ]; then
  BOOT_DEV="/dev/block/bootdevice/by-name/boot_a"
  SYS_DEV="/dev/block/bootdevice/by-name/system_a"
fi
if [ ! -e "$BOOT_DEV" ] || [ ! -e "$SYS_DEV" ]; then
  echo "FATAL: missing slot devices:"
  ls -la /dev/block/bootdevice/by-name/ 2>/dev/null || true
  exit 1
fi
echo "boot -> $BOOT_DEV"
echo "system -> $SYS_DEV"

echo "Extracting OTA (this needs free space on /ota)..."
rm -rf "$WORK"
mkdir -p "$WORK"
# BusyBox tar
tar -C "$WORK" -xf "$OTA"
ls -la "$WORK"

MAN="$WORK/manifest.ini"
if [ ! -f "$MAN" ]; then
  echo "FATAL: no manifest.ini in OTA"
  exit 1
fi
echo "---- manifest ----"
cat "$MAN"
echo "------------------"

BOOT_IMG="$WORK/apq8009-robot-boot.img.gz"
SYS_IMG="$WORK/apq8009-robot-sysfs.img.gz"
[ -f "$BOOT_IMG" ] || { echo "missing boot image"; exit 1; }
[ -f "$SYS_IMG" ] || { echo "missing system image"; exit 1; }

ENC=$(grep -A5 '^\[BOOT\]' "$MAN" | grep '^encryption=' | head -1 | cut -d= -f2)
COMP=$(grep -A5 '^\[BOOT\]' "$MAN" | grep '^compression=' | head -1 | cut -d= -f2)
BOOT_BYTES=$(grep -A5 '^\[BOOT\]' "$MAN" | grep '^bytes=' | head -1 | cut -d= -f2)
SYS_ENC=$(grep -A5 '^\[SYSTEM\]' "$MAN" | grep '^encryption=' | head -1 | cut -d= -f2)
SYS_COMP=$(grep -A5 '^\[SYSTEM\]' "$MAN" | grep '^compression=' | head -1 | cut -d= -f2)
SYS_BYTES=$(grep -A5 '^\[SYSTEM\]' "$MAN" | grep '^bytes=' | head -1 | cut -d= -f2)
echo "BOOT enc=$ENC comp=$COMP bytes=$BOOT_BYTES"
echo "SYSTEM enc=$SYS_ENC comp=$SYS_COMP bytes=$SYS_BYTES"

decode_pipe() {
  # $1=enc $2=comp  -> prints shell pipeline reading stdin
  enc="$1"; comp="$2"
  if [ "$enc" = "1" ]; then
    if [ "$comp" = "gz" ]; then
      echo "openssl enc -d -aes-256-ctr -md md5 -pass file:$PAS 2>/dev/null | gunzip"
    else
      echo "openssl enc -d -aes-256-ctr -md md5 -pass file:$PAS 2>/dev/null"
    fi
  else
    if [ "$comp" = "gz" ]; then
      echo "gunzip"
    else
      echo "cat"
    fi
  fi
}

systemctl stop anki-robot.target 2>/dev/null || true
killall -9 vic-engine vic-anim vic-cloud vic-robot python 2>/dev/null || true

echo "Marking slot $TARGET unbootable..."
"$BOOTCTL" "$CUR" set_unbootable "$TARGET" || true

BOOT_STAGE=/run/update-engine/boot.img
rm -f "$BOOT_STAGE"
PIPE=$(decode_pipe "$ENC" "$COMP")
echo "Decoding boot via: $PIPE"
# shellcheck disable=SC2086
eval "cat '$BOOT_IMG' | $PIPE > '$BOOT_STAGE'"
BST=$(stat -c %s "$BOOT_STAGE" 2>/dev/null || echo 0)
echo "boot staging size=$BST (expect ~$BOOT_BYTES)"
if [ "$BST" -lt 1000000 ]; then
  echo "FATAL: boot decode failed (is ota.pas wrong?)"
  exit 1
fi

echo "Writing boot to $BOOT_DEV ..."
dd if="$BOOT_STAGE" of="$BOOT_DEV" bs=1M conv=fsync
rm -f "$BOOT_STAGE"
sync

PIPE=$(decode_pipe "$SYS_ENC" "$SYS_COMP")
echo "Decoding+writing system via: $PIPE -> $SYS_DEV"
echo "(this takes several minutes)"
# Stream to block device; show dd progress if supported
# shellcheck disable=SC2086
eval "cat '$SYS_IMG' | $PIPE | dd of='$SYS_DEV' bs=1M status=progress conv=fsync" || \
  eval "cat '$SYS_IMG' | $PIPE | dd of='$SYS_DEV' bs=1M conv=fsync"
sync

echo "Setting active slot to $TARGET ..."
"$BOOTCTL" "$CUR" set_active "$TARGET"
sync

echo ""
echo "FLASH OK — rebooting into Seek. Keep charger connected."
sleep 2
reboot
