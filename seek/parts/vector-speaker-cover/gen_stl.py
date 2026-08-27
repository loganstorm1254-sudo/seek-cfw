#!/usr/bin/env python3
"""
Vector rear speaker COVER — cupped tombstone cowling (NOT a flat plate, NOT a bowl).

Photo match:
  - Wider at top, rounded bottom (shield / tombstone silhouette)
  - Mildly convex face, then sides fold back into a deep cup (~8–10 mm)
  - Tombstone recess + 2×5 capsule slots + center rib
  - Hinge peg lower-left, cable notch upper-left

  python3 gen_stl.py
"""
from __future__ import annotations

import math
import struct
from pathlib import Path

# --- overall (mm) ---
W_TOP = 35.0
W_BOT = 27.0
H = 37.0
FACE_DOME = 2.2          # front bulge at center
WALL_DEPTH = 9.5         # how far the rim wraps back (-Z)
WALL = 1.2               # shell thickness
RIM_INSET = 1.0          # walls lean slightly inward

# --- tombstone recess ---
REC_W, REC_H, REC_R = 13.2, 17.8, 3.0
REC_DEPTH = 0.5
REC_CY = 1.0

# --- slots 2×5 ---
SLOT_LEN, SLOT_H = 4.9, 1.05
SLOT_GAP_X, SLOT_GAP_Y = 2.15, 1.2
ROWS = 5

# --- hinge peg ---
PEG_R, PEG_L = 1.15, 2.5
PEG_Y = -7.0

NOTCH = True
NU, NV = 64, 72


def width_at(y: float) -> float:
    """Full width at height y (y=0 center, +y = top)."""
    t = (y / (H / 2) + 1.0) * 0.5  # 0 bottom → 1 top
    t = max(0.0, min(1.0, t))
    return W_BOT + (W_TOP - W_BOT) * t


def in_outline(x: float, y: float) -> bool:
    half_h = H / 2
    if abs(y) > half_h:
        return False
    half_w = width_at(y) / 2
    if half_w <= 1e-6:
        return False
    nx = x / half_w
    ny = y / half_h
    # Shield: flatter top, rounder bottom, less circular overall
    px, py = 3.4, (1.9 if y >= 0 else 3.6)
    return abs(nx) ** px + abs(ny) ** py <= 1.0


def outline_normal_2d(x: float, y: float):
    """Approx outward 2D normal via gradient of implicit."""
    eps = 0.15
    def f(xx, yy):
        if abs(yy) > H / 2:
            return 2.0
        hw = width_at(yy) / 2
        nx = xx / hw if hw else 0
        ny = yy / (H / 2)
        px, py = 3.4, (1.9 if yy >= 0 else 3.6)
        return abs(nx) ** px + abs(ny) ** py - 1.0
    gx = f(x + eps, y) - f(x - eps, y)
    gy = f(x, y + eps) - f(x, y - eps)
    L = math.sqrt(gx * gx + gy * gy) or 1.0
    return gx / L, gy / L


def in_tombstone(x: float, y: float) -> bool:
    cx, cy = 0.0, REC_CY
    hx, hy = REC_W / 2 - REC_R, REC_H / 2 - REC_R
    dx, dy = abs(x - cx), abs(y - cy)
    if dx <= hx and dy <= hy + REC_R:
        return True
    if dy <= hy and dx <= hx + REC_R:
        return True
    cx0 = hx if x >= cx else -hx
    cy0 = hy if y >= cy else -hy
    return (x - (cx + cx0)) ** 2 + (y - (cy + cy0)) ** 2 <= REC_R**2


def in_slot(x: float, y: float) -> bool:
    col_off = SLOT_LEN / 2 + SLOT_GAP_X / 2
    total_h = ROWS * SLOT_H + (ROWS - 1) * SLOT_GAP_Y
    start_y = REC_CY + total_h / 2 - SLOT_H / 2
    rr = SLOT_H / 2
    for sign in (-1.0, 1.0):
        cx = sign * col_off
        for r in range(ROWS):
            cy = start_y - r * (SLOT_H + SLOT_GAP_Y)
            hx = SLOT_LEN / 2 - rr
            dx, dy = abs(x - cx), abs(y - cy)
            if dx <= hx and dy <= rr:
                return True
            if dx > hx and (dx - hx) ** 2 + dy**2 <= rr**2:
                return True
    return False


