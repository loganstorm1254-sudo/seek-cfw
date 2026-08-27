# Vector rear speaker cover (3D print)

Replacement for the lost **black head-back speaker grille** — the cupped cowling with 2×5 horizontal slots (not a flat plate).

## Files

| File | Use |
|------|-----|
| `vector_speaker_cover.stl` | Slice & print (**use this**) |
| `gen_stl.py` | Regenerates the cupped STL |
| `vector_speaker_cover.scad` | Rough OpenSCAD twin for tweaks |

## Shape

- Tombstone / shield outline — wider at the top, rounded bottom
- Mildly domed face + **~9.5 mm wrap-back rim** (cup over the speaker)
- Recessed grille: 2 columns × 5 capsule slots
- Hinge peg (lower-left) + cable notch (upper-left)

## Print

- **Size (approx):** ~32 × 36 × 12 mm (estimated from photos — not OEM CAD)
- **Material:** PETG/ABS preferred; PLA OK for a fit check
- **Layer:** 0.12–0.16 mm, 100% infill
- **Orientation:** grille face up; support the wrap rim if your slicer needs it
- **Fit:** scale XY ±2–5% in the slicer, or edit sizes at the top of `gen_stl.py` and re-run

## Notes

- Peg/notch are approximate — sand or glue if the OEM snap doesn’t catch.
- Cover only — not the speaker driver or blue lead.
