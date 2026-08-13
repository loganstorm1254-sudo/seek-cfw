#!/bin/sh
# Run on the robot from an unpacked seek-wired tarball.
set -e
DIR=$(dirname "$0")
cd "$DIR"
if [ ! -f ./wired ] || [ ! -d ./webroot ]; then
    echo "Run this from the seek-wired folder."
    exit 1
fi
echo "Updating Seek dashboard (wired) — no OS flash, no reboot."
systemctl stop wired || true
cp ./wired /usr/bin/wired
chmod 0755 /usr/bin/wired
rm -rf /etc/wired/webroot
cp -a ./webroot /etc/wired/webroot
if [ -f ./update-seek ]; then
    cp ./update-seek /usr/sbin/update-seek
    chmod 0755 /usr/sbin/update-seek
elif [ -f ./update-seek.sh ]; then
    cp ./update-seek.sh /usr/sbin/update-seek
    chmod 0755 /usr/sbin/update-seek
fi
# /usr/sbin is read-only on live robots; bind-mount the fast updater over stock update-os.
src=""
if [ -f ./update-os.sh ]; then src=./update-os.sh; elif [ -f ./update-os ]; then src=./update-os; fi
if [ -n "$src" ]; then
    mkdir -p /data /run
    cp "$src" /data/update-os.sh
    cp "$src" /run/update-os
    chmod 0755 /run/update-os
    umount /usr/sbin/update-os 2>/dev/null || true
    mount --bind /run/update-os /usr/sbin/update-os || true
fi
sync
systemctl start wired
echo "Done. Hard-refresh http://$(hostname -I 2>/dev/null | awk '{print $1}'):8080/seek.html"
