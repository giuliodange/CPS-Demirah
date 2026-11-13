/*
  mirror: ACTUATION. It executes numbers and knows nothing about the person.

  Processing sends a line of text such as "12.5,8.0,255,180,40,-0.25,0.420,0.00":

    x      -> stepper X, rotation of the base, in degrees (0 = centre)
    y      -> stepper Y, tilt of the head, in degrees (0 = all the way down, positive = up)
    r,g,b  -> LED strip: a solid colour, 0 to 255
    c      -> servo, convexity, -1 (concave) to +1 (convex), 0 = flat
    phase  -> 0 to 1: how far the rainbow has turned around the strip
    mix    -> 0 to 1: 0 = only the solid colour, 1 = only the rainbow, in between = a blend

  The sketch has 3 jobs:
    1. Collect characters until a whole line has arrived: readSerial().
    2. Turn the values into targets: handleLine().  <-- the important part
    3. Move the steppers towards their targets: run(), in loop().

  Nothing in loop() is allowed to wait, because each call to run() makes at most
  one step: if the loop stops, the motors stop.

  BEFORE POWERING ON: put the mirror at rest by hand (base centred, head all the way down).
  The position at power-on counts as x = 0, y = 0. If the mirror ever points wrong,
  put it at rest by hand again and press the Arduino's reset button.
*/

#include <AccelStepper.h>
#include <Adafruit_NeoPixel.h>

// ================= 1. CALIBRATE: measured on the real mirror =================
// Find each value with arduino/calibration, following docs/calibration.md.
// Values marked [COPY] must also be written in mirror.pde. At power-on the sketch
// prints them, and Processing shows them in its console, so you can compare.

// Motor steps for one degree of movement. Negative = the motor turns the other way.
const float STEPS_PER_DEG_X = 50;
const float STEPS_PER_DEG_Y = -250;

// Limits in degrees: the motors never go past these, whatever arrives. [COPY]
const float X_MIN_DEG = -80, X_MAX_DEG = 80;
const float Y_MAX_DEG = 30;   // Tilt goes from 0 (down) to this.

// Top speed (steps per second) and acceleration (steps per second, per second).
// Too high and a motor buzzes without moving, or loses steps. Y lifts the head, so it needs
// to be slower: a stepper gets weaker as it speeds up.
// [COPY] as degrees per second: MAX_SPEED_X / STEPS_PER_DEG_X and MAX_SPEED_Y / STEPS_PER_DEG_Y.
const float MAX_SPEED_X = 800, ACCEL_X = 2000;
const float MAX_SPEED_Y = 700, ACCEL_Y = 800;

// Convexity servo. A servo reads the length of a pulse, in microseconds.
const int SERVO_FLAT_US = 1500;   // Pulse that leaves the mirror flat (c = 0).
const int SERVO_RANGE_US = 500;   // Pulse change from flat to the deepest curve (c = +1 or -1). Negative = other direction.

// ================= 2. FIXED: the wiring and the parts =================
const int PIN_X_IN1 = 2, PIN_X_IN2 = 3, PIN_X_IN3 = 4, PIN_X_IN4 = 5;   // Stepper X driver
const int PIN_Y_IN1 = 7, PIN_Y_IN2 = 8, PIN_Y_IN3 = 11, PIN_Y_IN4 = 12; // Stepper Y driver
const int PIN_SERVO = 9;         // Servo signal (orange wire). Must stay D9: see servoBegin().
const int PIN_LEDS = 6;          // LED strip data, through a 330 ohm resistor
const int NUM_LEDS = 75;
const int MAX_BRIGHTNESS = 60;   // 0 to 255. Keeps the LEDs inside the power budget.
const unsigned long X_REST_MS = 2000;  // Stepper X switches its coils off after this long without moving.
// ======================================================================

// IN1, IN3, IN2, IN4 is not a typo: it is the coil order these 4-wire steppers need.
AccelStepper stepperX(AccelStepper::HALF4WIRE, PIN_X_IN1, PIN_X_IN3, PIN_X_IN2, PIN_X_IN4);
AccelStepper stepperY(AccelStepper::HALF4WIRE, PIN_Y_IN1, PIN_Y_IN3, PIN_Y_IN2, PIN_Y_IN4);
Adafruit_NeoPixel strip(NUM_LEDS, PIN_LEDS, NEO_GRB + NEO_KHZ800);  // WS2812 read colours as green, red, blue.

char line[48];       // The line being received.
int lineLength = 0;
unsigned long lastMoveXMs = 0;
int shownRed = -1, shownGreen = -1, shownBlue = -1;  // The solid colour on the strip now. -1 = none.

void setup() {
  Serial.begin(115200);

  stepperX.setMaxSpeed(MAX_SPEED_X);
  stepperX.setAcceleration(ACCEL_X);
  stepperY.setMaxSpeed(MAX_SPEED_Y);
  stepperY.setAcceleration(ACCEL_Y);

  servoBegin(SERVO_FLAT_US);

  strip.begin();
  strip.setBrightness(MAX_BRIGHTNESS);
  strip.show();

  printSettings();
}

void loop() {
  readSerial();
  stepperX.run();
  stepperY.run();

  // The base stays put by friction, so stepper X rests when it has arrived: less heat and power.
  // Its coils come back on by themselves at the next step.
  // Stepper Y never rests: gravity pulls the head down, and it must hold it.
  if (stepperX.distanceToGo() != 0) {
    lastMoveXMs = millis();
  } else if (millis() - lastMoveXMs > X_REST_MS) {
    stepperX.disableOutputs();
  }
}

