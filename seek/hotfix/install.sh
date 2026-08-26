#!/bin/sh
# SeekOS head-only hotfix: skip 898/899, keep head/lift/backpack when spine is up.
# Do NOT force /data/seek/head_only — that freezes idle face (never SyncRobot).
# Dummy mode only engages if spine actually fails; it can recover.
set -e
cd "$(dirname "$0")"

mkdir -p /data/seek
# Previous hotfixes forced this and left Vector staring. Clear it.
rm -f /data/seek/head_only

mount -o remount,rw /anki 2>/dev/null || true
if [ ! -f /anki/bin/vic-robot ]; then
  echo "missing /anki/bin/vic-robot" >&2
  exit 1
fi
# Keep first backup only so we can always restore stock DVT binary.
if [ ! -f /anki/bin/vic-robot.seekbak ]; then
  cp -a /anki/bin/vic-robot /anki/bin/vic-robot.seekbak
fi
cp vic-robot /anki/bin/vic-robot
chown robot:anki /anki/bin/vic-robot 2>/dev/null || true
chmod 0755 /anki/bin/vic-robot

mount -o remount,rw / 2>/dev/null || true
if [ -f /usr/bin/fault-code-handler ]; then
  if [ ! -f /usr/bin/fault-code-handler.seekbak ]; then
    cp -a /usr/bin/fault-code-handler /usr/bin/fault-code-handler.seekbak
  fi
  cp fault-code-handler /usr/bin/fault-code-handler
  chmod 0755 /usr/bin/fault-code-handler
fi
if [ -f /usr/bin/rampost ]; then
  if [ ! -f /usr/bin/rampost.seekbak ]; then
    cp -a /usr/bin/rampost /usr/bin/rampost.seekbak
  fi
  cp rampost /usr/bin/rampost
  chmod 0755 /usr/bin/rampost
fi

sync
systemctl daemon-reload 2>/dev/null || true
systemctl restart vic-robot
sleep 1
systemctl restart vic-engine 2>/dev/null || true
systemctl restart vic-anim 2>/dev/null || true
echo SEEK_HEADONLY_OK
