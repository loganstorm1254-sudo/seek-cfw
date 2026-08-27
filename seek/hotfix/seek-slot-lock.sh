#!/bin/sh
# Lock the inactive A/B slot so Vector cannot boot WireOS/stock from the other slot.
# Safe to run any time while booted on Seek. Persists via /data/seek/slot_lock marker
# and boot-successful on future OTAs that include the Seek overlay.
set -e

BOOTCTL=""
for b in /bin/bootctl-anki /usr/bin/bootctl-anki; do
  if [ -x "$b" ]; then
    BOOTCTL="$b"
    break
  fi
done
if [ -z "$BOOTCTL" ]; then
  echo "ERROR: bootctl-anki not found" >&2
  exit 1
fi

SFX="_f"
for tok in $(cat /proc/cmdline); do
  case "$tok" in
    androidboot.slot_suffix=*) SFX=${tok#androidboot.slot_suffix=} ;;
  esac
done

case "$SFX" in
  _a) CUR=a; OTHER=b ;;
  _b) CUR=b; OTHER=a ;;
  *)
    echo "ERROR: not on A/B slot (suffix=$SFX)" >&2
    exit 1
    ;;
esac

mkdir -p /data/seek
touch /data/seek/slot_lock

echo "Seek slot lock: current=$CUR inactive=$OTHER"
echo "Marking slot $OTHER unbootable (WireOS/stock cannot boot from it)..."
"$BOOTCTL" "$CUR" set_unbootable "$OTHER"
"$BOOTCTL" "$CUR" mark_successful 2>/dev/null || true
sync
echo "SEEK_SLOT_LOCK_OK cur=$CUR other=$OTHER"
