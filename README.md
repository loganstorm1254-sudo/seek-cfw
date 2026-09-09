# ChosonOS

Custom firmware for **Anki Vector 1.0** (and 2.0). This is **not** SeekOS — it is a separate CFW image with its own identity, boot sequence, and fault policy, built from a [WireOS](https://github.com/os-vector/wire-os) tree.

## What you see on boot

1. **Static first screen** (rampost `anki_dev_unit`, initramfs `rampost -d`): DPRK passport cover — navy leather, gold **조선민주주의인민공화국** / **DEMOCRATIC PEOPLE'S REPUBLIC OF KOREA**, national emblem.
2. **Moving second screen** (`vic-bootAnim` looping `boot_anim.raw`): The Orville “500 cigarettes” clip.

Faults **890** (`CLIFF_FR`) and **899** (`NO_BODY`) never appear and never take down `anki-robot.target`.

## Branding (CCIS)

| Field | Value |
| --- | --- |
| OSProject | `CHOSON` |
| Creator | `DEMOCRATIC PEOPLE'S` |
| CreatorWebsite | `REPUBLIC OF KOREA` |

Hangul is rasterized on the static splash (Vector's OpenCV face fonts cannot draw it).

Source: `seek/overlays/anki/victor/animProcess/src/cozmoAnim/faceDisplay/faceInfoScreenManager.cpp`

## Install OTA

Release: https://github.com/loganstorm1254-sudo/seek-cfw/releases/tag/v4.0.0.1d-choson

SSH from a PC:

```bash
curl -L -o robot_sshkey https://github.com/kercre123/unlocking-vector/raw/refs/heads/main/ssh_root_key
chmod 600 robot_sshkey
ssh -i robot_sshkey root@VECTOR_IP
```

On the robot:

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v4.0.0.1d-choson/vicos-4.0.0.1d.ota
```

Recovery:

```bash
ota-start https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v4.0.0.1d-choson/vicos-4.0.0.1d.ota
```

## Assets

| Screen | Source | Overlay |
| --- | --- | --- |
| Static rampost | `seek/assets/dprk-passport.webp` | `seek/overlays/anki/rampost/anki_dev_unit.h` |
| Moving boot | `seek/assets/orville-500-cigarettes.mp4` | `.../animations/boot_anim.raw` (+ `_20` for Vector 2.0) |

Regenerate:

```bash
python3 seek/tools/make_boot_splash.py
python3 seek/tools/make_boot_anim.py   # needs ffmpeg
python3 seek/tools/test_cfw_assets.py
```

`seek/apply-overlay.sh` copies overlays into the tree before `./build/build.sh`.

## Fault codes 890 and 899

- `DisplayFaultCode()` in `faultCodes.h` returns immediately for those two codes.
- `fault-code-handler` also exits 0 if either code still arrives on the FIFO.

## Backpack button

| Gesture | Action |
| --- | --- |
| Single click | Wake word / attention |
| Double click (off charger) | Mic mute/unmute |
| **Triple click** (3 quick taps) | **Mute/unmute all sounds** + mute icon top-right |

## Prerequisites / full Yocto build

- Linux x86_64 with **git**, **docker**, **wget**, **ffmpeg** (boot anim)
- 16GB+ RAM, 100GB+ disk
- Unlocked Vector

```bash
git clone https://github.com/loganstorm1254-sudo/seek-cfw --recurse-submodules
cd seek-cfw
./build/build.sh -bt dev -v 1
```

Output: `./_build/vicos-4.0.0.1d.ota` (version comes from `ANKI_VERSION` + `-v`).

If `docker build` fails with an overlay mount `invalid argument` error:

```bash
sudo mkdir -p /etc/docker
echo '{"storage-driver":"vfs"}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

Bare metal: `./build/build.sh -nd -bt dev -v 1`

## Layout

- **seek-cfw** — OS / OTA builder (this repo)
- **Choson deltas** — `seek/overlays` + `seek/patches`
- **anki/victor** — WireOS victor submodule (applied overlays at build time)

## Upstream

Base OS tree tracks [os-vector/wire-os](https://github.com/os-vector/wire-os). Credit Wire/kercre123 for the maintained CFW platform.

## License

Same as upstream WireOS / Anki-derived sources in this tree. See `LICENSE` and `LICENSE-README`.
