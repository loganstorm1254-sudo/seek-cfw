#!/bin/sh
# Fix Vector error 920 (NO_GATEWAY_CERT) — missing gateway TLS cert after OS switch.
set -e

echo "=== Fix error 920 (NO_GATEWAY_CERT) ==="
echo "robot name: $(getprop anki.robot.name 2>/dev/null || echo unknown)"
echo ""

if [ ! -f /data/etc/robot.pem ]; then
  echo "Creating /data/etc/robot.pem ..."
  mkdir -p /data/etc
  openssl genrsa -out /data/etc/robot.pem 2048
  chown net:anki /data/etc/robot.pem 2>/dev/null || true
  chmod 440 /data/etc/robot.pem
fi

mkdir -p /data/vic-gateway
if [ -x /usr/sbin/vic-gateway-cert ]; then
  /usr/sbin/vic-gateway-cert
elif [ -x /sbin/vic-gateway-cert ]; then
  /sbin/vic-gateway-cert
else
  echo "FATAL: vic-gateway-cert not found"
  exit 1
fi

ls -la /data/vic-gateway/gateway.cert /data/etc/robot.pem
echo ""
echo "OK — rebooting"
sync
reboot
