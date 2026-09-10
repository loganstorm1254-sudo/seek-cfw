#!/usr/bin/env bash
# Apply LIFE OS overlays (stretched splash, Ordinary Life boot+music, 890/899).
# Per https://os-vector.github.io/vector-docs/6.-Make-Your-Own-CFW/3.%20how.html
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="${ROOT}/seek/overlays"

if [[ ! -d "${ROOT}/anki/victor/engine" ]]; then
  echo "anki/victor is missing; run: git submodule update --init --recursive" >&2
  exit 1
fi

if [[ ! -d "${OVERLAY}" ]]; then
  echo "No overlay directory at ${OVERLAY}; skipping." >&2
  exit 0
fi

echo "Applying LIFE OS overlay..."
# Copy overlay files into the working tree (do not commit submodule dirtiness;
# branding is owned by this repo under seek/overlays).
cp -a "${OVERLAY}/." "${ROOT}/"
echo "LIFE OS overlay applied."
