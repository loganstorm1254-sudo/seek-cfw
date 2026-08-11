const SEEK_FACE_W = 184;
const SEEK_FACE_H = 96;
const API = '/api/mods/SeekDashboard';

let seekVideoAbort = null;
let seekAudioCtrl = null; // AbortController for in-flight playPcm
let keysDown = new Set();
let padHeld = null; // {f,t} while touch pad pressed
let cameraOn = false;
let driveArmed = false;
let lastDriveSent = '';
let driveHeartbeat = null;

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

function isMobile() {
    return /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent || '') ||
        (window.matchMedia && window.matchMedia('(pointer: coarse)').matches);
}

async function api(path, opts) {
    opts = opts || {};
    const timeoutMs = opts.timeoutMs != null ? opts.timeoutMs : (opts.body ? 180000 : 10000);
    const maxAttempts = opts.retries != null ? opts.retries : (opts.body ? 1 : 3);
    const body = opts.body;
    const externalSignal = opts.signal;
    // Only retry bodies we can safely resend.
    const canRetryBody = body == null || typeof body === 'string' || body instanceof ArrayBuffer ||
        ArrayBuffer.isView(body) || (typeof Blob !== 'undefined' && body instanceof Blob);

    let lastErr = null;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        if (externalSignal && externalSignal.aborted) {
            throw new DOMException('Aborted', 'AbortError');
        }
        const ctrl = new AbortController();
        const onExternal = function () { ctrl.abort(); };
        if (externalSignal) externalSignal.addEventListener('abort', onExternal);
        const timer = setTimeout(function () { ctrl.abort(); }, timeoutMs);
        try {
            const o = {};
            for (const k in opts) {
                if (k === 'timeoutMs' || k === 'retries' || k === 'signal') continue;
                o[k] = opts[k];
            }
            o.cache = 'no-store';
            o.signal = ctrl.signal;
            if (body != null && attempt > 1 && canRetryBody) o.body = body;
            const res = await fetch(API + '/' + path, o);
            clearTimeout(timer);
            if (externalSignal) externalSignal.removeEventListener('abort', onExternal);
            return res;
        } catch (e) {
            clearTimeout(timer);
            if (externalSignal) externalSignal.removeEventListener('abort', onExternal);
            lastErr = e;
            if (externalSignal && externalSignal.aborted) throw e;
            if (attempt >= maxAttempts) break;
            if (opts.body && !canRetryBody) break;
            await new Promise(function (r) { setTimeout(r, 250 * attempt); });
        }
    }
    throw lastErr || new Error('network error');
}

function fire(path) {
    return api(path, { method: 'GET', timeoutMs: 4000, retries: 2 }).catch(function () {});
}

function startKeepalive() {
    // Phone Wi‑Fi power-save drops idle TCP; a light ping keeps the path warm.
    setInterval(function () {
        if (document.hidden) return;
        fetch('/api/health', { cache: 'no-store', method: 'GET' }).catch(function () {});
    }, 10000);

    function recover(reason) {
        setSeekStatus('Reconnected (' + reason + '). Try again if a button failed.');
        fetch('/api/health', { cache: 'no-store' }).catch(function () {});
        loadNetInfo();
    }
    window.addEventListener('online', function () { recover('online'); });
    window.addEventListener('pageshow', function (e) {
        if (e.persisted) recover('pageshow');
    });
    document.addEventListener('visibilitychange', function () {
        if (!document.hidden) {
            recover('visible');
            return;
        }
        // Backgrounding the tab mid-drive used to leave wheels latched.
        hardStopDrive('tab hidden');
    });
    window.addEventListener('pagehide', function () {
        hardStopDrive('leaving page');
    });
}

function hardStopDrive(reason) {
    keysDown.clear();
    padHeld = null;
    lastDriveSent = '';
    if (driveArmed) {
        fire('stopMotors');
        updateWasdKeys();
        if (reason) setSeekStatus('Stopped (' + reason + ').');
    }
}

