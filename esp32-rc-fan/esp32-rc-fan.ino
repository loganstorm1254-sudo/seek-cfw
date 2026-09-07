/*
 * RC-car fan on/off toggle from the ESP32 BOOT button.
 *
 * Wiring (ESP32 DevKit):
 *   Fan black  -> GND  (keep this)
 *   Fan red    -> D32 (GPIO32)
 *
 * VN (GPIO39) is input-only and cannot drive a fan. Move the red wire
 * two output-capable pins up from VN: skip 34 and 35, land on D32.
 *
 * If the fan is 5V or the board resets when it starts, use a MOSFET:
 *   Fan red -> VIN (5V)
 *   Fan black -> MOSFET drain
 *   MOSFET source -> GND
 *   MOSFET gate -> D32
 *
 * Flash with Arduino IDE: ESP32 Dev Module, upload, then press BOOT
 * to toggle. Onboard LED (GPIO2) follows the fan.
 */

#include "fan_toggle.h"

static const int kBootPin = 0; /* onboard BOOT button */
static const int kFanPin = 32; /* D32 — not VN */
static const int kLedPin = 2;  /* onboard LED on most DevKit boards */

static FanToggle gToggle;

static void applyFan(bool on) {
  digitalWrite(kFanPin, on ? HIGH : LOW);
  digitalWrite(kLedPin, on ? HIGH : LOW);
}

void setup() {
  pinMode(kBootPin, INPUT_PULLUP);
  pinMode(kFanPin, OUTPUT);
  pinMode(kLedPin, OUTPUT);

  Serial.begin(115200);
  fan_toggle_init(&gToggle, digitalRead(kBootPin));
  applyFan(false);
  Serial.println("fan off — press BOOT to toggle");
}

void loop() {
  const int reading = digitalRead(kBootPin);
  if (fan_toggle_update(&gToggle, reading, millis())) {
    applyFan(gToggle.fan_on);
    Serial.println(gToggle.fan_on ? "fan on" : "fan off");
  }
}
