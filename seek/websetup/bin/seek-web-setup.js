#!/usr/bin/env node
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const http = require("http");
const https = require("https");
const { URL } = require("url");

const FILES_HOST = process.env.SEEK_FILES_HOST || "https://files.anki.org.uk";
const OTA_LIST = FILES_HOST.replace(/\/$/, "") + "/api/otas.json";
const OTA_LATEST = FILES_HOST.replace(/\/$/, "") + "/ota/latest";
const PAGES_DIR = path.resolve(__dirname, "..", "..", "websetup-pages");
const DATA_DIR = path.join(os.homedir(), ".seek-web-setup");
const FW_DIR = path.join(DATA_DIR, "firmware", "seek");

function lanIp() {
  const ifs = os.networkInterfaces();
  for (const name of Object.keys(ifs)) {
    for (const i of ifs[name] || []) {
      const family = i.family === "IPv4" || i.family === 4;
      if (family && !i.internal) return i.address;
    }
  }
  return "127.0.0.1";
}

function fetchBuffer(url) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith("https:") ? https : http;
    const req = lib.get(url, { headers: { "user-agent": "seek-web-setup" } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        fetchBuffer(new URL(res.headers.location, url).href).then(resolve, reject);
        return;
      }
      if (res.statusCode !== 200) {
        res.resume();
        reject(new Error("GET " + url + " -> " + res.statusCode));
        return;
      }
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve(Buffer.concat(chunks)));
    });
    req.on("error", reject);
  });
}

function pipeUrl(url, destReq, destRes) {
  const lib = url.startsWith("https:") ? https : http;
  const headers = { "user-agent": "seek-web-setup" };
  if (destReq.headers.range) headers.range = destReq.headers.range;
  const req = lib.get(url, { headers }, (res) => {
    if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
      res.resume();
      pipeUrl(new URL(res.headers.location, url).href, destReq, destRes);
      return;
    }
    destRes.writeHead(res.statusCode, {
      "content-type": res.headers["content-type"] || "application/octet-stream",
      "content-length": res.headers["content-length"] || "",
      "accept-ranges": "bytes",
      "access-control-allow-origin": "*",
      "cache-control": "no-store",
    });
    res.pipe(destRes);
  });
  req.on("error", (err) => {
    if (!destRes.headersSent) destRes.writeHead(502);
    destRes.end(String(err));
  });
}

function ensureDirs() {
  fs.mkdirSync(FW_DIR, { recursive: true });
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

function cmdConfigure() {
  ensureDirs();
  const cfg = {
    filesHost: FILES_HOST,
    otaListUrl: OTA_LIST,
    pagesDir: PAGES_DIR,
  };
  fs.writeFileSync(path.join(DATA_DIR, "config.json"), JSON.stringify(cfg, null, 2));
  console.log("Wrote " + path.join(DATA_DIR, "config.json"));
  console.log("Files host: " + FILES_HOST);
}

async function cmdOtaSync() {
  ensureDirs();
  console.log("Fetching " + OTA_LIST);
  let list = [];
  try {
    const raw = JSON.parse((await fetchBuffer(OTA_LIST)).toString("utf8"));
    list = (raw && (raw.seek || raw.otas)) || [];
  } catch (e) {
    console.warn("otas.json failed (" + e.message + "), using /ota/latest only");
  }
  if (!list.length) {
    list = [{ url: OTA_LATEST, name: "latest.ota" }];
  }
  for (const item of list) {
    const url = item.url || item;
    const name = String(item.name || path.basename(String(url).split("?")[0]) || "update.ota")
      .replace(/\s+/g, "-")
      .replace(/[^a-zA-Z0-9._-]+/g, "");
    const dest = path.join(FW_DIR, name);
    process.stdout.write("Downloading " + url + " -> " + dest + " ... ");
    const buf = await fetchBuffer(url);
    fs.writeFileSync(dest, buf);
    console.log((buf.length / 1048576).toFixed(1) + " MiB");
  }
  console.log("OTA sync done. Run: npx seek-web-setup serve");
}

function mime(p) {
  if (p.endsWith(".html")) return "text/html; charset=utf-8";
  if (p.endsWith(".js")) return "application/javascript";
  if (p.endsWith(".css")) return "text/css";
  if (p.endsWith(".json")) return "application/json";
  if (p.endsWith(".svg")) return "image/svg+xml";
  if (p.endsWith(".png")) return "image/png";
  if (p.endsWith(".ota")) return "application/octet-stream";
  return "application/octet-stream";
}

function injectIndex(html, ip, port) {
  return html
    .replace(/<div id="serverIp"[^>]*>[\s\S]*?<\/div>/, '<div id="serverIp">' + ip + "</div>")
    .replace(/<div id="networkIp"[^>]*>[\s\S]*?<\/div>/, '<div id="networkIp">' + ip + "</div>")
    .replace(/<div id="serverPort"[^>]*>[\s\S]*?<\/div>/, '<div id="serverPort">' + port + "</div>");
}

function sendFile(res, filePath, extra) {
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end("not found");
      return;
    }
    res.writeHead(200, Object.assign({ "content-type": mime(filePath), "access-control-allow-origin": "*" }, extra || {}));
    res.end(data);
  });
}

