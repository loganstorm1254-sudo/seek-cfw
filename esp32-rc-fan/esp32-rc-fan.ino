/*
 * BOOT toggles fan on one GPIO + GND. No MOSFET.
 * Change kFanPin and re-upload to try another port.
 *
 * Fan + -> the pin below
 * Fan - -> any GND
 *
 * Try these (all can be outputs):
 *   15, 2, 4, 16, 17, 5, 18, 19, 21, 22, 23
 *   13, 14, 27, 26, 25, 33, 32
 *
 * Skip: 0 (BOOT), 34, 35, 36 (VP), 39 (VN) — not usable as outputs
 * Skip: VIN, 3V3 — always on, BOOT cannot switch them
 * Careful: 12 (strapping) — can mess with boot
 *
 * Pairs next to GND on DOIT DevKit V1:
 *   left:  GND + 15
 *   right: GND + 13
 */

static const int kBootPin = 0;
static const int kFanPin = 15; /* change this: 15, 2, 4, 16, 17, 5, 18, 19, 21, 22, 23, 13, 14, 27, 26, 25, 33, 32 */
static const int kLedPin = 2;
static const unsigned long kDebounceMs = 50;

static bool gFanOn = true;
static int gLastReading = HIGH;
static int gLastStable = HIGH;
static unsigned long gLastChangeMs = 0;

static void applyFan(bool on) {
  digitalWrite(kFanPin, on ? HIGH : LOW);
  if (kFanPin != kLedPin) {
    digitalWrite(kLedPin, on ? HIGH : LOW);
  }
}

void setup() {
  pinMode(kBootPin, INPUT_PULLUP);
  pinMode(kFanPin, OUTPUT);
  if (kFanPin != kLedPin) {
    pinMode(kLedPin, OUTPUT);
  }

  Serial.begin(115200);
  gLastReading = digitalRead(kBootPin);
  gLastStable = gLastReading;
  applyFan(true);
  Serial.print("fan pin GPIO");
  Serial.print(kFanPin);
  Serial.println(" ON — press BOOT to toggle");
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