def in_cable_notch(x: float, y: float) -> bool:
    if not NOTCH:
        return False
    # Upper-left bite
    return x < -W_TOP * 0.28 and y > H * 0.28 and (x + W_TOP * 0.22) ** 2 + (
        y - H * 0.38
    ) ** 2 < 3.4**2


def solid_xy(x: float, y: float) -> bool:
    if not in_outline(x, y):
        return False
    if in_cable_notch(x, y):
        return False
    if in_slot(x, y):
        return False
    return True


def face_z(x: float, y: float) -> float:
    """Outer face Z (+ toward outside). Mild dome; rim at z≈0 before wrap."""
    if not in_outline(x, y):
        return 0.0
    hw = width_at(y) / 2
    nx = (x / hw) if hw else 0.0
    ny = y / (H / 2)
    r = min(1.0, math.sqrt(nx * nx + ny * ny))
    z = FACE_DOME * math.cos(0.5 * math.pi * r)
    if in_tombstone(x, y) and not in_slot(x, y):
        z -= REC_DEPTH
    return z


def edge_dist(x: float, y: float) -> float:
    """0 at center-ish, 1 at outline edge (rough)."""
    hw = width_at(y) / 2
    nx = (x / hw) if hw else 0.0
    ny = y / (H / 2)
    px, py = 3.4, (1.9 if y >= 0 else 3.6)
    return min(1.0, (abs(nx) ** px + abs(ny) ** py) ** (1.0 / 2.8))


def clamp_to_outline(x: float, y: float):
    """Pull a point onto the outline if it sits outside (for clean rim walls)."""
    if in_outline(x, y):
        return x, y
    # March toward origin
    for s in (0.98, 0.95, 0.9, 0.85, 0.8, 0.7, 0.6, 0.5, 0.35, 0.2):
        xx, yy = x * s, y * s
        if in_outline(xx, yy):
            # refine outward
            lo, hi = s, min(1.0, s + 0.15)
            for _ in range(12):
                mid = (lo + hi) / 2
                if in_outline(x * mid, y * mid):
                    lo = mid
                else:
                    hi = mid
            return x * lo, y * lo
    return 0.0, 0.0


def wrap_t(x: float, y: float) -> float:
    """0 = face, 1 = fully wrapped rim. Always clamped."""
    e = min(1.0, edge_dist(x, y))
    # Kick walls in harder near the rim (distinct face → wrap, not a soft blob)
    t = max(0.0, min(1.0, (e - 0.50) / 0.50))
    return t * t * (3 - 2 * t)


def outer_pt(x: float, y: float):
    """
    Map face (x,y) to 3D on the cupped shell.
    Near center: on the domed face (z = face_z).
    Near rim: sweeps back in -Z and slightly inward → deep cup walls.
    """
    t = wrap_t(x, y)
    z_face = face_z(x, y)
    z = z_face * (1 - t) + (-WALL_DEPTH) * t
    if t > 0:
        nx, ny = outline_normal_2d(x, y)
        pull = RIM_INSET * t
        x = x - nx * pull
        y = y - ny * pull
    return (x, y, z)


def inner_pt(x: float, y: float):
    """Inward offset ≈ along local shell normal (approx -Z + radial)."""
    ox, oy, oz = outer_pt(x, y)
    t = wrap_t(x, y)
    if t < 0.35:
        return (ox, oy, oz - WALL)
    nx, ny = outline_normal_2d(x, y)
    return (ox + nx * WALL * 0.85, oy + ny * WALL * 0.85, oz + WALL * 0.15)


def tri_n(a, b, c):
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    L = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return (nx / L, ny / L, nz / L)


def add(faces, a, b, c, flip=False):
    if flip:
        a, b, c = a, c, b
    n = tri_n(a, b, c)
    if n == (0.0, 0.0, 0.0):
        return
    faces.append((n, a, b, c))


def add_quad(faces, a, b, c, d, flip=False):
    add(faces, a, b, c, flip)
    add(faces, a, c, d, flip)


