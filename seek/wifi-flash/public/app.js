(function () {
  'use strict';

  var releases = [];
  var flashing = false;

  var $ = function (id) { return document.getElementById(id); };

  function log(msg, append) {
    var el = $('log');
    if (!el) return;
    el.textContent = append ? el.textContent + msg : msg;
    el.scrollTop = el.scrollHeight;
  }

  function selected() {
    var sel = $('releaseSelect');
    if (!sel || !sel.value) return null;
    return releases.find(function (r) { return r.tag === sel.value; });
  }

  function updateBtn() {
    var btn = $('btnFlash');
    if (!btn) return;
    btn.disabled = flashing || !selected() || !$('keyFile').files.length || !$('ip').value.trim();
  }

  function loadReleases() {
    var status = $('releaseStatus');
    var sel = $('releaseSelect');
    if (status) status.textContent = 'checking GitHub…';
    fetch('/api/releases')
      .then(function (r) { return r.json(); })
      .then(function (j) {
        if (!j.ok) throw new Error(j.error || 'API failed');
        releases = j.releases || [];
        sel.innerHTML = '';
        releases.forEach(function (rel, i) {
          var opt = document.createElement('option');
          opt.value = rel.tag;
          opt.textContent = rel.label + (i === 0 ? ' (latest)' : '');
          sel.appendChild(opt);
        });
        sel.disabled = !releases.length;
        if (status) status.textContent = releases.length + ' DVT release(s)';
        updateBtn();
      })
      .catch(function (e) {
        if (status) status.textContent = 'failed: ' + e.message;
        log('Could not load releases: ' + e.message + '\n', true);
      });
  }

  function flash() {
    if (flashing) return;
    var rel = selected();
    var ip = $('ip').value.trim();
    var key = $('keyFile').files[0];
    if (!rel || !ip || !key) return;

    flashing = true;
    updateBtn();
    log('Starting…\n');

    var fd = new FormData();
    fd.append('ip', ip);
    fd.append('otaUrl', rel.otaUrl);
    fd.append('otaSize', String(rel.otaSize));
    fd.append('flashScriptUrl', rel.flashScriptUrl);
    fd.append('key', key);

    fetch('/api/flash', { method: 'POST', body: fd })
      .then(function (res) {
        if (!res.ok) {
          return res.json().then(function (j) { throw new Error(j.error || res.statusText); });
        }
        var reader = res.body.getReader();
        var dec = new TextDecoder();
        function pump() {
          return reader.read().then(function (chunk) {
            if (chunk.done) {
              flashing = false;
              updateBtn();
              return;
            }
            log(dec.decode(chunk.value), true);
            return pump();
          });
        }
        return pump();
      })
      .catch(function (e) {
        log('\nError: ' + e.message + '\n', true);
        flashing = false;
        updateBtn();
      });
  }

  $('btnFlash').addEventListener('click', flash);
  $('btnRefresh').addEventListener('click', loadReleases);
  $('keyFile').addEventListener('change', updateBtn);
  $('ip').addEventListener('input', updateBtn);
  $('releaseSelect').addEventListener('change', updateBtn);

  loadReleases();
})();
