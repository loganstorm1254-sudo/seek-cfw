#!/usr/bin/env node
/**
 * Upload Seek Web Setup UI + Worker to Cloudflare (files.anki.org.uk).
 *
 * Required once:
 *   export CLOUDFLARE_API_TOKEN=...   # Account permission: Workers Scripts + R2 Edit
 *   export SEEK_R2_BUCKET=your-bucket-name   # the R2 bucket bound as "OTA"
 *
 * Optional:
 *   export CLOUDFLARE_ACCOUNT_ID=...
 *   export SEEK_WORKER_NAME=seek-otas   # Workers script name in the dashboard
 *
 * Usage:
 *   node seek/websetup-pages/deploy-cloudflare.mjs
 *   node seek/websetup-pages/deploy-cloudflare.mjs --ui-only
 *   node seek/websetup-pages/deploy-cloudflare.mjs --worker-only
 */
"use strict";

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const ROOT = __dirname;
const BUCKET = process.env.SEEK_R2_BUCKET || "";
const WORKER_NAME = process.env.SEEK_WORKER_NAME || "seek-otas";
const args = new Set(process.argv.slice(2));
const uiOnly = args.has("--ui-only");
const workerOnly = args.has("--worker-only");

function die(msg) {
  console.error(msg);
  process.exit(1);
}

function run(cmd, cmdArgs, opts) {
  const r = spawnSync(cmd, cmdArgs, {
    stdio: "inherit",
    shell: false,
    ...opts,
  });
  if (r.status !== 0) {
    die("Command failed: " + cmd + " " + cmdArgs.join(" "));
  }
}

function walkFiles(dir, base, out) {
  for (const name of fs.readdirSync(dir)) {
    if (name === "seek-websetup-pages.zip") continue;
    if (name === "worker-otas.js") continue;
    if (name === "deploy-cloudflare.mjs") continue;
    if (name === "CLOUDFLARE.md") continue;
    if (name === "README.txt") continue;
    if (name.endsWith(".map")) continue;
    const full = path.join(dir, name);
    const st = fs.statSync(full);
    if (st.isDirectory()) walkFiles(full, base, out);
    else out.push({ full, rel: path.relative(base, full).split(path.sep).join("/") });
  }
}

function uploadUi() {
  if (!BUCKET) {
    die(
      "Set SEEK_R2_BUCKET to the R2 bucket name bound as OTA on your Worker.\n" +
        "Example: export SEEK_R2_BUCKET=anki-otas"
    );
  }
  if (!process.env.CLOUDFLARE_API_TOKEN && !process.env.CLOUDFLARE_API_KEY) {
    console.warn(
      "Warning: CLOUDFLARE_API_TOKEN not set — wrangler may prompt or fail."
    );
  }

  const files = [];
  walkFiles(ROOT, ROOT, files);
  console.log("Uploading", files.length, "files to r2://" + BUCKET + "/websetup/");
  for (const f of files) {
    const key = "websetup/" + f.rel;
    console.log("  " + key);
    run("npx", [
      "--yes",
      "wrangler@4",
      "r2",
      "object",
      "put",
      BUCKET + "/" + key,
      "--file",
      f.full,
      "--remote",
      "--content-type",
      contentType(f.rel),
    ]);
  }
  console.log("UI upload done.");
}

function contentType(rel) {
  const p = rel.toLowerCase();
  if (p.endsWith(".html")) return "text/html; charset=utf-8";
  if (p.endsWith(".js")) return "application/javascript; charset=utf-8";
  if (p.endsWith(".css")) return "text/css; charset=utf-8";
  if (p.endsWith(".json")) return "application/json; charset=utf-8";
  if (p.endsWith(".svg")) return "image/svg+xml";
  if (p.endsWith(".png")) return "image/png";
  if (p.endsWith(".jpg") || p.endsWith(".jpeg")) return "image/jpeg";
  return "application/octet-stream";
}

function deployWorker() {
  const workerSrc = path.join(ROOT, "worker-otas.js");
  if (!fs.existsSync(workerSrc)) die("missing worker-otas.js");

  // Prefer dashboard paste when wrangler.toml is incomplete; still try deploy.
  const toml = path.join(ROOT, "wrangler.toml");
  if (!fs.existsSync(toml)) {
    console.log(
      "No wrangler.toml — paste worker-otas.js into Cloudflare Workers → " +
        WORKER_NAME +
        " → Deploy."
    );
    console.log("File to paste:", workerSrc);
    return;
  }
  run("npx", ["--yes", "wrangler@4", "deploy"], { cwd: ROOT });
}

console.log("Seek Cloudflare deploy");
if (!workerOnly) uploadUi();
if (!uiOnly) deployWorker();
console.log("");
console.log("Verify in Chrome:");
console.log("  https://files.anki.org.uk/");
console.log("  Top-right must say: UI seek16");
console.log("  Install URL must be: http://files.anki.org.uk/ota/latest");
