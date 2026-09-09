#!/usr/bin/env python3
"""Convert the DPRK passport cover into Vector's *static* rampost splash.

Vector's face is 184x96 (Santek / 1.0) or 160x80 (Midas / 2.0), RGB565 LE.
Rampost's anki_dev_unit.h is a C array of those 184x96 pixels (first boot screen).
The moving second screen is boot_anim.raw — see make_boot_anim.py.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont

FACE_W, FACE_H = 184, 96
FACE_W_V2, FACE_H_V2 = 160, 80
GOLD = (220, 184, 58)


def sample_navy(src: Image.Image) -> tuple[int, int, int]:
    """Use the cover leather color so the emblem crop doesn't flash a box."""
    pix = src.getpixel((8, 8))
    return (int(pix[0]), int(pix[1]), int(pix[2]))


def rgb888_to_rgb565_le(img: Image.Image) -> bytes:
    img = img.convert("RGB")
    out = bytearray()
    pix = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b = pix[x, y]
            val = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
            out.append(val & 0xFF)
            out.append((val >> 8) & 0xFF)
    return bytes(out)


def write_c_header(raw: bytes, dest: Path, comment: str) -> None:
    lines = [
        "#ifndef __ANKI_PROPRIETARY_IMAGE_H_",
        "#define __ANKI_PROPRIETARY_IMAGE_H_",
        "",
        f"// {comment}",
        "unsigned char anki_dev_unit[] = {",
    ]
    row = []
    for i, b in enumerate(raw):
        row.append(f"0x{b:02x}")
        if len(row) == 12:
            lines.append("  " + ", ".join(row) + ",")
            row = []
    if row:
        lines.append("  " + ", ".join(row) + ",")
    lines.append("};")
    lines.append(f"unsigned int anki_dev_unit_len = {len(raw)};")
    lines.append("")
    lines.append("#endif")
    dest.write_text("\n".join(lines) + "\n")


def load_font(path: str, size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def extract_emblem(src: Image.Image, navy: tuple[int, int, int]) -> Image.Image:
    """Crop the gold national emblem and punch out the leather background."""
    w, h = src.size
    # Tight crop around the circular emblem (skip header text and PASSPORT).
    x0 = int(w * 0.22)
    x1 = int(w * 0.78)
    y0 = int(h * 0.32)
    y1 = int(h * 0.70)
    emblem = src.crop((x0, y0, x1, y1)).convert("RGBA")
    emblem = ImageEnhance.Contrast(emblem).enhance(1.25)
    pix = emblem.load()
    nr, ng, nb = navy
    for y in range(emblem.size[1]):
        for x in range(emblem.size[0]):
            r, g, b, a = pix[x, y]
            # Leather is navy; gold emblem is much warmer / brighter.
            if abs(r - nr) < 28 and abs(g - ng) < 28 and abs(b - nb) < 36:
                pix[x, y] = (r, g, b, 0)
            elif r < 70 and g < 70 and b < 110:
                pix[x, y] = (r, g, b, 0)
    return emblem


def compose_splash(src: Image.Image, width: int, height: int) -> Image.Image:
    """Build a readable Vector face splash from the passport cover.

    Vector's LCD is 184x96 landscape; the cover is portrait. Paint the requested
    top-of-cover text (Hangul + English) in gold on navy, then sit the emblem
    underneath so the static boot screen is this cover — not a tiny unread crop.
    """
    navy = sample_navy(src)
    canvas = Image.new("RGB", (width, height), navy)
    emblem = extract_emblem(src, navy)

    # Leave a text band at the top; fit the emblem into the remaining height.
    text_band = 34 if height >= 96 else 30
    max_emblem_h = height - text_band - 2
    ew, eh = emblem.size
    scale = min(width / ew, max_emblem_h / eh)
    emblem = emblem.resize((max(1, int(ew * scale)), max(1, int(eh * scale))), Image.Resampling.LANCZOS)
    ex = (width - emblem.size[0]) // 2
    ey = height - emblem.size[1]
    canvas_rgba = canvas.convert("RGBA")
    canvas_rgba.paste(emblem, (ex, ey), emblem)
    canvas = canvas_rgba.convert("RGB")

    draw = ImageDraw.Draw(canvas)
    hangul = "조선민주주의인민공화국"
    english = [
        "DEMOCRATIC PEOPLE'S",
        "REPUBLIC OF KOREA",
    ]

    hangul_font = load_font("/usr/share/fonts/truetype/wqy/wqy-microhei.ttc", 12 if width >= 184 else 10)
    latin_font = load_font("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", 8 if width >= 184 else 7)

    def center_text(text: str, font, y: int, fill=GOLD) -> int:
        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        x = max(1, (width - tw) // 2)
        # 1px navy outline so gold stays readable over the emblem
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            draw.text((x + dx, y - bbox[1] + dy), text, font=font, fill=navy)
        draw.text((x, y - bbox[1]), text, font=font, fill=fill)
        return th

    y = 2
    y += center_text(hangul, hangul_font, y) + 0
    for line in english:
        y += center_text(line, latin_font, y)

    return canvas


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", default="seek/assets/dprk-passport.webp")
    parser.add_argument("--repo", default=".")
    args = parser.parse_args()
    repo = Path(args.repo).resolve()
    src = Image.open(repo / args.src).convert("RGB")

    splash = compose_splash(src, FACE_W, FACE_H)
    splash_v2 = compose_splash(src, FACE_W_V2, FACE_H_V2)

    assets = repo / "seek" / "assets"
    overlay_rampost = repo / "seek" / "overlays" / "anki" / "rampost"
    overlay_rampost.mkdir(parents=True, exist_ok=True)
    assets.mkdir(parents=True, exist_ok=True)

    png_path = assets / "dprk-boot-184x96.png"
    png_v2_path = assets / "dprk-boot-160x80.png"
    splash.save(png_path)
    splash_v2.save(png_v2_path)

    raw = rgb888_to_rgb565_le(splash)
    raw_v2 = rgb888_to_rgb565_le(splash_v2)
    (assets / "dprk-boot.raw").write_bytes(raw)
    (assets / "dprk-boot-20.raw").write_bytes(raw_v2)

    write_c_header(
        raw,
        overlay_rampost / "anki_dev_unit.h",
        "ChosonOS static rampost splash: DPRK passport cover (184x96 RGB565). "
        "Top text: 조선민주주의인민공화국 / DEMOCRATIC PEOPLE'S REPUBLIC OF KOREA",
    )
    anki_copy = repo / "anki" / "rampost" / "anki_dev_unit.h"
    if anki_copy.parent.is_dir():
        anki_copy.write_text((overlay_rampost / "anki_dev_unit.h").read_text())

    print(f"wrote {png_path} {png_path.stat().st_size} bytes")
    print(f"wrote {overlay_rampost / 'anki_dev_unit.h'} header bytes={len(raw)}")
    print("passport is rampost-only; moving boot_anim is generated by make_boot_anim.py")


if __name__ == "__main__":
    main()
