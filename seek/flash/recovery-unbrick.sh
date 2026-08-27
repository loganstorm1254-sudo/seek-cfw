#!/bin/sh
# Unbrick both slots using static /data/bootctl-anki (no libs needed).
set -e
[ -x /data/bootctl-anki ] || { echo "FATAL: /data/bootctl-anki missing"; exit 1; }
rm -f /data/ota/v.ota
rm -rf /data/ota/chunks
echo "slot A:"; /data/bootctl-anki f status a || true
echo "---"
echo "slot B:"; /data/bootctl-anki f status b || true
/data/bootctl-anki f set_bootable a
/data/bootctl-anki f set_bootable b
rm -f /data/unbrick
/data/bootctl-anki f set_active b
sync
reboot
