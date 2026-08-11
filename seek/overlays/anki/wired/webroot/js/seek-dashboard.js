const SEEK_FACE_W = 184;
const SEEK_FACE_H = 96;
const API = '/api/mods/SeekDashboard';

let seekVideoAbort = null;
let keysDown = new Set();
let cameraOn = false;
let driveArmed = false;
let lastDriveSent = '';

function $(id) { return document.getElementById(id); }

function setSeekStatus(msg, isError) {
    const el = $('seekStatus');
    if (!el) return;
    if (!msg) {
        el.hidden = true;
        el.textContent = '';
        el.classList.remove('err');
        return;
    }
    el.hidden = false;
    el.classList.toggle('err', !!isError);
    el.textContent = msg;
}

function api(path, opts) {
    return fetch(API + '/' + path, opts);
}

function fire(path) {
    // Non-blocking command for drive/pad — keep UI snappy.
    return fetch(API + '/' + path, { method: 'GET', cache: 'no-store' }).catch(() => {});
}

/* ---------------- Tabs ---------------- */

function switchTab(name) {
    document.querySelectorAll('.tab').forEach((btn) => {
        btn.classList.toggle('active', btn.dataset.tab === name);
    });
    document.querySelectorAll('.panel').forEach((panel) => {
        const on = panel.id === 'tab-' + name;
        panel.hidden = !on;
        panel.classList.toggle('active', on);
    });
    if (name === 'drive') {
        setSeekStatus('Drive tab ready. Click “Take control”, then hold WASD.');
    } else if (driveArmed) {
        keysDown.clear();
        lastDriveSent = '';
        sendDrive(0, 0);
        updateWasdKeys();
    }
    if (name === 'look') seekRefresh();
}

function initTabs() {
    document.querySelectorAll('.tab').forEach((btn) => {
        btn.addEventListener('click', () => switchTab(btn.dataset.tab));
    });
}

/* ---------------- Look / Speak / Media ---------------- */

function seekEyeModeChanged() {
    const mode = $('eyeMode').value;
    $('eyeCustomControls').hidden = mode !== 'custom';
    $('eyePresetControls').hidden = mode !== 'preset';
}

async function seekRefresh() {
    try {
        const eyeRes = await api('getEyeColor');
        if (eyeRes.ok) {
            const eye = await eyeRes.json();
            if (eye.iscustom) {
                $('eyeMode').value = 'custom';
                $('eyeHue').value = eye.hue;
                $('eyeSat').value = eye.saturation;
                $('eyeHueVal').textContent = Number(eye.hue).toFixed(2);
                $('eyeSatVal').textContent = Number(eye.saturation).toFixed(2);
            } else {
                $('eyeMode').value = 'preset';
                $('eyePreset').value = String(eye.preset);
            }
            seekEyeModeChanged();
        }
        const volRes = await api('getVolume');
        if (volRes.ok) $('masterVolume').value = (await volRes.text()).trim();
    } catch (e) {
        console.log('seekRefresh', e);
    }
}

async function seekSetEyeColor() {
    setSeekStatus('Setting eye color...');
    try {
        const mode = $('eyeMode').value;
        let url = 'setEyeColor?mode=' + encodeURIComponent(mode);
        if (mode === 'preset') url += '&preset=' + encodeURIComponent($('eyePreset').value);
        else {
            url += '&hue=' + encodeURIComponent($('eyeHue').value);
            url += '&saturation=' + encodeURIComponent($('eyeSat').value);
        }
        const res = await api(url);
        if (!res.ok) {
            const e = await res.json();
            setSeekStatus(`${e.status}: ${e.message}`, true);
            return;
        }
        setSeekStatus('Eye color updated.');
        seekRefresh();
    } catch (e) {
        setSeekStatus('network error: ' + e.message, true);
    }
}

