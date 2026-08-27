#!/bin/sh
# Flash a Seek OTA to the CURRENT A/B slot (no slot flip).
# Usage: flash-ota-current-slot.sh <ota-file-or-url>
set -e

OTA="${1:?usage: flash-ota-current-slot.sh <ota-file-or-url>}"
PAS=/anki/etc/ota.pas
ANKIDEV_B64='6YCZ5piv5LiA5YCL5a+G56K8'
TMP=/data/seek-flash
OTAFILE="$OTA"

mount -o remount,rw / 2>/dev/null || true
mkdir -p "$TMP" /data/ota

BOOTCTL=""
for b in /bin/bootctl-anki /usr/bin/bootctl-anki /bin/bootctl; do
  [ -x "$b" ] && BOOTCTL="$b" && break
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
  _a) CUR=a ;;
  _b) CUR=b ;;
  *)  CUR=a ;;
esac

BOOT_DEV="/dev/block/bootdevice/by-name/boot_${CUR}"
SYS_DEV="/dev/block/bootdevice/by-name/system_${CUR}"
[ -e "$BOOT_DEV" ] && [ -e "$SYS_DEV" ] || {
  echo "FATAL: missing $BOOT_DEV or $SYS_DEV"
  exit 1
}

echo "Seek current-slot flash: keeping slot $CUR"
echo "boot -> $BOOT_DEV"
echo "system -> $SYS_DEV"
echo "OS now: $(getprop ro.anki.version 2>/dev/null || echo unknown)"

case "$OTA" in
  http://*|https://*)
    echo "Downloading OTA..."
    CURL=""
    for c in /usr/bin/curl.anki /usr/bin/curl; do
      [ -x "$c" ] && CURL="$c" && break
    done
    [ -n "$CURL" ] || { echo "FATAL: no curl"; exit 1; }
    OTAFILE=/data/ota/v.ota
    "$CURL" -k -L --http1.1 -4 --fail -o "$OTAFILE" "$OTA"
    ;;
esac

[ -f "$OTAFILE" ] || { echo "FATAL: missing $OTAFILE"; exit 1; }

if [ ! -s "$PAS" ]; then
  echo "Creating $PAS (ankidev)"
  echo "$ANKIDEV_B64" | base64 -d >"$PAS"
  chmod 644 "$PAS"
fi

ini_get() {
  awk -F= -v sec="$1" -v key="$2" '
    $0 == "[" sec "]" { insec=1; next }
    /^\[/ { insec=0 }
    insec && $1 == key { print $2; exit }
  ' "$MAN"
}

MAN="$TMP/manifest.ini"
tar -xOf "$OTAFILE" manifest.ini >"$MAN"
[ -s "$MAN" ] || { echo "FATAL: no manifest.ini"; exit 1; }

ENC=$(ini_get BOOT encryption)
COMP=$(ini_get BOOT compression)
BOOT_BYTES=$(ini_get BOOT bytes)
SYS_ENC=$(ini_get SYSTEM encryption)
SYS_COMP=$(ini_get SYSTEM compression)
SYS_BYTES=$(ini_get SYSTEM bytes)

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

BOOT_STAGE="$TMP/boot.img"
rm -f "$BOOT_STAGE"
echo "Streaming boot decode..."
tar -xOf "$OTAFILE" apq8009-robot-boot.img.gz | decode_pipe "$ENC" "$COMP" >"$BOOT_STAGE"
BST=$(wc -c <"$BOOT_STAGE")
echo "boot staging size=$BST (expect ~$BOOT_BYTES)"
[ "$BST" -ge 1000000 ] || { echo "FATAL: boot decode failed"; exit 1; }

echo "Writing boot..."
dd if="$BOOT_STAGE" of="$BOOT_DEV" bs=1048576
sync
rm -f "$BOOT_STAGE"

echo "Streaming system decode+write (several minutes)..."
tar -xOf "$OTAFILE" apq8009-robot-sysfs.img.gz | decode_pipe "$SYS_ENC" "$SYS_COMP" | dd of="$SYS_DEV" bs=1048576
sync

echo "Keeping active slot $CUR"
"$BOOTCTL" "$CUR" set_active "$CUR"
"$BOOTCTL" "$CUR" mark_successful
sync
rm -rf "$TMP"

echo "FLASH OK (current slot $CUR) — rebooting."
sleep 2
reboot
