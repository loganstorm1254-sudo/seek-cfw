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
fi
sync
systemctl start wired
echo "Done. Hard-refresh http://$(hostname -I 2>/dev/null | awk '{print $1}'):8080/seek.html"