// 1. Take the characters that have already arrived, without waiting for the others.
void readSerial() {
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\n') {
      line[lineLength] = '\0';
      handleLine();
      lineLength = 0;
    } else if (c != '\r' && lineLength < (int)sizeof(line) - 1) {
      line[lineLength] = c;
      lineLength++;
    }
  }
}

// 2. THE IMPORTANT PART: each value of the line goes to its part of the mirror.
void handleLine() {
  if (strcmp(line, "?") == 0) {  // Processing asks for the settings when it connects.
    printSettings();
    return;
  }
  float values[8];
  if (!parseLine(values, 8)) {
    Serial.println("line discarded");
    return;
  }

  // Rotation and tilt: degrees, kept inside the limits, then turned into steps.
  stepperX.moveTo(constrain(values[0], X_MIN_DEG, X_MAX_DEG) * STEPS_PER_DEG_X);
  stepperY.moveTo(constrain(values[1], 0, Y_MAX_DEG) * STEPS_PER_DEG_Y);

  // Convexity: -1..+1 becomes a pulse length around "flat".
  servoWrite(SERVO_FLAT_US + constrain(values[5], -1, 1) * SERVO_RANGE_US);

  showLeds(constrain(values[2], 0, 255), constrain(values[3], 0, 255), constrain(values[4], 0, 255),
           values[6], constrain(values[7], 0, 1));
}

// Split the line at the commas. A valid line has only number characters and exactly
// `expected` values. The first line after connecting is often cut, and this catches that.
bool parseLine(float* values, int expected) {
  if (strspn(line, "0123456789+-.,") != strlen(line)) {
    return false;
  }
  int count = 0;
  for (char* part = strtok(line, ","); part != NULL; part = strtok(NULL, ",")) {
    if (count == expected) {
      return false;
    }
    values[count] = atof(part);
    count++;
  }
  return count == expected;
}

// The LEDs: a solid colour, a rainbow around the ring, or a blend of the two (mix).
// strip.show() stops everything else for about 2 ms, so a solid colour that is already
// on the strip is not sent again.
void showLeds(int red, int green, int blue, float phase, float mix) {
  if (mix == 0 && red == shownRed && green == shownGreen && blue == shownBlue) {
    return;
  }
  for (int i = 0; i < NUM_LEDS; i++) {
    // Each LED's rainbow colour comes from its place along the strip, plus the turn so far.
    // Hues go from 0 to 65535, and gamma32() makes the colours look even to the eye.
    float hue = fmod((float)i / NUM_LEDS + phase, 1.0);
    uint32_t rainbow = strip.gamma32(strip.ColorHSV((uint16_t)(hue * 65535)));
    // A colour is packed as 0xRRGGBB: shifting and masking takes each part out.
    strip.setPixelColor(i, blend(red, (rainbow >> 16) & 0xFF, mix),
                           blend(green, (rainbow >> 8) & 0xFF, mix),
                           blend(blue, rainbow & 0xFF, mix));
  }
  strip.show();
  // Remember a solid colour. While the rainbow is mixed in, the strip changes at every line.
  shownRed = mix == 0 ? red : -1;
  shownGreen = green;
  shownBlue = blue;
}

// A value between `solid` (mix = 0) and `rainbow` (mix = 1).
int blend(int solid, int rainbow, float mix) {
  return solid + (rainbow - solid) * mix;
}

// The servo pulse is made in hardware by the timer TCA0, not by the Servo library.
// The Servo library ends each pulse with an interrupt. strip.show() switches interrupts off for
// about 2 ms, so some pulses came out longer and the servo twitched during the idle rainbow.
// TCA0 drives D9 by itself, so the pulse stays exact whatever the code is doing.
// TCA0 already counts one tick every 4 microseconds (16 MHz / 64), and millis() relies on that,
// so only the period changes: 5000 ticks = 20 ms, one pulse every 20 ms as servos expect.
// Side effect: analogWrite() on D5 and D10 would also run at 50 Hz. This sketch does not use it.
void servoBegin(int pulseUs) {
  pinMode(PIN_SERVO, OUTPUT);
  TCA0.SINGLE.PER = 5000 - 1;                 // Counts 0..4999, then starts the next pulse.
  servoWrite(pulseUs);
  TCA0.SINGLE.CTRLB |= TCA_SINGLE_CMP0EN_bm;  // Connect the timer to D9 (pin PB0 of the chip).
}

// The output stays high until the count reaches pulseUs / 4. The new length starts with the
// next pulse (the "BUF" register), never halfway through one.
void servoWrite(int pulseUs) {
  TCA0.SINGLE.CMP0BUF = pulseUs / 4;
}

// Print the values that mirror.pde must repeat. Processing asks for them with "?" when it
// connects, and shows this line in its console.
void printSettings() {
  Serial.print("mirror ready. Copy to mirror.pde: X_MIN_DEG = ");
  Serial.print(X_MIN_DEG, 0);
  Serial.print(", X_MAX_DEG = ");
  Serial.print(X_MAX_DEG, 0);
  Serial.print(", Y_MAX_DEG = ");
  Serial.print(Y_MAX_DEG, 0);
  Serial.print(", X_MAX_DEG_PER_S = ");
  Serial.print(MAX_SPEED_X / fabs(STEPS_PER_DEG_X), 1);
  Serial.print(", Y_MAX_DEG_PER_S = ");
  Serial.println(MAX_SPEED_Y / fabs(STEPS_PER_DEG_Y), 1);
}
