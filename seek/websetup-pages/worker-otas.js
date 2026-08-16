/**
 * Seek OTA + Web Setup Worker (files.anki.org.uk)
 *
 * Paste into Cloudflare Worker for files.anki.org.uk (R2 binding: OTA), Deploy.
 *
 *   GET /           → landing (Web Setup | OTA storage)
 *   GET /setup      → Seek Web Setup UI
 *   GET /files      → white "Index of /" directory listing (same as before)
 *   GET /OTA/       → browse OTA folder
 *   GET /ota/latest → newest .ota (Vector HTTP)
 *   GET /fast-ota.ps1 → Windows one-liner helper (no Node/git)
 *   GET /fast-ota.bat → double-click launcher
 *   GET /fast-ota.sh  → Mac/Linux helper
 */
function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
    "Access-Control-Allow-Headers": "*",
  };
}

function safeName(name) {
  return String(name || "update.ota")
    .replace(/\s+/g, "-")
    .replace(/[^a-zA-Z0-9._-]+/g, "")
    .replace(/-+/g, "-")
    .toLowerCase();
}

function contentTypeFor(path) {
  const p = String(path).toLowerCase();
  if (p.endsWith(".html")) return "text/html; charset=utf-8";
  if (p.endsWith(".js")) return "application/javascript; charset=utf-8";
  if (p.endsWith(".css")) return "text/css; charset=utf-8";
  if (p.endsWith(".json")) return "application/json; charset=utf-8";
  if (p.endsWith(".svg")) return "image/svg+xml";
  if (p.endsWith(".png")) return "image/png";
  if (p.endsWith(".jpg") || p.endsWith(".jpeg")) return "image/jpeg";
  if (p.endsWith(".ico")) return "image/x-icon";
  if (p.endsWith(".map")) return "application/json";
  if (p.endsWith(".txt") || p.endsWith(".ps1") || p.endsWith(".sh") || p.endsWith(".bat") || p.endsWith(".cmd")) {
    return "text/plain; charset=utf-8";
  }
  return "application/octet-stream";
}

async function listOtaObjects(env) {
  const prefixes = ["OTA/", "ota/", ""];
  const seen = new Set();
  const out = [];
  for (const prefix of prefixes) {
    let cursor;
    do {
      const listed = await env.OTA.list({ prefix, limit: 1000, cursor });
      for (const obj of listed.objects || []) {
        if (!obj.key.toLowerCase().endsWith(".ota")) continue;
        // Do not treat websetup UI copies as OTAs.
        if (obj.key.toLowerCase().startsWith("websetup/")) continue;
        if (seen.has(obj.key)) continue;
        seen.add(obj.key);
        out.push(obj);
      }
      cursor = listed.truncated ? listed.cursor : undefined;
    } while (cursor);
  }
  out.sort((a, b) => {
    const ta = a.uploaded ? new Date(a.uploaded).getTime() : 0;
    const tb = b.uploaded ? new Date(b.uploaded).getTime() : 0;
    if (tb !== ta) return tb - ta;
    return String(b.key).localeCompare(String(a.key));
  });
  return out;
}

function otaHeadHeaders(cors, size) {
  const headers = new Headers(cors);
  headers.set("content-type", "application/octet-stream");
  if (size != null) headers.set("content-length", String(size));
  headers.set("accept-ranges", "bytes");
  // Old Vector curl stalls if the edge advertises HTTP/3.
  headers.set("alt-svc", "clear");
  headers.set("cache-control", "public, max-age=86400");
  return headers;
}

function otaResponse(obj, cors, downloadName) {
  const headers = new Headers(cors);
  obj.writeHttpMetadata(headers);
  headers.set("etag", obj.httpEtag);
  headers.set("accept-ranges", "bytes");
  headers.set("content-type", "application/octet-stream");
  const fname = safeName(downloadName || "update.ota");
  headers.set("content-disposition", 'inline; filename="' + fname + '"');
  if (obj.size != null) headers.set("content-length", String(obj.size));
  headers.set("alt-svc", "clear");
  headers.set("Alt-Svc", "clear");
  headers.set("cache-control", "public, max-age=86400");
  return new Response(obj.body, { headers });
}

