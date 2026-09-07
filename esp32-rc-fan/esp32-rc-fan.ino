/*
 * RC-car fan on/off toggle from the ESP32 BOOT button.
 * Single-file sketch — paste this whole file into Arduino IDE
 * (or replace ESP_NAT.ino). No extra headers.
 *
 * Board: DOIT ESP32 DEVKIT V1 (esp32doit-devkit-v1)
 *
 * Fan plug (keep the 2-pin connector together):
 *   Fan +  -> D15
 *   Fan -  -> GND
 *
 * Left header, other side from VIN: 3V3, GND, D15.
 * Plug into GND + D15. Do not use 3V3, VIN, or VN.
 *
 * If the fan does not spin, rotate the plug 180 degrees on D15+GND.
 */

static const int kBootPin = 0; /* onboard BOOT button */
static const int kFanPin = 15; /* D15 */
static const int kLedPin = 2;  /* onboard LED */
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
