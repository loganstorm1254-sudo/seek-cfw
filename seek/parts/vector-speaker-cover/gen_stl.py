#!/usr/bin/env python3
"""Generate an approximate Vector rear speaker-cover STL (no OpenSCAD required).

Estimated from photos — test-fit and scale ±2–5% if needed.
"""
from __future__ import annotations

import math
import struct
from pathlib import Path

# --- params (mm) ---
W, H, T = 34.0, 36.0, 1.4
DOME = 2.0
SLOT_LEN, SLOT_H = 5.2, 1.15
SLOT_GAP_X, SLOT_GAP_Y = 2.4, 1.35
ROWS, COLS = 5, 2
NX, NY = 48, 52  # mesh resolution


def outline_radius(nx: float, ny: float) -> float:
    """Normalized radius of cover silhouette (0 at center → 1 at edge)."""
    # Wider toward bottom
    bot_bias = 1.0 + 0.12 * max(0.0, -ny)
    a = abs(nx) / bot_bias
    b = abs(ny)
    # superellipse-ish
    return (a**2.4 + b**2.2) ** (1 / 2.3)


def dome_z(nx: float, ny: float) -> float:
    r = outline_radius(nx, ny)
    if r >= 1.0:
        return 0.0
    return DOME * math.cos(0.5 * math.pi * min(1.0, r))


def in_slot(x: float, y: float) -> bool:
    col_off = SLOT_LEN / 2 + SLOT_GAP_X / 2
    total_h = ROWS * SLOT_H + (ROWS - 1) * SLOT_GAP_Y
    start_y = total_h / 2 - SLOT_H / 2 + 0.5
    for c in range(COLS):
        cx = -col_off if c == 0 else col_off
        for r in range(ROWS):
            cy = start_y - r * (SLOT_H + SLOT_GAP_Y)
            # capsule test
            hx = SLOT_LEN / 2 - SLOT_H / 2
            dx = abs(x - cx)
            dy = abs(y - cy)
            if dx <= hx and dy <= SLOT_H / 2:
                return True
            if dx > hx:
                if (dx - hx) ** 2 + dy**2 <= (SLOT_H / 2) ** 2:
                    return True
    return False


def in_body(x: float, y: float) -> bool:
    return outline_radius(x / (W / 2), y / (H / 2)) <= 1.0


def tri_normal(a, b, c):
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx = uy * vz - uz * vy
    ny = uz * vx - ux * vz
    nz = ux * vy - uy * vx
    L = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return (nx / L, ny / L, nz / L)


def add_tri(faces, a, b, c):
    faces.append((tri_normal(a, b, c), a, b, c))


def main() -> None:
    faces: list = []
    # Sample grid
    xs = [(-W / 2) + i * (W / (NX - 1)) for i in range(NX)]
    ys = [(-H / 2) + j * (H / (NY - 1)) for j in range(NY)]

    def pt(i, j, z_extra=0.0):
        x, y = xs[i], ys[j]
        z = dome_z(x / (W / 2), y / (H / 2)) + z_extra
        return (x, y, z)

    solid = [[in_body(xs[i], ys[j]) and not in_slot(xs[i], ys[j]) for j in range(NY)] for i in range(NX)]

    # Outer surface (top)
    for i in range(NX - 1):
        for j in range(NY - 1):
            cells = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            if not all(solid[a][b] for a, b in cells):
                continue
            p00, p10 = pt(i, j, T), pt(i + 1, j, T)
            p11, p01 = pt(i + 1, j + 1, T), pt(i, j + 1, T)
            add_tri(faces, p00, p10, p11)
            add_tri(faces, p00, p11, p01)

    # Inner surface (bottom) — reverse winding
    for i in range(NX - 1):
        for j in range(NY - 1):
            cells = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            if not all(solid[a][b] for a, b in cells):
                continue
            p00, p10 = pt(i, j, 0), pt(i + 1, j, 0)
            p11, p01 = pt(i + 1, j + 1, 0), pt(i, j + 1, 0)
            add_tri(faces, p00, p11, p10)
            add_tri(faces, p00, p01, p11)

    # Side walls between solid/empty
    def wall(i0, j0, i1, j1):
        if solid[i0][j0] == solid[i1][j1]:
            return
        # edge from solid toward empty
        if solid[i0][j0]:
            a_top, a_bot = pt(i0, j0, T), pt(i0, j0, 0)
            b_top, b_bot = pt(i1, j1, T), pt(i1, j1, 0)
            # orient outward roughly
            add_tri(faces, a_bot, b_bot, b_top)
            add_tri(faces, a_bot, b_top, a_top)
        else:
            a_top, a_bot = pt(i1, j1, T), pt(i1, j1, 0)
            b_top, b_bot = pt(i0, j0, T), pt(i0, j0, 0)
            add_tri(faces, a_bot, b_bot, b_top)
            add_tri(faces, a_bot, b_top, a_top)

    for i in range(NX - 1):
        for j in range(NY):
            wall(i, j, i + 1, j)
    for i in range(NX):
        for j in range(NY - 1):
            wall(i, j, i, j + 1)

    # Side clip (left)
    cw, ch, cd = 2.0, 4.0, 1.6
    cx0, cy0, cz0 = -W / 2 + 0.2, -2.0, T * 0.3
    clip = [
        (cx0, cy0 - cw / 2, cz0),
        (cx0, cy0 + cw / 2, cz0),
        (cx0, cy0 + cw / 2, cz0 + ch),
        (cx0, cy0 - cw / 2, cz0 + ch),
        (cx0 - cd, cy0 - cw / 2 * 0.7, cz0 + 0.4),
        (cx0 - cd, cy0 + cw / 2 * 0.7, cz0 + 0.4),
        (cx0 - cd, cy0 + cw / 2 * 0.7, cz0 + ch - 0.4),
        (cx0 - cd, cy0 - cw / 2 * 0.7, cz0 + ch - 0.4),
    ]
    # box faces (rough)
    faces_idx = [
        (0, 1, 2, 3),
        (4, 7, 6, 5),
        (0, 4, 5, 1),
        (1, 5, 6, 2),
        (2, 6, 7, 3),
        (3, 7, 4, 0),
    ]
    for a, b, c, d in faces_idx:
        add_tri(faces, clip[a], clip[b], clip[c])
        add_tri(faces, clip[a], clip[c], clip[d])

    out = Path(__file__).resolve().parent / "vector_speaker_cover.stl"
    with out.open("wb") as f:
        f.write(b"\0" * 80)
        f.write(struct.pack("<I", len(faces)))
        for n, a, b, c in faces:
            f.write(struct.pack("<3f", *n))
            f.write(struct.pack("<3f", *a))
            f.write(struct.pack("<3f", *b))
            f.write(struct.pack("<3f", *c))
            f.write(struct.pack("<H", 0))
    print(f"Wrote {out} ({len(faces)} triangles, ~{W}x{H}x{T+DOME} mm)")


if __name__ == "__main__":
    main()
