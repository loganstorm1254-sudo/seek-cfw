# LIFE OS

Custom Vector firmware. **Not SeekOS.** Built from official **WireOS 3.0.1.32d**, then rebranded.

## Boot

1. **Static first screen** (rampost): the portrait, stretched to 184×96.
2. **Moving second screen** (`vic-bootAnim`): the animated boot clip.

CCIS: `MYLIFE` / `Ordinary Life OS`. Faults **800**, **890**, and **899** never show.

## CCIS menu

Stock: **EXIT** / **SELF TEST** / **CLEAR**.

## Install

Release: https://github.com/loganstorm1254-sudo/seek-cfw/releases/tag/v5.0.0.14d-life

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v5.0.0.14d-life/vicos-5.0.0.14d.ota
```

```bash
curl -L -o robot_sshkey https://github.com/kercre123/unlocking-vector/raw/refs/heads/main/ssh_root_key
chmod 600 robot_sshkey
ssh -i robot_sshkey root@VECTOR_IP
```

Dev-signed unlocked Vector only. Do **not** install `v5.0.0.2d-life`, `v5.0.0.10d-life`, or `v5.0.0.12d-life` (bootloop / fault 800).
