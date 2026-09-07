/*
 * RC-car fan on/off toggle from the ESP32 BOOT button.
 * Single-file sketch — paste this whole file into Arduino IDE
 * (or replace ESP_NAT.ino). No extra headers.
 *
 * Board: DOIT ESP32 DEVKIT V1 (esp32doit-devkit-v1)
 *
 * Wiring:
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
 */

static const int kBootPin = 0; /* onboard BOOT button */
static const int kFanPin = 32; /* D32 — not VN */
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
