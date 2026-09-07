/*
 * RC-car fan on/off toggle from the ESP32 BOOT button.
 * Single-file sketch — paste this whole file into Arduino IDE
 * (or replace ESP_NAT.ino). No extra headers.
 *
 * Board: DOIT ESP32 DEVKIT V1 (esp32doit-devkit-v1)
 *
 * Wiring (keep the 2-pin plug together — do not split the fan wires):
 *
 * On DOIT DevKit V1 the right header is: VIN, GND, D13, ...
 * You are on VIN + GND. That pair is always 5V and cannot be toggled.
 *
 * Unplug the whole 2-pin connector and shift it one pin so it sits on
 * GND + D13. Fan + must land on D13, fan - on GND. If the fan does not
 * spin, rotate the plug 180 degrees on those same two pins.
 *
 * If you leave it on VIN + GND, the fan stays on whenever USB is plugged
 * in. BOOT cannot switch VIN.
 */

static const int kBootPin = 0; /* onboard BOOT button */
static const int kFanPin = 13; /* D13, next to GND on the VIN header */
static const int kLedPin = 2;  /* onboard LED on DOIT DevKit V1 */
static const unsigned long kDebounceMs = 50;

static bool gFanOn = false;
static int gLastReading = HIGH;
static int gLastStable = HIGH;
static unsigned long gLastChangeMs = 0;

static void applyFan(bool on) {
  digitalWrite(kFanPin, on ? HIGH : LOW);
  digitalWrite(kLedPin, on ? HIGH : LOW);
}

void setup() {
  pinMode(kBootPin, INPUT_PULLUP);
  pinMode(kFanPin, OUTPUT);
  pinMode(kLedPin, OUTPUT);

  Serial.begin(115200);
  gLastReading = digitalRead(kBootPin);
  gLastStable = gLastReading;
  applyFan(false);
  Serial.println("fan off — press BOOT to toggle");
}

void loop() {
  const int reading = digitalRead(kBootPin);
  const unsigned long now = millis();

  if (reading != gLastReading) {
    gLastChangeMs = now;
    gLastReading = reading;
  }
  if ((now - gLastChangeMs) < kDebounceMs) {
    return;
  }
  if (reading == gLastStable) {
    return;
  }

  gLastStable = reading;
  if (gLastStable != LOW) {
    return;
  }

  gFanOn = !gFanOn;
  applyFan(gFanOn);
  Serial.println(gFanOn ? "fan on" : "fan off");
}
