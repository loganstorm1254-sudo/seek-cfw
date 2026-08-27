#!/usr/bin/env python3
"""Samsung-style CRYPTO OS boot: black background, white logo, fade + shine."""
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "seek", "assets")
VICTOR_ANIM = os.path.join(
    ROOT, "anki", "victor", "resources", "config", "engine", "animations"
)
OVERLAY_RAMPOST = os.path.join(ROOT, "seek", "overlays", "anki", "rampost")
RAMPOST_H = os.path.join(ROOT, "anki", "rampost", "anki_dev_unit.h")

W, H = 184, 96
FRAMES = 231
FADE = 28
NEED = W * H * 2


def load_font(size, bold=True):
    paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
        if bold
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
        if bold
        else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for path in paths:
        if os.path.isfile(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def rgb565(r, g, b):
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def image_to_rgb565(img):
    img = img.convert("RGB")
    px = img.load()
    out = bytearray()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            out += struct.pack("<H", rgb565(r, g, b))
    return bytes(out)


def make_logo_layer(shine_x=None):
    img = Image.new("RGB", (W, H), (0, 0, 0))
    font = load_font(24, True)
    text = "CRYPTO OS"

    glow = Image.new("RGB", (W, H), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    bbox = gd.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (W - tw) // 2
    y = (H - th) // 2 - 1
    for ox, oy in [(-2, 0), (2, 0), (0, -2), (0, 2), (-1, -1), (1, 1), (1, -1), (-1, 1)]:
        gd.text((x + ox, y + oy), text, font=font, fill=(40, 40, 48))
    glow = glow.filter(ImageFilter.GaussianBlur(1.2))
    img = Image.blend(img, glow, 0.85)

    d = ImageDraw.Draw(img)
    d.text((x, y), text, font=font, fill=(245, 245, 250))

    if shine_x is not None:
        px = img.load()
        for yy in range(H):
            for xx in range(W):
                dist = abs(xx - shine_x)
                if dist < 18:
                    t = 1.0 - dist / 18.0
                    boost = int(55 * t * t)
                    r, g, b = px[xx, yy]
                    px[xx, yy] = (
                        min(255, r + boost),
                        min(255, g + boost),
                        min(255, b + boost // 4),
                    )
    return img


def fade_frame(raw, t):
    if t >= 1.0:
        return raw
    frame = bytearray(len(raw))
    for p in range(0, len(raw), 2):
        v = struct.unpack_from("<H", raw, p)[0]
        r = int(((v >> 11) & 0x1F) * t)
        g = int(((v >> 5) & 0x3F) * t)
        b = int((v & 0x1F) * t)
        struct.pack_into("<H", frame, p, (r << 11) | (g << 5) | b)
    return bytes(frame)


def write_header(raw, path):
    lines = [
        "#ifndef __ANKI_PROPRIETARY_IMAGE_H_",
        "#define __ANKI_PROPRIETARY_IMAGE_H_",
        "",
        "// Samsung-style Crypto OS boot splash (black + white logo)",
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


def write_anim(path, make_frame):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        for i in range(FRAMES):
            f.write(make_frame(i))
    print("wrote", path, os.path.getsize(path))


def main():
    splash = make_logo_layer(shine_x=W // 2)
    os.makedirs(ASSETS, exist_ok=True)
    png_path = os.path.join(ASSETS, "crypto-boot-184x96.png")
    splash.save(png_path)
    print("wrote", png_path)

    raw = image_to_rgb565(splash)
    if len(raw) != NEED:
        print("bad splash size", len(raw), file=sys.stderr)
        return 1
    open(os.path.join(ASSETS, "crypto-boot.raw"), "wb").write(raw)
    small = splash.resize((160, 80), Image.Resampling.LANCZOS)
    raw20 = image_to_rgb565(small)
    open(os.path.join(ASSETS, "crypto-boot-160x80.raw"), "wb").write(raw20)

    write_header(raw, os.path.join(OVERLAY_RAMPOST, "anki_dev_unit.h"))
    write_header(raw, RAMPOST_H)

    base = image_to_rgb565(make_logo_layer(shine_x=None))

    def frame184(i):
        if i < FADE:
            t = (i + 1) / float(FADE)
            t = t * t * (3 - 2 * t)
            return fade_frame(base, t)
        if i < FADE + 40:
            progress = (i - FADE) / 40.0
            sx = int(-10 + progress * (W + 20))
            return image_to_rgb565(make_logo_layer(shine_x=sx))
        return base

    def frame160(i):
        if i < FADE:
            t = (i + 1) / float(FADE)
            t = t * t * (3 - 2 * t)
            im = make_logo_layer(shine_x=None).resize((160, 80), Image.Resampling.NEAREST)
            return fade_frame(image_to_rgb565(im), t)
        if i < FADE + 40:
            progress = (i - FADE) / 40.0
            sx = int(-10 + progress * (W + 20))
            im = make_logo_layer(shine_x=sx).resize((160, 80), Image.Resampling.NEAREST)
            return image_to_rgb565(im)
        im = splash.resize((160, 80), Image.Resampling.NEAREST)
        return image_to_rgb565(im)

    write_anim(os.path.join(VICTOR_ANIM, "boot_anim.raw"), frame184)
    write_anim(os.path.join(VICTOR_ANIM, "boot_anim_20.raw"), frame160)
    return 0


if __name__ == "__main__":
    sys.exit(main())
