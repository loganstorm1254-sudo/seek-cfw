#!/usr/bin/env python3
"""Sanity checks for LIFE OS — fault-800-safe CCIS SONGS menu."""
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
    gif = REPO / "seek/assets/starfield-boot.gif"
    update_os = REPO / "seek/overlays/usr/sbin/update-os"
    anim_unit = REPO / "seek/overlays/lib/systemd/system/vic-anim.service"
    songs = REPO / "seek/overlays/usr/bin/life-songs"
    watch = REPO / "seek/overlays/usr/bin/life-songs-watch"
    watch_unit = REPO / "seek/overlays/lib/systemd/system/life-songs-watch.service"
    song_dir = REPO / "seek/overlays/anki/data/life-songs"

    text = header.read_text()
    if "anki_dev_unit_len = 35328" not in text:
        fail("rampost splash is not 184x96 RGB565")

    if not gif.is_file():
        fail("starfield-boot.gif missing")
    boot_bytes = boot.read_bytes()
    if len(boot_bytes) <= FRAME * 8 or len(boot_bytes) % FRAME:
        fail("boot_anim.raw invalid")
    if len(boot20.read_bytes()) // FRAME_V2 != len(boot_bytes) // FRAME:
        fail("boot_anim frame count mismatch")

    from PIL import Image

    if Image.open(png).size != (184, 96):
        fail("static PNG size")

    if "life-boot-music.service" in anim_unit.read_text():
        fail("vic-anim must not wait on boot music")

    upd = update_os.read_text()
    if "curl.anki" not in upd or "rm -f /usr/bin/curl" not in upd:
        fail("update-os ETXTBSY fix missing")

    songs_txt = songs.read_text()
    if "/dev/fb0" not in songs_txt or "SONG_DIR=/anki/data/assets/life-songs" not in songs_txt:
        fail("life-songs fb0 path missing")
    watch_txt = watch.read_text()
    if "python" in watch_txt.splitlines()[0]:
        fail("watcher must be shell")
    if "SONGS_SCREEN=8" not in watch_txt:
        fail("watcher must hijack SelfTest (8) for SONGS")
    if "ExecStart=/usr/bin/life-songs-watch" not in watch_unit.read_text():
        fail("watcher unit missing")

    brand = branding.read_text()
    if 'ADD_MENU_ITEM(Main, "EX", None)' not in brand:
        fail("Main EX missing")
    if 'ADD_MENU_ITEM(Main, "SONGS", SelfTest)' not in brand:
        fail("Main SONGS→SelfTest missing")
    if 'ADD_MENU_ITEM(Main, "CLR", ClearUserData)' not in brand:
        fail("Main CLR missing")
    if 'ADD_MENU_ITEM(Main, "SONGS", Network)' in brand:
        fail("do not use Network destination (10d-style)")
    if "fault 800" not in brand.lower() and "AppendMenuItem" not in brand:
        pass  # comment optional

    for name in ("muffin", "survive", "ordinary", "neveralone"):
        raw = song_dir / f"{name}.raw"
        wav = song_dir / f"{name}.wav"
        if not raw.is_file() or raw.stat().st_size < FRAME * 8:
            fail(f"song raw: {name}")
        with wave.open(str(wav), "rb") as w:
            if w.getnchannels() != 2 or w.getframerate() != 48000 or w.getsampwidth() != 2:
                fail(f"wav: {name}")

    if "890" not in handler.read_text() or "899" not in handler.read_text():
        fail("890/899 suppress missing")

    print(
        f"ok: starfield frames={len(boot_bytes)//FRAME}, "
        "EX/SONGS/CLR (no 4th-item cave), fb0 player, MYLIFE"
    )


if __name__ == "__main__":
    main()
