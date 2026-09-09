#!/usr/bin/env python3
"""Sanity checks for LIFE OS stretched splash, Ordinary Life boot anim, and 890/899."""
from __future__ import annotations

import re
import sys
import wave
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
    hold = REPO / "seek/overlays/usr/bin/life-boot-hold"
    anim_unit = REPO / "seek/overlays/lib/systemd/system/vic-anim.service"
    boot_unit = REPO / "seek/overlays/lib/systemd/system/vic-bootAnim.service"

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
    wav_bytes = wav.read_bytes()
    if wav_bytes[:4] != b"RIFF":
        fail("boot-music.wav is not a WAV")
    if wav_bytes[36:40] != b"data":
        fail("boot-music.wav is not a canonical 44-byte PCM header (tinyplay would chirp)")
    with wave.open(str(wav), "rb") as w:
        if w.getnchannels() != 2 or w.getframerate() != 48000 or w.getsampwidth() != 2:
            fail(f"boot-music.wav must be 48k stereo s16, got {w.getnchannels()}ch {w.getframerate()}Hz")

    hold_txt = hold.read_text()
    if "aplay" not in hold_txt or "boot-music.wav" not in hold_txt:
        fail("life-boot-hold does not play boot music")
    if "aplay -D" not in hold_txt or hold_txt.find("aplay -D") > hold_txt.find("tinyplay \"$WAV\""):
        fail("life-boot-hold must try aplay before tinyplay")
    if "boot_adsp" in hold_txt:
        fail("life-boot-hold must not poke boot_adsp (causes bootloops)")

    music_unit = REPO / "seek/overlays/lib/systemd/system/life-boot-music.service"
    if "ExecStart=/usr/bin/life-boot-hold" not in music_unit.read_text():
        fail("life-boot-music.service does not run life-boot-hold")
    if "life-boot-music.service" not in anim_unit.read_text():
        fail("vic-anim.service does not wait for boot music")
    if "TimeoutStartSec=3min" in anim_unit.read_text():
        fail("vic-anim should not block 3min in ExecStartPre anymore")

    boot_unit_txt = boot_unit.read_text()
    if "vic-boot-wrap" in boot_unit_txt:
        fail("vic-bootAnim.service must run stock vic-bootAnim, not the wrap")
    if "ExecStart=/anki/bin/vic-bootAnim" not in boot_unit_txt:
        fail("vic-bootAnim.service is not stock video-only")

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
        "canonical 48k wav + aplay-first boot music, 890/899, MYLIFE"
    )


if __name__ == "__main__":
    main()
