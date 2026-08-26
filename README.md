# SeekOS (Seek CFW)

Custom firmware for **Anki Vector 1.0** (and 2.0), based on [WireOS](https://github.com/os-vector/wire-os).

This repo follows the [Make Your Own CFW](https://os-vector.github.io/vector-docs/6.-Make-Your-Own-CFW/1.%20prerequisites.html) guide: WireOS is the base OS tree; Seek-specific identity lives under `seek/` and is applied at build time.

## Branding

CCIS face-info strings (guide step in `faceInfoScreenManager.cpp`):

| Field | Value |
| --- | --- |
| OSProject | `SeekOS` |
| Creator | `By Logan / Seek CFW` |
| CreatorWebsite | `github.com/loganstorm1254-sudo/seek-cfw` |

Source of truth: `seek/overlays/anki/victor/animProcess/src/cozmoAnim/faceDisplay/faceInfoScreenManager.cpp`



## Head-only (no 898 / 899)

**898** (`SPINE_SELECT_TIMEOUT`) and **899** (`NO_BODY`) mean the head board cannot talk to the body board (flaky spine cable, body MCU, etc.). SeekOS does **not** show those faults.

- If the body answers, Vector still drives and uses sensors as usual.
- If spine comms fail at boot or drop out later, `vic-robot` switches to a dummy body so **face and eyes still power up**. It **keeps talking to the body for the backpack button and backpack lights** (motors/cliffs stay ignored so 898/899 cannot come back).
- Early boot (`rampost`) also continues when syscon/DFU does not answer, so 801/802 no longer block the LCD.

To **always** use dummy sensors (still tries backpack button + lights if the UART opens):

```sh
mkdir -p /data/seek
touch /data/seek/head_only
```

Remove that file and reboot to try full body sensors/motors again.


## Install / update on the robot

SSH in (or BLE shell) and run:

```sh
update-os http://files.anki.org.uk/ota/latest
```

Eyes go dark while it downloads, then Vector reboots onto the new OTA.

**Slow Wi‑Fi:** Vector’s 2.4 GHz radio crawling ~200MB from the internet can take a long time. Faster: download the `.ota` on your PC, then serve it on the LAN:

1. On the PC, download `vicos-3.0.1.20d.ota` (GitHub release or any host).
2. In that folder: `python -m http.server 8000` (Windows: `py -m http.server 8000`).
3. `ipconfig` / `ip addr` — use the PC’s address on the **same Wi‑Fi as Vector** (e.g. `192.168.42.10`).
4. On the robot:

```sh
update-os http://192.168.42.10:8000/vicos-3.0.1.20d.ota
```

If an `update-os` is already running, Ctrl+C it first (that stops `update-engine`). Windows Firewall must allow TCP 8000.

GitHub release (same idea, pick the `.ota` you want):

```sh
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v3.0.1.20d-dvt/vicos-3.0.1.20d.ota
```

This head-only / backpack keep-alive build needs a new OTA built from this branch, then uploaded to `files.anki.org.uk` (or a GitHub release) before that URL contains the fix.


## Backpack button

| Gesture | Action |
| --- | --- |
| Single click | Wake word / attention |
| Double click (off charger) | Mic mute/unmute |
| **Triple click** (3 quick taps) | **Mute/unmute all sounds** + mute icon top-right |

## Boot splash

The first static early-boot screen (rampost `anki_dev_unit`) is the **SeekAra** wordmark.

- Source: `seek/assets/seekara-boot-184x96.png`
- Overlay: `seek/overlays/anki/rampost/anki_dev_unit.h` (184×96 RGB565)
- Applied automatically by `seek/apply-overlay.sh` before `./build/build.sh`

## Prerequisites

- Linux x86_64 (recommended) with **git**, **docker**, **wget**
- Comfortable build box: 16GB+ RAM, plenty of disk (100GB+ free)
- An unlocked Vector to flash/test

See the [official prerequisites](https://os-vector.github.io/vector-docs/6.-Make-Your-Own-CFW/1.%20prerequisites.html).

## Clone

```bash
git clone https://github.com/loganstorm1254-sudo/seek-cfw --recurse-submodules
cd seek-cfw
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

## Build a Vector OTA (SeekOS)

Docker method (x86_64):

```bash
./build/build.sh -bt dev -v 1
```

- `-bt dev` — unlocked / “dev” robot type (typical for CFW)
- `-v 1` — build increment → OTA version `3.0.1.1`

Output (after a successful build):

```text
./_build/vicos-3.0.1.1d.ota
```


### Cloud / nested-container Docker tip

If `docker build` fails with an overlay mount `invalid argument` error (common when Docker runs inside another overlay filesystem), configure the VFS storage driver:

```bash
sudo mkdir -p /etc/docker
echo '{"storage-driver":"vfs"}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker   # or restart dockerd
```

Bare metal (no Docker):

```bash
./build/build.sh -nd -bt dev -v 1
```

## Develop personality code (/anki)

Most day-to-day work is in `anki/victor` (WireOS victor submodule). After editing, you can build/deploy just `/anki` from that tree (`./build/build-v.sh` / `./build/deploy-v.sh`) once a compatible base OTA is on the robot — see the [how-to-develop](https://os-vector.github.io/vector-docs/6.-Make-Your-Own-CFW/3.%20how.html) docs.

Seek branding is re-applied whenever you run `./build/build.sh` via `seek/apply-overlay.sh`.

## Fork layout note

The upstream guide recommends three repos (`*-os`, `*-os-victor`, `*-os-externals`). This cloud environment can only write to **seek-cfw**, so Seek uses:

- **seek-cfw** — OS / OTA builder (this repo, WireOS-based)
- **anki/victor** — still the upstream `wire-os-victor` submodule
- **Seek deltas** — `seek/overlays` + `seek/patches` (instead of a separate victor fork)

If you later create `seek-cfw-victor` and `seek-cfw-externals` under your account, point the submodules at them as described in [Forking](https://os-vector.github.io/vector-docs/6.-Make-Your-Own-CFW/2.%20forking.html).

## Upstream

SeekOS tracks [os-vector/wire-os](https://github.com/os-vector/wire-os) and its submodules. WireOS is the maintained base CFW from Wire/kercre123 — please credit upstream and sync their fixes when you can.

## License

Same as upstream WireOS / Anki-derived sources in this tree. See `LICENSE` and `LICENSE-README`.