async function seekSetVolume() {
    setSeekStatus('Setting volume...');
    try {
        const res = await api('setVolume?volume=' + encodeURIComponent($('masterVolume').value));
        if (!res.ok) {
            const e = await res.json();
            setSeekStatus(`${e.status}: ${e.message}`, true);
            return;
        }
        setSeekStatus('Volume updated.');
    } catch (e) {
        setSeekStatus('network error: ' + e.message, true);
    }
}

async function seekSayText() {
    const text = $('sayText').value.trim();
    if (!text) {
        setSeekStatus('Enter something for Vector to say.', true);
        return;
    }
    setSeekStatus('Saying...');
    try {
        const res = await api(
            'sayText?text=' + encodeURIComponent(text) +
            '&vectorVoice=' + encodeURIComponent($('sayVectorVoice').value)
        );
        if (!res.ok) {
            const e = await res.json();
            setSeekStatus(`${e.status}: ${e.message}`, true);
            return;
        }
        setSeekStatus('Done speaking.');
    } catch (e) {
        setSeekStatus('network error: ' + e.message, true);
    }
}

async function seekPlayAudio() {
    const input = $('audioFile');
    if (!input.files || !input.files[0]) {
        setSeekStatus('Choose an MP3 or WAV file first.', true);
        return;
    }
    const file = input.files[0];
    setSeekStatus('Playing ' + file.name + '...');
    try {
        const fd = new FormData();
        fd.append('file', file, file.name);
        fd.append('volume', $('audioPlayVolume').value);
        const res = await api('playAudio', { method: 'POST', body: fd });
        if (!res.ok) {
            const e = await res.json();
            setSeekStatus(`${e.status}: ${e.message}`, true);
            return;
        }
        setSeekStatus('Audio finished.');
    } catch (e) {
        setSeekStatus('network error: ' + e.message, true);
    }
}

function rgbaToRgb565Dithered(rgba) {
    const w = SEEK_FACE_W;
    const h = SEEK_FACE_H;
    const buf = new Float32Array(w * h * 3);
    for (let i = 0, p = 0; i < rgba.length; i += 4, p += 3) {
        buf[p] = rgba[i];
        buf[p + 1] = rgba[i + 1];
        buf[p + 2] = rgba[i + 2];
    }
    const out = new Uint8Array(w * h * 2);
    let o = 0;
    for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
            const idx = (y * w + x) * 3;
            let r = buf[idx], g = buf[idx + 1], b = buf[idx + 2];
            const r5 = Math.max(0, Math.min(31, Math.round(r / 8.225806)));
            const g6 = Math.max(0, Math.min(63, Math.round(g / 4.047619)));
            const b5 = Math.max(0, Math.min(31, Math.round(b / 8.225806)));
            const er = r - r5 * 8.225806;
            const eg = g - g6 * 4.047619;
            const eb = b - b5 * 8.225806;
            const distribute = (nx, ny, fr) => {
                if (nx < 0 || nx >= w || ny < 0 || ny >= h) return;
                const j = (ny * w + nx) * 3;
                buf[j] += er * fr;
                buf[j + 1] += eg * fr;
                buf[j + 2] += eb * fr;
            };
            distribute(x + 1, y, 7 / 16);
            distribute(x - 1, y + 1, 3 / 16);
            distribute(x, y + 1, 5 / 16);
            distribute(x + 1, y + 1, 1 / 16);
            out[o++] = (r5 << 3) | (g6 >> 3);
            out[o++] = ((g6 & 0x07) << 5) | b5;
        }
    }
    return out;
}

function drawVideoFrame(ctx, video, fit) {
    const vw = video.videoWidth || SEEK_FACE_W;
    const vh = video.videoHeight || SEEK_FACE_H;
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, SEEK_FACE_W, SEEK_FACE_H);
    const scale = fit === 'contain'
        ? Math.min(SEEK_FACE_W / vw, SEEK_FACE_H / vh)
        : Math.max(SEEK_FACE_W / vw, SEEK_FACE_H / vh);
    const dw = Math.max(1, Math.round(vw * scale));
    const dh = Math.max(1, Math.round(vh * scale));
    ctx.drawImage(video, Math.floor((SEEK_FACE_W - dw) / 2), Math.floor((SEEK_FACE_H - dh) / 2), dw, dh);
}

