#!/usr/bin/env python3
"""Generate printable STLs for TORRAS Guardian Magnetic S23 Ultra replaceable buttons.

Visible face matches the installed volume rocker: one stadium pill with a thin
center groove (vol up / vol down), slightly proud of the bumper, matte cap.

Retention is a T-slot, same as the originals:
  larger inner flange stays inside the bumper, smaller outer face sits in the
  pocket. Install from the inside of the empty case; push out from inside to remove.

Units: millimeters.
Print orientation: inner flange on the bed, grooved outer face pointing up.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import trimesh
from trimesh.exchange.stl import export_stl


SECTIONS = 64


def _union(meshes: list[trimesh.Trimesh]) -> trimesh.Trimesh:
    meshes = [m for m in meshes if m is not None and len(m.faces)]
    if len(meshes) == 1:
        return meshes[0]
    return trimesh.boolean.union(meshes, engine="manifold")


def _difference(a: trimesh.Trimesh, b: trimesh.Trimesh) -> trimesh.Trimesh:
    return trimesh.boolean.difference([a, b], engine="manifold")


def stadium_prism(length: float, width: float, height: float, z0: float) -> trimesh.Trimesh:
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


def frustum_rect(
    length0: float,
    width0: float,
    length1: float,
    width1: float,
    height: float,
    z0: float,
) -> trimesh.Trimesh:
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


def grooved_cap(
    *,
    length: float,
    width: float,
    height: float,
    z0: float,
    fillet: float,
    groove_r: float,
    groove_depth: float,
) -> trimesh.Trimesh:
    """Outer pill: body + inset top (edge fillet) minus a U-groove across the face."""
    body_h = max(height - fillet, height * 0.62)
    body = stadium_prism(length, width, body_h, z0)
    loft = frustum_rect(
        length0=length,
        width0=width,
        length1=length - 2.0 * fillet,
        width1=width - 2.0 * fillet,
        height=fillet + 0.02,
        z0=z0 + body_h - 0.02,
    )
    top = stadium_prism(
        length - 2.0 * fillet,
        width - 2.0 * fillet,
        max(fillet * 0.35, 0.08),
        z0 + body_h,
    )
    cap = _union([body, loft, top])

    # Cylinder along Y cuts a U-groove at the outer face, full width.
    face_z = z0 + height
    cutter = trimesh.creation.cylinder(
        radius=groove_r, height=width + 1.6, sections=SECTIONS
    )
    cutter.apply_transform(
        trimesh.transformations.rotation_matrix(np.pi / 2.0, [1.0, 0.0, 0.0])
    )
    # Sink the cutter so the groove depth is groove_depth at center.
    cutter.apply_translation([0.0, 0.0, face_z - groove_depth + groove_r])
    return _difference(cap, cutter)


def volume_button() -> trimesh.Trimesh:
    # S23 Ultra volume rocker ~20.5 mm; case cap a bit longer/wider to fill the pocket.
    cap_l, cap_w, cap_h = 24.40, 3.80, 1.28
    stem_l, stem_w, stem_h = 23.10, 2.85, 1.95
    flange_l, flange_w, flange_h = 25.20, 4.70, 0.78
    nub_h, nub_d = 0.55, 1.90
    nub_span = 11.20  # center-to-center of vol-up / vol-down pads

    flange = stadium_prism(flange_l, flange_w, flange_h, nub_h)
    stem = stadium_prism(stem_l, stem_w, stem_h, nub_h + flange_h - 0.04)
    cap_z = nub_h + flange_h + stem_h - 0.08
    cap = grooved_cap(
        length=cap_l,
        width=cap_w,
        height=cap_h,
        z0=cap_z,
        fillet=0.38,
        groove_r=0.22,
        groove_depth=0.42,
    )
    nubs = []
    for sx in (-0.5, 0.5):
        nub = trimesh.creation.cylinder(
            radius=nub_d / 2.0, height=nub_h + 0.06, sections=SECTIONS
        )
        nub.apply_translation([sx * nub_span, 0.0, (nub_h + 0.06) / 2.0])
        nubs.append(nub)
    return _union([flange, stem, cap, *nubs])


def power_button() -> trimesh.Trimesh:
    cap_l, cap_w, cap_h = 9.70, 3.80, 1.28
    stem_l, stem_w, stem_h = 8.40, 2.85, 1.95
    flange_l, flange_w, flange_h = 10.50, 4.70, 0.78
    nub_h, nub_d = 0.55, 1.90

    flange = stadium_prism(flange_l, flange_w, flange_h, nub_h)
    stem = stadium_prism(stem_l, stem_w, stem_h, nub_h + flange_h - 0.04)
    cap_z = nub_h + flange_h + stem_h - 0.08
    cap = stadium_prism(cap_l, cap_w, cap_h, cap_z)
    # Small fillet on power cap via inset loft.
    loft = frustum_rect(
        length0=cap_l,
        width0=cap_w,
        length1=cap_l - 0.76,
        width1=cap_w - 0.76,
        height=0.40,
        z0=cap_z + cap_h - 0.40,
    )
    cap = _union([cap, loft])
    nub = trimesh.creation.cylinder(
        radius=nub_d / 2.0, height=nub_h + 0.06, sections=SECTIONS
    )
    nub.apply_translation([0.0, 0.0, (nub_h + 0.06) / 2.0])
    return _union([flange, stem, cap, nub])


def scaled_xy(mesh: trimesh.Trimesh, factor: float) -> trimesh.Trimesh:
    out = mesh.copy()
    out.apply_scale([factor, factor, 1.0])
    return out


def fit_kit(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    copies = []
    for i, factor in enumerate((0.98, 1.00, 1.02)):
        part = scaled_xy(mesh, factor)
        part.apply_translation([0.0, i * 10.0 - 10.0, 0.0])
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
    path.write_bytes(export_stl(mesh))
    e = mesh.extents
    print(
        f"wrote {path.name:48s}  "
        f"{e[0]:6.2f} x {e[1]:5.2f} x {e[2]:5.2f} mm  "
        f"watertight={mesh.is_watertight}  volume={mesh.volume:.2f} mm^3"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--outdir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    volume = volume_button()
    power = power_button()
    write_stl(volume, args.outdir / "torras_s23u_guardian_volume_button.stl")
    write_stl(power, args.outdir / "torras_s23u_guardian_power_button.stl")
    write_stl(fit_kit(volume), args.outdir / "torras_s23u_guardian_volume_button_fitkit.stl")


if __name__ == "__main__":
    main()
