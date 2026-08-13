/**
 * Seek OTA file host Worker
 * - GET /OTA/ or /          → white "Index of" listing
 * - GET /api/otas.json      → JSON list for websetup auto-menu
 * - GET /OTA/foo.ota        → download file from R2
 * - GET /fetch?url=https://… → proxy (follows redirects) for Vector BLE OTA
 *
 * Bind R2 bucket as env.OTA
 * Put files under prefix OTA/  e.g. OTA/vicos-3.0.1.42d.ota
 */
export default {
  async fetch(request, env) {
    if (!env.OTA) {
      return new Response("R2 binding missing: add binding named OTA", {
        status: 500,
      });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
      "Access-Control-Allow-Headers": "*",
    };
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: cors });
    }

    // Proxy GitHub (or any https) OTA so Vector's update-engine gets HTTP 200
    // with Content-Length — it dies on GitHub's 302 redirects.
    if (path === "/fetch") {
      const src = url.searchParams.get("url") || "";
      if (!/^https:\/\//i.test(src) || !/\.ota(\?|$)/i.test(src)) {
        return new Response("usage: /fetch?url=https://…/file.ota", {
          status: 400,
          headers: cors,
        });
      }
      let upstream;
      try {
        upstream = await fetch(src, {
          method: request.method === "HEAD" ? "HEAD" : "GET",
          redirect: "follow",
          headers: {
            "user-agent": "SeekOS-OTA-Proxy/1",
            ...(request.headers.get("range")
              ? { range: request.headers.get("range") }
              : {}),
          },
        });
      } catch (e) {
        return new Response("upstream fetch failed: " + e, {
          status: 502,
          headers: cors,
        });
      }
      if (!upstream.ok && upstream.status !== 206) {
        return new Response(
          "upstream HTTP " + upstream.status + " for " + src,
          { status: 502, headers: cors }
        );
      }
      const headers = new Headers(cors);
      const cl = upstream.headers.get("content-length");
      if (cl) headers.set("content-length", cl);
      const cr = upstream.headers.get("content-range");
      if (cr) headers.set("content-range", cr);
      const ar = upstream.headers.get("accept-ranges");
      headers.set("accept-ranges", ar || "bytes");
      headers.set("content-type", "application/octet-stream");
      headers.set("cache-control", "no-store");
      const name = src.split("/").pop().split("?")[0] || "update.ota";
      headers.set("content-disposition", 'inline; filename="' + name + '"');
      if (request.method === "HEAD") {
        return new Response(null, { status: upstream.status, headers });
      }
      return new Response(upstream.body, { status: upstream.status, headers });
    }

    // JSON API for Seek websetup (+ GitHub releases merged in)
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

      // Also list GitHub Seek releases, rewritten through /fetch so BLE works.
      try {
        const gh = await fetch(
          "https://api.github.com/repos/loganstorm1254-sudo/seek-cfw/releases?per_page=40",
          {
            headers: {
              accept: "application/vnd.github+json",
              "user-agent": "SeekOS-OTA-Proxy/1",
            },
          }
        );
        if (gh.ok) {
          const releases = await gh.json();
          for (const rel of releases || []) {
            for (const asset of rel.assets || []) {
              const name = asset.name || "";
              if (!name.toLowerCase().endsWith(".ota")) continue;
              if (seen.has("gh:" + name)) continue;
              seen.add("gh:" + name);
              const direct = asset.browser_download_url;
              otas.push({
                url:
                  url.origin +
                  "/fetch?url=" +
                  encodeURIComponent(direct),
                name: name,
                size: asset.size,
                uploaded: asset.updated_at || rel.published_at,
                source: "github",
              });
            }
          }
        }
      } catch (e) {
        // R2-only is fine if GitHub is unreachable from the Worker.
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

    // File download from R2
    if (!path.endsWith("/")) {
      const key = path.replace(/^\/+/, "");
      if (!key) return Response.redirect(url.origin + "/", 302);
      const obj = await env.OTA.get(key);
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
      if (key.toLowerCase().endsWith(".ota")) {
        headers.set("content-type", "application/octet-stream");
        // inline — update-engine wants a normal file body, not an "attachment"
        headers.set(
          "content-disposition",
          'inline; filename="' + key.split("/").pop() + '"'
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
        `<a href="/${obj.key}">${name}</a>` +
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
