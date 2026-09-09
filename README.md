# SeekOS (Seek CFW)

Custom firmware for **Anki Vector 1.0** (and 2.0), based on [WireOS](https://github.com/os-vector/wire-os).

This repo follows the [Make Your Own CFW](https://os-vector.github.io/vector-docs/6.-Make-Your-Own-CFW/1.%20prerequisites.html) guide: WireOS is the base OS tree; Seek-specific identity lives under `seek/` and is applied at build time.

## Branding

CCIS face-info strings (guide step in `faceInfoScreenManager.cpp`):

| Field | Value |
| --- | --- |
| OSProject | `DPRK` |
| Creator | `DEMOCRATIC PEOPLE'S` |
| CreatorWebsite | `REPUBLIC OF KOREA` |

These are the English lines from the top of the boot-cover image. The Hangul `조선민주주의인민공화국` is rasterized on the static boot splash (Vector's OpenCV face fonts cannot draw Hangul).

Source of truth: `seek/overlays/anki/victor/animProcess/src/cozmoAnim/faceDisplay/faceInfoScreenManager.cpp`

## Fault codes 890 and 899

**890** (`CLIFF_FR`, front-right cliff self-test) and **899** (`NO_BODY`, syscon not answering) are suppressed so they never appear on the face and never take down `anki-robot.target`.

- `DisplayFaultCode()` in `faultCodes.h` returns immediately for those two codes (nothing is written to `/run/fault_code`).
- `fault-code-handler` also exits 0 if either code still arrives on the FIFO.

899 is a known false-positive from Anki 1.6. Other fault codes still display normally.

## Backpack button

| Gesture | Action |
| --- | --- |
| Single click | Wake word / attention |
| Double click (off charger) | Mic mute/unmute |
| **Triple click** (3 quick taps) | **Mute/unmute all sounds** + mute icon top-right |

## Boot splash

The first static early-boot screen (rampost `anki_dev_unit`, always shown because initramfs runs `rampost -d`) is the passport-cover splash: navy, gold **조선민주주의인민공화국** / **DEMOCRATIC PEOPLE'S REPUBLIC OF KOREA**, and the national emblem.

`vic-bootAnim` uses a **single-frame** `boot_anim.raw` of the same image, so the later boot sequence stays static too.

- Source cover: `seek/assets/dprk-passport.webp`
- Preview: `seek/assets/dprk-boot-184x96.png`
- Overlay: `seek/overlays/anki/rampost/anki_dev_unit.h` (184×96 RGB565)
- Boot anim: `seek/overlays/anki/victor/resources/config/engine/animations/boot_anim.raw` (and `_20` for Vector 2.0)
- Regenerate: `python3 seek/tools/make_boot_splash.py`
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
