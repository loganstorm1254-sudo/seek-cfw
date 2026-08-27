# Seek Cozmo Companion

Controls **Vector** (WireOS / Seek CFW) with a Cozmo-styled UI.

The official Cozmo app cannot talk to Vector (different protocol). This companion
uses Vector’s SDK/gRPC over Wi‑Fi instead.

## Status

| Piece | Status |
|-------|--------|
| Python drive tool | Usable now (see `python/`) |
| Android APK | Source scaffold in `android/` — open in Android Studio to build |
| Cozmo sounds on robot | Needs your soundbanks — see `../cozmo-audio/` |

## Quick start (Python, today)

1. Pair Vector with the SDK (same as normal Vector SDK / Wire DDL credentials).
2. Note the robot IP from CCIS Main (`IP: …`).
3. On your PC:

```bash
cd seek/companion/python
pip3 install -e ../../../anki/victor/tools/sdk/vector-python-sdk-private/sdk
python3 drive_cozmo.py --ip 192.168.42.111
```

WASD / arrows drive. Space stop. `a` plays a greet anim. `q` quit.

## Android

Open `android/` in Android Studio (Giraffe+), sync Gradle, run on a phone on the
same Wi‑Fi as Vector. Enter IP + SDK serial/guid/cert from your SDK config.

APK is **not** prebuilt in this cloud environment (no Android SDK here).

## Cozmo mode on the robot

CCIS Main → **COZMO** → confirm. That only changes the face (CRT eyes). Sounds
stay Vector until you install a Cozmo sound pack (see `../cozmo-audio/`).
