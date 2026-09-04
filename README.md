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

- **Default:** full body stays on — **wheels, head, lift, backpack button, lights**. Flaky spine just retries; no 898/899 face code and no service teardown.
- Dummy-body fallback (synthetic sensors) is only for `spine_open` failure or optional `/data/seek/head_only`.
- Early boot (`rampost`) also continues when syscon/DFU does not answer, so 801/802 no longer block the LCD.

**The published `v3.0.1.20d-dvt` GitHub OTA does not include this.** That is stock SeekOS DVT. Head-only lives on this branch and needs its own OTA (or a `vic-robot` hotfix) built from it.

Only force dummy sensors if you need to (keeps motors when UART opens; blocks normal SyncRobot until spine recovers):

```sh
mkdir -p /data/seek
touch /data/seek/head_only
```

Default install does **not** create that file. Remove it and restart `vic-robot` if eyes are frozen idle.


## Install / update on the robot

### Head-only hotfix (this branch)

If you already have SeekOS DVT on the robot, **do not flash that DVT OTA again**. Drop in the patched `vic-robot` (~150KB):

On the robot:

```sh
curl -L -o /data/seek-headonly.tgz https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/head-only-ignore-body-7a4a/seek/hotfix/seek-headonly.tgz
mkdir -p /data/seek-headonly
tar -C /data/seek-headonly -xzf /data/seek-headonly.tgz
sh /data/seek-headonly/install.sh
```

That replaces `/anki/bin/vic-robot` (dummy wheels, live **lift** + backpack button/lights), installs the 898/899 handler, and `touch /data/seek/head_only`. Eyes stay up; no 200MB download.

### Full OTA (stock SeekOS, not head-only)

```sh
update-os http://files.anki.org.uk/ota/latest
```

The published `v3.0.1.20d-dvt` GitHub OTA is that same DVT image. It does **not** include the body-ignore HAL.


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
