async function setAutoUpdateStatus(status) {
    const el = document.getElementById('autoUpdateStatus');
    el.innerHTML = `<p>${status}</p>`;
    show('autoUpdateStatus');
}

async function checkAutoUpdateStatus() {
    ['autoUpdateStatus', 'autoUpdateInhibit', 'autoUpdateAllow'].forEach(hide);
    let res = await fetch('/api/mods/AutoUpdate/isSelfMadeBuild');
    let txt = await res.text();
    if (txt.includes('true')) {
        setAutoUpdateStatus('This is a self-made build. This build cannot auto-update.');
    } else {
        res = await fetch('/api/mods/AutoUpdate/isInhibitedByUser');
        txt = await res.text();
        if (txt.includes('true')) {
            setAutoUpdateStatus('Auto-updates: not enabled');
            show('autoUpdateAllow');
        } else {
            setAutoUpdateStatus('Auto-updates: enabled');
            show('autoUpdateInhibit');
        }
    }
    checkFaceUpdateStatus();
}

async function autoUpdateInhibit() {
    ['autoUpdateStatus', 'autoUpdateInhibit', 'autoUpdateAllow'].forEach(hide);
    await fetch('/api/mods/AutoUpdate/setInhibited');
    checkAutoUpdateStatus();
}
async function autoUpdateAllow() {
    ['autoUpdateStatus', 'autoUpdateInhibit', 'autoUpdateAllow'].forEach(hide);
    await fetch('/api/mods/AutoUpdate/setAllowed');
    checkAutoUpdateStatus();
}

async function setFaceUpdateStatus(status) {
    const el = document.getElementById('faceUpdateStatus');
    if (!el) return;
    el.innerHTML = `<p>${status}</p>`;
    show('faceUpdateStatus');
}

async function checkFaceUpdateStatus() {
    ['faceUpdateStatus', 'faceUpdateDisable', 'faceUpdateEnable'].forEach(hide);
    try {
        const res = await fetch('/api/mods/SeekFaceUpdate/isEnabled');
        const txt = await res.text();
        if (txt.includes('true')) {
            setFaceUpdateStatus('Face Update OS: enabled');
            show('faceUpdateDisable');
        } else {
            setFaceUpdateStatus('Face Update OS: disabled');
            show('faceUpdateEnable');
        }
    } catch (e) {
        setFaceUpdateStatus('Face Update OS: unavailable');
    }
}

async function faceUpdateDisable() {
    ['faceUpdateStatus', 'faceUpdateDisable', 'faceUpdateEnable'].forEach(hide);
    await fetch('/api/mods/SeekFaceUpdate/setDisabled');
    checkFaceUpdateStatus();
}

async function faceUpdateEnable() {
    ['faceUpdateStatus', 'faceUpdateDisable', 'faceUpdateEnable'].forEach(hide);
    await fetch('/api/mods/SeekFaceUpdate/setEnabled');
    checkFaceUpdateStatus();
}
