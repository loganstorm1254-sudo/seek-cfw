# TORRAS Guardian S23 Ultra — replacement buttons

3D-printable replacements for the swappable side buttons on the **TORRAS Guardian Magnetic** case for Galaxy S23 Ultra (Amazon `B0BNNMWCW3`).

You asked for the volume button. The power button uses the same clip, so that STL is here too.

## Files to print

| File | What it is |
| --- | --- |
| [`torras_s23u_guardian_volume_button.stl`](torras_s23u_guardian_volume_button.stl) | Volume rocker (the long one) |
| [`torras_s23u_guardian_power_button.stl`](torras_s23u_guardian_power_button.stl) | Power / side key |
| [`torras_s23u_guardian_volume_button_fitkit.stl`](torras_s23u_guardian_volume_button_fitkit.stl) | Three volume copies at 98 / 100 / 102% XY |

Print the **fit kit** first if your printer tends to run big or small.

## Geometry (volume)

Watertight binary STL, millimeters:

- Outer pill: **24.60 × 3.50 × 1.22 mm**
- Two snap-in legs through the bumper wall, flared barbs on the inside
- Actuator pads on the inner face that press the phone's volume rocker
- Overall height **4.39 mm** (outer face to pad tips)

The Guardian bumper has a pill-shaped outer pocket and two inner holes split by a TPU bridge. Legs go through those holes; the cap sits in the pocket.

Dimensions are reverse-engineered from the S23 Ultra (163.4 × 78.1 × 8.9 mm), TORRAS product photos, empty-slot photos, and the spare-button card. They are not factory CAD.

## Print settings

- **Orientation:** outer pill face on the bed, legs pointing up
- **Supports:** none
- **Layer height:** 0.08–0.12 mm (0.08 extra-fine is ideal for the barbs)
- **Infill:** 100%
- **Perimeters:** 3+
- **Nozzle:** 0.4 mm works; 0.2 mm is nicer
- **Material:** PETG or tough PLA. TPU 95A also snaps in, closer to a soft original. Avoid brittle PLA — the barbs can snap on first install

Elephant foot on the bed face is fine; it is the outer visible surface. A light brim can help, then peel it.

## Install

1. Take the phone out of the case.
2. From the **outside**, align the two legs with the two holes in the volume pocket.
3. Press until the barbs click past the bumper (you will feel it).
4. Put the phone back in. The inner pads should sit on the phone's volume rocker.

To remove: from the **inside** of the empty case, push the legs outward until the barbs pop through.

## If the fit is wrong

Do **not** scale Z (bumper thickness stays the same). Scale **X and Y only**:

- Too tight / will not click in → 98% XY (already on the fit kit)
- Rattles or falls out → 102% XY

You can also edit the numbers at the top of `volume_button()` / `power_button()` in [`generate_buttons.py`](generate_buttons.py) and regenerate:

```bash
pip install trimesh manifold3d numpy
python3 generate_buttons.py
```
