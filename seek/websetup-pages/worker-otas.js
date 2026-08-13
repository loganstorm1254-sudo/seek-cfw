/**
 * Seek OTA file host Worker
 * - GET /OTA/ or /         → directory index
 * - GET /api/otas.json     → JSON list of .ota files IN YOUR R2 BUCKET ONLY
 * - GET /OTA/foo.ota       → download from R2
 *
 * Bind R2 bucket as env.OTA
 * Put files under prefix OTA/  e.g. OTA/vicos-3.0.1.42d.ota
 *
 * Does NOT pull GitHub releases — only what you upload to R2.
 */
function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
    "Access-Control-Allow-Headers": "*",
  };
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
      const prefixes = ["OTA/", "ota/", ""];
      const seen = new Set();
      const otas = [];

      for (const prefix of prefixes) {
        let cursor;
        do {
          const listed = await env.OTA.list({ prefix, limit: 1000, cursor });
          for (const obj of listed.objects || []) {
            if (!obj.key.toLowerCase().endsWith(".ota")) continue;
            if (seen.has(obj.key)) continue;
            seen.add(obj.key);
            const name = obj.key.split("/").pop();
            otas.push({
              url: new URL("/" + obj.key, url.origin).href,
              name: name,
              size: obj.size,
              uploaded: obj.uploaded,
              source: "r2",
            });
          }
          cursor = listed.truncated ? listed.cursor : undefined;
        } while (cursor);
      }

      otas.sort((a, b) =>
        String(b.name).localeCompare(String(a.name), undefined, {
          numeric: true,
        })
      );
      return new Response(JSON.stringify({ seek: otas }, null, 2), {
        headers: {
          ...cors,
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store",
        },
      });
    }

    // R2 file download
    if (!path.endsWith("/")) {
      const key = path.replace(/^\/+/, "");
      if (!key) return Response.redirect(url.origin + "/", 302);
      // decode spaces etc. (e.g. "seek os 3.01.42d.ota")
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
      const headers = new Headers(cors);
      obj.writeHttpMetadata(headers);
      headers.set("etag", obj.httpEtag);
      headers.set("accept-ranges", "bytes");
      if (decoded.toLowerCase().endsWith(".ota") || key.toLowerCase().endsWith(".ota")) {
        headers.set("content-type", "application/octet-stream");
        headers.set(
          "content-disposition",
          'inline; filename="' + decoded.split("/").pop() + '"'
        );
      }
      if (obj.size != null) headers.set("content-length", String(obj.size));
      return new Response(obj.body, { headers });
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
      rows.push(
        `<a href="/${encodeURI(obj.key)}">${name}</a>` +
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