function parseBytesRange(header, size) {
  if (!header || !size) return null;
  const m = String(header).match(/^bytes=(\d*)-(\d*)$/i);
  if (!m) return null;
  const start = m[1] === "" ? 0 : Number(m[1]);
  let end = m[2] === "" ? size - 1 : Number(m[2]);
  if (!Number.isFinite(start) || !Number.isFinite(end)) return null;
  if (start < 0 || start >= size || end < start) return null;
  end = Math.min(end, size - 1);
  return { offset: start, length: end - start + 1, start, end, size };
}

async function serveOtaKey(env, key, request, cors, downloadName, listedSize) {
  const size = listedSize || 0;
  if (request.method === "HEAD") {
    return new Response(null, { headers: otaHeadHeaders(cors, size) });
  }
  const range = parseBytesRange(request.headers.get("range"), size);
  if (range) {
    const obj = await env.OTA.get(key, {
      range: { offset: range.offset, length: range.length },
    });
    if (!obj) {
      return new Response("Missing object", { status: 404, headers: cors });
    }
    const headers = new Headers(cors);
    headers.set("content-type", "application/octet-stream");
    headers.set("accept-ranges", "bytes");
    headers.set("content-range", "bytes " + range.start + "-" + range.end + "/" + range.size);
    headers.set("content-length", String(range.length));
    headers.set("alt-svc", "clear");
    headers.set("cache-control", "public, max-age=86400");
    return new Response(obj.body, { status: 206, headers });
  }
  const obj = await env.OTA.get(key);
  if (!obj) {
    return new Response("Missing object", { status: 404, headers: cors });
  }
  return otaResponse(obj, cors, downloadName);
}

// Public repo mirror of seek/websetup-pages (Worker fetches server-side).
// GitHub raw (short cache) so Worker paste picks up seek17 UI quickly.
const WEBSETUP_CDN =
  "https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/seek-web-dashboard-f1f4/seek/websetup-pages";

