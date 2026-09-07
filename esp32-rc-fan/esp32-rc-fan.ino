/*
 * RC-car fan on/off from BOOT. Two ESP32 pins only. No MOSFET.
 *
 *   Fan +  -> D15
 *   Fan -  -> GND
 *
 * Paste into ESP_NAT.ino. Board: DOIT ESP32 DEVKIT V1.
 * Fan starts ON so you can see if it spins. Press BOOT to toggle.
 */

static const int kBootPin = 0;
static const int kFanPin = 15;
static const int kLedPin = 2;
static const unsigned long kDebounceMs = 50;

static bool gFanOn = true;
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
  applyFan(true);
  Serial.println("fan on — press BOOT to toggle");
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
