#!/bin/bash

# Saves 1.6-rebuild's eye color settings to load at next boot
# By Emily ONLY for 1.6-rebuild

SATURATION="$1"
HUE="$2"

mkdir -p /data/data/rebuild
echo $SATURATION > /data/data/rebuild/rebuildEyesSaturation
echo $HUE > /data/data/rebuild/rebuildEyesHue
chown -R engine:engine /data/data/rebuild