#!/usr/bin/env python3
"""Sanity checks for ChosonOS splash, Orville boot anim, and 890/899 suppression."""
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
    faults = REPO / "seek/overlays/anki/victor/robot/include/anki/cozmo/shared/factory/faultCodes.h"
    branding = REPO / "seek/overlays/anki/victor/animProcess/src/cozmoAnim/faceDisplay/faceInfoScreenManager.cpp"
    boot = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim.raw"
    boot20 = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim_20.raw"
    png = REPO / "seek/assets/dprk-boot-184x96.png"
    passport_raw = REPO / "seek/assets/dprk-boot.raw"

    text = header.read_text()
    if "anki_dev_unit_len = 35328" not in text:
        fail("rampost splash is not 184x96 RGB565 (35328 bytes)")
    if "조선민주주의인민공화국" not in text:
        fail("rampost splash header missing Hangul top-of-cover text")
    if "DEMOCRATIC PEOPLE'S REPUBLIC OF KOREA" not in text:
        fail("rampost splash header missing English top-of-cover text")

    header_bytes = bytes(int(x, 16) for x in re.findall(r"0x([0-9a-f]{2})", text))
    if header_bytes != passport_raw.read_bytes():
        fail("anki_dev_unit.h bytes do not match passport dprk-boot.raw")

    boot_bytes = boot.read_bytes()
    boot20_bytes = boot20.read_bytes()
    if len(boot_bytes) <= FRAME:
        fail(f"boot_anim.raw is {len(boot_bytes)} bytes; 2nd boot must be a moving clip")
    if len(boot_bytes) % FRAME:
        fail("boot_anim.raw is not a multiple of 184x96 RGB565")
    if len(boot20_bytes) % FRAME_V2:
        fail("boot_anim_20.raw is not a multiple of 160x80 RGB565")
    n = len(boot_bytes) // FRAME
    n20 = len(boot20_bytes) // FRAME_V2
    if n != n20:
        fail(f"boot_anim frame count {n} != boot_anim_20 {n20}")
    if n < 8:
        fail(f"boot_anim.raw only has {n} frames")
    if boot_bytes[:FRAME] == passport_raw.read_bytes():
        fail("boot_anim.raw starts with the passport still — that belongs on rampost only")

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
    if 'OSProject = "CHOSON"' not in brand:
        fail("CCIS OSProject is not CHOSON")
    if "DEMOCRATIC PEOPLE'S" not in brand or "REPUBLIC OF KOREA" not in brand:
        fail("CCIS branding missing English top-of-cover text")
    if "조선민주주의인민공화국" not in brand:
        fail("CCIS comments missing Hangul top-of-cover text")
    if "SeekOS" in brand.split("OSProject")[0][-80:] + brand.split("OSProject")[1][:200]:
        # keep Seek mute comments elsewhere; the identity block must not say SeekOS
        ident = brand[brand.find("CHANGE THIS") : brand.find("LOG_CHANNEL")]
        if "SeekOS" in ident:
            fail("CCIS identity still says SeekOS")

    print(
        f"ok: passport rampost 184x96, orville boot_anim frames={n}, "
        "890/899 never-show, CHOSON branding"
    )


if __name__ == "__main__":
    main()
