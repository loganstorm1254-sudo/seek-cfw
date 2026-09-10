# LIFE OS

Custom Vector firmware. **Not SeekOS.** Built from official **WireOS 3.0.1.32d**, then rebranded.

## Boot

1. **Static first screen** (rampost): the portrait, stretched to 184×96.
2. **Moving second screen** (`vic-bootAnim`): the starfield GIF animation (silent).

CCIS: `MYLIFE` / `Ordinary Life OS`. Faults **890** and **899** never show.

## CCIS menu

- **EX** — leave
- **SONGS** — face playlist (confirm with lift)
- **CLR** — wipe data

Do **not** install `v5.0.0.10d` (fault **800** bootloop from a bad `vic-anim` patch).

SSH: `life-songs muffin|survive|ordinary|neveralone|menu`

## Install (recovery from 800)

Release: https://github.com/loganstorm1254-sudo/seek-cfw/releases/tag/v5.0.0.11d-life

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v5.0.0.11d-life/vicos-5.0.0.11d.ota
```

If `update-os` will not run in the bootloop, use recovery / `ota-start` with the same URL.

```bash
curl -L -o robot_sshkey https://github.com/kercre123/unlocking-vector/raw/refs/heads/main/ssh_root_key
chmod 600 robot_sshkey
ssh -i robot_sshkey root@VECTOR_IP
```

Dev-signed unlocked Vector only. Do **not** install `v5.0.0.2d-life` (bootloop).
