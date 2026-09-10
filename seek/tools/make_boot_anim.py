#!/usr/bin/env python3
"""Convert the Orville '500 cigarettes' clip into Vector boot_anim.raw frames.

This is the *moving* second boot screen (vic-bootAnim). The static first splash
is the passport cover in anki_dev_unit.h (see make_boot_splash.py).
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

FACE_W, FACE_H = 184, 96
FACE_W_V2, FACE_H_V2 = 160, 80
FRAME = FACE_W * FACE_H * 2
FRAME_V2 = FACE_W_V2 * FACE_H_V2 * 2


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


def extract_frames(src: Path, width: int, height: int, dest: Path) -> list[Path]:
    dest.mkdir(parents=True, exist_ok=True)
    vf = (
        f"scale={width}:{height}:force_original_aspect_ratio=increase,"
        f"crop={width}:{height},format=rgb24"
    )
    subprocess.check_call(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(src),
            "-vf",
            vf,
            str(dest / "%04d.png"),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    frames = sorted(dest.glob("*.png"))
    if not frames:
        raise SystemExit(f"ffmpeg produced no frames from {src}")
    return frames


def frames_to_raw(frames: list[Path], expected_size: tuple[int, int]) -> bytes:
    blobs = []
    for path in frames:
        im = Image.open(path)
        if im.size != expected_size:
            raise SystemExit(f"{path} is {im.size}, expected {expected_size}")
        blobs.append(rgb888_to_rgb565_le(im))
    return b"".join(blobs)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", default="seek/assets/orville-500-cigarettes.mp4")
    parser.add_argument("--repo", default=".")
    args = parser.parse_args()
    repo = Path(args.repo).resolve()
    src = repo / args.src
    if not src.is_file():
        raise SystemExit(f"missing video {src}")
    if shutil.which("ffmpeg") is None:
        raise SystemExit("ffmpeg is required to rebuild boot_anim.raw")

    overlay_anims = (
        repo
        / "seek"
        / "overlays"
        / "anki"
        / "victor"
        / "resources"
        / "config"
        / "engine"
        / "animations"
    )
    overlay_anims.mkdir(parents=True, exist_ok=True)
    assets = repo / "seek" / "assets"
    assets.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="choson-boot-") as tmp:
        tmp_path = Path(tmp)
        frames = extract_frames(src, FACE_W, FACE_H, tmp_path / "f184")
        frames_v2 = extract_frames(src, FACE_W_V2, FACE_H_V2, tmp_path / "f160")
        raw = frames_to_raw(frames, (FACE_W, FACE_H))
        raw_v2 = frames_to_raw(frames_v2, (FACE_W_V2, FACE_H_V2))
        Image.open(frames[0]).save(assets / "orville-boot-184x96.png")
        Image.open(frames[len(frames) // 2]).save(assets / "orville-boot-184x96-mid.png")

    if len(raw) % FRAME:
        raise SystemExit("boot_anim.raw is not a multiple of one 184x96 frame")
    if len(raw_v2) % FRAME_V2:
        raise SystemExit("boot_anim_20.raw is not a multiple of one 160x80 frame")
    n = len(raw) // FRAME
    if n < 8:
        raise SystemExit(f"boot anim only has {n} frames; expected a looping clip")

    (overlay_anims / "boot_anim.raw").write_bytes(raw)
    (overlay_anims / "boot_anim_20.raw").write_bytes(raw_v2)
    print(f"wrote boot_anim.raw frames={n} bytes={len(raw)}")
    print(f"wrote boot_anim_20.raw frames={len(raw_v2) // FRAME_V2} bytes={len(raw_v2)}")


if __name__ == "__main__":
    main()
