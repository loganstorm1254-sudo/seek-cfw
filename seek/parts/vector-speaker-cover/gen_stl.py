#!/usr/bin/env python3
"""
Vector rear speaker COVER — matches OEM photos (inside + outside).

Silhouette (user correction):
  TOP  = widest, nearly flat edge (ANKI side)
  SIDES = taper inward going down
  BOTTOM = narrower + much more rounded

Outside: recessed 2×5 capsule grille, hinge peg lower-left, cable notch upper-left.
Inside: circular speaker well + two screw bosses (part 000-00623 style).

  python3 gen_stl.py
"""
from __future__ import annotations

import math
import struct
from pathlib import Path

# --- outer silhouette (mm) — wide gently-curved top, smooth taper, round bottom ---
W_TOP = 35.5          # widest near top
W_JOIN = 26.0         # = 2*BOT_R — sides meet bottom U at its equator
H = 37.5
TOP_CROWN = 0.6       # slight crown — top is nearly flat like the photo
CORNER_R_TOP = 4.0    # soft top corners (no ear tabs)
BOT_R = 13.0          # bottom round radius (smooth U, not a tiny ball)

# Bottom circle center sits so the circle is tangent to the tapered sides.
# Join height from bottom: BOT_R - something; place center on midline.
# y_center = -H/2 + BOT_R
# At tangency, side line touches circle.

# --- cup ---
FACE_DOME = 2.0
WALL_DEPTH = 9.0
WALL = 1.25
RIM_INSET = 0.9

# --- exterior grille ---
REC_W, REC_H, REC_R = 13.0, 17.5, 2.8
REC_DEPTH = 0.45
REC_CY = 0.5
SLOT_LEN, SLOT_H = 4.8, 1.0
SLOT_GAP_X, SLOT_GAP_Y = 2.1, 1.15
ROWS = 5

# --- interior speaker well + bosses (from inside photo) ---
WELL_R = 7.2
WELL_DEPTH = 1.4
BOSS_DX = 11.0        # ±X from center
BOSS_Y = 0.0
BOSS_OR, BOSS_IR = 2.6, 0.85
BOSS_H = 3.2

# --- peg / notch ---
PEG_R, PEG_L = 1.15, 2.5
PEG_Y = -8.5
NOTCH = True

NU, NV = 72, 84


def bot_center_y() -> float:
    return -H / 2 + BOT_R


def half_width_at(y: float) -> float:
    """Half-width of tapered sides above the bottom U."""
    y_top = H / 2
    y_join = bot_center_y()
    if y >= y_top:
        return W_TOP / 2
    if y <= y_join:
        return W_JOIN / 2
    t = (y_top - y) / (y_top - y_join)
    return 0.5 * (W_TOP + (W_JOIN - W_TOP) * t)


def top_edge_y(x: float) -> float:
    """Top edge: highest at center, slight drop toward corners."""
    half = max(1e-6, W_TOP / 2 - CORNER_R_TOP)
    u = max(-1.0, min(1.0, x / half))
    return H / 2 - TOP_CROWN * (u * u)


def in_outline(x: float, y: float) -> bool:
    """
    OEM shield from your photos:
      wide soft-crowned top → tapering sides → smooth U bottom.
    No ear tabs — top corners are inset quarter-rounds only.
    """
    cy = bot_center_y()

    # Bottom U
    if y <= cy:
        return x * x + (y - cy) ** 2 <= BOT_R**2 + 1e-6

    hw = half_width_at(y)
    if abs(x) > hw + 1e-6:
        return False

    half_flat = W_TOP / 2 - CORNER_R_TOP
    sy = H / 2 - CORNER_R_TOP

    # Main body below the corner band
    if y <= sy:
        return True

    # Top corner band: inset quarter-circle (stays inside W_TOP)
    if abs(x) <= half_flat:
        return y <= top_edge_y(x) + 1e-6

    sx = half_flat if x > 0 else -half_flat
    return (x - sx) ** 2 + (y - sy) ** 2 <= CORNER_R_TOP**2 + 1e-6


