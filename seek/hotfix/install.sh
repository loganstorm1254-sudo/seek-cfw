#!/bin/sh
# SeekOS head-only hotfix: dummy wheels, live lift + backpack button/lights.
# Run on the robot as root, from this directory.
set -e
cd "$(dirname "$0")"

mkdir -p /data/seek
touch /data/seek/head_only

mount -o remount,rw /anki 2>/dev/null || true
if [ ! -f /anki/bin/vic-robot ]; then
  echo "missing /anki/bin/vic-robot" >&2
  exit 1
fi
cp -a /anki/bin/vic-robot /anki/bin/vic-robot.seekbak
cp vic-robot /anki/bin/vic-robot
chown robot:anki /anki/bin/vic-robot 2>/dev/null || true
chmod 0755 /anki/bin/vic-robot

mount -o remount,rw / 2>/dev/null || true
if [ -f /usr/bin/fault-code-handler ]; then
  cp -a /usr/bin/fault-code-handler /usr/bin/fault-code-handler.seekbak
  cp fault-code-handler /usr/bin/fault-code-handler
  chmod 0755 /usr/bin/fault-code-handler
fi
if [ -f /usr/bin/rampost ]; then
  cp -a /usr/bin/rampost /usr/bin/rampost.seekbak
  cp rampost /usr/bin/rampost
  chmod 0755 /usr/bin/rampost
fi

sync
systemctl daemon-reload 2>/dev/null || true
systemctl restart vic-robot
sleep 1
systemctl restart vic-engine 2>/dev/null || true
echo SEEK_HEADONLY_OK
