/*
 * RC-car fan on/off toggle from the ESP32 BOOT button.
 * Single-file sketch — paste this whole file into Arduino IDE
 * (or replace ESP_NAT.ino). No extra headers.
 *
 * Board: DOIT ESP32 DEVKIT V1 (esp32doit-devkit-v1)
 *
 * D15 cannot power the fan. A GPIO is 3.3V and only a few mA; an RC
 * fan needs 5V from VIN. BOOT drives D15, D15 drives a MOSFET, the
 * MOSFET switches the fan.
 *
 * Fan 2-pin plug stays together:
 *   Fan +  -> VIN
 *   Fan -  -> MOSFET drain (center/left pin on a typical N-MOSFET)
 *
 * MOSFET:
 *   drain  -> fan -
 *   source -> GND
 *   gate   -> D15
 *
 * Logic-level N-MOSFET (AO3400, IRLZ44N, or a cheap IRF520 module).
 * Do not wire the fan between VIN and D15 — that will kill the pin.
 *
 * Fan starts OFF. Press BOOT. Onboard LED on = MOSFET/fan on.
 */

static const int kBootPin = 0;
static const int kFanPin = 15; /* MOSFET gate, not fan power */
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
  Serial.println("LED on means D15 HIGH (MOSFET/fan on)");
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
