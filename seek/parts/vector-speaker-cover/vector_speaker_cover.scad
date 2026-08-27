// Approximate Anki Vector rear speaker cover (head back grille).
// Dimensions are estimated from photos — print, test-fit, tweak params below.
//
// Print tips:
//  - 0.12–0.16 mm layers, 100% infill, PETG or ABS preferred (PLA is brittle)
//  - Print grille face UP or on a raft; support the side clip if needed
//  - Black filament closest to OEM; sand lightly for snap fit

/* [Size] */
width_mm        = 34.0;   // left–right
height_mm       = 36.0;   // top–bottom
thickness_mm    = 1.4;
dome_bulge_mm   = 2.2;    // outward curve of outer face
edge_radius_mm  = 3.0;

/* [Grille] */
slot_cols       = 2;
slot_rows       = 5;
slot_len_mm     = 5.2;    // horizontal length of each slot
slot_h_mm       = 1.15;
slot_gap_x_mm   = 2.4;    // gap between the two columns
slot_gap_y_mm   = 1.35;   // vertical gap between slots
slot_round_mm   = 0.55;

/* [Recess around grille] */
recess_w_mm     = 14.5;
recess_h_mm     = 18.5;
recess_depth_mm = 0.45;
recess_r_mm     = 3.5;

/* [Side clip] */
clip_enable     = true;
clip_w_mm       = 2.2;
clip_h_mm       = 4.0;
clip_d_mm       = 1.6;
clip_y_mm       = -2.0;   // offset from center toward bottom

$fn = 48;

module rounded_rect_2d(w, h, r) {
  offset(r = r)
    square([w - 2*r, h - 2*r], center = true);
}

module slot_2d() {
  hull() {
    translate([-slot_len_mm/2 + slot_round_mm, 0])
      circle(r = slot_h_mm/2);
    translate([ slot_len_mm/2 - slot_round_mm, 0])
      circle(r = slot_h_mm/2);
  }
}

module grille_slots_2d() {
  total_h = slot_rows * slot_h_mm + (slot_rows - 1) * slot_gap_y_mm;
  start_y = total_h/2 - slot_h_mm/2;
  col_off = slot_len_mm/2 + slot_gap_x_mm/2;
  for (c = [0, 1]) {
    x = (c == 0) ? -col_off : col_off;
    for (r = [0 : slot_rows - 1]) {
      y = start_y - r * (slot_h_mm + slot_gap_y_mm);
      translate([x, y]) slot_2d();
    }
  }
}

module cover_outline_2d() {
  // Slightly wider at bottom (matches photo silhouette)
  hull() {
    translate([0,  height_mm*0.28])
      scale([0.92, 0.55])
        rounded_rect_2d(width_mm, height_mm, edge_radius_mm);
    translate([0, -height_mm*0.18])
      scale([1.0, 0.62])
        rounded_rect_2d(width_mm, height_mm, edge_radius_mm);
  }
}

module domed_plate() {
  // Mild dome via minkowski on a thin plate + sphere slice approximation
  difference() {
    union() {
      linear_extrude(height = thickness_mm, center = false)
        cover_outline_2d();
      // Outer bulge
      translate([0, 0, thickness_mm - 0.2])
        resize([width_mm*0.95, height_mm*0.9, dome_bulge_mm*2])
          intersection() {
            sphere(r = 20);
            translate([0, 0, 20]) cube([50, 50, 40], center = true);
          }
    }
    // Hollow slightly from back for speaker clearance
    translate([0, 0, -0.05])
      linear_extrude(height = thickness_mm * 0.45)
        offset(r = -1.2)
          cover_outline_2d();
  }
}

module recess() {
  translate([0, 0.5, thickness_mm + dome_bulge_mm - recess_depth_mm - 0.1])
    linear_extrude(height = recess_depth_mm + 1.0)
      offset(r = recess_r_mm)
        square([recess_w_mm - 2*recess_r_mm, recess_h_mm - 2*recess_r_mm], center = true);
}

module slots_cut() {
  translate([0, 0.5, -1])
    linear_extrude(height = thickness_mm + dome_bulge_mm + 4)
      grille_slots_2d();
}

module side_clip() {
  if (clip_enable) {
    translate([-width_mm/2 + 0.4, clip_y_mm, thickness_mm * 0.35])
      rotate([0, 90, 0])
        hull() {
          cube([clip_h_mm*0.6, clip_w_mm, 0.2], center = true);
          translate([0, 0, clip_d_mm])
            cube([clip_h_mm, clip_w_mm*0.7, 0.2], center = true);
        }
  }
}

difference() {
  union() {
    domed_plate();
    side_clip();
  }
  recess();
  slots_cut();
}
