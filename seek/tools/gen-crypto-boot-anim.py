#!/usr/bin/env python3
"""Generate purple CRYPTO OS boot splash (184x96 RGB565) + boot movie + rampost header."""
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFont

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

# Purple-on-black WireOS-ish vibe
BG = (8, 0, 18)
PURPLE = (180, 70, 220)
PURPLE_DIM = (120, 40, 160)


def rgb565(r, g, b):
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def image_to_rgb565(img: Image.Image) -> bytes:
    img = img.convert("RGB")
    out = bytearray()
    px = img.load()
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            out += struct.pack("<H", rgb565(r, g, b))
    return bytes(out)


def make_splash() -> bytes:
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)

    # Soft purple vignette bar
    for y in range(H):
        t = abs(y - H / 2) / (H / 2)
        shade = int(18 * (1.0 - t * t))
        draw.line([(0, y), (W - 1, y)], fill=(8 + shade // 2, 0, 18 + shade))

    font = None
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    ):
        if os.path.isfile(path):
            font = ImageFont.truetype(path, 22)
            break
    if font is None:
        font = ImageFont.load_default()

    text = "CRYPTO OS"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (W - tw) // 2
    y = (H - th) // 2 - 2
    # slight glow
    draw.text((x + 1, y + 1), text, font=font, fill=PURPLE_DIM)
    draw.text((x, y), text, font=font, fill=PURPLE)

    sub = ImageFont.truetype(
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 10
    ) if os.path.isfile("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf") else font
    sub_text = "custom firmware"
    sb = draw.textbbox((0, 0), sub_text, font=sub)
    sx = (W - (sb[2] - sb[0])) // 2
    draw.text((sx, y + th + 6), sub_text, font=sub, fill=PURPLE_DIM)

    png_path = os.path.join(ASSETS, "crypto-boot-184x96.png")
    os.makedirs(ASSETS, exist_ok=True)
    img.save(png_path)
    print("wrote", png_path)

    raw = image_to_rgb565(img)
    raw_path = os.path.join(ASSETS, "crypto-boot.raw")
    with open(raw_path, "wb") as f:
        f.write(raw)
    print("wrote", raw_path, len(raw))

    # 160x80 downscale
    small = img.resize((160, 80), Image.Resampling.NEAREST)
    raw20 = bytearray()
    spx = small.load()
    for y in range(80):
        for x in range(160):
            r, g, b = spx[x, y]
            raw20 += struct.pack("<H", rgb565(r, g, b))
    raw20_path = os.path.join(ASSETS, "crypto-boot-160x80.raw")
    with open(raw20_path, "wb") as f:
        f.write(raw20)
    print("wrote", raw20_path, len(raw20))
    return raw, bytes(raw20)


def write_header(raw, path):
    lines = [
        "#ifndef __ANKI_PROPRIETARY_IMAGE_H_",
        "#define __ANKI_PROPRIETARY_IMAGE_H_",
        "",
        "// Crypto OS boot splash (purple)",
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
    print("wrote", path)


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
    raw, raw20 = make_splash()
    if len(raw) != NEED:
        print("bad splash size", len(raw), file=sys.stderr)
        return 1
    write_header(raw, os.path.join(OVERLAY_RAMPOST, "anki_dev_unit.h"))
    write_header(raw, RAMPOST_H)
    write_anim(raw, os.path.join(VICTOR_ANIM, "boot_anim.raw"), FRAMES)
    write_anim(raw20, os.path.join(VICTOR_ANIM, "boot_anim_20.raw"), FRAMES)
    return 0


if __name__ == "__main__":
    sys.exit(main())