def outline_normal_2d(x: float, y: float):
    cy = bot_center_y()
    if y <= cy:
        dx, dy = x, y - cy
        L = math.sqrt(dx * dx + dy * dy) or 1.0
        return dx / L, dy / L
    x1, y1 = W_TOP / 2, H / 2
    x2, y2 = W_JOIN / 2, cy
    ex, ey = x2 - x1, y2 - y1
    nx, ny = ey, -ex
    L = math.sqrt(nx * nx + ny * ny) or 1.0
    nx, ny = nx / L, ny / L
    if nx < 0:
        nx, ny = -nx, -ny
    if x < 0:
        nx = -nx
    return nx, ny


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
    return x < -W_TOP * 0.30 and y > H * 0.28 and (x + W_TOP * 0.24) ** 2 + (
        y - H * 0.36
    ) ** 2 < 3.2**2


def in_boss_hole(x: float, y: float) -> bool:
    for sx in (-BOSS_DX, BOSS_DX):
        if (x - sx) ** 2 + (y - BOSS_Y) ** 2 <= BOSS_IR**2:
            return True
    return False


def solid_xy(x: float, y: float) -> bool:
    if not in_outline(x, y):
        return False
    if in_cable_notch(x, y):
        return False
    if in_slot(x, y):
        return False
    if in_boss_hole(x, y):
        return False
    return True


def face_z(x: float, y: float) -> float:
    if not in_outline(x, y):
        return 0.0
    hw = max(half_width_at(y), 1e-6)
    nx = abs(x) / hw
    # Vertical: 0 at mid of body, normalize to top/bottom extents
    ny = (0.5 * H - y) / H  # 0 top → 1 bottom — use radial-ish from face center
    cy = 0.5  # face center slightly above geometric mid
    rx = x / (0.5 * W_TOP)
    ry = (y - cy) / (0.5 * H)
    r = min(1.0, math.sqrt(rx * rx + ry * ry))
    z = FACE_DOME * math.cos(0.5 * math.pi * r)
    if in_tombstone(x, y) and not in_slot(x, y):
        z -= REC_DEPTH
    return z


def edge_dist(x: float, y: float) -> float:
    """Approx 0 center → 1 rim, for wrap blend."""
    if not in_outline(x, y):
        return 1.0
    best = 1e9
    step = 0.25
    for ang in range(0, 360, 15):
        rad = math.radians(ang)
        dx, dy = math.cos(rad), math.sin(rad)
        dist = 0.0
        px, py = x, y
        for _ in range(100):
            px += dx * step
            py += dy * step
            dist += step
            if not in_outline(px, py):
                break
        best = min(best, dist)
    # ~half-width ≈ 15–18 mm at mid → map to 0..1
    return max(0.0, min(1.0, 1.0 - best / 16.0))


def clamp_to_outline(x: float, y: float):
    if in_outline(x, y):
        return x, y
    for s in (0.98, 0.95, 0.9, 0.85, 0.8, 0.7, 0.6, 0.5, 0.35, 0.2, 0.1):
        # pull toward face center (0, 0.5)
        cx, cy = 0.0, 0.5
        xx = cx + (x - cx) * s
        yy = cy + (y - cy) * s
        if in_outline(xx, yy):
            lo, hi = s, min(1.0, s + 0.12)
            for _ in range(14):
                mid = (lo + hi) / 2
                mx = cx + (x - cx) * mid
                my = cy + (y - cy) * mid
                if in_outline(mx, my):
                    lo = mid
                else:
                    hi = mid
            return cx + (x - cx) * lo, cy + (y - cy) * lo
    return 0.0, 0.5


def wrap_t(x: float, y: float) -> float:
    e = edge_dist(x, y)
    t = max(0.0, min(1.0, (e - 0.48) / 0.52))
    return t * t * (3 - 2 * t)


