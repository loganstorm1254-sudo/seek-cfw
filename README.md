# LIFE OS

Custom Vector firmware. **Not SeekOS.** Built from official **WireOS 3.0.1.32d**, then rebranded.

## Boot

1. **Static first screen** (rampost): the portrait, stretched to 184×96.
2. **Moving second screen** (`vic-bootAnim`): the starfield GIF animation (silent — no boot-song hold).

CCIS: `MYLIFE` / `Ordinary Life OS`. Faults **890** and **899** never show.

## Songs menu

Double-click backpack on charger → pairing → lift into the CCIS menu. The first item is **SONG** (patched from EXIT). Confirm it with a lift (or backpack once debug screens are unlocked). That starts a face playlist with video + audio:

- Muffin
- I Will Survive
- Ordinary Life
- Never Be Alone

SSH: `life-songs muffin|survive|ordinary|neveralone|menu`

## Install

Release: https://github.com/loganstorm1254-sudo/seek-cfw/releases/tag/v5.0.0.5d-life

If `update-os` dies with `Text file busy` on `/usr/bin/curl`, unlink first:

```bash
mount -o remount,rw /
cp -L /usr/bin/curl /usr/bin/curl.anki
chmod 755 /usr/bin/curl.anki
rm -f /usr/bin/curl
cat > /usr/bin/curl << 'EOF'
#!/bin/sh
exec /usr/bin/curl.anki -k -L --http1.1 -4 --connect-timeout 30 "$@"
EOF
chmod 755 /usr/bin/curl
```

Then:

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v5.0.0.5d-life/vicos-5.0.0.5d.ota
```

```bash
curl -L -o robot_sshkey https://github.com/kercre123/unlocking-vector/raw/refs/heads/main/ssh_root_key
chmod 600 robot_sshkey
ssh -i robot_sshkey root@VECTOR_IP
```

Recovery: `ota-start` with the same URL. Dev-signed unlocked Vector only.

Do **not** install `v5.0.0.2d-life` (bootloop).

## Assets

- Static: `seek/assets/life-static-source.png` → stretched `life-static-184x96.png`
- Moving: `seek/assets/starfield-boot.gif` → `boot_anim.raw`
- Songs: `seek/overlays/anki/data/life-songs/`

```bash
python3 seek/tools/test_cfw_assets.py
```
