#!/bin/sh
# Unlock manual flash — stream from OTA (no full extract).
# BusyBox-safe (Vector / WireOS). Stay on charger.
#
#   sh unlock-manual-flash.sh
#   sh unlock-manual-flash.sh /data/ota/v.ota
set -e
OTA="${1:-/ota/v.ota}"
PAS=/anki/etc/ota.pas
ANKIDEV_B64='6YCZ5piv5LiA5YCL5a+G56K8'
TMP=/cache/seek-flash
# Prefer /cache for tiny temps; fall back to /data then /tmp
for d in /cache /data /tmp; do
  mkdir -p "$d" 2>/dev/null || continue
  touch "$d/.w" 2>/dev/null || continue
  rm -f "$d/.w"
  TMP="$d/seek-flash"
  break
done

mount -o remount,rw / 2>/dev/null || true
mkdir -p "$TMP" /run/update-engine
rm -rf /ota/seek-flash 2>/dev/null || true

if [ ! -f "$OTA" ]; then
  echo "Missing $OTA"
  exit 1
fi
SZ=$(stat -c %s "$OTA" 2>/dev/null || wc -c <"$OTA")
echo "OS now: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "OTA: $OTA ($SZ bytes)"
echo "temp: $TMP"
df -h /ota /cache /data 2>/dev/null || true

if [ ! -s "$PAS" ]; then
  echo "Creating $PAS (ankidev)"
  echo "$ANKIDEV_B64" | base64 -d >"$PAS"
  chmod 644 "$PAS"
fi

BOOTCTL=""
for b in /bin/bootctl-anki /usr/bin/bootctl-anki /bin/bootctl; do
  if [ -x "$b" ]; then BOOTCTL="$b"; break; fi
done
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

echo "Reading manifest (stream, no extract)..."
MAN="$TMP/manifest.ini"
rm -f "$MAN"
tar -xOf "$OTA" manifest.ini >"$MAN"
[ -s "$MAN" ] || { echo "FATAL: could not read manifest.ini"; exit 1; }
cat "$MAN"

# BusyBox: use head -n 1 (head -1 is invalid)
ENC=$(grep -A5 '^\[BOOT\]' "$MAN" | grep '^encryption=' | head -n 1 | cut -d= -f2)
COMP=$(grep -A5 '^\[BOOT\]' "$MAN" | grep '^compression=' | head -n 1 | cut -d= -f2)
BOOT_BYTES=$(grep -A5 '^\[BOOT\]' "$MAN" | grep '^bytes=' | head -n 1 | cut -d= -f2)
SYS_ENC=$(grep -A5 '^\[SYSTEM\]' "$MAN" | grep '^encryption=' | head -n 1 | cut -d= -f2)
SYS_COMP=$(grep -A5 '^\[SYSTEM\]' "$MAN" | grep '^compression=' | head -n 1 | cut -d= -f2)
SYS_BYTES=$(grep -A5 '^\[SYSTEM\]' "$MAN" | grep '^bytes=' | head -n 1 | cut -d= -f2)
echo "BOOT enc=$ENC comp=$COMP bytes=$BOOT_BYTES"
echo "SYSTEM enc=$SYS_ENC comp=$SYS_COMP bytes=$SYS_BYTES"

[ -n "$ENC" ] && [ -n "$COMP" ] && [ -n "$BOOT_BYTES" ] || {
  echo "FATAL: could not parse BOOT section from manifest"
  exit 1
}
[ -n "$SYS_ENC" ] && [ -n "$SYS_COMP" ] && [ -n "$SYS_BYTES" ] || {
  echo "FATAL: could not parse SYSTEM section from manifest"
  exit 1
}

decode_cmd() {
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
killall -9 vic-engine vic-anim vic-cloud vic-robot 2>/dev/null || true

echo "Marking slot $TARGET unbootable..."
"$BOOTCTL" "$CUR" set_unbootable "$TARGET" 2>/dev/null || true

BOOT_STAGE="$TMP/boot.img"
rm -f "$BOOT_STAGE"
PIPE=$(decode_cmd "$ENC" "$COMP")
echo "Streaming boot decode: tar | $PIPE"
# shellcheck disable=SC2086
eval "tar -xOf '$OTA' apq8009-robot-boot.img.gz | $PIPE > '$BOOT_STAGE'"
BST=$(stat -c %s "$BOOT_STAGE" 2>/dev/null || wc -c <"$BOOT_STAGE")
echo "boot staging size=$BST (expect ~$BOOT_BYTES)"
if [ "$BST" -lt 1000000 ]; then
  echo "FATAL: boot decode failed (check openssl + ota.pas)"
  ls -la "$PAS"; od -Ax -tx1 "$PAS" | head -n 2
  exit 1
fi

echo "Writing boot..."
# BusyBox dd often has no conv=fsync / status=progress
dd if="$BOOT_STAGE" of="$BOOT_DEV" bs=1M
sync
rm -f "$BOOT_STAGE"

PIPE=$(decode_cmd "$SYS_ENC" "$SYS_COMP")
echo "Streaming system decode+write (several minutes): tar | $PIPE | dd -> $SYS_DEV"
# shellcheck disable=SC2086
eval "tar -xOf '$OTA' apq8009-robot-sysfs.img.gz | $PIPE | dd of='$SYS_DEV' bs=1M"
sync

echo "Setting active slot $TARGET ..."
"$BOOTCTL" "$CUR" set_active "$TARGET"
sync
rm -rf "$TMP"

echo ""
echo "FLASH OK — rebooting. Keep charger connected."
sleep 2
reboot
