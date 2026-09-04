#!/bin/sh
# DISABLED — full partition write to the RUNNING slot corrupts rootfs and bootloops.
# Use unlock-manual-flash-v2.sh (inactive slot) or vic-anim hotfix instead.
echo "ERROR: flash-ota-current-slot.sh is disabled."
echo "Full OTA must target the INACTIVE slot while booted from the other."
echo "Recovery: sh seek/flash/unlock-manual-flash-v2.sh /data/ota/v.ota"
exit 1
