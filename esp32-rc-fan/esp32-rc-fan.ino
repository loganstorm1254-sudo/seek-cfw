/*
 * BOOT toggles the RC fan.
 *
 * Fan needs 5V from VIN. D15 only flips a MOSFET on/off.
 *
 * Wiring:
 *   Fan +           -> VIN
 *   Fan -           -> MOSFET drain
 *   MOSFET source   -> GND
 *   MOSFET gate     -> D15
 *
 * Use a logic-level N-MOSFET (AO3400, IRLZ44N, IRF520 module).
 * Paste into ESP_NAT.ino. Board: DOIT ESP32 DEVKIT V1.
 * Fan starts OFF. Press BOOT to toggle. LED follows.
 */

static const int kBootPin = 0;
static const int kFanPin = 15; /* MOSFET gate */
static const int kLedPin = 2;
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
