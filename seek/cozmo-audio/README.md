# Cozmo audio drop-in for Seek CFW

Vector only ships **Victor_*** Wwise banks. Authentic Cozmo beeps live in Cozmo
app / Viccyware banks (`.bnk` + `.wem`). Those assets are **not** in this repo
and will not be downloaded or redistributed here.

## What you do

1. Obtain Cozmo-compatible banks yourself (e.g. from a Viccyware install you
   already have, or banks you authored in Wwise).
2. Place them under this folder:

```
seek/cozmo-audio/drop-in/
  SoundbankBundleInfo.json   # optional override fragment
  *.bnk
  *.wem
```

3. On the robot (after Seek hotfix), install:

```sh
mkdir -p /data/seek/cozmo_sound
# copy your .bnk/.wem onto the robot, e.g.:
# scp -i %TEMP%\vector_dev_key drop-in/* root@192.168.42.111:/data/seek/cozmo_sound/
```

4. Enable **COZMO** in CCIS. Face CRT look is already active; audio swap needs
   banks whose event names match what `vic-anim` posts (Viccyware-style packs).

## Why it is not automatic

- Vector animation events reference `Victor_*` Wwise events.
- Cozmo banks use different event IDs/names unless remapped.
- Shipping Anki’s Cozmo banks in Seek would be copyright redistribution.

If you drop a Viccyware-style remapped pack on `/data/seek/cozmo_sound/`, the
next Seek audio hook can load it when Cozmo mode is on. Until then, Cozmo mode
is **face-only** (scanlines + eye shape).