async function decodeFileToPcm16k(file) {
    const arr = await file.arrayBuffer();
    const probe = new (window.AudioContext || window.webkitAudioContext)();
    const decoded = await probe.decodeAudioData(arr.slice(0));
    await probe.close();
    const srcFrames = decoded.length;
    const left = decoded.getChannelData(0);
    const right = decoded.numberOfChannels > 1 ? decoded.getChannelData(1) : null;
    const monoBuf = new AudioBuffer({ length: srcFrames, numberOfChannels: 1, sampleRate: decoded.sampleRate });
    const monoData = monoBuf.getChannelData(0);
    let peak = 0;
    for (let i = 0; i < srcFrames; i++) {
        const s = right ? (left[i] + right[i]) * 0.5 : left[i];
        monoData[i] = s;
        const a = Math.abs(s);
        if (a > peak) peak = a;
    }
    if (peak > 0.001 && peak < 0.95) {
        const gain = 0.92 / peak;
        for (let i = 0; i < srcFrames; i++) monoData[i] *= gain;
    }
    const outFrames = Math.max(1, Math.ceil(decoded.duration * 16000));
    const offline = new OfflineAudioContext(1, outFrames, 16000);
    const src = offline.createBufferSource();
    src.buffer = monoBuf;
    src.connect(offline.destination);
    src.start(0);
    const rendered = await offline.startRendering();
    const f32 = rendered.getChannelData(0);
    const pcm = new ArrayBuffer(f32.length * 2);
    const view = new DataView(pcm);
    for (let i = 0; i < f32.length; i++) {
        const s = Math.max(-1, Math.min(1, f32[i]));
        view.setInt16(i * 2, (s * 32767) | 0, true);
    }
    return new Uint8Array(pcm);
}

async function seekStopMedia() {
    if (seekVideoAbort) seekVideoAbort.abort = true;
    try { await api('controlEnd'); } catch (_) {}
    setSeekStatus('Stopped.');
}

async function seekPlayVideo() {
    const input = $('videoFile');
    if (!input.files || !input.files[0]) {
        setSeekStatus('Choose a video first.', true);
        return;
    }
    const file = input.files[0];
    const fps = Math.max(1, Math.min(15, Number($('videoFps').value) || 12));
    const withAudio = $('videoWithAudio').value !== '0';
    const fit = $('videoFit').value;
    const canvas = $('seekVideoCanvas');
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const btn = $('videoPlayBtn');
    const vol = $('audioPlayVolume') ? $('audioPlayVolume').value : '100';
    btn.disabled = true;

    const url = URL.createObjectURL(file);
    const video = document.createElement('video');
    video.src = url;
    video.muted = true;
    video.playsInline = true;
    video.preload = 'auto';
    seekVideoAbort = { abort: false };
    const token = seekVideoAbort;

    try {
        await new Promise((resolve, reject) => {
            video.onloadeddata = () => resolve();
            video.onerror = () => reject(new Error('could not load video'));
        });

        let pcm = null;
        if (withAudio) {
            setSeekStatus('Decoding audio...');
            try { pcm = await decodeFileToPcm16k(file); }
            catch (err) { setSeekStatus('Playing without audio (' + err.message + ')'); }
        }

        setSeekStatus('Taking control...');
        let res = await api('controlStart');
        if (!res.ok) {
            const e = await res.json();
            throw new Error(e.message || 'controlStart failed');
        }

        const audioPromise = pcm
            ? api('playPcm?rate=16000&volume=' + encodeURIComponent(vol), {
                method: 'POST',
                headers: { 'Content-Type': 'application/octet-stream' },
                body: pcm
            }).then(async (audioRes) => {
                if (!audioRes.ok) {
                    const e = await audioRes.json().catch(() => ({ message: 'audio failed' }));
                    throw new Error(e.message || 'audio failed');
                }
            })
            : Promise.resolve();

        await video.play();
        const frameMs = Math.round(1000 / fps);
        const holdMs = Math.max(frameMs + 40, Math.round(frameMs * 1.35));
        setSeekStatus('Playing on face @ ' + fps + ' fps...');
        let nextT = performance.now();
        while (!video.ended && !token.abort) {
            drawVideoFrame(ctx, video, fit);
            const rgba = ctx.getImageData(0, 0, SEEK_FACE_W, SEEK_FACE_H).data;
            const frameRes = await api('frame?duration_ms=' + holdMs, {
                method: 'POST',
                headers: { 'Content-Type': 'application/octet-stream' },
                body: rgbaToRgb565Dithered(rgba)
            });
            if (!frameRes.ok) {
                const e = await frameRes.json().catch(() => ({ message: 'frame failed' }));
                throw new Error(e.message || 'frame failed');
            }
            nextT += frameMs;
            const wait = nextT - performance.now();
            if (wait > 0) await new Promise((r) => setTimeout(r, wait));
            else nextT = performance.now();
        }
        await audioPromise;
        await api('controlEnd');
        setSeekStatus(token.abort ? 'Stopped.' : 'Video finished.');
    } catch (e) {
        try { await api('controlEnd'); } catch (_) {}
        setSeekStatus('video error: ' + e.message, true);
    } finally {
        video.pause();
        URL.revokeObjectURL(url);
        btn.disabled = false;
        seekVideoAbort = null;
    }
}

