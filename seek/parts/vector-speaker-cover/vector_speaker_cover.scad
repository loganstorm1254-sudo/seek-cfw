// Approximate Anki Vector rear speaker COVER — cupped tombstone cowling.
// Dimensions estimated from photos — print, test-fit, tweak params below.
// Prefer regenerating with gen_stl.py for the full wrap-around cup mesh.
//
// Print tips:
//  - 0.12–0.16 mm layers, 100% infill, PETG or ABS preferred
//  - Print grille face UP; support the wrap-back rim if needed
//  - Black filament; sand lightly for snap fit

/* [Size] */
width_top_mm    = 35.0;
width_bot_mm    = 27.0;
height_mm       = 37.0;
wall_mm         = 1.2;
face_dome_mm    = 2.2;
wrap_depth_mm   = 9.5;    // rim folds back — this is the cup, not a flat plate

/* [Grille] */
slot_cols       = 2;
slot_rows       = 5;
slot_len_mm     = 4.9;
slot_h_mm       = 1.05;
slot_gap_x_mm   = 2.15;
slot_gap_y_mm   = 1.2;

/* [Recess] */
recess_w_mm     = 13.2;
recess_h_mm     = 17.8;
recess_depth_mm = 0.5;
recess_r_mm     = 3.0;

/* [Peg] */
peg_r_mm        = 1.15;
peg_len_mm      = 2.5;
peg_y_mm        = -7.0;

$fn = 48;

module cover_outline_2d() {
  hull() {
    translate([0,  height_mm*0.32])
      scale([width_top_mm/width_bot_mm, 0.5])
        offset(r = 4) square([width_bot_mm-8, height_mm*0.35], center=true);
    translate([0, -height_mm*0.12])
      offset(r = 5) square([width_bot_mm-10, height_mm*0.55], center=true);
  }
}

module slot_2d() {
  hull() {
    translate([-slot_len_mm/2 + slot_h_mm/2, 0]) circle(r = slot_h_mm/2);
    translate([ slot_len_mm/2 - slot_h_mm/2, 0]) circle(r = slot_h_mm/2);
  }
}

module grille_slots_2d() {
  total_h = slot_rows*slot_h_mm + (slot_rows-1)*slot_gap_y_mm;
  start_y = total_h/2 - slot_h_mm/2;
  col_off = slot_len_mm/2 + slot_gap_x_mm/2;
  for (c = [0, 1]) {
    x = (c == 0) ? -col_off : col_off;
    for (r = [0 : slot_rows-1]) {
      y = start_y - r*(slot_h_mm + slot_gap_y_mm);
      translate([x, y + 1.0]) slot_2d();
    }
  }
}

module cupped_shell() {
  // Approximate cup: outer face + extruded wrap rim
  difference() {
    union() {
      // Mild dome face
      minkowski() {
        linear_extrude(height = 0.4)
          offset(r = -1.0) cover_outline_2d();
        sphere(r = face_dome_mm);
      }
      // Wrap-back rim walls
      difference() {
        translate([0, 0, -wrap_depth_mm])
          linear_extrude(height = wrap_depth_mm + face_dome_mm)
            cover_outline_2d();
        translate([0, 0, -wrap_depth_mm - 0.1])
          linear_extrude(height = wrap_depth_mm + face_dome_mm + 0.2)
            offset(r = -wall_mm) cover_outline_2d();
      }
    }
    // Hollow the dome underside
    translate([0, 0, -0.05])
      linear_extrude(height = face_dome_mm * 0.55)
        offset(r = -wall_mm) cover_outline_2d();
    // Tombstone recess
    translate([0, 1.0, face_dome_mm - recess_depth_mm])
      linear_extrude(height = recess_depth_mm + 1)
        offset(r = recess_r_mm)
          square([recess_w_mm - 2*recess_r_mm, recess_h_mm - 2*recess_r_mm], center=true);
    // Slots through
    translate([0, 0, -wrap_depth_mm - 1])
      linear_extrude(height = wrap_depth_mm + face_dome_mm + 4)
        grille_slots_2d();
    // Cable notch (upper-left)
    translate([-width_top_mm*0.38, height_mm*0.38, -wrap_depth_mm - 1])
      cylinder(h = wrap_depth_mm + face_dome_mm + 4, r = 3.2);
  }
  // Hinge peg
  translate([-width_bot_mm/2 + 0.2, peg_y_mm, face_dome_mm*0.2])
    rotate([0, -90, 0])
      cylinder(h = peg_len_mm, r = peg_r_mm);
}

cupped_shell();