function cmdServe(port) {
  ensureDirs();
  const ip = lanIp();
  const server = http.createServer((req, res) => {
    const u = new URL(req.url, "http://127.0.0.1");
    const p = decodeURIComponent(u.pathname);

    if (req.method === "OPTIONS") {
      res.writeHead(204, { "access-control-allow-origin": "*", "access-control-allow-methods": "GET, HEAD, OPTIONS" });
      res.end();
      return;
    }

    if (p === "/firmware/latest" || p === "/firmware/latest.ota" || p === "/ota/latest") {
      const files = fs.readdirSync(FW_DIR).filter((f) => f.toLowerCase().endsWith(".ota"));
      if (files.length) {
        sendFile(res, path.join(FW_DIR, files.sort().pop()));
        return;
      }
      pipeUrl(OTA_LATEST, req, res);
      return;
    }

    if (p.startsWith("/firmware/")) {
      const name = path.basename(p);
      const local = path.join(FW_DIR, name);
      if (fs.existsSync(local)) {
        sendFile(res, local);
        return;
      }
      pipeUrl(FILES_HOST.replace(/\/$/, "") + "/dl/" + name, req, res);
      return;
    }

    if (p === "/static/data/inventory.json") {
      const files = fs.existsSync(FW_DIR)
        ? fs.readdirSync(FW_DIR).filter((f) => f.toLowerCase().endsWith(".ota"))
        : [];
      const body = JSON.stringify({ seek: files }, null, 2);
      res.writeHead(200, { "content-type": "application/json", "access-control-allow-origin": "*" });
      res.end(body);
      return;
    }

    let rel = p === "/" ? "/index.html" : p;
    if (rel.includes("..")) {
      res.writeHead(400);
      res.end("bad path");
      return;
    }
    const filePath = path.join(PAGES_DIR, rel.replace(/^\//, ""));
    if (rel === "/index.html" || p === "/") {
      fs.readFile(path.join(PAGES_DIR, "index.html"), "utf8", (err, html) => {
        if (err) {
          res.writeHead(500);
          res.end("missing websetup-pages/index.html");
          return;
        }
        const out = injectIndex(html, ip, String(port));
        res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
        res.end(out);
      });
      return;
    }
    sendFile(res, filePath);
  });

  server.listen(port, "0.0.0.0", () => {
    console.log("Seek Web Setup");
    console.log("  Chrome (required):  http://localhost:" + port + "/");
    console.log("  Robot OTA (HTTP):   http://" + ip + ":" + port + "/firmware/latest.ota");
    console.log("Same Wi-Fi / hotspot as Vector. BLE only works on localhost or HTTPS.");
  });
}

async function main() {
  const argv = process.argv.slice(2);
  const cmd = argv[0] || "serve";
  let port = 8000;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "-p" || argv[i] === "--port") port = parseInt(argv[i + 1], 10) || 8000;
  }
  if (cmd === "configure") cmdConfigure();
  else if (cmd === "ota-sync") await cmdOtaSync();
  else if (cmd === "serve") cmdServe(port);
  else if (cmd === "-h" || cmd === "--help") {
    console.log("seek-web-setup configure | ota-sync | serve [-p 8000]");
  } else {
    console.error("Unknown command: " + cmd);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