/* ---------------- Drive + Camera (WASD) ---------------- */

function driveSpeed() {
    return Number($('driveSpeed').value) || 60;
}

function setArmedUI(on) {
    driveArmed = on;
    const el = $('driveArmed');
    if (!el) return;
    el.textContent = on ? 'CONTROL ON · WASD ready' : 'Not armed — click Take control';
    el.classList.toggle('on', on);
}

async function armDrive() {
    if (driveArmed) {
        setSeekStatus('Already armed. Hold WASD.');
        return;
    }
    setSeekStatus('Taking control (safe mode)...');
    try {
        const res = await api('controlStart');
        if (!res.ok) {
            const e = await res.json().catch(() => ({ message: 'control failed' }));
            setArmedUI(false);
            setSeekStatus(e.message || 'control failed', true);
            return;
        }
        setArmedUI(true);
        setSeekStatus('Armed. Hold WASD to drive.');
        window.focus();
    } catch (e) {
        setArmedUI(false);
        setSeekStatus('network error: ' + e.message, true);
    }
}

function sendDrive(forward, turn) {
    if (!driveArmed && (forward !== 0 || turn !== 0)) {
        setSeekStatus('Click Take control first.', true);
        return;
    }
    const s = Math.min(120, driveSpeed());
    let left = forward * s + turn * s * 0.7;
    let right = forward * s - turn * s * 0.7;
    left = Math.max(-120, Math.min(120, left));
    right = Math.max(-120, Math.min(120, right));
    const key = left.toFixed(1) + ',' + right.toFixed(1);
    if (key === lastDriveSent) return;
    lastDriveSent = key;
    if (left === 0 && right === 0) {
        fire('stopMotors');
        return;
    }
    fire('drive?left=' + left.toFixed(1) + '&right=' + right.toFixed(1));
}

function updateWasdKeys() {
    document.querySelectorAll('.wasd-board .key').forEach((el) => {
        el.classList.toggle('held', keysDown.has(el.dataset.k));
    });
}

function syncKeysToDrive() {
    let f = 0, t = 0;
    if (keysDown.has('w')) f += 1;
    if (keysDown.has('s')) f -= 1;
    if (keysDown.has('a')) t += 1;
    if (keysDown.has('d')) t -= 1;
    updateWasdKeys();
    sendDrive(f, t);
}

