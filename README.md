# LIFE OS

Custom Vector firmware. **Not SeekOS.** This image is built from official **WireOS 3.0.1.32d**, then rebranded.

## Boot

1. **Static first screen** (rampost): the portrait, stretched to 184×96.
2. **Moving second screen** (`vic-bootAnim`): *My Ordinary Life* starting at the singing (~0:44). The Living Tombstone intro/credits are cut. After the speaker is up, the clip stays on and the **full 40s song** plays (`aplay`), then the eyes take over.

CCIS: `MYLIFE` / `Ordinary Life OS`. Faults **890** and **899** never show.

## Install

Release: https://github.com/loganstorm1254-sudo/seek-cfw/releases/tag/v5.0.0.4d-life

```bash
curl -L -o robot_sshkey https://github.com/kercre123/unlocking-vector/raw/refs/heads/main/ssh_root_key
chmod 600 robot_sshkey
ssh -i robot_sshkey root@VECTOR_IP
```

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v5.0.0.4d-life/vicos-5.0.0.4d.ota
```

Recovery: `ota-start` with the same URL. Dev-signed unlocked Vector only.

Do **not** install `v5.0.0.2d-life` (bootloop). Skip 5.0.0.1d/3d if boot sound was only a chirp.

## Assets

- Static: `seek/assets/life-static-source.png` → stretched `life-static-184x96.png`
- Moving: *My Ordinary Life* from 0:44, 40s, 12 fps, plus a **canonical 44-byte** 48 kHz stereo `boot-music.wav` (no LIST chunk — Vector `tinyplay` cannot skip those)
- Music: `life-boot-music.service` runs `aplay` after WireOS audio init, while the clip is still on the face

```bash
python3 seek/tools/test_cfw_assets.py
```
