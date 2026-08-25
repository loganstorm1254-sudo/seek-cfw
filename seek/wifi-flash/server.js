#!/usr/bin/env node
'use strict';

const express = require('express');
const multer = require('multer');
const { Client } = require('ssh2');
const path = require('path');
const fs = require('fs');

const PORT = Number(process.env.PORT || 3847);
const GITHUB_REPO = process.env.SEEK_GITHUB_REPO || 'loganstorm1254-sudo/seek-cfw';
const TAG_FILTER = process.env.SEEK_TAG_FILTER || '-dvt';

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 256 * 1024 } });
const app = express();

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

async function fetchDvtReleases() {
  const url = `https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=40`;
  const res = await fetch(url, { headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'seek-wifi-flash' } });
  if (!res.ok) throw new Error(`GitHub API ${res.status}`);
  const list = await res.json();
  if (!Array.isArray(list)) return [];
  return list
    .filter((r) => r.tag_name && r.tag_name.includes(TAG_FILTER))
    .map((r) => {
      const ota = (r.assets || []).find((a) => /\.ota$/i.test(a.name) && !/\.sha256$/i.test(a.name));
      const flash = (r.assets || []).find((a) => /unlock-manual-flash/i.test(a.name));
      if (!ota) return null;
      return {
        tag: r.tag_name,
        label: r.name || r.tag_name,
        otaUrl: ota.browser_download_url,
        otaSize: ota.size,
        flashScriptUrl: flash
          ? flash.browser_download_url
          : `https://github.com/${GITHUB_REPO}/releases/download/${r.tag_name}/unlock-manual-flash-v2.sh`,
        htmlUrl: r.html_url,
      };
    })
    .filter(Boolean);
}

function buildRemoteScript(otaUrl, otaSize, flashUrl) {
  const q = (s) => s.replace(/'/g, "'\\''");
  return `set -e
mount -o remount,rw / 2>/dev/null || true
mkdir -p /data/ota /run/update-engine /cache
if [ ! -x /usr/bin/curl.anki ]; then
  cp -L /usr/bin/curl /usr/bin/curl.anki 2>/dev/null || cp /usr/bin/curl /usr/bin/curl.anki
  chmod 755 /usr/bin/curl.anki
fi
echo "OS now: $(getprop ro.anki.version 2>/dev/null || echo unknown)"
echo "Downloading OTA..."
/usr/bin/curl.anki -k -L --http1.1 -4 --fail -o /data/ota/v.ota '${q(otaUrl)}'
SZ=$(wc -c </data/ota/v.ota)
echo "size=$SZ (expect ${otaSize})"
[ "$SZ" = "${otaSize}" ] || { echo "OTA size mismatch"; exit 1; }
echo "Fetching flash script..."
/usr/bin/curl.anki -k -fsSL --http1.1 -4 -o /data/unlock-manual-flash-v2.sh '${q(flashUrl)}'
chmod 755 /data/unlock-manual-flash-v2.sh
echo "Flashing (eyes go dark, ~5-10 min)..."
sh /data/unlock-manual-flash-v2.sh /data/ota/v.ota
echo "Flash script finished — Vector should reboot."
`;
}

function sshFlash({ ip, privateKey, otaUrl, otaSize, flashScriptUrl, onData, onError, onClose }) {
  const conn = new Client();
  const script = buildRemoteScript(otaUrl, otaSize, flashScriptUrl);

  conn
    .on('ready', () => {
      onData('[connected] SSH OK\n');
      conn.exec(script, { pty: true }, (err, stream) => {
        if (err) {
          onError(err);
          conn.end();
          return;
        }
        stream.on('close', (code) => {
          onData(`\n[exit ${code}]\n`);
          onClose(code);
          conn.end();
        });
        stream.on('data', (d) => onData(d.toString()));
        stream.stderr.on('data', (d) => onData(d.toString()));
      });
    })
    .on('error', (err) => onError(err))
    .connect({
      host: ip,
      port: 22,
      username: 'root',
      privateKey,
      readyTimeout: 20000,
      algorithms: {
        serverHostKey: ['ssh-rsa', 'ssh-dss', 'ecdsa-sha2-nistp256', 'ssh-ed25519'],
        pubkey: ['ssh-rsa', 'ssh-dss', 'ecdsa-sha2-nistp256', 'ssh-ed25519'],
      },
    });

  return conn;
}

app.get('/api/releases', async (_req, res) => {
  try {
    const releases = await fetchDvtReleases();
    res.json({ ok: true, releases });
  } catch (e) {
    res.status(502).json({ ok: false, error: e.message });
  }
});

app.post('/api/flash', upload.single('key'), (req, res) => {
  const ip = (req.body.ip || '').trim();
  const otaUrl = (req.body.otaUrl || '').trim();
  const otaSize = String(req.body.otaSize || '').trim();
  const flashScriptUrl = (req.body.flashScriptUrl || '').trim();
  const keyFile = req.file;

  if (!ip) return res.status(400).json({ ok: false, error: 'IP required' });
  if (!keyFile || !keyFile.buffer?.length) return res.status(400).json({ ok: false, error: 'SSH private key file required' });
  if (!otaUrl || !otaSize || !flashScriptUrl) return res.status(400).json({ ok: false, error: 'Pick a release' });

  let privateKey;
  try {
    privateKey = keyFile.buffer.toString('utf8');
    if (!privateKey.includes('PRIVATE KEY')) throw new Error('not a PEM key');
  } catch (e) {
    return res.status(400).json({ ok: false, error: 'Invalid key file — use your ssh_root_key (OpenSSH PEM)' });
  }

  res.writeHead(200, {
    'Content-Type': 'text/plain; charset=utf-8',
    'Cache-Control': 'no-cache',
    'Transfer-Encoding': 'chunked',
  });

  const write = (msg) => {
    try { res.write(msg); } catch (_) { /* client gone */ }
  };

  write(`Seek Wi-Fi flash → ${ip}\n`);
  write(`OTA: ${otaUrl}\n\n`);

  sshFlash({
    ip,
    privateKey,
    otaUrl,
    otaSize,
    flashScriptUrl,
    onData: write,
    onError: (err) => write(`\n[SSH ERROR] ${err.message}\n`),
    onClose: (code) => {
      if (code === 0) write('\nDone. Wait for reboot, then http://' + ip + ':8080/dash.html\n');
      res.end();
    },
  });
});

app.listen(PORT, '127.0.0.1', () => {
  console.log('');
  console.log('  Seek Wi-Fi Flash');
  console.log(`  → http://127.0.0.1:${PORT}`);
  console.log('');
  console.log('  Same Wi-Fi as Vector. Upload SSH key, enter IP, flash from GitHub.');
  console.log('');
});
