#!/usr/bin/env bash
# Apply Seek CFW overlays on top of the wire-os-victor checkout.
# Per https://os-vector.github.io/vector-docs/6.-Make-Your-Own-CFW/3.%20how.html
# DVT replicate OS look + head-only HAL (skip 898/899, keep motors).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="${ROOT}/seek/overlays"

if [[ ! -d "${ROOT}/anki/victor/engine" ]]; then
  echo "anki/victor is missing; run: git submodule update --init --recursive" >&2
  exit 1
fi

if [[ ! -d "${OVERLAY}" ]]; then
  echo "No Seek overlay directory at ${OVERLAY}; skipping." >&2
  exit 0
fi

echo "Applying Seek CFW overlay..."
# Copy overlay files into the working tree (do not commit submodule dirtiness;
# branding is owned by this repo under seek/overlays).
cp -a "${OVERLAY}/." "${ROOT}/"

# Keep DVT confidential splash as the boot movie (replaces stock Anki/WireOS logo).
if [[ -x "${ROOT}/seek/tools/gen-dvt-boot-anim.py" ]] || [[ -f "${ROOT}/seek/tools/gen-dvt-boot-anim.py" ]]; then
  python3 "${ROOT}/seek/tools/gen-dvt-boot-anim.py"
fi

echo "Seek overlay applied."
