#!/usr/bin/env python3
"""Sanity checks for LIFE OS starfield boot, backpack songs, update-os curl fix."""
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
    boot_unit = REPO / "seek/overlays/lib/systemd/system/vic-bootAnim.service"
    songs = REPO / "seek/overlays/usr/bin/life-songs"
    watch = REPO / "seek/overlays/usr/bin/life-songs-watch"
    watch_unit = REPO / "seek/overlays/lib/systemd/system/life-songs-watch.service"
    song_dir = REPO / "seek/overlays/anki/data/life-songs"

    text = header.read_text()
    if "anki_dev_unit_len = 35328" not in text:
        fail("rampost splash is not 184x96 RGB565")
    hex_bytes = bytes(int(x, 16) for x in re.findall(r"0x([0-9a-f]{2})", text))
    if hex_bytes != (REPO / "seek/assets/life-static.raw").read_bytes():
        fail("anki_dev_unit.h does not match stretched portrait raw")

    if not gif.is_file():
        fail("starfield-boot.gif missing")

    boot_bytes = boot.read_bytes()
    if len(boot_bytes) <= FRAME * 8:
        fail("boot_anim.raw is too short for a moving clip")
    if len(boot_bytes) % FRAME:
        fail("boot_anim.raw is not a multiple of 184x96")
    if len(boot20.read_bytes()) // FRAME_V2 != len(boot_bytes) // FRAME:
        fail("boot_anim / boot_anim_20 frame counts differ")
    if boot_bytes[:FRAME] == hex_bytes:
        fail("boot_anim starts with the static portrait — moving boot must be the starfield")

    from PIL import Image

    im = Image.open(png)
    if im.size != (184, 96):
        fail(f"static PNG is {im.size}")

    anim_txt = anim_unit.read_text()
    if "life-boot-music.service" in anim_txt:
        fail("vic-anim.service must not wait on life-boot-music (starfield boot is silent)")
    if "TimeoutStartSec=3min" in anim_txt:
        fail("vic-anim should not block 3min in ExecStartPre")

    boot_unit_txt = boot_unit.read_text()
    if "vic-boot-wrap" in boot_unit_txt:
        fail("vic-bootAnim.service must run stock vic-bootAnim, not the wrap")
    if "ExecStart=/anki/bin/vic-bootAnim" not in boot_unit_txt:
        fail("vic-bootAnim.service is not stock video-only")

    upd = update_os.read_text()
    if "curl.anki" not in upd:
        fail("update-os does not preserve real curl as curl.anki")
    if "rm -f /usr/bin/curl" not in upd:
        fail("update-os must unlink /usr/bin/curl before rewriting (ETXTBSY fix)")

    if not songs.is_file() or not watch.is_file():
        fail("life-songs scripts missing")
    songs_txt = songs.read_text()
    if "SONG_DIR=/anki/data/assets/life-songs" not in songs_txt:
        fail("life-songs points at wrong asset dir")
    if "/dev/fb0" not in songs_txt:
        fail("life-songs must draw RGB565 to /dev/fb0 (not persist/bootAnim)")
    if "vic-bootAnim" in songs_txt and "persist" in songs_txt:
        fail("life-songs must not use /persist + vic-bootAnim (black screen)")
    if songs_txt.startswith("#!") and "python" in songs_txt.splitlines()[0]:
        fail("life-songs must be shell (no python on robot)")
    watch_txt = watch.read_text()
    if watch_txt.startswith("#!") and "python" in watch_txt.splitlines()[0]:
        fail("life-songs-watch must be shell (no python on robot)")
    if "NETWORK_SCREEN=10" not in watch_txt:
        fail("life-songs-watch must launch songs on Network (backpack from Main)")
    if "MAIN_SCREEN=4" not in watch_txt:
        fail("life-songs-watch must arm on Main")
    if "/var/log/messages" not in watch_txt:
        fail("life-songs-watch must follow /var/log/messages (WireOS Anki logs)")
    if "life-songs-stop" not in watch_txt or "request_stop" not in watch_txt:
        fail("life-songs-watch must stop songs on backpack while playing")
    if "ExecStart=/usr/bin/life-songs-watch" not in watch_unit.read_text():
        fail("life-songs-watch.service missing ExecStart")
    brand_menu = branding.read_text()
    if 'ADD_MENU_ITEM(Main, "EXIT", None)' not in brand_menu:
        fail("CCIS Main must keep EXIT")
    if 'ADD_MENU_ITEM(Main, "SONGS", SelfTest)' in brand_menu:
        fail("SONGS menu item must be removed")
    if 'ADD_MENU_ITEM(Main, "SELF TEST", SelfTest)' not in brand_menu:
        fail("CCIS Main must restore SELF TEST")
    if 'ADD_MENU_ITEM(Main, "CLEAR", ClearUserData)' not in brand_menu:
        fail("CCIS Main CLEAR should be the short label")

    for name in ("muffin", "survive", "ordinary", "neveralone"):
        raw = song_dir / f"{name}.raw"
        wav = song_dir / f"{name}.wav"
        if not raw.is_file() or raw.stat().st_size < FRAME * 8:
            fail(f"song raw missing/short: {name}")
        if not wav.is_file():
            fail(f"song wav missing: {name}")
        wb = wav.read_bytes()
        if wb[:4] != b"RIFF" or wb[36:40] != b"data":
            fail(f"{name}.wav is not canonical PCM")
        with wave.open(str(wav), "rb") as w:
            if w.getnchannels() != 2 or w.getframerate() != 48000 or w.getsampwidth() != 2:
                fail(f"{name}.wav must be 48k stereo s16")
        if not (song_dir / "menu" / f"{name}.raw").is_file():
            fail(f"menu frame missing for {name}")

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
        f"ok: starfield boot_anim frames={len(boot_bytes)//FRAME}, "
        "backpack songs via Network, fb0 player, update-os ETXTBSY fix, 890/899, MYLIFE"
    )


if __name__ == "__main__":
    main()