function landingPage(cors) {
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Seek — files.anki.org.uk</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@500;700&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet" />
  <style>
    :root {
      --bg0: #0c1219;
      --bg1: #152033;
      --ink: #e8eef6;
      --muted: #8fa3b8;
      --line: rgba(232,238,246,0.14);
      --accent: #3d9bfd;
      --accent2: #7ddea2;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "DM Sans", system-ui, sans-serif;
      color: var(--ink);
      background:
        radial-gradient(900px 500px at 10% -10%, #1a3a5c 0%, transparent 55%),
        radial-gradient(700px 420px at 100% 0%, #163528 0%, transparent 50%),
        linear-gradient(165deg, var(--bg0), var(--bg1));
      display: grid;
      place-items: center;
      padding: 32px 20px;
    }
    main { width: min(640px, 100%); }
    .brand {
      font-family: "IBM Plex Mono", monospace;
      font-size: 13px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--accent2);
      margin: 0 0 10px;
    }
    h1 {
      margin: 0 0 8px;
      font-size: clamp(1.8rem, 4vw, 2.4rem);
      font-weight: 700;
      letter-spacing: -0.02em;
    }
    .sub {
      margin: 0 0 28px;
      color: var(--muted);
      font-size: 1.02rem;
      line-height: 1.45;
      max-width: 34em;
    }
    .choices { display: grid; gap: 14px; }
    a.choice {
      display: block;
      text-decoration: none;
      color: inherit;
      border: 1px solid var(--line);
      background: rgba(12, 18, 25, 0.55);
      padding: 18px 20px;
      transition: border-color 0.15s ease, transform 0.15s ease, background 0.15s ease;
    }
    a.choice:hover {
      border-color: rgba(61, 155, 253, 0.55);
      background: rgba(21, 32, 51, 0.9);
      transform: translateY(-1px);
    }
    a.choice .label {
      display: block;
      font-size: 1.2rem;
      font-weight: 700;
      margin-bottom: 4px;
    }
    a.choice .hint {
      display: block;
      color: var(--muted);
      font-size: 0.92rem;
      line-height: 1.35;
      font-family: "IBM Plex Mono", monospace;
    }
    a.choice.primary .label { color: var(--accent); }
    footer {
      margin-top: 28px;
      color: var(--muted);
      font-size: 12px;
      font-family: "IBM Plex Mono", monospace;
    }
  </style>
</head>
<body>
  <main>
    <p class="brand">Seek · files.anki.org.uk</p>
    <h1>What do you need?</h1>
    <p class="sub">Pick Web Setup to flash Vector, or open the file browser for raw OTA storage.</p>
    <div class="choices">
      <a class="choice primary" href="/setup">
        <span class="label">Web Setup</span>
        <span class="hint">Pair Vector — use Fast install (one PowerShell paste)</span>
      </a>
      <a class="choice" href="/fast-ota.bat">
        <span class="label">Fast OTA helper (Windows)</span>
        <span class="hint">Download · double-click · same hotspot as Vector</span>
      </a>
      <a class="choice" href="/files/">
        <span class="label">OTA storage</span>
        <span class="hint">White directory listing — browse /OTA files</span>
      </a>
    </div>
    <footer>http://files.anki.org.uk/ota/latest · robot installs over plain HTTP</footer>
  </main>
</body>
</html>`;
  return new Response(html, {
    headers: {
      ...cors,
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-cache",
      "x-seek-landing": "1",
    },
  });
}

/** Serve Seek Web Setup UI from R2 websetup/*, else GitHub via jsDelivr. */
async function serveWebsetup(env, urlPath, cors) {
  let rel = urlPath;
  if (rel === "/setup" || rel === "/setup/" || rel === "/websetup" || rel === "/websetup/") {
    rel = "/index.html";
  }
  if (!rel.startsWith("/")) rel = "/" + rel;
  // Only allow index + static assets (never OTA keys via this helper).
  if (
    rel !== "/index.html" &&
    !rel.startsWith("/static/") &&
    rel !== "/fast-ota.ps1" &&
    rel !== "/fast-ota.sh" &&
    rel !== "/fast-ota.bat"
  ) {
    return null;
  }

  const headers = new Headers(cors);
  headers.set("content-type", contentTypeFor(rel));
  if (rel === "/index.html" || rel.endsWith(".js") || rel.endsWith(".css")) {
    headers.set("cache-control", "no-cache");
  } else {
    headers.set("cache-control", "public, max-age=3600");
  }

  const key = "websetup" + rel;
  try {
    const obj = await env.OTA.get(key);
    if (obj) {
      if (obj.size != null) headers.set("content-length", String(obj.size));
      headers.set("x-seek-ui", "r2");
      return new Response(obj.body, { headers });
    }
  } catch (e) {
    // fall through to CDN
  }

  const cdnUrl = WEBSETUP_CDN + rel;
  const upstream = await fetch(cdnUrl, {
    cf: { cacheTtl: 300, cacheEverything: true },
  });
  if (!upstream.ok) {
    return new Response(
      "Websetup UI missing (R2 " +
        key +
        " and CDN " +
        cdnUrl +
        " → " +
        upstream.status +
        "). Paste the latest worker-otas.js from the seek-cfw repo.",
      {
        status: 502,
        headers: { ...cors, "content-type": "text/plain; charset=utf-8" },
      }
    );
  }
  headers.set("x-seek-ui", "cdn");
  return new Response(upstream.body, { headers });
}

async function directoryListing(env, path, cors) {
  const prefix = path.replace(/^\/+/, "");
  const listed = await env.OTA.list({ prefix, delimiter: "/" });
  const rows = [];
  for (const p of listed.delimitedPrefixes || []) {
    if (p.toLowerCase().startsWith("websetup")) continue;
    const name = p.slice(prefix.length);
    rows.push(`<a href="/${p}">${name}</a>`);
  }
  for (const obj of listed.objects || []) {
    if (obj.key.toLowerCase().startsWith("websetup/")) continue;
    const name = obj.key.slice(prefix.length);
    if (!name) continue;
    const when = obj.uploaded.toISOString().replace("T", " ").slice(0, 16);
    const safe = safeName(name);
    rows.push(
      `<a href="/dl/${safe}">${name}</a>` +
        " ".repeat(Math.max(2, 40 - name.length)) +
        when +
        " ".repeat(4) +
        String(obj.size)
    );
  }
  const displayPath = path === "/files" || path === "/files/" ? "/" : path;
  const title = "Index of " + displayPath;
  const up =
    displayPath === "/"
      ? `<a href="/">home</a>`
      : `<a href="../">../</a>`;
  const html = `<!DOCTYPE html>
<html><head><title>${title}</title></head>
<body bgcolor="white">
<h1>${title}</h1><hr><pre>${up}
${rows.join("\n")}
</pre><hr>
<p style="font-family:sans-serif;font-size:13px;"><a href="/">← Seek home</a> · <a href="/setup">Web Setup</a></p>
</body></html>`;
  return new Response(html, {
    headers: { ...cors, "content-type": "text/html; charset=utf-8" },
  });
}

export default {
  async fetch(request, env) {
    if (!env.OTA) {
      return new Response("R2 binding missing: add binding named OTA", {
        status: 500,
      });
    }

    const url = new URL(request.url);
    const path = url.pathname;
    const cors = corsHeaders();

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: cors });
    }

    // Landing: two choices
    if (path === "/" || path === "") {
      return landingPage(cors);
    }

    // Same white directory listing as before (Index of /)
    if (
      path === "/files" ||
      path === "/files/" ||
      path === "/browse" ||
      path === "/browse/" ||
      path === "/storage" ||
      path === "/storage/"
    ) {
      return directoryListing(env, "/", cors);
    }

    // Fast-install helpers (no git / no Node)
    if (
      path === "/fast-ota.ps1" ||
      path === "/fast-ota.sh" ||
      path === "/fast-ota.bat"
    ) {
      const page = await serveWebsetup(env, path, cors);
      if (page) return page;
    }

    // Seek Web Setup UI
    if (
      path === "/setup" ||
      path === "/setup/" ||
      path === "/websetup" ||
      path === "/websetup/" ||
      path === "/index.html" ||
      path.startsWith("/static/")
    ) {
      const page = await serveWebsetup(env, path, cors);
      if (page) return page;
    }

    if (path === "/api/otas.json") {
      const objs = await listOtaObjects(env);
      const otas = objs.map((obj) => {
        const name = obj.key.split("/").pop();
        const safe = safeName(name);
        const origin = url.origin;
        const httpsUrl = new URL("/dl/" + safe, origin);
        httpsUrl.protocol = "https:";
        const httpUrl = new URL(httpsUrl.href);
        httpUrl.protocol = "http:";
        return {
          url: httpsUrl.href,
          robotUrl: httpUrl.href,
          name: name,
          size: obj.size,
          uploaded: obj.uploaded,
          source: "r2",
          key: obj.key,
        };
      });
      if (otas.length) {
        const latestHttps = new URL("/ota/latest", url.origin);
        latestHttps.protocol = "https:";
        const latestHttp = new URL(latestHttps.href);
        latestHttp.protocol = "http:";
        otas.unshift({
          url: latestHttps.href,
          robotUrl: latestHttp.href,
          name: "Seek OS (latest)",
          size: objs[0].size,
          uploaded: objs[0].uploaded,
          source: "r2",
          key: "latest",
        });
      }
      return new Response(JSON.stringify({ seek: otas }, null, 2), {
        headers: {
          ...cors,
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store",
        },
      });
    }

    // Newest OTA — shortest possible URL for BLE
    if (path === "/ota/latest" || path === "/latest.ota") {
      const objs = await listOtaObjects(env);
      if (!objs.length) {
        return new Response("No .ota in R2", { status: 404, headers: cors });
      }
      return serveOtaKey(
        env,
        objs[0].key,
        request,
        cors,
        objs[0].key.split("/").pop(),
        objs[0].size || 0
      );
    }

    // Clean download alias: /dl/seek-os-3.01.42d.ota
    const dl = path.match(/^\/dl\/([^/]+)$/i);
    if (dl) {
      const want = safeName(decodeURIComponent(dl[1]));
      const objs = await listOtaObjects(env);
      const match = objs.find((o) => safeName(o.key.split("/").pop()) === want);
      if (!match) {
        return new Response("Not found: /dl/" + want, {
          status: 404,
          headers: cors,
        });
      }
      return serveOtaKey(
        env,
        match.key,
        request,
        cors,
        match.key.split("/").pop(),
        match.size || 0
      );
    }

    // Raw R2 key path (files only — not directories)
    if (!path.endsWith("/")) {
      const key = path.replace(/^\/+/, "");
      let decoded = key;
      try {
        decoded = decodeURIComponent(key);
      } catch (e) {}
      if (decoded.toLowerCase().startsWith("websetup/")) {
        return new Response("Not found: " + key, {
          status: 404,
          headers: cors,
        });
      }
      const objHead =
        (await env.OTA.head(decoded)) ||
        (decoded !== key ? await env.OTA.head(key) : null);
      if (!objHead) {
        return new Response("Not found: " + key, {
          status: 404,
          headers: cors,
        });
      }
      const realKey = objHead.key || decoded;
      return serveOtaKey(
        env,
        realKey,
        request,
        cors,
        decoded.split("/").pop(),
        objHead.size || 0
      );
    }

    // Directory listing (e.g. /OTA/)
    return directoryListing(env, path, cors);
  },
};
