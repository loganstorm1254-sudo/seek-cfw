#!/usr/bin/env python3
"""Sanity checks for Seek CFW splash + 890/899 suppression overlays."""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    header = REPO / "seek/overlays/anki/rampost/anki_dev_unit.h"
    handler = REPO / "seek/overlays/anki/fault-code/fault-code-handler"
    faults = REPO / "seek/overlays/anki/victor/robot/include/anki/cozmo/shared/factory/faultCodes.h"
    branding = REPO / "seek/overlays/anki/victor/animProcess/src/cozmoAnim/faceDisplay/faceInfoScreenManager.cpp"
    boot = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim.raw"
    boot20 = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim_20.raw"
    png = REPO / "seek/assets/dprk-boot-184x96.png"
    raw_src = REPO / "seek/assets/dprk-boot.raw"

    text = header.read_text()
    if "anki_dev_unit_len = 35328" not in text:
        fail("rampost splash is not 184x96 RGB565 (35328 bytes)")
    if "조선민주주의인민공화국" not in text:
        fail("rampost splash header missing Hangul top-of-cover text")
    if "DEMOCRATIC PEOPLE'S REPUBLIC OF KOREA" not in text:
        fail("rampost splash header missing English top-of-cover text")

    boot_bytes = boot.read_bytes()
    if len(boot_bytes) != 35328:
        fail(f"boot_anim.raw is {len(boot_bytes)} bytes, expected one 184x96 frame")
    if len(boot20.read_bytes()) != 25600:
        fail("boot_anim_20.raw is not one 160x80 frame")
    if raw_src.read_bytes() != boot_bytes:
        fail("seek/assets/dprk-boot.raw does not match boot_anim.raw")

    from PIL import Image
    im = Image.open(png)
    if im.size != (184, 96):
        fail(f"preview PNG is {im.size}, expected 184x96")

    handler_txt = handler.read_text()
    if 'FAULT_CODE" -eq 890' not in handler_txt or 'FAULT_CODE" -eq 899' not in handler_txt:
        fail("fault-code-handler does not suppress 890 and 899")
    if "never-show: CLIFF_FR=890, NO_BODY=899" not in handler_txt:
        fail("fault-code-handler missing never-show log")
    suppress = handler_txt.split('FAULT_CODE" -eq 890')[1][:400]
    if "exit 0" not in suppress:
        fail("fault-code-handler does not exit after suppressing 890/899")

    faults_txt = faults.read_text()
    if "code == CLIFF_FR || code == NO_BODY" not in faults_txt:
        fail("DisplayFaultCode does not no-op CLIFF_FR/NO_BODY")
    if "suppressed" not in faults_txt:
        fail("DisplayFaultCode missing suppress log")

    brand = branding.read_text()
    if 'OSProject = "DPRK"' not in brand:
        fail("CCIS OSProject is not DPRK")
    if "DEMOCRATIC PEOPLE'S" not in brand or "REPUBLIC OF KOREA" not in brand:
        fail("CCIS branding missing English top-of-cover text")
    if "조선민주주의인민공화국" not in brand:
        fail("CCIS comments missing Hangul top-of-cover text")

    # Reconstruct RGB565 from header and compare to raw
    hex_bytes = [int(x, 16) for x in re.findall(r"0x([0-9a-f]{2})", text)]
    if bytes(hex_bytes) != boot_bytes:
        fail("anki_dev_unit.h bytes do not match boot_anim.raw")

    print("ok: splash 184x96, boot anim static, 890/899 never-show, DPRK branding")


if __name__ == "__main__":
    main()
