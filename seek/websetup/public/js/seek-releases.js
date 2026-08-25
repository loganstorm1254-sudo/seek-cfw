/* Seek websetup — fetch DVT releases from GitHub API, version picker for all install paths */
(function () {
  'use strict';

  var baseCfg = null;
  var releases = [];
  var selected = null;
  var readyResolve;
  var readyReject;

  window.SeekReleases = {
    ready: new Promise(function (resolve, reject) {
      readyResolve = resolve;
      readyReject = reject;
    }),
    releases: function () { return releases.slice(); },
    getSelected: function () { return selected; },
    getConfig: function () { return window.SEEK_CONFIG || null; },
    refresh: loadAll
  };

  function $(id) { return document.getElementById(id); }

  function parseRelease(r) {
    var otaAsset = r.assets.find(function (x) {
      return /\.ota$/i.test(x.name) && !/\.sha256$/i.test(x.name);
    });
    if (!otaAsset) return null;
    var flash = r.assets.find(function (x) { return /unlock-manual-flash/i.test(x.name); });
    var ver = r.tag_name.replace(/^v/, '').replace(/-dvt$/i, '');
    return {
      tag: r.tag_name,
      version: ver,
      label: r.name || r.tag_name,
      notes: (r.body || '').split('\n').filter(Boolean)[0] || '',
      publishedAt: r.published_at,
      prerelease: !!r.prerelease,
      otaUrl: otaAsset.browser_download_url,
      otaSize: otaAsset.size,
      flashScriptUrl: flash
        ? flash.browser_download_url
        : 'https://github.com/' + (baseCfg.githubRepo || 'loganstorm1254-sudo/seek-cfw') +
          '/releases/download/' + r.tag_name + '/unlock-manual-flash-v2.sh',
      htmlUrl: r.html_url
    };
  }

  function fetchGithubReleases() {
    var repo = baseCfg.githubRepo || 'loganstorm1254-sudo/seek-cfw';
    var filter = baseCfg.releaseTagFilter || '-dvt';
    return fetch('https://api.github.com/repos/' + repo + '/releases?per_page=40', {
      headers: { Accept: 'application/vnd.github+json' },
      cache: 'no-store'
    })
      .then(function (r) {
        if (!r.ok) throw new Error('GitHub API ' + r.status);
        return r.json();
      })
      .then(function (list) {
        if (!Array.isArray(list)) return [];
        return list
          .filter(function (rel) { return rel.tag_name && rel.tag_name.indexOf(filter) !== -1; })
          .map(parseRelease)
          .filter(Boolean);
      });
  }

  function applySelected(rel) {
    if (!rel) return;
    selected = rel;
    window.SEEK_CONFIG = {
      channel: baseCfg.channel || 'dvt',
      githubRepo: baseCfg.githubRepo,
      releaseTagFilter: baseCfg.releaseTagFilter,
      version: rel.version,
      label: rel.label,
      notes: rel.notes,
      otaUrl: rel.otaUrl,
      otaSize: rel.otaSize,
      flashScriptUrl: rel.flashScriptUrl,
      tag: rel.tag,
      repo: baseCfg.repo,
      releasesPage: baseCfg.releasesPage,
      websetupZipUrl: baseCfg.websetupZipUrl
    };
    try {
      localStorage.setItem('seek-setup-tag', rel.tag);
    } catch (e) { /* ignore */ }
    updateUi();
    document.dispatchEvent(new CustomEvent('seek-release-changed', { detail: rel }));
  }

  function updateUi() {
    if (!selected) return;
    var v = $('cfgVersion');
    if (v) v.textContent = selected.label || selected.version;
    var notes = $('releaseNotes');
    if (notes) notes.textContent = selected.notes || '';
    var otaBle = $('cfgOtaUrlBle');
    var otaWifi = $('cfgOtaUrl');
    if (otaBle) otaBle.textContent = selected.otaUrl;
    if (otaWifi) otaWifi.textContent = selected.otaUrl;
    var sizeEl = $('cfgOtaSize');
    if (sizeEl) sizeEl.textContent = String(selected.otaSize);
    var link = $('cfgReleaseLink');
    if (link) {
      link.href = selected.htmlUrl || baseCfg.releasesPage;
      link.textContent = selected.tag;
    }
    var env = $('vecEnv');
    if (env) env.textContent = selected.version;
    var status = $('releaseStatus');
    if (status) {
      status.textContent = releases.length + ' DVT release(s) from GitHub · selected ' + selected.tag;
      status.className = 'seek-note';
    }
  }

  function populateSelect() {
    var sel = $('releaseSelect');
    if (!sel) return;
    sel.innerHTML = '';
    releases.forEach(function (rel, i) {
      var opt = document.createElement('option');
      opt.value = rel.tag;
      var badge = i === 0 ? ' (latest)' : '';
      opt.textContent = rel.label + badge + ' — ' + rel.tag;
      sel.appendChild(opt);
    });
    var want = selected ? selected.tag : (baseCfg.defaultTag || (releases[0] && releases[0].tag));
    try {
      var saved = localStorage.getItem('seek-setup-tag');
      if (saved && releases.some(function (r) { return r.tag === saved; })) want = saved;
    } catch (e) { /* ignore */ }
    if (want) sel.value = want;
    var pick = releases.find(function (r) { return r.tag === sel.value; }) || releases[0];
    applySelected(pick);
  }

  function loadAll() {
    var status = $('releaseStatus');
    if (status) {
      status.textContent = 'Checking GitHub for DVT releases…';
      status.className = 'seek-note';
    }
    return fetch('/config.json', { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (cfg) {
        baseCfg = cfg;
        var zip = $('websetupDownload');
        var zipFoot = $('websetupDownloadFooter');
        if (cfg.websetupZipUrl) {
          if (zip) { zip.href = cfg.websetupZipUrl; zip.hidden = false; }
          if (zipFoot) { zipFoot.href = cfg.websetupZipUrl; }
        }
        return fetchGithubReleases();
      })
      .then(function (list) {
        releases = list;
        if (!releases.length) throw new Error('No DVT releases found on GitHub');
        populateSelect();
        return selected;
      })
      .catch(function (err) {
        if (status) {
          status.textContent = 'GitHub unavailable — using bundled fallback.';
          status.className = 'seek-note seek-note-err';
        }
        if (baseCfg && baseCfg.fallbackRelease) {
          releases = [baseCfg.fallbackRelease];
          populateSelect();
          return selected;
        }
        throw err;
      });
  }

  document.addEventListener('DOMContentLoaded', function () {
    var sel = $('releaseSelect');
    if (sel) {
      sel.addEventListener('change', function () {
        var rel = releases.find(function (r) { return r.tag === sel.value; });
        if (rel) applySelected(rel);
      });
    }
    var btn = $('btnRefreshReleases');
    if (btn) {
      btn.addEventListener('click', function () {
        btn.disabled = true;
        loadAll()
          .catch(function () {})
          .finally(function () { btn.disabled = false; });
      });
    }

    loadAll()
      .then(function () { readyResolve(window.SEEK_CONFIG); })
      .catch(function (err) {
        readyReject(err);
        readyResolve(window.SEEK_CONFIG || baseCfg || {});
      });
  });
})();