function startDriveHeartbeat() {
    if (driveHeartbeat) return;
    // Holding W only used to send once; robot motors latch that speed.
    // Re-poke every 200ms so a dead phone path trips the server watchdog.
    driveHeartbeat = setInterval(function () {
        if (!driveArmed || document.hidden) return;
        if (keysDown.size === 0 && !padHeld) return;
        lastDriveSent = '';
        if (padHeld) {
            sendDrive(padHeld.f, padHeld.t);
        } else {
            syncKeysToDrive();
        }
    }, 200);
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
        setSeekStatus('Drive ready. Tap Take control, then hold the pad (or WASD).');
    } else if (name === 'moves') {
        setSeekStatus('Moves: Activate voice, or tap a behavior.');
    } else if (name === 'media') {
        if (cameraOn) stopCamera();
        setSeekStatus(isMobile() ? 'Tip: use 5 fps on phone for less lag.' : 'Media ready.');
    } else if (driveArmed) {
        keysDown.clear();
        lastDriveSent = '';
        sendDrive(0, 0);
        updateWasdKeys();
    }
    if (name !== 'drive' && cameraOn) stopCamera();
    if (name === 'look') seekRefresh();
}

function initTabs() {
    document.querySelectorAll('.tab').forEach((btn) => {
        btn.addEventListener('click', () => switchTab(btn.dataset.tab));
    });
}

/* ---------------- Look / Speak / Media ---------------- */

function seekEyeModeChanged() {
    const modeEl = $('eyeMode');
    if (!modeEl) return;
    const mode = modeEl.value;
    if ($('eyeCustomControls')) $('eyeCustomControls').hidden = mode !== 'custom';
    if ($('eyePresetControls')) $('eyePresetControls').hidden = mode !== 'preset';
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
    const vol = $('audioPlayVolume').value;
    setSeekStatus('Decoding on phone (faster)...');
    if (seekAudioCtrl) seekAudioCtrl.abort();
    seekAudioCtrl = new AbortController();
    const ac = seekAudioCtrl;
    try {
        // Decode in the browser so the robot doesn't burn CPU on MP3.
        const pcm = await decodeFileToPcm16k(file);
        setSeekStatus('Streaming audio...');
        const res = await api('playPcm?rate=16000&volume=' + encodeURIComponent(vol), {
            method: 'POST',
            headers: { 'Content-Type': 'application/octet-stream' },
            body: pcm,
            timeoutMs: 300000,
            retries: 1,
            signal: ac.signal
        });
        if (!res.ok) {
            const e = await res.json().catch(() => ({ message: 'audio failed' }));
            setSeekStatus((e.status ? e.status + ': ' : '') + (e.message || 'audio failed'), true);
            return;
        }
        setSeekStatus('Audio finished.');
    } catch (e) {
        if (e.name === 'AbortError' && ac.signal.aborted) {
            setSeekStatus('Stopped.');
            return;
        }
        setSeekStatus('audio error: ' + (e.name === 'AbortError' ? 'timed out — toggle Wi‑Fi and retry' : e.message), true);
    } finally {
        if (seekAudioCtrl === ac) seekAudioCtrl = null;
    }
}

function rgbaToRgb565Fast(rgba) {
    const out = new Uint8Array((rgba.length / 4) * 2);
    let o = 0;
    for (let i = 0; i < rgba.length; i += 4) {
        const r5 = rgba[i] >> 3;
        const g6 = rgba[i + 1] >> 2;
        const b5 = rgba[i + 2] >> 3;
        out[o++] = (r5 << 3) | (g6 >> 3);
        out[o++] = ((g6 & 7) << 5) | b5;
    }
    return out;
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
    if (seekAudioCtrl) {
        seekAudioCtrl.abort();
        seekAudioCtrl = null;
    }
    setSeekStatus('Stopping…');
    // Hammer every stop path — Stop must work even mid-Macarena.
    try {
        await Promise.all([
            api('stopMedia', { timeoutMs: 4000, retries: 2 }).catch(function () {}),
            api('stopMotors', { timeoutMs: 3000, retries: 1 }).catch(function () {}),
            api('stopAudio', { timeoutMs: 3000, retries: 1 }).catch(function () {}),
            api('controlEnd', { timeoutMs: 4000, retries: 1 }).catch(function () {})
        ]);
    } catch (_) {}
    setArmedUI(false);
    setSeekStatus('Stopped.');
}

