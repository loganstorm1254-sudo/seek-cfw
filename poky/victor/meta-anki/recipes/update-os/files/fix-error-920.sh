#!/bin/sh
# Fix Vector error 920 (NO_GATEWAY_CERT) — missing gateway TLS cert after OS switch.
set -e

echo "=== Fix error 920 (NO_GATEWAY_CERT) ==="
echo "robot name: $(getprop anki.robot.name 2>/dev/null || echo unknown)"
echo ""

mkdir -p /data/etc /data/vic-gateway

if [ ! -f /data/etc/robot.pem ]; then
  echo "Creating /data/etc/robot.pem ..."
  openssl genrsa -out /data/etc/robot.pem 2048
fi

if [ -x /usr/sbin/vic-gateway-cert ]; then
  /usr/sbin/vic-gateway-cert
elif [ -x /sbin/vic-gateway-cert ]; then
  /sbin/vic-gateway-cert
else
  RNAME=$(getprop anki.robot.name 2>/dev/null | tr ' ' '-')
  [ -n "$RNAME" ] || RNAME=Vector-N9U1
  echo "Creating gateway.cert with openssl (vic-gateway-cert missing)..."
  openssl req -x509 -new -nodes -days 36500 \
    -key /data/etc/robot.pem -out /data/vic-gateway/gateway.cert \
    -subj "/C=US/ST=California/L=SF/O=Anki/CN=$RNAME"
fi

chmod 440 /data/etc/robot.pem /data/vic-gateway/gateway.cert 2>/dev/null || true
chown net:anki /data/etc/robot.pem /data/vic-gateway/gateway.cert 2>/dev/null || true

ls -la /data/vic-gateway/gateway.cert /data/etc/robot.pem
echo ""
echo "OK — rebooting"
sync
reboot
