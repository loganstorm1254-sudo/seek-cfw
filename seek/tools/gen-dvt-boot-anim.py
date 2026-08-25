#!/usr/bin/env python3
"""Install authentic Anki DVT splash (from 1.0.1.1768 rampost) as boot movie."""
import os
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "seek", "assets")
VICTOR_ANIM = os.path.join(
    ROOT, "anki", "victor", "resources", "config", "engine", "animations"
)
OVERLAY_RAMPOST = os.path.join(ROOT, "seek", "overlays", "anki", "rampost")
RAMPOST_H = os.path.join(ROOT, "anki", "rampost", "anki_dev_unit.h")

W, H = 184, 96
FRAMES = 231
NEED = W * H * 2


def write_header(raw, path):
    lines = [
        "#ifndef __ANKI_PROPRIETARY_IMAGE_H_",
        "#define __ANKI_PROPRIETARY_IMAGE_H_",
        "",
        "// Authentic Anki DVT proprietary splash (from Anki OTA 1.0.1.1768 rampost)",
        "// PROPERTY OF ANKI / NOT FOR SALE / CONFIDENTIAL TEST UNIT",
        "unsigned char anki_dev_unit[] = {",
    ]
    for i in range(0, len(raw), 12):
        chunk = raw[i : i + 12]
        lines.append("  " + ", ".join(f"0x{b:02x}" for b in chunk) + ",")
    lines += [
        "};",
        "",
        f"unsigned int anki_dev_unit_len = {len(raw)};",
        "",
        "#endif // __ANKI_PROPRIETARY_IMAGE_H_",
        "",
    ]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(lines))


def fade_frame(raw, t, need):
    if t >= 1.0:
        return raw
    frame = bytearray(need)
    for p in range(0, need, 2):
        v = struct.unpack_from("<H", raw, p)[0]
        r = int(((v >> 11) & 0x1F) * t)
        g = int(((v >> 5) & 0x3F) * t)
        b = int((v & 0x1F) * t)
        struct.pack_into("<H", frame, p, (r << 11) | (g << 5) | b)
    return bytes(frame)


def write_anim(raw, path, frames, fade=12):
    need = len(raw)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        for i in range(frames):
            t = 1.0 if i >= fade else (i + 1) / float(fade)
            f.write(fade_frame(raw, t, need))
    print("wrote", path, os.path.getsize(path))


def main():
    raw_path = os.path.join(ASSETS, "dvt3-boot.raw")
    raw20_path = os.path.join(ASSETS, "dvt3-boot-160x80.raw")
    if not os.path.isfile(raw_path) or os.path.getsize(raw_path) != NEED:
        print("missing authentic splash raw at", raw_path, file=sys.stderr)
        return 1
    raw = open(raw_path, "rb").read()
    write_header(raw, os.path.join(OVERLAY_RAMPOST, "anki_dev_unit.h"))
    write_header(raw, RAMPOST_H)
    write_anim(raw, os.path.join(VICTOR_ANIM, "boot_anim.raw"), FRAMES)
    if os.path.isfile(raw20_path) and os.path.getsize(raw20_path) == 160 * 80 * 2:
        raw20 = open(raw20_path, "rb").read()
        write_anim(raw20, os.path.join(VICTOR_ANIM, "boot_anim_20.raw"), FRAMES)
    else:
        # nearest-neighbor downscale without Pillow
        out = bytearray()
        for y in range(80):
            sy = y * H // 80
            for x in range(160):
                sx = x * W // 160
                out += raw[(sy * W + sx) * 2 : (sy * W + sx) * 2 + 2]
        write_anim(bytes(out), os.path.join(VICTOR_ANIM, "boot_anim_20.raw"), FRAMES)
    return 0


if __name__ == "__main__":
    sys.exit(main())
