#!/usr/bin/env bash
# Repack a SeekOS DVT OTA with head-only HAL binaries (no full Yocto rebuild).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_OTA="${1:-}"
OUT_VER="${2:-3.0.1.21d}"
WORK="${ROOT}/_build/ota-repack"
OTA_DIR="${ROOT}/ota"
HOTFIX="${ROOT}/seek/hotfix"

if [[ -z "$BASE_OTA" ]]; then
  echo "Usage: $0 <base.ota> [out-version]" >&2
  echo "  e.g. $0 /tmp/vicos-3.0.1.20d.ota 3.0.1.21d" >&2
  exit 1
fi

for f in "$BASE_OTA" \
  "$HOTFIX/vic-robot" "$HOTFIX/vic-anim" "$HOTFIX/rampost" "$HOTFIX/fault-code-handler" \
  "$OTA_DIR/ota_test.pass"; do
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
  echo "need simg2img (vicos-sdk or android-tools" >&2
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
BOOT_ENC=apq8009-robot-boot.img.gz
[[ -f apq8009-robot-sysfs.img.gz.enc ]] && SYS_ENC=apq8009-robot-sysfs.img.gz.enc
[[ -f apq8009-robot-boot.img.gz.enc ]] && BOOT_ENC=apq8009-robot-boot.img.gz.enc

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

patch_bin() {
  local src="$1"
  local dest="$2"
  echo "  -> $dest"
  debugfs -w -R "rm $dest" "$SYSIMG" 2>/dev/null || true
  debugfs -w -R "write $src $dest" "$SYSIMG"
}

echo "Patching rootfs..."
patch_bin "$HOTFIX/vic-robot" /anki/bin/vic-robot
patch_bin "$HOTFIX/vic-anim" /anki/bin/vic-anim
patch_bin "$HOTFIX/rampost" /usr/bin/rampost
patch_bin "$HOTFIX/fault-code-handler" /usr/bin/fault-code-handler

# DVT boot movie (stock paths — bootAnim picks by LCD)
if [[ -f "$HOTFIX/boot_anim.raw" ]]; then
  patch_bin "$HOTFIX/boot_anim.raw" \
    /anki/data/assets/cozmo_resources/config/engine/animations/boot_anim.raw
fi
if [[ -f "$HOTFIX/boot_anim_20.raw" ]]; then
  patch_bin "$HOTFIX/boot_anim_20.raw" \
    /anki/data/assets/cozmo_resources/config/engine/animations/boot_anim_20.raw
fi

# Ensure head_only is not forced on fresh flash.
debugfs -w -R "rm /data/seek/head_only" "$SYSIMG" 2>/dev/null || true
# Clear WireOS persist boot override if present in image
debugfs -w -R "rm /persist/boot_anim.raw" "$SYSIMG" 2>/dev/null || true

echo "Recompressing system image..."
gzip -9 -c "$SYSIMG" > apq8009-robot-sysfs.img.gz.plain
openssl aes-256-ctr -pass "file:${OTA_DIR}/ota_test.pass" -md md5 \
  -in apq8009-robot-sysfs.img.gz.plain -out apq8009-robot-sysfs.img.gz.out
mv apq8009-robot-sysfs.img.gz.out apq8009-robot-sysfs.img.gz
# Boot partition unchanged from base OTA.

BYTES=$(wc -c < apq8009-robot-sysfs.img)
SHA=$(sha256sum apq8009-robot-sysfs.img | awk '{print $1}')
cat > apq8009-robot-sysfs.stats <<EOF
bytes=${BYTES}
sha256=${SHA}
EOF

# Boot image unchanged — copy stats from original manifest if present.
grep -A2 '^\[BOOT\]' manifest.ini.orig >/dev/null || true
BOOT_STATS=$(awk '/^\[BOOT\]/{f=1;next} /^\[/{f=0} f && /^(bytes|sha256)=/{print}' manifest.ini.orig)
if [[ -z "$BOOT_STATS" ]]; then
  cp ../_build/apq8009-robot-boot.stats apq8009-robot-boot.stats 2>/dev/null || \
    grep -A2 '^\[BOOT\]' manifest.ini.orig | tail -2 > apq8009-robot-boot.stats || true
fi

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
echo "Wrote $OUT ($(wc -c < "$OUT") bytes)"