async function seekMacarena() {
    if (cameraOn) stopCamera();
    setArmedUI(false);
    const vol = $('audioPlayVolume') ? $('audioPlayVolume').value : '100';
    setSeekStatus('Arming Macarena on Vector…');
    try {
        const res = await api('macarena?volume=' + encodeURIComponent(vol), {
            timeoutMs: 30000,
            retries: 1
        });
        if (!res.ok) {
            const e = await res.json().catch(() => ({ message: 'macarena failed' }));
            setSeekStatus((e.message || 'macarena failed'), true);
            return;
        }
        setSeekStatus('Macarena on Vector — music + dance. Hit Stop to end.');
        const started = Date.now();
        while (Date.now() - started < 280000) {
            await new Promise((r) => setTimeout(r, 1500));
            try {
                const st = await api('status', { timeoutMs: 5000, retries: 1 });
                if (!st.ok) continue;
                const j = await st.json();
                if (j.danceErr) {
                    setSeekStatus('Macarena error: ' + j.danceErr, true);
                    return;
                }
                if (!j.dancing) {
                    setSeekStatus('Macarena finished.');
                    return;
                }
            } catch (_) {}
        }
        setSeekStatus('Macarena still going — hit Stop if you want out.');
    } catch (e) {
        setSeekStatus('macarena error: ' + e.message, true);
    }
}

async function seekPlayVideo() {
    const input = $('videoFile');
    if (!input.files || !input.files[0]) {
        setSeekStatus('Choose a video first.', true);
        return;
    }
    const file = input.files[0];
    // Phone Wi‑Fi + robot CPU: keep FPS low for snappier playback.
    const defaultFps = isMobile() ? 5 : 8;
    const fps = Math.max(1, Math.min(10, Number($('videoFps').value) || defaultFps));
    const withAudio = $('videoWithAudio').value !== '0';
    const fit = $('videoFit').value;
    const canvas = $('seekVideoCanvas');
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const btn = $('videoPlayBtn');
    const vol = $('audioPlayVolume') ? $('audioPlayVolume').value : '100';
    btn.disabled = true;
    if (cameraOn) stopCamera();

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
            setSeekStatus('Decoding audio on phone...');
            try { pcm = await decodeFileToPcm16k(file); }
            catch (err) { setSeekStatus('Playing without audio (' + err.message + ')'); }
        }

        setSeekStatus('Taking control...');
        let res = await api('controlStart', { timeoutMs: 15000, retries: 2 });
        if (!res.ok) {
            const e = await res.json().catch(() => ({ message: 'controlStart failed' }));
            throw new Error(e.message || 'controlStart failed');
        }

        if (seekAudioCtrl) seekAudioCtrl.abort();
        seekAudioCtrl = new AbortController();
        const audioCtrl = seekAudioCtrl;
        const audioPromise = pcm
            ? api('playPcm?rate=16000&volume=' + encodeURIComponent(vol), {
                method: 'POST',
                headers: { 'Content-Type': 'application/octet-stream' },
                body: pcm,
                timeoutMs: 300000,
                retries: 1,
                signal: audioCtrl.signal
            }).then(async (audioRes) => {
                if (!audioRes.ok) {
                    const e = await audioRes.json().catch(() => ({ message: 'audio failed' }));
                    throw new Error(e.message || 'audio failed');
                }
            }).catch(function (err) {
                if (err && err.name === 'AbortError') return;
                throw err;
            })
            : Promise.resolve();

        await video.play();
        const frameMs = Math.round(1000 / fps);
        const holdMs = Math.max(frameMs + 20, Math.round(frameMs * 1.2));
        setSeekStatus('Playing on face @ ' + fps + ' fps...');
        let nextT = performance.now();
        let inFlight = null;
        let frames = 0;
        while (!video.ended && !token.abort) {
            drawVideoFrame(ctx, video, fit);
            const rgba = ctx.getImageData(0, 0, SEEK_FACE_W, SEEK_FACE_H).data;
            // Fast convert — dithering every frame is what made phones feel dead.
            const body = rgbaToRgb565Fast(rgba);
            if (inFlight) {
                const prev = await inFlight;
                if (!prev.ok) {
                    const e = await prev.json().catch(() => ({ message: 'frame failed' }));
                    throw new Error(e.message || 'frame failed');
                }
            }
            inFlight = api('frame?duration_ms=' + holdMs, {
                method: 'POST',
                headers: { 'Content-Type': 'application/octet-stream' },
                body: body,
                timeoutMs: 8000,
                retries: 2
            });
            frames++;
            if (frames % 10 === 0) {
                setSeekStatus('Playing… frame ' + frames);
            }
            nextT += frameMs;
            const wait = nextT - performance.now();
            if (wait > 0) await new Promise((r) => setTimeout(r, wait));
            else nextT = performance.now();
        }
        if (token.abort) {
            if (seekAudioCtrl) {
                seekAudioCtrl.abort();
                seekAudioCtrl = null;
            }
            try { await api('stopMedia', { timeoutMs: 8000, retries: 2 }); } catch (_) {}
            setSeekStatus('Stopped.');
            return;
        }
        if (inFlight) {
            const last = await inFlight;
            if (!last.ok) {
                const e = await last.json().catch(() => ({ message: 'frame failed' }));
                throw new Error(e.message || 'frame failed');
            }
        }
        await audioPromise;
        await api('controlEnd', { timeoutMs: 8000, retries: 2 });
        setSeekStatus('Video finished.');
    } catch (e) {
        if (seekAudioCtrl) {
            seekAudioCtrl.abort();
            seekAudioCtrl = null;
        }
        try { await api('stopMedia', { timeoutMs: 5000, retries: 1 }); } catch (_) {}
        const msg = e.name === 'AbortError' ? 'timed out — toggle Wi‑Fi once, then retry' : e.message;
        setSeekStatus('video error: ' + msg, true);
    } finally {
        video.pause();
        URL.revokeObjectURL(url);
        btn.disabled = false;
        seekVideoAbort = null;
        if (seekAudioCtrl) seekAudioCtrl = null;
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
        startDriveHeartbeat();
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
        hardStopDrive('window blur');
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
    function on(id, ev, fn) {
        const el = $(id);
        if (el) el.addEventListener(ev, fn);
    }

    on('eyeMode', 'change', seekEyeModeChanged);
    on('eyeHue', 'input', () => {
        if ($('eyeHueVal')) $('eyeHueVal').textContent = Number($('eyeHue').value).toFixed(2);
    });
    on('eyeSat', 'input', () => {
        if ($('eyeSatVal')) $('eyeSatVal').textContent = Number($('eyeSat').value).toFixed(2);
    });
    on('audioPlayVolume', 'input', () => {
        if ($('audioPlayVolVal')) $('audioPlayVolVal').textContent = $('audioPlayVolume').value;
    });
    on('driveSpeed', 'input', () => {
        if ($('driveSpeedVal')) $('driveSpeedVal').textContent = $('driveSpeed').value;
        lastDriveSent = '';
        syncKeysToDrive();
    });

    on('btnEye', 'click', seekSetEyeColor);
    on('btnVolume', 'click', seekSetVolume);
    on('btnSay', 'click', seekSayText);
    on('btnAudio', 'click', seekPlayAudio);
    on('videoPlayBtn', 'click', seekPlayVideo);
    on('btnStopMedia', 'click', seekStopMedia);
    on('btnCamStart', 'click', startCamera);
    on('btnCamStop', 'click', stopCamera);
    on('btnArmDrive', 'click', armDrive);
    on('btnRelease', 'click', async () => {
        keysDown.clear();
        lastDriveSent = '';
        sendDrive(0, 0);
        stopCamera();
        setArmedUI(false);
        await api('controlEnd');
        setSeekStatus('Control released.');
        updateWasdKeys();
    });
    on('btnListen', 'click', activateVoice);
    on('btnMacarena', 'click', seekMacarena);
    on('btnMacarenaStop', 'click', seekStopMedia);
    on('btnMeet', 'click', () => {
        runMove('intent', { id: 'intent_meet_victor', label: 'Meet Vector' });
    });
    bindTouchPad();
}

