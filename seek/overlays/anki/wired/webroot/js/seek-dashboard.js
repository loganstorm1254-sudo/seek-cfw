const SEEK_FACE_W = 184;
const SEEK_FACE_H = 96;
let seekVideoAbort = null;

function setSeekStatus(msg, isError) {
    const el = document.getElementById('seekStatus');
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

function seekEyeModeChanged() {
    const mode = document.getElementById('eyeMode').value;
    const custom = document.getElementById('eyeCustomControls');
    const preset = document.getElementById('eyePresetControls');
    if (custom) custom.hidden = mode !== 'custom';
    if (preset) preset.hidden = mode !== 'preset';
}

async function seekRefresh() {
    try {
        const eyeRes = await fetch('/api/mods/SeekDashboard/getEyeColor');
        if (eyeRes.ok) {
            const eye = await eyeRes.json();
            if (eye.iscustom) {
                document.getElementById('eyeMode').value = 'custom';
                document.getElementById('eyeHue').value = eye.hue;
                document.getElementById('eyeSat').value = eye.saturation;
                document.getElementById('eyeHueVal').textContent = Number(eye.hue).toFixed(2);
                document.getElementById('eyeSatVal').textContent = Number(eye.saturation).toFixed(2);
            } else {
                document.getElementById('eyeMode').value = 'preset';
                document.getElementById('eyePreset').value = String(eye.preset);
            }
            seekEyeModeChanged();
        }
        const volRes = await fetch('/api/mods/SeekDashboard/getVolume');
        if (volRes.ok) {
            document.getElementById('masterVolume').value = (await volRes.text()).trim();
        }
    } catch (e) {
        console.log('seekRefresh', e);
    }
}

async function seekSetEyeColor() {
    setSeekStatus('Setting eye color...');
    try {
        const mode = document.getElementById('eyeMode').value;
        let url = '/api/mods/SeekDashboard/setEyeColor?mode=' + encodeURIComponent(mode);
        if (mode === 'preset') {
            url += '&preset=' + encodeURIComponent(document.getElementById('eyePreset').value);
        } else {
            url += '&hue=' + encodeURIComponent(document.getElementById('eyeHue').value);
            url += '&saturation=' + encodeURIComponent(document.getElementById('eyeSat').value);
        }
        const res = await fetch(url);
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
        const v = document.getElementById('masterVolume').value;
        const res = await fetch('/api/mods/SeekDashboard/setVolume?volume=' + encodeURIComponent(v));
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
    const text = document.getElementById('sayText').value.trim();
    if (!text) {
        setSeekStatus('Enter something for Vector to say.', true);
        return;
    }
    setSeekStatus('Saying...');
    try {
        const useVoice = document.getElementById('sayVectorVoice').value;
        const res = await fetch(
            '/api/mods/SeekDashboard/sayText?text=' + encodeURIComponent(text) +
            '&vectorVoice=' + useVoice
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
    const input = document.getElementById('audioFile');
    if (!input.files || !input.files[0]) {
        setSeekStatus('Choose an MP3 or WAV file first.', true);
        return;
    }
    const file = input.files[0];
    const vol = document.getElementById('audioPlayVolume').value;
    setSeekStatus('Uploading and playing ' + file.name + '...');
    try {
        const fd = new FormData();
        fd.append('file', file, file.name);
        fd.append('volume', vol);
        const res = await fetch('/api/mods/SeekDashboard/playAudio', { method: 'POST', body: fd });
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

// Official Vector SDK byte order: HIGH byte first (not little-endian).
function rgbaToRgb565(rgba) {
    const out = new Uint8Array(SEEK_FACE_W * SEEK_FACE_H * 2);
    let o = 0;
    for (let i = 0; i < rgba.length; i += 4) {
        const r5 = rgba[i] >> 3;
        const g6 = rgba[i + 1] >> 2;
        const b5 = rgba[i + 2] >> 3;
        const g3hi = g6 >> 3;
        const g3lo = g6 & 0x07;
        out[o++] = (r5 << 3) | g3hi;
        out[o++] = (g3lo << 5) | b5;
    }
    return out;
}

// Floyd–Steinberg dithering improves perceived quality on RGB565.
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
            let r = buf[idx];
            let g = buf[idx + 1];
            let b = buf[idx + 2];
            const r5 = Math.max(0, Math.min(31, Math.round(r / 8.225806)));
            const g6 = Math.max(0, Math.min(63, Math.round(g / 4.047619)));
            const b5 = Math.max(0, Math.min(31, Math.round(b / 8.225806)));
            const qr = r5 * 8.225806;
            const qg = g6 * 4.047619;
            const qb = b5 * 8.225806;
            const er = r - qr;
            const eg = g - qg;
            const eb = b - qb;
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
            const g3hi = g6 >> 3;
            const g3lo = g6 & 0x07;
            out[o++] = (r5 << 3) | g3hi;
            out[o++] = (g3lo << 5) | b5;
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
    let scale;
    if (fit === 'contain') {
        scale = Math.min(SEEK_FACE_W / vw, SEEK_FACE_H / vh);
    } else {
        scale = Math.max(SEEK_FACE_W / vw, SEEK_FACE_H / vh);
    }
    const dw = Math.max(1, Math.round(vw * scale));
    const dh = Math.max(1, Math.round(vh * scale));
    const dx = Math.floor((SEEK_FACE_W - dw) / 2);
    const dy = Math.floor((SEEK_FACE_H - dh) / 2);
    ctx.drawImage(video, dx, dy, dw, dh);
}

async function decodeFileToPcm16k(file) {
    const arr = await file.arrayBuffer();
    const probe = new (window.AudioContext || window.webkitAudioContext)();
    const decoded = await probe.decodeAudioData(arr.slice(0));
    await probe.close();

    const srcRate = decoded.sampleRate;
    const srcFrames = decoded.length;
    const left = decoded.getChannelData(0);
    const right = decoded.numberOfChannels > 1 ? decoded.getChannelData(1) : null;
    const monoBuf = new AudioBuffer({
        length: srcFrames,
        numberOfChannels: 1,
        sampleRate: srcRate
    });
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
        let s = Math.max(-1, Math.min(1, f32[i]));
        view.setInt16(i * 2, (s * 32767) | 0, true);
    }
    return new Uint8Array(pcm);
}

async function seekStopMedia() {
    if (seekVideoAbort) seekVideoAbort.abort = true;
    try { await fetch('/api/mods/SeekDashboard/controlEnd'); } catch (_) {}
    setSeekStatus('Stopped.');
}

async function seekPlayVideo() {
    const input = document.getElementById('videoFile');
    if (!input.files || !input.files[0]) {
        setSeekStatus('Choose an MP4 (or other video) first.', true);
        return;
    }
    const file = input.files[0];
    const fps = Math.max(1, Math.min(15, Number(document.getElementById('videoFps').value) || 12));
    const withAudio = document.getElementById('videoWithAudio').value !== '0';
    const fit = document.getElementById('videoFit').value;
    const canvas = document.getElementById('seekVideoCanvas');
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const btn = document.getElementById('videoPlayBtn');
    const vol = document.getElementById('audioPlayVolume')
        ? document.getElementById('audioPlayVolume').value
        : '100';
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
            setSeekStatus('Decoding audio (16 kHz)...');
            try {
                pcm = await decodeFileToPcm16k(file);
            } catch (err) {
                console.log('audio extract failed', err);
                setSeekStatus('Playing video without audio (' + err.message + ')');
            }
        }

        setSeekStatus('Taking control...');
        let res = await fetch('/api/mods/SeekDashboard/controlStart');
        if (!res.ok) {
            const e = await res.json();
            throw new Error(e.message || 'controlStart failed');
        }

        // Start audio streaming immediately (server streams body; no full buffer wait).
        const audioPromise = pcm
            ? fetch('/api/mods/SeekDashboard/playPcm?rate=16000&volume=' + encodeURIComponent(vol), {
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
            const rgb565 = rgbaToRgb565Dithered(rgba);
            const frameRes = await fetch('/api/mods/SeekDashboard/frame?duration_ms=' + holdMs, {
                method: 'POST',
                headers: { 'Content-Type': 'application/octet-stream' },
                body: rgb565
            });
            if (!frameRes.ok) {
                const e = await frameRes.json().catch(() => ({ message: 'frame failed' }));
                throw new Error(e.message || 'frame failed');
            }
            nextT += frameMs;
            const wait = nextT - performance.now();
            if (wait > 0) await new Promise(r => setTimeout(r, wait));
            else nextT = performance.now();
        }

        await audioPromise;
        await fetch('/api/mods/SeekDashboard/controlEnd');
        setSeekStatus(token.abort ? 'Stopped.' : 'Video finished.');
    } catch (e) {
        try { await fetch('/api/mods/SeekDashboard/controlEnd'); } catch (_) {}
        setSeekStatus('video error: ' + e.message, true);
    } finally {
        video.pause();
        URL.revokeObjectURL(url);
        btn.disabled = false;
        seekVideoAbort = null;
    }
}

// Page boot
if (document.getElementById('eyeMode')) {
    seekEyeModeChanged();
    seekRefresh();
}
