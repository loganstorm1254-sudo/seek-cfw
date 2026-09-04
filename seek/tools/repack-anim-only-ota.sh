#!/usr/bin/env bash
# Repack a SeekOS OTA with vic-anim only (CCIS / face visuals — no HAL/robot changes).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_OTA="${1:-}"
OUT_VER="${2:-3.0.1.29d}"
WORK="${ROOT}/_build/ota-repack-anim"
OTA_DIR="${ROOT}/ota"
HOTFIX="${ROOT}/seek/hotfix"

if [[ -z "$BASE_OTA" ]]; then
  echo "Usage: $0 <base.ota> [out-version]" >&2
  echo "  e.g. $0 _build/vicos-3.0.1.27d.ota 3.0.1.29d" >&2
  exit 1
fi

for f in "$BASE_OTA" "$HOTFIX/vic-anim" "$OTA_DIR/ota_test.pass"; do
  [[ -f "$f" ]] || { echo "missing $f" >&2; exit 1; }
done

command -v openssl >/dev/null
command -v gzip >/dev/null
command -v debugfs >/dev/null || { echo "install e2tools (debugfs)" >&2; exit 1; }

SDK_BIN="${HOME}/.anki/vicos-sdk/dist/5.3.0-r07/prebuilt/bin"
if [[ -x "${SDK_BIN}/simg2img" ]]; then
  SIMG2IMG="${SDK_BIN}/simg2img"
elif command -v simg2img >/dev/null; then
  SIMG2IMG=simg2img
else
  echo "need simg2img (vicos-sdk or android-tools)" >&2
  exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

echo "Extracting $BASE_OTA..."
tar xf "$BASE_OTA"
chmod u+w apq8009-robot-*.img.gz manifest.ini 2>/dev/null || true
cp manifest.ini manifest.ini.orig

SYS_ENC=apq8009-robot-sysfs.img.gz
[[ -f apq8009-robot-sysfs.img.gz.enc ]] && SYS_ENC=apq8009-robot-sysfs.img.gz.enc

echo "Decrypting + decompressing system image..."
openssl aes-256-ctr -d -pass "file:${OTA_DIR}/ota_test.pass" -md md5 \
  -in "$SYS_ENC" -out apq8009-robot-sysfs.img.gz.dec
gzip -dc apq8009-robot-sysfs.img.gz.dec > apq8009-robot-sysfs.img

if file apq8009-robot-sysfs.img | grep -q 'Android sparse'; then
  "$SIMG2IMG" apq8009-robot-sysfs.img apq8009-robot-sysfs.raw
  SYSIMG=apq8009-robot-sysfs.raw
else
  SYSIMG=apq8009-robot-sysfs.img
fi

echo "Patching vic-anim only..."
debugfs -w -R "rm /anki/bin/vic-anim" "$SYSIMG" 2>/dev/null || true
debugfs -w -R "write ${HOTFIX}/vic-anim /anki/bin/vic-anim" "$SYSIMG"

echo "Recompressing system image..."
gzip -9 -c "$SYSIMG" > apq8009-robot-sysfs.img.gz.plain
openssl aes-256-ctr -pass "file:${OTA_DIR}/ota_test.pass" -md md5 \
  -in apq8009-robot-sysfs.img.gz.plain -out apq8009-robot-sysfs.img.gz.out
mv apq8009-robot-sysfs.img.gz.out apq8009-robot-sysfs.img.gz

BYTES=$(wc -c < apq8009-robot-sysfs.img)
SHA=$(sha256sum apq8009-robot-sysfs.img | awk '{print $1}')
cat > apq8009-robot-sysfs.stats <<EOF
bytes=${BYTES}
sha256=${SHA}
EOF

cat > manifest.ini <<EOF
[META]
manifest_version=1.0.0
update_version=${OUT_VER}
ankidev=1
num_images=2
reboot_after_install=0
[BOOT]
encryption=1
delta=0
compression=gz
wbits=31
$(awk '/^\[BOOT\]/{f=1;next} /^\[/{f=0} f && /^(bytes|sha256)=/{print}' manifest.ini.orig)
[SYSTEM]
encryption=1
delta=0
compression=gz
wbits=31
bytes=${BYTES}
sha256=${SHA}
EOF

mkdir -p "${ROOT}/_build"
OUT="${ROOT}/_build/vicos-${OUT_VER}.ota"
tar -cf "$OUT" \
  --mode=0400 --owner=root:0 --group=root:0 \
  -C "$WORK" manifest.ini apq8009-robot-boot.img.gz apq8009-robot-sysfs.img.gz

ls -la "$OUT"
echo "Wrote $OUT ($(wc -c < "$OUT") bytes) — vic-anim only"
