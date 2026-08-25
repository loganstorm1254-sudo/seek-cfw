const tabs = document.querySelectorAll('.tabs button');
tabs.forEach(btn => btn.addEventListener('click', () => {
    tabs.forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
    document.querySelector(btn.dataset.target).classList.add('active');
}));

function hide(id) { document.getElementById(id).style.display = 'none'; }
function show(id) { document.getElementById(id).style.display = 'block'; }

async function GetCurrent(mod) {
    let res = await fetch(`/api/mods/${mod}/get`);
    return res.text();
}

function SetModStatus(msg) {
    const div = document.getElementById('modStatus');
    div.innerHTML = `<h3>${msg}</h3>`;
    div.style.display = msg ? 'block' : 'none';
}

function HideModStatus() { hide('modStatus'); }

async function UpdateAllMods() {
    hide('restartNeeded');
    hide('showDuringVicRestart');

    const data = await GetCurrent('FreqChange');
    document.getElementsByName('frequency')
        .forEach(rb => { if (rb.value == data) rb.checked = true; });
    checkAutoUpdateStatus();
    setSensitivity();
    getTimezone()
    getLocation()
    getTempUnits()
    facesRefresh()
}

UpdateAllMods();