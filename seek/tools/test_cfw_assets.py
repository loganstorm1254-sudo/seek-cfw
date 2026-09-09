#!/usr/bin/env python3
"""Sanity checks for LIFE OS stretched splash, Ordinary Life boot anim, and 890/899."""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FRAME = 184 * 96 * 2
FRAME_V2 = 160 * 80 * 2


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    header = REPO / "seek/overlays/anki/rampost/anki_dev_unit.h"
    handler = REPO / "seek/overlays/anki/fault-code/fault-code-handler"
    branding = REPO / "seek/overlays/anki/victor/animProcess/src/cozmoAnim/faceDisplay/faceInfoScreenManager.cpp"
    boot = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim.raw"
    boot20 = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim_20.raw"
    png = REPO / "seek/assets/life-static-184x96.png"
    wav = REPO / "seek/overlays/anki/data/boot-music.wav"
    wrap = REPO / "seek/overlays/usr/bin/vic-boot-wrap"

    text = header.read_text()
    if "anki_dev_unit_len = 35328" not in text:
        fail("rampost splash is not 184x96 RGB565")
    hex_bytes = bytes(int(x, 16) for x in re.findall(r"0x([0-9a-f]{2})", text))
    if hex_bytes != (REPO / "seek/assets/life-static.raw").read_bytes():
        fail("anki_dev_unit.h does not match stretched portrait raw")

    boot_bytes = boot.read_bytes()
    if len(boot_bytes) <= FRAME * 8:
        fail("boot_anim.raw is too short for a moving clip")
    if len(boot_bytes) % FRAME:
        fail("boot_anim.raw is not a multiple of 184x96")
    if len(boot20.read_bytes()) // FRAME_V2 != len(boot_bytes) // FRAME:
        fail("boot_anim / boot_anim_20 frame counts differ")
    if boot_bytes[:FRAME] == hex_bytes:
        fail("boot_anim starts with the static portrait — moving boot must be the song clip")

    from PIL import Image
    im = Image.open(png)
    if im.size != (184, 96):
        fail(f"static PNG is {im.size}")

    if not wav.is_file() or wav.stat().st_size < 10000:
        fail("boot-music.wav missing or tiny")
    if b"RIFF" not in wav.read_bytes()[:4]:
        fail("boot-music.wav is not a WAV")
    wrap_txt = wrap.read_text()
    if "tinyplay" not in wrap_txt or "boot-music.wav" not in wrap_txt:
        fail("vic-boot-wrap does not loop boot music")

    handler_txt = handler.read_text()
    if "890" not in handler_txt or "899" not in handler_txt or "exit 0" not in handler_txt:
        fail("fault-code-handler does not suppress 890/899")

    brand = branding.read_text()
    ident = brand[brand.find("OSProject") : brand.find("LOG_CHANNEL")]
    if "MYLIFE" not in ident:
        fail("CCIS OSProject is not MYLIFE")
    if "SeekOS" in ident or "CHOSON" in ident or "DPRK" in ident:
        fail("CCIS identity still has old OS names")

    print(
        f"ok: stretched portrait rampost, ordinary-life boot_anim frames={len(boot_bytes)//FRAME}, "
        "wav+wrap, 890/899, MYLIFE"
    )


if __name__ == "__main__":
    main()
