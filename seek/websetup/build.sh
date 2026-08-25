#!/usr/bin/env bash
# Bundle BLE stack for static hosting (Cloudflare Pages).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -d node_modules/browserify ]]; then
  npm install --no-audit --no-fund
fi

echo "Bundling rts.js (vector-web-setup BLE fork)…"
npx browserify vendor/rts-js/seek-main.js -o public/js/rts.js

echo "Built public/js/rts.js ($(wc -c < public/js/rts.js) bytes)"

ZIP="${ROOT}/seek-websetup.zip"
rm -f "$ZIP"
(cd public && zip -r -q "$ZIP" .)
echo "Created $ZIP ($(wc -c < "$ZIP") bytes) — upload to GitHub release as seek-websetup.zip"
echo "Deploy folder: seek/websetup/public"