def outer_pt(x: float, y: float):
    t = wrap_t(x, y)
    z_face = face_z(x, y)
    z = z_face * (1 - t) + (-WALL_DEPTH) * t
    if t > 0:
        nx, ny = outline_normal_2d(x, y)
        x = x - nx * RIM_INSET * t
        y = y - ny * RIM_INSET * t
    return (x, y, z)


def inner_pt(x: float, y: float):
    ox, oy, oz = outer_pt(x, y)
    t = wrap_t(x, y)
    # Speaker well recess on the inner face (center)
    well_extra = 0.0
    if x * x + (y - 0.3) ** 2 <= WELL_R * WELL_R:
        well_extra = WELL_DEPTH * (1.0 - math.sqrt(x * x + (y - 0.3) ** 2) / WELL_R)
    if t < 0.35:
        return (ox, oy, oz - WALL - well_extra)
    nx, ny = outline_normal_2d(x, y)
    return (ox + nx * WALL * 0.85, oy + ny * WALL * 0.85, oz + WALL * 0.15 - well_extra * 0.3)


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


def add_cylinder(faces, base, axis, radius, segs=16, capped=True):
    """axis = full offset vector from base to tip."""
    tip = (base[0] + axis[0], base[1] + axis[1], base[2] + axis[2])
    ax, ay, az = axis
    aL = math.sqrt(ax * ax + ay * ay + az * az) or 1.0
    ax, ay, az = ax / aL, ay / aL, az / aL
    tmp = (0.0, 1.0, 0.0) if abs(ay) < 0.9 else (1.0, 0.0, 0.0)
    bx = tmp[1] * az - tmp[2] * ay
    by = tmp[2] * ax - tmp[0] * az
    bz = tmp[0] * ay - tmp[1] * ax
    bL = math.sqrt(bx * bx + by * by + bz * bz) or 1.0
    bx, by, bz = bx / bL, by / bL, bz / bL
    cx = ay * bz - az * by
    cy = az * bx - ax * bz
    cz = ax * by - ay * bx
    rb, rt = [], []
    for k in range(segs):
        ang = 2 * math.pi * k / segs
        ca, sa = math.cos(ang), math.sin(ang)
        ox = (bx * ca + cx * sa) * radius
        oy = (by * ca + cy * sa) * radius
        oz = (bz * ca + cz * sa) * radius
        rb.append((base[0] + ox, base[1] + oy, base[2] + oz))
        rt.append((tip[0] + ox, tip[1] + oy, tip[2] + oz))
    for k in range(segs):
        k2 = (k + 1) % segs
        add_quad(faces, rb[k], rb[k2], rt[k2], rt[k])
        if capped:
            add(faces, base, rb[k2], rb[k])
            add(faces, tip, rt[k], rt[k2])


def main() -> None:
    faces: list = []
    xs = [(-W_TOP / 2 - 1) + i * ((W_TOP + 2) / (NU - 1)) for i in range(NU)]
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

    # Hinge peg lower-left
    peg_x = -half_width_at(PEG_Y) + 0.5
    base = outer_pt(peg_x, PEG_Y)
    base = (base[0] - 0.15, base[1], base[2] + 0.2)
    add_cylinder(faces, base, (-PEG_L, 0.0, 0.0), PEG_R, segs=16)

    # Interior screw bosses (point inward / -Z from inner face)
    for sx in (-BOSS_DX, BOSS_DX):
        # Boss sits on inner face around (sx, BOSS_Y)
        face = inner_pt(sx, BOSS_Y)
        # Outer boss cylinder toward interior (-Z)
        add_cylinder(
            faces,
            (face[0], face[1], face[2]),
            (0.0, 0.0, -BOSS_H),
            BOSS_OR,
            segs=14,
            capped=True,
        )

    out = Path(__file__).resolve().parent / "vector_speaker_cover.stl"
    with out.open("wb") as f:
        f.write(b"Seek Vector speaker cover v5 trapezoid flat-top".ljust(80, b"\0")[:80])
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
    print(f"  silhouette: top {W_TOP}mm → U-bottom {2*BOT_R}mm, H={H}mm")


if __name__ == "__main__":
    main()
