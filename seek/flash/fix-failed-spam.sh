#!/bin/sh
# Stop face "Failed" text spam from vic-verbose boot anim (indev builds).
# Run on robot over SSH, stay optional charger.
set -e
mount -o remount,rw / 2>/dev/null || true
echo release > /etc/rebuild-dev-or-indev
rm -f /etc/use-vic-verbose
touch /etc/do-not-auto-update
cat > /anki/bin/vic-bootAnim <<'EOF'
#!/bin/bash
if [ -f /etc/use-vic-verbose ] && [ -x /bin/vic-verbose ]; then
  exec /bin/vic-verbose
fi
if [ -x /anki/bin/vic-bootAnim-stock ]; then
  exec /anki/bin/vic-bootAnim-stock
fi
exit 0
EOF
chmod 755 /anki/bin/vic-bootAnim
systemctl stop update-engine-rebuild.timer 2>/dev/null || true
systemctl disable update-engine-rebuild.timer 2>/dev/null || true
killall -9 vic-verbose 2>/dev/null || true
echo "OK — rebooting with stock boot anim"
sync
reboot
