#!/usr/bin/env python3
"""Sanity checks for LIFE OS — boot anim + fault 800/890/899 suppress."""
from __future__ import annotations

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
    gif = REPO / "seek/assets/life-boot.gif"
    update_os = REPO / "seek/overlays/usr/sbin/update-os"
    anim_unit = REPO / "seek/overlays/lib/systemd/system/vic-anim.service"
    fault_h = REPO / "seek/overlays/anki/victor/robot/include/anki/cozmo/shared/factory/faultCodes.h"

    text = header.read_text()
    if "anki_dev_unit_len = 35328" not in text:
        fail("rampost splash is not 184x96 RGB565")

    if not gif.is_file():
        fail("life-boot.gif missing")
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

    brand = branding.read_text()
    if 'ADD_MENU_ITEM(Main, "EXIT", None)' not in brand:
        fail("Main EXIT missing")
    if 'ADD_MENU_ITEM(Main, "SELF TEST", SelfTest)' not in brand:
        fail("Main SELF TEST missing")
    if 'ADD_MENU_ITEM(Main, "CLEAR", ClearUserData)' not in brand:
        fail("Main CLEAR missing")
    if 'ADD_MENU_ITEM(Main, "SONGS"' in brand:
        fail("songs menu item must stay removed")

    h = handler.read_text()
    if "-eq 800" not in h or "-eq 890" not in h or "-eq 899" not in h:
        fail("fault-code-handler must suppress 800/890/899")
    fh = fault_h.read_text()
    if "NO_ANIM_PROCESS" not in fh or "CLIFF_FR" not in fh:
        fail("faultCodes.h missing suppress symbols")
    if "code == NO_ANIM_PROCESS || code == CLIFF_FR || code == NO_BODY" not in fh:
        fail("faultCodes.h must suppress 800/890/899")

    print(
        f"ok: boot frames={len(boot_bytes)//FRAME}, "
        "static splash, suppress 800/890/899, no songs, MYLIFE"
    )


if __name__ == "__main__":
    main()
