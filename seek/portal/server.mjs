#!/usr/bin/env node
/**
 * Seek portal: HTTPS-friendly host for the Vector dashboard.
 *
 * Phone (any browser) → this site → Vector
 *   1. Same Wi‑Fi as this server: reverse-proxies http://VECTOR_IP:8080
 *   2. Hosted on the internet: Vector connects outbound (wss://host/vector)
 *
 * Login: Vector LAN IP + Wi‑Fi SSID (must match the robot).
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(__dirname, 'public');
const PORT = Number(process.env.PORT || 8787);
const COOKIE = 'SeekBot';

const vectors = new Map(); // ip -> { ws, ssid, esn, seen }

function parseCookie(req) {
  const raw = req.headers.cookie || '';
  const m = raw.match(new RegExp('(?:^|; )' + COOKIE + '=([^;]*)'));
  if (!m) return null;
  try {
    const [ip, ssid] = decodeURIComponent(m[1]).split('|');
    if (!ip) return null;
    return { ip: ip.trim(), ssid: (ssid || '').trim() };
  } catch {
    return null;
  }
}

function setSession(res, ip, ssid) {
  const v = encodeURIComponent(ip + '|' + ssid);
  res.setHeader('Set-Cookie', `${COOKIE}=${v}; Path=/; SameSite=Lax; Max-Age=2592000`);
}

function norm(s) {
  return String(s || '').trim().toLowerCase();
}

function ssidOk(got, want) {
  if (!want) return false;
  if (!got) return true; // older robots may not report SSID
  return norm(got) === norm(want);
}

function sendJson(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(obj));
}

function servePublic(req, res) {
  let p = req.url.split('?')[0];
  if (p === '/' || p === '') p = '/index.html';
  const full = path.normalize(path.join(PUBLIC, p));
  if (!full.startsWith(PUBLIC)) {
    res.writeHead(403);
    res.end('forbidden');
    return;
  }
  fs.readFile(full, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('not found');
      return;
    }
    const ext = path.extname(full);
    const types = {
      '.html': 'text/html; charset=utf-8',
      '.css': 'text/css; charset=utf-8',
      '.js': 'application/javascript; charset=utf-8',
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.svg': 'image/svg+xml',
      '.json': 'application/json',
    };
    res.writeHead(200, { 'Content-Type': types[ext] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(data);
  });
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let n = 0;
    req.on('data', (c) => {
      n += c.length;
      if (n > limit) {
        reject(new Error('too large'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function parseForm(buf) {
  const out = {};
  const s = buf.toString('utf8');
  for (const part of s.split('&')) {
    if (!part) continue;
    const [k, v] = part.split('=');
    out[decodeURIComponent((k || '').replace(/\+/g, ' '))] = decodeURIComponent((v || '').replace(/\+/g, ' '));
  }
  return out;
}

function directProxy(sess, req, res, robotPath) {
  const opts = {
    hostname: sess.ip,
    port: 8080,
    path: robotPath,
    method: req.method,
    headers: { ...req.headers, host: sess.ip + ':8080' },
    timeout: 25000,
  };
  delete opts.headers['cookie'];
  const p = http.request(opts, (pr) => {
    const hdrs = { ...pr.headers };
    delete hdrs['transfer-encoding'];
    res.writeHead(pr.statusCode || 502, hdrs);
    pr.pipe(res);
  });
  p.on('timeout', () => p.destroy());
  p.on('error', () => {
    if (!res.headersSent) sendJson(res, 502, { status: 'error', message: 'Cannot reach Vector at ' + sess.ip + ':8080 from this host. Put the portal on the same Wi‑Fi, or save the portal URL on Vector (Look tab).' });
  });
  req.pipe(p);
}

let reqSeq = 0;
function tunnelProxy(entry, req, res, robotPath) {
  const id = String(++reqSeq);
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const msg = {
      t: 'http',
      id,
      method: req.method,
      path: robotPath,
      header: { 'Content-Type': req.headers['content-type'] || '' },
      body: body.length ? body.toString('base64') : '',
    };
    const timer = setTimeout(() => {
      entry.pending.delete(id);
      if (!res.headersSent) sendJson(res, 504, { status: 'error', message: 'Vector tunnel timed out' });
    }, 60000);
    entry.pending.set(id, { res, timer });
    try {
      entry.ws.send(JSON.stringify(msg));
    } catch (e) {
      clearTimeout(timer);
      entry.pending.delete(id);
      if (!res.headersSent) sendJson(res, 502, { status: 'error', message: 'Vector tunnel closed' });
    }
  });
  req.on('error', () => {
    if (!res.headersSent) sendJson(res, 502, { status: 'error', message: 'read failed' });
  });
}

const server = http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://localhost');

  if (req.method === 'GET' && (u.pathname === '/' || u.pathname === '/index.html' || u.pathname === '/login')) {
    servePublic({ url: '/index.html' }, res);
    return;
  }

  if (req.method === 'POST' && u.pathname === '/connect') {
    let ip = '';
    let ssid = '';
    try {
      const buf = await readBody(req, 64 << 10);
      const ct = req.headers['content-type'] || '';
      if (ct.includes('json')) {
        const j = JSON.parse(buf.toString() || '{}');
        ip = String(j.ip || '').trim();
        ssid = String(j.ssid || '').trim();
      } else {
        const f = parseForm(buf);
        ip = String(f.ip || '').trim();
        ssid = String(f.ssid || '').trim();
      }
    } catch (e) {
      sendJson(res, 400, { status: 'error', message: 'bad form' });
      return;
    }
    ip = ip.replace(/^https?:\/\//, '').replace(/\/.*$/, '').replace(/:8080$/, '');
    if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) {
      sendJson(res, 400, { status: 'error', message: 'Enter Vector’s Wi‑Fi IPv4 address (example 192.168.42.209).' });
      return;
    }
    if (!ssid) {
      sendJson(res, 400, { status: 'error', message: 'Enter the Wi‑Fi name (SSID) Vector is on.' });
      return;
    }

    const tun = vectors.get(ip);
    if (tun && tun.ws && tun.ws.readyState === 1) {
      if (!ssidOk(tun.ssid, ssid)) {
        sendJson(res, 403, { status: 'error', message: 'SSID does not match this Vector.' });
        return;
      }
      setSession(res, ip, ssid);
      sendJson(res, 200, { status: 'success', via: 'tunnel', redirect: '/v/seek.html' });
      return;
    }

    // Direct LAN probe
    const probe = http.get({ hostname: ip, port: 8080, path: '/api/netinfo', timeout: 4000 }, (pr) => {
      const chunks = [];
      pr.on('data', (c) => chunks.push(c));
      pr.on('end', () => {
        let robotSsid = '';
        try {
          const j = JSON.parse(Buffer.concat(chunks).toString() || '{}');
          robotSsid = j.ssid || '';
        } catch {}
        if (!ssidOk(robotSsid, ssid)) {
          sendJson(res, 403, { status: 'error', message: 'SSID does not match this Vector (robot is on “' + (robotSsid || 'unknown') + '”).' });
          return;
        }
        setSession(res, ip, ssid);
        sendJson(res, 200, { status: 'success', via: 'direct', redirect: '/v/seek.html' });
      });
    });
    probe.on('timeout', () => probe.destroy());
    probe.on('error', () => {
      sendJson(res, 502, {
        status: 'error',
        message: 'Cannot reach ' + ip + ':8080 from this server. If this site is on the internet, open Seek on Vector → Look → save this portal URL (wss://' + (req.headers.host || 'your-host') + '/vector), wait until it says connected, then try again.',
      });
    });
    return;
  }

  if (u.pathname.startsWith('/v/')) {
    const sess = parseCookie(req);
    if (!sess) {
      res.writeHead(302, { Location: '/' });
      res.end();
      return;
    }
    const robotPath = u.pathname.slice('/v'.length) + u.search;
    const tun = vectors.get(sess.ip);
    if (tun && tun.ws && tun.ws.readyState === 1 && ssidOk(tun.ssid, sess.ssid)) {
      tunnelProxy(tun, req, res, robotPath);
      return;
    }
    directProxy(sess, req, res, robotPath);
    return;
  }

  servePublic(req, res);
});

const wss = new WebSocketServer({ server, path: '/vector' });
wss.on('connection', (ws) => {
  let ip = '';
  ws.on('message', (data) => {
    let msg;
    try {
      msg = JSON.parse(String(data));
    } catch {
      return;
    }
    if (msg.t === 'hello' && msg.ip) {
      ip = String(msg.ip);
      const prev = vectors.get(ip);
      if (prev && prev.pending) {
        for (const [, p] of prev.pending) {
          clearTimeout(p.timer);
          if (!p.res.headersSent) sendJson(p.res, 502, { status: 'error', message: 'Vector reconnected' });
        }
      }
      vectors.set(ip, { ws, ssid: msg.ssid || '', esn: msg.esn || '', seen: Date.now(), pending: new Map() });
      console.log('vector online', ip, msg.ssid || '');
      return;
    }
    if (msg.t === 'pong') return;
    if (msg.t === 'http-res' && ip) {
      const entry = vectors.get(ip);
      if (!entry) return;
      const pending = entry.pending.get(msg.id);
      if (!pending) return;
      entry.pending.delete(msg.id);
      clearTimeout(pending.timer);
      const buf = msg.body ? Buffer.from(msg.body, 'base64') : Buffer.alloc(0);
      const headers = { 'Cache-Control': 'no-store' };
      if (msg.header && msg.header['Content-Type']) headers['Content-Type'] = msg.header['Content-Type'];
      if (msg.err && !buf.length) {
        sendJson(pending.res, msg.status || 502, { status: 'error', message: msg.err });
        return;
      }
      pending.res.writeHead(msg.status || 200, headers);
      pending.res.end(buf);
    }
  });
  ws.on('close', () => {
    if (ip && vectors.get(ip)?.ws === ws) {
      vectors.delete(ip);
      console.log('vector offline', ip);
    }
  });
  const ping = setInterval(() => {
    if (ws.readyState === 1) {
      try { ws.send(JSON.stringify({ t: 'ping' })); } catch {}
    }
  }, 20000);
  ws.on('close', () => clearInterval(ping));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('Seek portal http://0.0.0.0:' + PORT);
});