/* ---------------- Moves (behaviors + anims) ---------------- */

const MOVE_INTENT_ORDER = [
    'intent_play_fistbump',
    'intent_imperative_dance',
    'intent_imperative_come',
    'explore_start',
    'intent_play_popawheelie',
    'intent_play_rollcube',
    'intent_play_pickupcube',
    'intent_play_blackjack',
    'intent_play_anytrick',
    'intent_play_anygame',
    'intent_imperative_lookatme',
    'intent_imperative_fetchcube',
    'intent_imperative_findcube',
    'intent_greeting_goodmorning',
    'intent_greeting_goodnight',
    'intent_greeting_goodbye',
    'intent_imperative_praise',
    'intent_imperative_love',
    'intent_imperative_affirmative',
    'intent_imperative_negative',
    'intent_imperative_apologize',
    'intent_imperative_scold',
    'intent_status_feeling',
    'intent_clock_time',
    'intent_character_age',
    'intent_names_ask',
    'intent_meet_victor',
    'intent_system_sleep',
    'intent_system_charger',
    'intent_imperative_volumeup',
    'intent_imperative_volumedown',
    'intent_imperative_quiet',
    'intent_imperative_shutup',
    'intent_seasonal_happyholidays',
    'intent_seasonal_happynewyear',
    'intent_global_stop_extend',
];