function bindKeyboard() {
    window.addEventListener('keydown', (e) => {
        if (e.repeat) return;
        if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT')) return;
        const driveTab = $('tab-drive');
        if (!driveTab || driveTab.hidden) return;
        const k = e.key.toLowerCase();
        if (['w', 'a', 's', 'd', ' ', 'q', 'e', 'r', 'f'].includes(k)) e.preventDefault();
        if (!driveArmed && ['w', 'a', 's', 'd'].includes(k)) {
            setSeekStatus('Click Take control first, then WASD.', true);
            return;
        }
        if (e.key === ' ') {
            keysDown.clear();
            lastDriveSent = '';
            sendDrive(0, 0);
            fire('stopMotors');
            updateWasdKeys();
            return;
        }
        if (k === 'q') { fire('moveHead?speed=3'); return; }
        if (k === 'e') { fire('moveHead?speed=-3'); return; }
        if (k === 'r') { fire('moveLift?speed=3'); return; }
        if (k === 'f') { fire('moveLift?speed=-3'); return; }
        if (['w', 'a', 's', 'd'].includes(k) && !keysDown.has(k)) {
            keysDown.add(k);
            syncKeysToDrive();
        }
    }, { passive: false });

    window.addEventListener('keyup', (e) => {
        const k = e.key.toLowerCase();
        if (k === 'q' || k === 'e') fire('moveHead?speed=0');
        if (k === 'r' || k === 'f') fire('moveLift?speed=0');
        if (keysDown.delete(k)) {
            lastDriveSent = '';
            syncKeysToDrive();
        }
    });

    window.addEventListener('blur', () => {
        keysDown.clear();
        lastDriveSent = '';
        sendDrive(0, 0);
        updateWasdKeys();
    });
}

function startCamera() {
    if (cameraOn) return;
    cameraOn = true;
    $('cameraView').src = API + '/cameraMjpeg?' + Date.now();
    setSeekStatus('Camera on (optional — uses CPU).');
    api('cameraStart').catch(() => {});
}

function stopCamera() {
    cameraOn = false;
    const img = $('cameraView');
    img.removeAttribute('src');
    img.src = '';
    fire('cameraStop');
}

function bindUI() {
    $('eyeMode').addEventListener('change', seekEyeModeChanged);
    $('eyeHue').addEventListener('input', () => {
        $('eyeHueVal').textContent = Number($('eyeHue').value).toFixed(2);
    });
    $('eyeSat').addEventListener('input', () => {
        $('eyeSatVal').textContent = Number($('eyeSat').value).toFixed(2);
    });
    $('audioPlayVolume').addEventListener('input', () => {
        $('audioPlayVolVal').textContent = $('audioPlayVolume').value;
    });
    $('driveSpeed').addEventListener('input', () => {
        $('driveSpeedVal').textContent = $('driveSpeed').value;
        lastDriveSent = '';
        syncKeysToDrive();
    });

    $('btnEye').addEventListener('click', seekSetEyeColor);
    $('btnVolume').addEventListener('click', seekSetVolume);
    $('btnSay').addEventListener('click', seekSayText);
    $('btnAudio').addEventListener('click', seekPlayAudio);
    $('videoPlayBtn').addEventListener('click', seekPlayVideo);
    $('btnStopMedia').addEventListener('click', seekStopMedia);
    $('btnCamStart').addEventListener('click', startCamera);
    $('btnCamStop').addEventListener('click', stopCamera);
    $('btnArmDrive').addEventListener('click', armDrive);
    $('btnRelease').addEventListener('click', async () => {
        keysDown.clear();
        lastDriveSent = '';
        sendDrive(0, 0);
        stopCamera();
        setArmedUI(false);
        await api('controlEnd');
        setSeekStatus('Control released.');
        updateWasdKeys();
    });
}

/* boot */
initTabs();
bindUI();
bindKeyboard();
seekEyeModeChanged();
seekRefresh();
