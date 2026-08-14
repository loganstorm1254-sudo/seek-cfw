/**
 * Seek OTA file host Worker
 * - GET /api/otas.json  → R2 .ota files (url=https for Chrome, robotUrl=http for Vector)
 * Vector cannot verify TLS (status 203). Keep HTTP working on /ota and /dl
 * (do not Always-HTTPS-redirect those paths).
 * - GET /OTA/...        → raw R2 key
 * - GET /ota/latest     → newest .ota (safe for Vector BLE)
 * - GET /dl/<safe-name> → same file via ASCII-only path
 *
 * Bind R2 as OTA. Upload under OTA/ preferably without spaces in the name.
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
  headers.set("alt-svc", "clear");
  headers.set("cache-control", "public, max-age=86400");
  return headers;
}
  const headers = new Headers(cors);
  obj.writeHttpMetadata(headers);
  headers.set("etag", obj.httpEtag);
  headers.set("accept-ranges", "bytes");
  headers.set("content-type", "application/octet-stream");
  const fname = safeName(downloadName || "update.ota");
  headers.set("content-disposition", 'inline; filename="' + fname + '"');
  if (obj.size != null) headers.set("content-length", String(obj.size));
  // Old Vector curl stalls if the edge advertises HTTP/3.
  headers.set("alt-svc", "clear");
  headers.set("cache-control", "public, max-age=86400");
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
      const obj = await env.OTA.get(objs[0].key);
      if (!obj) {
        return new Response("Missing object", { status: 404, headers: cors });
      }
      if (request.method === "HEAD") {
        return new Response(null, {
          headers: otaHeadHeaders(cors, objs[0].size || obj.size || 0),
        });
      }
      return otaResponse(obj, cors, objs[0].key.split("/").pop());
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
      const obj = await env.OTA.get(match.key);
      if (!obj) {
        return new Response("Missing object", { status: 404, headers: cors });
      }
      if (request.method === "HEAD") {
        return new Response(null, {
          headers: otaHeadHeaders(cors, match.size || obj.size || 0),
        });
      }
      return otaResponse(obj, cors, match.key.split("/").pop());
    }

    // Raw R2 key path
    if (!path.endsWith("/")) {
      const key = path.replace(/^\/+/, "");
      if (!key) return Response.redirect(url.origin + "/", 302);
      let decoded = key;
      try {
        decoded = decodeURIComponent(key);
      } catch (e) {}
      const obj =
        (await env.OTA.get(decoded)) ||
        (decoded !== key ? await env.OTA.get(key) : null);
      if (!obj) {
        return new Response("Not found: " + key, {
          status: 404,
          headers: cors,
        });
      }
      if (request.method === "HEAD") {
        return new Response(null, {
          headers: otaHeadHeaders(cors, obj.size),
        });
      }
      return otaResponse(obj, cors, decoded.split("/").pop());
    }

    // Directory listing
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