const MOVE_FAVORITES = [
    { id: 'intent_play_fistbump', label: 'Fist bump' },
    { id: 'intent_imperative_dance', label: 'Dance' },
    { id: 'intent_imperative_come', label: 'Come here' },
    { id: 'intent_imperative_love', label: 'I love you' },
    { id: 'intent_imperative_praise', label: 'Good robot' },
    { id: 'intent_system_sleep', label: 'Go to sleep' },
    { id: 'intent_system_charger', label: 'Go to charger' },
    { id: 'explore_start', label: 'Explore' },
    { id: 'intent_global_stop_extend', label: 'Stop' },
];

function sortMoves(items, order) {
    const rank = new Map(order.map((id, i) => [id, i]));
    return items.slice().sort((a, b) => {
        const ra = rank.has(a.id) ? rank.get(a.id) : 999;
        const rb = rank.has(b.id) ? rank.get(b.id) : 999;
        if (ra !== rb) return ra - rb;
        return a.label.localeCompare(b.label);
    });
}

function fillMoveGrid(el, items, kind) {
    if (!el) return;
    el.textContent = '';
    items.forEach((item) => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'ghost';
        btn.textContent = item.label;
        btn.dataset.id = item.id;
        btn.addEventListener('click', () => runMove(kind, item));
        el.appendChild(btn);
    });
}

async function loadMoves() {
    try {
        const res = await api('moves');
        if (!res.ok) {
            setSeekStatus('Moves catalog failed to load — robot may still be waking up.', true);
            return;
        }
        const data = await res.json();
        fillMoveGrid($('movesFavorites'), MOVE_FAVORITES, 'intent');
        fillMoveGrid($('movesIntents'), sortMoves(data.intents || [], MOVE_INTENT_ORDER), 'intent');
        fillMoveGrid($('movesAnims'), sortMoves(data.anims || [], []), 'anim');
    } catch (_) {
        setSeekStatus('Cannot reach robot API yet. Pull to refresh in a moment.', true);
    }
}

async function runMove(kind, item) {
    setSeekStatus('Running: ' + item.label + '…');
    try {
        let path;
        if (kind === 'intent') {
            let param = '';
            if (item.id === 'intent_meet_victor') {
                const meet = $('meetName');
                param = (meet && meet.value.trim()) || 'friend';
            }
            path = 'appIntent?intent=' + encodeURIComponent(item.id) + '&param=' + encodeURIComponent(param);
            setArmedUI(false);
        } else {
            path = 'playAnim?name=' + encodeURIComponent(item.id);
        }
        const res = await api(path);
        if (!res.ok) {
            const e = await res.json().catch(() => ({ message: 'failed' }));
            setSeekStatus(e.message || 'failed', true);
            return;
        }
        setSeekStatus(item.label + ' — sent.');
    } catch (e) {
        setSeekStatus('network error: ' + e.message, true);
    }
}

async function activateVoice() {
    setSeekStatus('Freeing control so Vector can listen…');
    try {
        setArmedUI(false);
        const res = await api('listen');
        if (!res.ok) {
            const e = await res.json().catch(() => ({ message: 'failed' }));
            setSeekStatus(e.message || 'failed', true);
            return;
        }
        setSeekStatus('Voice ready — say “Hey Vector” or press his backpack.');
    } catch (e) {
        setSeekStatus('network error: ' + e.message, true);
    }
}

