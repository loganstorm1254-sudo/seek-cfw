/**
 * Seek OTA + Web Setup Worker (files.anki.org.uk)
 *
 * Web UI (Chrome):
 *   GET /              → R2 websetup/index.html (Seek Web Setup seek16+)
 *   GET /static/...    → R2 websetup/static/...
 *
 * OTA (Vector BLE — plain HTTP only):
 *   GET /api/otas.json → R2 .ota list (url=https, robotUrl=http)
 *   GET /ota/latest    → newest .ota
 *   GET /dl/<name>     → ASCII download alias
 *   GET /OTA/...       → raw R2 key
 *
 * Bind R2 as OTA. Keep HTTP working on /ota and /dl (no Always-HTTPS on those).
 * After every UI change: upload seek/websetup-pages → R2 prefix websetup/
 *   node seek/websetup-pages/deploy-cloudflare.mjs
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
  if (p.endsWith(".txt")) return "text/plain; charset=utf-8";
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

/** Serve Seek Web Setup UI from R2 keys under websetup/ */
async function serveWebsetup(env, urlPath, cors) {
  let rel = urlPath === "/" ? "/index.html" : urlPath;
  if (rel === "/setup" || rel === "/setup/") rel = "/index.html";
  if (!rel.startsWith("/")) rel = "/" + rel;
  // Only allow index + static assets (never OTA keys via this helper).
  if (rel !== "/index.html" && !rel.startsWith("/static/")) {
    return null;
  }
  const key = "websetup" + rel;
  const obj = await env.OTA.get(key);
  if (!obj) {
    return new Response(
      "Websetup UI missing in R2 (" +
        key +
        "). Upload with: node seek/websetup-pages/deploy-cloudflare.mjs",
      { status: 404, headers: { ...cors, "content-type": "text/plain; charset=utf-8" } }
    );
  }
  const headers = new Headers(cors);
  headers.set("content-type", contentTypeFor(rel));
  if (rel === "/index.html" || rel.endsWith(".js") || rel.endsWith(".css")) {
    headers.set("cache-control", "no-cache");
  } else {
    headers.set("cache-control", "public, max-age=3600");
  }
  if (obj.size != null) headers.set("content-length", String(obj.size));
  return new Response(obj.body, { headers });
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

    // ---- Seek Web Setup UI (same host as OTA) ----
    if (
      path === "/" ||
      path === "/index.html" ||
      path === "/setup" ||
      path === "/setup/" ||
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
      if (!key) {
        const page = await serveWebsetup(env, "/", cors);
        if (page) return page;
      }
      let decoded = key;
      try {
        decoded = decodeURIComponent(key);
      } catch (e) {}
      // Never treat websetup UI paths as raw OTA keys here (already handled).
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
    const prefix = path.replace(/^\/+/, "");
    const listed = await env.OTA.list({ prefix, delimiter: "/" });
    const rows = [];
    for (const p of listed.delimitedPrefixes || []) {
      const name = p.slice(prefix.length);
      rows.push(`<a href="/${p}">${name}</a>`);
    }
    for (const obj of listed.objects || []) {
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
    const title = "Index of " + path;
    const html = `<!DOCTYPE html>
<html><head><title>${title}</title></head>
<body bgcolor="white">
<h1>${title}</h1><hr><pre><a href="../">../</a>
${rows.join("\n")}
</pre><hr></body></html>`;
    return new Response(html, {
      headers: { ...cors, "content-type": "text/html; charset=utf-8" },
    });
  },
};
