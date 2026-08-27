#!/bin/sh
# Drop on robot: bash /data/seek-wifi-boot-install.sh
# Adds early Wi-Fi reconnect on boot (no full OTA required).
set -e
cat > /data/seek-wifi-boot.sh << 'EOF'
#!/bin/bash
set +e
wlan_has_ip() { ip -4 addr show wlan0 2>/dev/null | grep -q 'inet '; }
for pass in 1 2 3 4 5 6; do
  if wlan_has_ip; then exit 0; fi
  connmanctl enable wifi 2>/dev/null
  connmanctl scan wifi 2>/dev/null
  sleep 3
  prov=$(connmanctl services 2>/dev/null | grep '^\*' | grep wifi_ | head -1 | awk '{print $3}')
  [ -n "$prov" ] && connmanctl connect "$prov" 2>/dev/null
  sleep 8
  if wlan_has_ip; then exit 0; fi
  if [ ! -f /data/seek/skip-dvt2-wifi ] && [ "$pass" -ge 2 ]; then
    connmanctl scan wifi 2>/dev/null
    sleep 5
    ar=$(connmanctl services 2>/dev/null | grep -i AnkiRobits | head -1 | awk '{print $3}')
    [ -n "$ar" ] && connmanctl connect "$ar" 2>/dev/null
    sleep 10
    if wlan_has_ip; then exit 0; fi
  fi
  if [ "$pass" -eq 3 ]; then systemctl restart wpa_supplicant connman; sleep 8; fi
done
EOF
chmod 755 /data/seek-wifi-boot.sh
mkdir -p /data/seek
if ! grep -q seek-wifi-boot /etc/rc.local 2>/dev/null; then
  mount -o remount,rw / 2>/dev/null || true
  if [ -f /etc/rc.local ]; then
    sed -i '/^exit 0/i /data/seek-wifi-boot.sh &' /etc/rc.local 2>/dev/null || true
  fi
fi
echo "Installed /data/seek-wifi-boot.sh — run now: /data/seek-wifi-boot.sh"
/data/seek-wifi-boot.sh