def main() -> None:
    faces: list = []
    xs = [(-W_TOP / 2) + i * (W_TOP / (NU - 1)) for i in range(NU)]
    ys = [(-H / 2) + j * (H / (NV - 1)) for j in range(NV)]
    solid = [[solid_xy(xs[i], ys[j]) for j in range(NV)] for i in range(NU)]

    def O(i, j):
        return outer_pt(xs[i], ys[j])

    def I(i, j):
        return inner_pt(xs[i], ys[j])

    for i in range(NU - 1):
        for j in range(NV - 1):
            cells = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            if not all(solid[a][b] for a, b in cells):
                continue
            o00, o10, o11, o01 = O(i, j), O(i + 1, j), O(i + 1, j + 1), O(i, j + 1)
            add_quad(faces, o00, o10, o11, o01)
            i00, i10, i11, i01 = I(i, j), I(i + 1, j), I(i + 1, j + 1), I(i, j + 1)
            add_quad(faces, i00, i11, i10, i01)

    def edge_wall(i0, j0, i1, j1):
        s0, s1 = solid[i0][j0], solid[i1][j1]
        if s0 == s1:
            return
        # Always build from solid → empty; clamp empty XY onto outline / keep slots
        if s0:
            si, sj, ei, ej = i0, j0, i1, j1
        else:
            si, sj, ei, ej = i1, j1, i0, j0
        sx, sy = xs[si], ys[sj]
        ex, ey = xs[ei], ys[ej]
        if not in_outline(ex, ey):
            ex, ey = clamp_to_outline(ex, ey)
        ao, ai = outer_pt(sx, sy), inner_pt(sx, sy)
        bo, bi = outer_pt(ex, ey), inner_pt(ex, ey)
        add_quad(faces, ai, bi, bo, ao)

    for i in range(NU - 1):
        for j in range(NV):
            edge_wall(i, j, i + 1, j)
    for i in range(NU):
        for j in range(NV - 1):
            edge_wall(i, j, i, j + 1)

    # Hinge peg — lower left rim, axis mostly -X
    peg_x = -width_at(PEG_Y) / 2 + 0.6
    peg_y = PEG_Y
    base = outer_pt(peg_x, peg_y)
    # Lift peg to sit on the wall exterior
    base = (base[0] - 0.2, base[1], base[2] + 0.3)
    tip = (base[0] - PEG_L, base[1], base[2])
    segs = 16
    ring_b, ring_t = [], []
    for k in range(segs):
        ang = 2 * math.pi * k / segs
        cy = PEG_R * math.cos(ang)
        cz = PEG_R * math.sin(ang)
        ring_b.append((base[0], base[1] + cy, base[2] + cz))
        ring_t.append((tip[0], tip[1] + cy, tip[2] + cz))
    for k in range(segs):
        k2 = (k + 1) % segs
        add_quad(faces, ring_b[k], ring_b[k2], ring_t[k2], ring_t[k])
        add(faces, base, ring_b[k2], ring_b[k])
        add(faces, tip, ring_t[k], ring_t[k2])

    out = Path(__file__).resolve().parent / "vector_speaker_cover.stl"
    with out.open("wb") as f:
        f.write(b"Seek Vector speaker cover v4 cupped tombstone".ljust(80, b"\0")[:80])
        f.write(struct.pack("<I", len(faces)))
        for n, a, b, c in faces:
            f.write(struct.pack("<3f", *n))
            for p in (a, b, c):
                f.write(struct.pack("<3f", *p))
            f.write(struct.pack("<H", 0))

    pts = [p for _, a, b, c in faces for p in (a, b, c)]
    mins = [min(p[i] for p in pts) for i in range(3)]
    maxs = [max(p[i] for p in pts) for i in range(3)]
    size = [round(maxs[i] - mins[i], 2) for i in range(3)]
    print(f"Wrote {out}")
    print(f"  triangles={len(faces)}")
    print(f"  bbox_mm={size}  (X Y Z)")
    print(f"  cup depth≈{WALL_DEPTH}mm wrap + {FACE_DOME}mm dome")


if __name__ == "__main__":
    main()
