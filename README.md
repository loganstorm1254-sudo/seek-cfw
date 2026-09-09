# LIFE OS

Custom Vector firmware. **Not SeekOS.** This image is built from official **WireOS 3.0.1.32d**, then rebranded.

## Boot

1. **Static first screen** (rampost): the portrait, stretched to 184×96.
2. **Moving second screen** (`vic-bootAnim`): *My Ordinary Life* starting at the singing (~0:44). The Living Tombstone intro/credits are cut. The clip stays on the face and **plays the song** once the speaker is up, then the eyes take over.

CCIS: `MYLIFE` / `Ordinary Life OS`. Faults **890** and **899** never show.

## Install

Release: https://github.com/loganstorm1254-sudo/seek-cfw/releases/tag/v5.0.0.3d-life

```bash
curl -L -o robot_sshkey https://github.com/kercre123/unlocking-vector/raw/refs/heads/main/ssh_root_key
chmod 600 robot_sshkey
ssh -i robot_sshkey root@VECTOR_IP
```

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v5.0.0.3d-life/vicos-5.0.0.3d.ota
```

Recovery: `ota-start` with the same URL. Dev-signed unlocked Vector only.

Do **not** install `v5.0.0.2d-life` (bootloop) or the older Seek/Choson OTAs.

## Assets

- Static: `seek/assets/life-static-source.png` → stretched `life-static-184x96.png`
- Moving: *My Ordinary Life* from 0:44, 40s loop, 12 fps, plus `boot-music.wav` (48 kHz stereo)
- Hold: `life-boot-hold` plays that WAV on the still-running clip after WireOS audio init, then starts the eyes. Does **not** poke the Hexagon ADSP (that bootlooped 5.0.0.2d).

```bash
python3 seek/tools/test_cfw_assets.py
```
