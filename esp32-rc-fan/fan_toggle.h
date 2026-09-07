#ifndef FAN_TOGGLE_H
#define FAN_TOGGLE_H

#include <stdbool.h>
#include <stdint.h>

/* BOOT is active-low: 0 = pressed, 1 = released. */
#define FAN_TOGGLE_DEBOUNCE_MS 50u

typedef struct {
  bool fan_on;
  int last_reading;
  int last_stable;
  uint32_t last_change_ms;
} FanToggle;

static inline void fan_toggle_init(FanToggle *t, int initial_reading) {
  t->fan_on = false;
  t->last_reading = initial_reading;
  t->last_stable = initial_reading;
  t->last_change_ms = 0;
}

/* Returns true when fan_on flipped (rising press after debounce). */
static inline bool fan_toggle_update(FanToggle *t, int reading, uint32_t now_ms) {
  if (reading != t->last_reading) {
    t->last_change_ms = now_ms;
    t->last_reading = reading;
  }
  if ((now_ms - t->last_change_ms) < FAN_TOGGLE_DEBOUNCE_MS) {
    return false;
  }
  if (reading != t->last_stable) {
    t->last_stable = reading;
    if (t->last_stable == 0) {
      t->fan_on = !t->fan_on;
      return true;
    }
  }
  return false;
}

#endif
