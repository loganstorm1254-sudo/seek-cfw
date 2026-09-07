#include "../fan_toggle.h"

#include <stdio.h>
#include <stdlib.h>

static int gFailures = 0;

static void expect(int cond, const char *msg) {
  if (!cond) {
    fprintf(stderr, "FAIL: %s\n", msg);
    gFailures++;
  }
}

int main(void) {
  FanToggle t;
  fan_toggle_init(&t, 1);
  expect(!t.fan_on, "fan starts off");

  /* Bounce on press should not toggle until it stays low. */
  fan_toggle_update(&t, 0, 10);
  fan_toggle_update(&t, 1, 12);
  fan_toggle_update(&t, 0, 14);
  expect(!t.fan_on, "bounce before debounce must not toggle");
  expect(!fan_toggle_update(&t, 0, 14 + 20), "still inside debounce window");
  expect(fan_toggle_update(&t, 0, 14 + FAN_TOGGLE_DEBOUNCE_MS), "stable press toggles on");
  expect(t.fan_on, "fan on after first press");

  /* Holding the button must not retrigger. */
  expect(!fan_toggle_update(&t, 0, 200), "held press does not toggle again");
  expect(t.fan_on, "fan stays on while held");

  /* Release is not a toggle. */
  fan_toggle_update(&t, 1, 210);
  expect(!fan_toggle_update(&t, 1, 210 + FAN_TOGGLE_DEBOUNCE_MS), "release does not toggle");
  expect(t.fan_on, "fan stays on after release");

  /* Second press turns it off. */
  fan_toggle_update(&t, 0, 300);
  expect(fan_toggle_update(&t, 0, 300 + FAN_TOGGLE_DEBOUNCE_MS), "second press toggles off");
  expect(!t.fan_on, "fan off after second press");

  /* Third press turns it on again. */
  fan_toggle_update(&t, 1, 400);
  fan_toggle_update(&t, 1, 400 + FAN_TOGGLE_DEBOUNCE_MS);
  fan_toggle_update(&t, 0, 500);
  expect(fan_toggle_update(&t, 0, 500 + FAN_TOGGLE_DEBOUNCE_MS), "third press toggles on");
  expect(t.fan_on, "fan on after third press");

  if (gFailures) {
    fprintf(stderr, "%d failure(s)\n", gFailures);
    return EXIT_FAILURE;
  }
  puts("ok");
  return EXIT_SUCCESS;
}
