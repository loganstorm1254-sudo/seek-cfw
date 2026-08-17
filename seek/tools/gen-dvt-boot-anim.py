#!/usr/bin/env python3
"""Build DVT3 confidential splash + looping boot_anim.raw (no Anki/WireOS logo)."""
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "seek", "assets")
OVERLAY_ANIM = os.path.join(
    ROOT, "seek", "overlays", "anki", "victor", "resources", "config", "engine", "animations"
)
OVERLAY_RAMPOST = os.path.join(ROOT, "seek", "overlays", "anki", "rampost")
VICTOR_ANIM = os.path.join(
    ROOT, "anki", "victor", "resources", "config", "engine", "animations"
)
RAMPOST_H = os.path.join(ROOT, "anki", "rampost", "anki_dev_unit.h")

W, H = 184, 96
FRAMES = 231  # match stock boot_anim duration (~9.5s at 41ms/frame)


def find_font():
    for p in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    ):
        if os.path.exists(p):
            return p
    return None


def fit_text(draw, text, max_w, start, font_path):
    size = start
    while size >= 6:
        font = ImageFont.truetype(font_path, size) if font_path else ImageFont.load_default()
        bbox = draw.textbbox((0, 0), text, font=font)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        if w <= max_w:
            return font, w, h
        size -= 1
    font = ImageFont.truetype(font_path, 6) if font_path else ImageFont.load_default()
    bbox = draw.textbbox((0, 0), text, font=font)
    return font, bbox[2] - bbox[0], bbox[3] - bbox[1]


def make_splash(w, h):
    img = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(img)
    font_path = find_font()
    lines = [
        ("PROPERTY OF ANKI", 13),
        ("CONFIDENTIAL TEST UNIT", 12),
        ("IF FOUND, CONTACT", 12),
        ("security@anki.com", 11),
    ]
    ys = [int(h * 0.20), int(h * 0.38), int(h * 0.56), int(h * 0.74)]
    max_w = w - 8
    for (text, start), y in zip(lines, ys):
        font, tw, th = fit_text(d, text, max_w, start, font_path)
        x = (w - tw) // 2
        d.text((x, y - th // 2), text, fill=(255, 255, 255), font=font)
    return img


def to_rgb565(img):
    w, h = img.size
    raw = bytearray()
    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
            raw += struct.pack("<H", v)
    return bytes(raw)


def fade(img, t):
    """t in [0,1] — LCD coming up onto the DVT splash."""
    if t >= 1:
        return img
    black = Image.new("RGB", img.size, (0, 0, 0))
    return Image.blend(black, img, t)


def write_header(raw, path):
    lines = [
        "#ifndef __ANKI_PROPRIETARY_IMAGE_H_",
        "#define __ANKI_PROPRIETARY_IMAGE_H_",
        "",
        "// Classic Anki DVT confidential test-unit splash (184x96 RGB565)",
        "unsigned char anki_dev_unit[] = {",
    ]
    for i in range(0, len(raw), 12):
        chunk = raw[i : i + 12]
        lines.append("  " + ", ".join(f"0x{b:02x}" for b in chunk) + ",")
    lines.append("};")
    lines.append("")
    lines.append(f"unsigned int anki_dev_unit_len = {len(raw)};")
    lines.append("")
    lines.append("#endif // __ANKI_PROPRIETARY_IMAGE_H_")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def write_anim(splash, path, frames, fade_frames=12):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        for i in range(frames):
            t = 1.0 if i >= fade_frames else (i + 1) / float(fade_frames)
            f.write(to_rgb565(fade(splash, t)))
    print("wrote", path, "bytes", os.path.getsize(path))


def main():
    splash = make_splash(W, H)
    os.makedirs(ASSETS, exist_ok=True)
    splash.save(os.path.join(ASSETS, "dvt3-boot-184x96.png"))
    raw = to_rgb565(splash)
    open(os.path.join(ASSETS, "dvt3-boot.raw"), "wb").write(raw)
    write_header(raw, os.path.join(OVERLAY_RAMPOST, "anki_dev_unit.h"))
    write_header(raw, RAMPOST_H)

    write_anim(splash, os.path.join(OVERLAY_ANIM, "boot_anim.raw"), FRAMES)
    write_anim(splash, os.path.join(VICTOR_ANIM, "boot_anim.raw"), FRAMES)

    splash20 = splash.resize((160, 80), Image.NEAREST)
    write_anim(splash20, os.path.join(OVERLAY_ANIM, "boot_anim_20.raw"), FRAMES)
    write_anim(splash20, os.path.join(VICTOR_ANIM, "boot_anim_20.raw"), FRAMES)
    return 0


if __name__ == "__main__":
    sys.exit(main())
