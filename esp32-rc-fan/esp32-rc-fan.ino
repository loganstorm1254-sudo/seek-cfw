/*
 * BOOT button toggle for DOIT ESP32 DEVKIT V1.
 *
 * The fan stays on VIN + GND. Those are the 5V supply pins, not a GPIO,
 * so this sketch cannot turn the fan off. BOOT only toggles the onboard
 * LED so you can confirm the button works.
 *
 * Single-file sketch — paste into ESP_NAT.ino. No extra headers.
 */

static const int kBootPin = 0;
static const int kLedPin = 2;
static const unsigned long kDebounceMs = 50;

static bool gLedOn = false;
static int gLastReading = HIGH;
static int gLastStable = HIGH;
static unsigned long gLastChangeMs = 0;

void setup() {
  pinMode(kBootPin, INPUT_PULLUP);
  pinMode(kLedPin, OUTPUT);
  digitalWrite(kLedPin, LOW);

  Serial.begin(115200);
  gLastReading = digitalRead(kBootPin);
  gLastStable = gLastReading;
  Serial.println("BOOT toggles the LED only");
  Serial.println("fan on VIN/GND cannot be switched in software");
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

  gLedOn = !gLedOn;
  digitalWrite(kLedPin, gLedOn ? HIGH : LOW);
  Serial.println(gLedOn ? "led on" : "led off");
}
