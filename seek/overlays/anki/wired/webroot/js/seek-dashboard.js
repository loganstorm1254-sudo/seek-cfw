const SEEK_FACE_W = 184;
const SEEK_FACE_H = 96;
let seekVideoAbort = null;

function setSeekStatus(msg, isError) {
    const el = document.getElementById('seekStatus');
    if (!el) return;
    if (!msg) {
        el.style.display = 'none';
        el.innerHTML = '';
        return;
    }
    el.style.display = 'block';
    el.style.color = isError ? '#f87171' : '#86efac';
    el.innerHTML = `<p>${msg}</p>`;
}

function seekEyeModeChanged() {
    const mode = document.getElementById('eyeMode').value;
    document.getElementById('eyeCustomControls').style.display = mode === 'custom' ? 'block' : 'none';
    document.getElementById('eyePresetControls').style.display = mode === 'preset' ? 'block' : 'none';
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
            const vol = await volRes.text();
            document.getElementById('masterVolume').value = vol.trim();
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

function rgbaToRgb565(rgba) {
    const out = new Uint8Array(SEEK_FACE_W * SEEK_FACE_H * 2);
    let o = 0;
    for (let i = 0; i < rgba.length; i += 4) {
        const r = rgba[i] >> 3;
        const g = rgba[i + 1] >> 2;
        const b = rgba[i + 2] >> 3;
        const v = (r << 11) | (g << 5) | b;
        out[o++] = v & 0xff;
        out[o++] = (v >> 8) & 0xff;
    }
    return out;
}

function resampleAudioBufferToPCM16(audioBuffer, targetRate) {
    const channels = audioBuffer.numberOfChannels;
    const srcRate = audioBuffer.sampleRate;
    const srcLen = audioBuffer.length;
    const ratio = srcRate / targetRate;
    const outLen = Math.max(1, Math.floor(srcLen / ratio));
    const pcm = new ArrayBuffer(outLen * 2);
    const view = new DataView(pcm);
    const left = audioBuffer.getChannelData(0);
    const right = channels > 1 ? audioBuffer.getChannelData(1) : null;
    for (let i = 0; i < outLen; i++) {
        const srcPos = i * ratio;
        const i0 = Math.min(srcLen - 1, Math.floor(srcPos));
        const i1 = Math.min(srcLen - 1, i0 + 1);
        const frac = srcPos - i0;
        let s0 = left[i0];
        let s1 = left[i1];
        if (right) {
            s0 = (s0 + right[i0]) * 0.5;
            s1 = (s1 + right[i1]) * 0.5;
        }
        let s = s0 * (1 - frac) + s1 * frac;
        s = Math.max(-1, Math.min(1, s));
        view.setInt16(i * 2, (s * 32767) | 0, true);
    }
    return new Uint8Array(pcm);
}

async function seekStopMedia() {
    if (seekVideoAbort) {
        seekVideoAbort.abort = true;
    }
    try {
        await fetch('/api/mods/SeekDashboard/controlEnd');
    } catch (_) {}
    setSeekStatus('Stopped.');
}

async function seekPlayVideo() {
    const input = document.getElementById('videoFile');
    if (!input.files || !input.files[0]) {
        setSeekStatus('Choose an MP4 (or other video) first.', true);
        return;
    }
    const file = input.files[0];
    const fps = Math.max(1, Math.min(15, Number(document.getElementById('videoFps').value) || 8));
    const withAudio = document.getElementById('videoWithAudio').value !== '0';
    const canvas = document.getElementById('seekVideoCanvas');
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const btn = document.getElementById('videoPlayBtn');
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

        setSeekStatus('Taking control...');
        let res = await fetch('/api/mods/SeekDashboard/controlStart');
        if (!res.ok) {
            const e = await res.json();
            throw new Error(e.message || 'controlStart failed');
        }

        let pcm = null;
        if (withAudio) {
            setSeekStatus('Decoding audio...');
            try {
                const arr = await file.arrayBuffer();
                const ac = new (window.AudioContext || window.webkitAudioContext)();
                const decoded = await ac.decodeAudioData(arr.slice(0));
                pcm = resampleAudioBufferToPCM16(decoded, 16000);
                await ac.close();
            } catch (err) {
                console.log('audio extract failed', err);
                setSeekStatus('Playing video without audio (' + err.message + ')');
            }
        }

        const audioPromise = pcm
            ? fetch('/api/mods/SeekDashboard/playPcm?rate=16000&volume=80', {
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
        setSeekStatus('Playing video on face @ ' + fps + ' fps...');

        while (!video.ended && !token.abort) {
            // letterbox into 184x96
            const vw = video.videoWidth || SEEK_FACE_W;
            const vh = video.videoHeight || SEEK_FACE_H;
            const scale = Math.min(SEEK_FACE_W / vw, SEEK_FACE_H / vh);
            const dw = Math.max(1, Math.round(vw * scale));
            const dh = Math.max(1, Math.round(vh * scale));
            const dx = Math.floor((SEEK_FACE_W - dw) / 2);
            const dy = Math.floor((SEEK_FACE_H - dh) / 2);
            ctx.fillStyle = '#000';
            ctx.fillRect(0, 0, SEEK_FACE_W, SEEK_FACE_H);
            ctx.drawImage(video, dx, dy, dw, dh);
            const rgba = ctx.getImageData(0, 0, SEEK_FACE_W, SEEK_FACE_H).data;
            const rgb565 = rgbaToRgb565(rgba);
            const frameRes = await fetch('/api/mods/SeekDashboard/frame?duration_ms=' + frameMs, {
                method: 'POST',
                headers: { 'Content-Type': 'application/octet-stream' },
                body: rgb565
            });
            if (!frameRes.ok) {
                const e = await frameRes.json().catch(() => ({ message: 'frame failed' }));
                throw new Error(e.message || 'frame failed');
            }
            await new Promise(r => setTimeout(r, frameMs));
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
