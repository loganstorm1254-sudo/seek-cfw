#!/usr/bin/env python3
"""Generate printable STLs for TORRAS Guardian Magnetic S23 Ultra replaceable buttons.

The Guardian bumper uses a pill-shaped outer pocket with two inner through-holes
(volume) or one hole (power), separated by a TPU bridge. The original parts are a
hard-plastic cap with snap-in legs: insert from the outside, push the extra set
out from the inside of the empty case.

Dimensions are reverse-engineered from S23 Ultra geometry (163.4 x 78.1 x 8.9 mm),
product photos of the Magnetic Guardian case (ASIN B0BNNMWCW3), empty-slot photos,
and the spare-button card. If a print is tight or loose, scale X/Y in the slicer
by 1–2% (Z stays the same — bumper wall thickness does not change).

Units: millimeters. Origin: cap outer-face center, +Z toward the phone.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import trimesh
from trimesh.exchange.stl import export_stl


SECTIONS = 48


def _union(meshes: list[trimesh.Trimesh]) -> trimesh.Trimesh:
    meshes = [m for m in meshes if m is not None and len(m.faces)]
    if len(meshes) == 1:
        return meshes[0]
    return trimesh.boolean.union(meshes, engine="manifold")


def stadium_prism(length: float, width: float, height: float, z0: float) -> trimesh.Trimesh:
    """Extruded stadium (rectangle + semicircle caps) along X, thickness along Z."""
    if height <= 0 or width <= 0 or length <= 0:
        raise ValueError("stadium dimensions must be positive")
    radius = width / 2.0
    straight = max(length - width, 0.05)
    box = trimesh.creation.box(extents=[straight, width, height])
    c1 = trimesh.creation.cylinder(radius=radius, height=height, sections=SECTIONS)
    c2 = c1.copy()
    c1.apply_translation([-straight / 2.0, 0.0, 0.0])
    c2.apply_translation([straight / 2.0, 0.0, 0.0])
    mesh = _union([box, c1, c2])
    mesh.apply_translation([0.0, 0.0, z0 + height / 2.0])
    return mesh


def rounded_rect_prism(
    length: float, width: float, height: float, z0: float, corner_r: float
) -> trimesh.Trimesh:
    """Extruded rounded rectangle. Falls back to a stadium if the radius is large."""
    r = min(corner_r, length / 2.0 - 0.05, width / 2.0 - 0.05)
    if r <= 0.05:
        mesh = trimesh.creation.box(extents=[length, width, height])
        mesh.apply_translation([0.0, 0.0, z0 + height / 2.0])
        return mesh
    inner_l = length - 2.0 * r
    inner_w = width - 2.0 * r
    x_box = trimesh.creation.box(extents=[length, inner_w, height])
    y_box = trimesh.creation.box(extents=[inner_l, width, height])
    corners = []
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            c = trimesh.creation.cylinder(radius=r, height=height, sections=SECTIONS)
            c.apply_translation([sx * inner_l / 2.0, sy * inner_w / 2.0, 0.0])
            corners.append(c)
    mesh = _union([x_box, y_box, *corners])
    mesh.apply_translation([0.0, 0.0, z0 + height / 2.0])
    return mesh


def frustum_rect(
    length0: float,
    width0: float,
    length1: float,
    width1: float,
    height: float,
    z0: float,
) -> trimesh.Trimesh:
    """Convex hull of two rectangles — used for insertion tapers and barbs."""
    z1 = z0 + height
    pts = []
    for z, length, width in ((z0, length0, width0), (z1, length1, width1)):
        hl, hw = length / 2.0, width / 2.0
        pts.extend(
            [
                [-hl, -hw, z],
                [hl, -hw, z],
                [hl, hw, z],
                [-hl, hw, z],
            ]
        )
    return trimesh.convex.convex_hull(np.array(pts, dtype=float))


def snap_leg(
    *,
    x: float,
    length: float,
    width: float,
    z0: float,
    stem_h: float,
    barb_overhang: float,
    barb_h: float,
    chamfer_h: float,
    actuator_h: float,
    actuator_d: float,
) -> trimesh.Trimesh:
    """One snap-in leg: stem through the bumper, flared barb, contact pad."""
    parts: list[trimesh.Trimesh] = []
    parts.append(rounded_rect_prism(length, width, stem_h, z0, corner_r=0.45))

    barb_w = width + 2.0 * barb_overhang
    # Taper in: stem -> full barb (wedges through the TPU hole).
    parts.append(
        frustum_rect(
            length0=length,
            width0=width,
            length1=length,
            width1=barb_w,
            height=chamfer_h,
            z0=z0 + stem_h,
        )
    )
    # Short catch shelf that seats on the inside of the bumper.
    shelf_h = max(barb_h - chamfer_h, 0.18)
    parts.append(
        rounded_rect_prism(
            length, barb_w, shelf_h, z0 + stem_h + chamfer_h, corner_r=0.35
        )
    )

    pad_z = z0 + stem_h + barb_h
    pad = trimesh.creation.cylinder(
        radius=actuator_d / 2.0, height=actuator_h, sections=SECTIONS
    )
    pad.apply_translation([0.0, 0.0, pad_z + actuator_h / 2.0])
    parts.append(pad)

    leg = _union(parts)
    leg.apply_translation([x, 0.0, 0.0])
    return leg


def button_cap(length: float, width: float, height: float, chamfer: float) -> trimesh.Trimesh:
    """Outer pill cap, face at Z=0. Small inner chamfer so it does not print a sharp lip."""
    body_h = max(height - chamfer, height * 0.7)
    body = stadium_prism(length, width, body_h, 0.0)
    if chamfer <= 0.05:
        return body
    top = stadium_prism(length - 2.0 * chamfer, width - 2.0 * chamfer, chamfer, body_h)
    # Chamfer loft between body and inset top.
    loft = frustum_rect(
        length0=length,
        width0=width,
        length1=length - 2.0 * chamfer,
        width1=width - 2.0 * chamfer,
        height=chamfer,
        z0=body_h - 0.02,
    )
    return _union([body, loft, top])


def volume_button() -> trimesh.Trimesh:
    # Reverse-engineered for TORRAS Guardian Magnetic / Guardian S23 Ultra.
    cap_l, cap_w, cap_h = 24.60, 3.50, 1.22
    cap = button_cap(cap_l, cap_w, cap_h, chamfer=0.28)

    leg_l, leg_w = 8.10, 2.50
    inset = 1.55  # cap-end to outer end of each leg
    # Centers of the two legs (volume up / volume down).
    half_span = (cap_l / 2.0) - inset - (leg_l / 2.0)
    legs = [
        snap_leg(
            x=sx * half_span,
            length=leg_l,
            width=leg_w,
            z0=cap_h - 0.05,
            stem_h=2.05,
            barb_overhang=0.42,
            barb_h=0.62,
            chamfer_h=0.42,
            actuator_h=0.55,
            actuator_d=2.10,
        )
        for sx in (-1.0, 1.0)
    ]
    return _union([cap, *legs])


def power_button() -> trimesh.Trimesh:
    cap_l, cap_w, cap_h = 9.80, 3.50, 1.22
    cap = button_cap(cap_l, cap_w, cap_h, chamfer=0.28)
    leg = snap_leg(
        x=0.0,
        length=6.20,
        width=2.50,
        z0=cap_h - 0.05,
        stem_h=2.05,
        barb_overhang=0.42,
        barb_h=0.62,
        chamfer_h=0.42,
        actuator_h=0.55,
        actuator_d=2.10,
    )
    return _union([cap, leg])


def scaled_xy(mesh: trimesh.Trimesh, factor: float) -> trimesh.Trimesh:
    out = mesh.copy()
    out.apply_scale([factor, factor, 1.0])
    return out


def fit_kit(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    """98 / 100 / 102% XY copies, spaced so they slice as three separate parts."""
    copies = []
    for i, factor in enumerate((0.98, 1.00, 1.02)):
        part = scaled_xy(mesh, factor)
        # Shift along Y so they sit side-by-side on the bed.
        part.apply_translation([0.0, i * 8.5 - 8.5, 0.0])
        copies.append(part)
    return trimesh.util.concatenate(copies)


def finalize(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    mesh.merge_vertices()
    mesh.update_faces(mesh.unique_faces())
    mesh.update_faces(mesh.nondegenerate_faces())
    trimesh.repair.fill_holes(mesh)
    if mesh.volume < 0:
        mesh.invert()
    trimesh.repair.fix_winding(mesh)
    trimesh.repair.fix_normals(mesh)
    return mesh


def write_stl(mesh: trimesh.Trimesh, path: Path) -> None:
    mesh = finalize(mesh)
    path.parent.mkdir(parents=True, exist_ok=True)
    # numpy-stl / trimesh binary STL
    data = export_stl(mesh)
    path.write_bytes(data)
    extents = mesh.extents
    print(
        f"wrote {path.name:48s}  "
        f"{extents[0]:6.2f} x {extents[1]:5.2f} x {extents[2]:5.2f} mm  "
        f"watertight={mesh.is_watertight}  volume={mesh.volume:.2f} mm^3"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-o",
        "--outdir",
        type=Path,
        default=Path(__file__).resolve().parent,
    )
    args = parser.parse_args()
    outdir: Path = args.outdir

    volume = volume_button()
    power = power_button()
    write_stl(volume, outdir / "torras_s23u_guardian_volume_button.stl")
    write_stl(power, outdir / "torras_s23u_guardian_power_button.stl")
    write_stl(fit_kit(volume), outdir / "torras_s23u_guardian_volume_button_fitkit.stl")


if __name__ == "__main__":
    main()
