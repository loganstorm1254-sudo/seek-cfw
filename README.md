# LIFE OS

Custom Vector firmware. **Not SeekOS.** Built from official **WireOS 3.0.1.32d**, then rebranded.

## Boot

1. **Static first screen** (rampost): the portrait, stretched to 184×96.
2. **Moving second screen** (`vic-bootAnim`): the starfield GIF animation (silent).

CCIS: `MYLIFE` / `Ordinary Life OS`. Faults **890** and **899** never show.

## CCIS menu

- **EXIT** — leave
- **SELF TEST** — hardware self-test
- **CLEAR** — wipe data
- **SONGS** — face playlist (confirm with lift)

Do **not** install `v5.0.0.10d` (fault **800** bootloop — bad `vic-anim` patch). Prefer **12d** over 11d (11d replaced TEST with SONGS).

SSH: `life-songs muffin|survive|ordinary|neveralone|menu`

## Install

Release: https://github.com/loganstorm1254-sudo/seek-cfw/releases/tag/v5.0.0.12d-life

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v5.0.0.12d-life/vicos-5.0.0.12d.ota
```

```bash
curl -L -o robot_sshkey https://github.com/kercre123/unlocking-vector/raw/refs/heads/main/ssh_root_key
chmod 600 robot_sshkey
ssh -i robot_sshkey root@VECTOR_IP
```

Dev-signed unlocked Vector only. Do **not** install `v5.0.0.2d-life` (bootloop).
