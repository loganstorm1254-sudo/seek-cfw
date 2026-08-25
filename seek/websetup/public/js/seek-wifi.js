/* Seek websetup — Wi-Fi upgrade + SSH (uses SeekReleases for OTA URL) */
(function () {
  'use strict';

  var pollTimer = null;

  function $(id) { return document.getElementById(id); }

  function cfg() {
    return (window.SeekReleases && window.SeekReleases.getConfig()) || window.SEEK_CONFIG || null;
  }

  function note(msg, isErr) {
    var el = $('wifiFlashStatus');
    if (el) {
      el.textContent = msg;
      el.className = 'seek-note' + (isErr ? ' seek-note-err' : '');
    }
  }

  function robotBase(ip) {
    ip = (ip || '').trim().replace(/^https?:\/\//, '').replace(/\/.*$/, '');
    return 'http://' + ip + ':8080/api/mods/SeekDashboard';
  }

  function fillSshCommand() {
    var c = cfg();
    if (!c || !c.otaUrl) return;
    var el = $('sshCommand');
    if (!el) return;
    var ip = ($('sshRobotIp') && $('sshRobotIp').value.trim()) || '192.168.43.3';
    el.value =
      'ssh root@' + ip + ' -i %USERPROFILE%\\Downloads\\ssh_root_key ' +
      '-o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostkeyAlgorithms=+ssh-rsa ' +
      '-o StrictHostKeyChecking=no -t "mount -o remount,rw /; mkdir -p /data/ota; ' +
      '[ -x /usr/bin/curl.anki ]||cp -L /usr/bin/curl /usr/bin/curl.anki; chmod 755 /usr/bin/curl.anki; ' +
      '/usr/bin/curl.anki -k -L --http1.1 -4 --fail -o /data/ota/v.ota \'' + c.otaUrl + '\'; ' +
      'SZ=$(wc -c </data/ota/v.ota); echo size=$SZ; [ \\\"$SZ\\\" = \\\"' + c.otaSize + '\\\" ]||exit 1; ' +
      '/usr/bin/curl.anki -k -fsSL --http1.1 -4 -o /data/unlock-manual-flash-v2.sh \'' + c.flashScriptUrl + '\'; ' +
      'sh /data/unlock-manual-flash-v2.sh /data/ota/v.ota"';
    var sizeNote = $('sshSizeNote');
    if (sizeNote) sizeNote.textContent = 'Verifies OTA size ' + c.otaSize + ' bytes before flash.';
  }

  function pollOta(ip) {
    fetch(robotBase(ip) + '/otaStatus', { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (j) {
        if (j.error || j.engineError) {
          note('Flash failed: ' + (j.error || j.engineError), true);
          stopPoll();
          return;
        }
        if (j.phase === 'rebooting') {
          note('Done — Vector is rebooting. Wait ~2 min, then open http://' + ip + ':8080/dash.html');
          stopPoll();
          return;
        }
        var pct = typeof j.pct === 'number' ? j.pct : 0;
        var bar = $('wifiFlashBar');
        if (bar) {
          bar.hidden = false;
          bar.value = Math.max(0, Math.min(100, pct));
        }
        note(j.detail || j.phase || ('Flashing… ' + pct + '%'));
      })
      .catch(function () {
        note('Lost contact — Vector may be rebooting. Wait ~2 min.');
      });
  }

  function stopPoll() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function startWifiFlash() {
    var ip = ($('wifiRobotIp') && $('wifiRobotIp').value.trim()) || '';
    var c = cfg();
    if (!ip) {
      note('Enter Vector\'s Wi‑Fi IP (same network as this phone/PC).', true);
      return;
    }
    if (!c || !c.otaUrl) {
      note('Pick a release first (or wait for GitHub check).', true);
      return;
    }
    stopPoll();
    note('Flashing ' + (c.label || c.version) + ' from GitHub…');
    var bar = $('wifiFlashBar');
    if (bar) { bar.hidden = false; bar.value = 0; }

    fetch(robotBase(ip) + '/otaFromUrl?url=' + encodeURIComponent(c.otaUrl), {
      method: 'POST',
      cache: 'no-store'
    })
      .then(function (r) {
        if (!r.ok) {
          return r.json().catch(function () { return {}; }).then(function (e) {
            throw new Error(e.message || ('HTTP ' + r.status));
          });
        }
        note('update-os running — polling progress…');
        pollTimer = setInterval(function () { pollOta(ip); }, 2500);
        pollOta(ip);
      })
      .catch(function (e) {
        note('Could not reach Vector at ' + ip + ':8080 — ' + e.message, true);
      });
  }

  function copySsh() {
    fillSshCommand();
    var el = $('sshCommand');
    if (!el) return;
    el.select();
    el.setSelectionRange(0, 99999);
    try {
      navigator.clipboard.writeText(el.value);
      note('SSH one-liner copied.');
    } catch (e) {
      document.execCommand('copy');
      note('Copied.');
    }
  }

  function showTab(name) {
    document.querySelectorAll('[data-seek-tab]').forEach(function (btn) {
      btn.classList.toggle('active', btn.getAttribute('data-seek-tab') === name);
    });
    document.querySelectorAll('[data-seek-panel]').forEach(function (p) {
      p.hidden = p.getAttribute('data-seek-panel') !== name;
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('[data-seek-tab]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        showTab(btn.getAttribute('data-seek-tab'));
      });
    });

    var flashBtn = $('btnWifiFlash');
    if (flashBtn) flashBtn.addEventListener('click', startWifiFlash);

    var copyBtn = $('btnCopySsh');
    if (copyBtn) copyBtn.addEventListener('click', copySsh);

    var sshIp = $('sshRobotIp');
    if (sshIp) sshIp.addEventListener('input', fillSshCommand);

    document.addEventListener('seek-release-changed', fillSshCommand);

    if (window.SeekReleases && window.SeekReleases.ready) {
      window.SeekReleases.ready.then(fillSshCommand);
    }
  });
})();