function bindTouchPad() {
    const pad = $('touchPad');
    if (!pad) return;
    let heldBtn = null;

    function setHeld(btn, on) {
        if (!btn) return;
        btn.classList.toggle('held', on);
    }

    function start(btn, e) {
        if (e) {
            e.preventDefault();
            e.stopPropagation();
        }
        if (!driveArmed) {
            setSeekStatus('Tap Take control first.', true);
            return;
        }
        if (heldBtn && heldBtn !== btn) {
            setHeld(heldBtn, false);
        }
        heldBtn = btn;
        setHeld(btn, true);
        const f = Number(btn.dataset.f) || 0;
        const t = Number(btn.dataset.t) || 0;
        padHeld = { f: f, t: t };
        lastDriveSent = '';
        sendDrive(f, t);
    }

    function stop(e) {
        if (e) {
            e.preventDefault();
            e.stopPropagation();
        }
        if (!heldBtn && !padHeld) return;
        setHeld(heldBtn, false);
        heldBtn = null;
        padHeld = null;
        lastDriveSent = '';
        sendDrive(0, 0);
    }

    pad.querySelectorAll('.pad-btn').forEach((btn) => {
        // pointer + touch + mouse so iOS Safari / old WebViews all work
        btn.addEventListener('pointerdown', (e) => {
            try { btn.setPointerCapture(e.pointerId); } catch (_) {}
            start(btn, e);
        }, { passive: false });
        btn.addEventListener('pointerup', stop, { passive: false });
        btn.addEventListener('pointercancel', stop, { passive: false });
        btn.addEventListener('lostpointercapture', stop);
        btn.addEventListener('touchstart', (e) => start(btn, e), { passive: false });
        btn.addEventListener('touchend', stop, { passive: false });
        btn.addEventListener('touchcancel', stop, { passive: false });
        btn.addEventListener('mousedown', (e) => start(btn, e));
        btn.addEventListener('mouseup', stop);
        btn.addEventListener('mouseleave', stop);
        btn.addEventListener('contextmenu', (e) => e.preventDefault());
    });
}

async function loadNetInfo() {
    const ipEl = $('netLanIp');
    const urlEl = $('netPhoneUrl');
    const listEl = $('netAddrList');
    if (!ipEl && !urlEl && !listEl) return;
    try {
        const res = await fetch('/api/netinfo', { cache: 'no-store' });
        if (!res.ok) return;
        const data = await res.json();
        // Prefer the IP the browser already used (e.g. 192.168.42.209).
        const hostIp = location.hostname;
        const lanIp = hostIp && hostIp !== 'localhost' && hostIp !== '127.0.0.1'
            ? hostIp
            : (data.lanIp || '');
        const one = 'http://' + lanIp + ':8080/seek.html';
        if (ipEl) {
            ipEl.hidden = false;
            ipEl.textContent = lanIp || 'waiting for IP…';
        }
        if (urlEl) {
            urlEl.hidden = false;
            if (lanIp) {
                urlEl.innerHTML = '<a href="' + one + '">' + one + '</a>';
            } else {
                urlEl.textContent = 'Connect Vector to Wi‑Fi, then refresh.';
            }
        }
        if (listEl) {
            listEl.textContent = '';
            (data.addrs || []).forEach((a) => {
                const li = document.createElement('li');
                li.textContent = a.iface + ' · ' + a.ip + ' · ' + a.kind;
                listEl.appendChild(li);
            });
        }
    } catch (_) { /* ignore */ }
}

async function waitForRobot() {
    setSeekStatus('Connecting to Vector…');
    for (let i = 0; i < 30; i++) {
        try {
            const res = await fetch('/api/health', { cache: 'no-store' });
            if (res.ok) {
                const data = await res.json();
                if (data.ready) {
                    setSeekStatus('Connected.');
                    return true;
                }
                setSeekStatus('Robot waking up… (' + (i + 1) + ')');
            } else {
                setSeekStatus('Dashboard up — waiting for SDK…', true);
            }
        } catch (_) {
            setSeekStatus('Cannot reach ' + location.host + ' — use http://<ip>:8080/seek.html on Wi‑Fi.', true);
        }
        await new Promise((r) => setTimeout(r, 1000));
    }
    setSeekStatus('Still waking up — UI is usable; retry actions in a bit.', true);
    return false;
}

/* boot */
window.__seekLoaded = true;
(function boot() {
    try {
        initTabs();
        bindUI();
        bindKeyboard();
        startKeepalive();
        seekEyeModeChanged();
        if (isMobile() && $('videoFps')) $('videoFps').value = '5';
        if (isMobile() && $('driveSpeed')) {
            $('driveSpeed').value = '50';
            if ($('driveSpeedVal')) $('driveSpeedVal').textContent = '50';
        }
        loadNetInfo();
        seekRefresh();
        loadMoves();
        waitForRobot().then(function (ok) {
            if (ok) {
                seekRefresh();
                loadMoves();
            }
        });
    } catch (e) {
        setSeekStatus('Boot error: ' + (e && e.message ? e.message : e), true);
        console.error(e);
    }
})();
