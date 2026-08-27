#!/bin/sh
set -e

SLOT_SUFFIX=`tr ' ' '\n' < /proc/cmdline | awk -F= /androidboot.slot_suffix/'{print $2}' | xargs`

case "$SLOT_SUFFIX" in
  '_a')
    THIS_SLOT='a'
    OTHER_SLOT='b'
    ;;
  '_b')
    THIS_SLOT='b'
    OTHER_SLOT='a'
    ;;
  *)
    THIS_SLOT='f'
    OTHER_SLOT=''
    ;;
esac

bootctl-anki $THIS_SLOT mark_successful
setprop ro.boot.successful 1

# Seek CFW: lock the other A/B slot so the bootloader cannot fall back to
# WireOS, stock Anki, or any other image left in the inactive slot.
if [ -n "$OTHER_SLOT" ]; then
  LOCK_OTHER=0
  CFW_NAME=`getprop ro.build.os.cfw.name 2>/dev/null`
  case "$CFW_NAME" in
    seek_*|Seek*) LOCK_OTHER=1 ;;
  esac
  if [ "$LOCK_OTHER" != "1" ] && [ -f /data/seek/slot_lock ]; then
    LOCK_OTHER=1
  fi
  if [ "$LOCK_OTHER" = "1" ]; then
    bootctl-anki "$THIS_SLOT" set_unbootable "$OTHER_SLOT" 2>/dev/null || true
    setprop seek.slot.other_locked 1
  fi
fi

dmesg > /data/boot.log
