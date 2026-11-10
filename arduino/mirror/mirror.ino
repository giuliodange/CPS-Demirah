/*
  mirror: ACTUATION. It executes numbers and knows nothing about the person.

  Processing sends a line of text such as "12.5,-3.0,255,180,40,-0.25,0.420,0.00":

    x      -> stepper X, rotation of the base, in degrees
    y      -> stepper Y, tilt of the mirror, in degrees: 0 = all the way down (rest), positive = up
    r,g,b  -> LED strip: a solid colour, 0 to 255
    c      -> servo, convexity, -1 (concave) to +1 (convex)
    phase  -> 0 to 1: how far a rainbow around the strip has turned (Processing makes it turn)
    mix    -> 0 to 1: 0 = only the solid colour, 1 = only the rainbow, in between = a blend.
              Processing changes it slowly, so the lights fade from one to the other.

  The sketch has only 3 jobs:
    1. Collect characters until a whole line has arrived: readSerial().
    2. Turn the values into targets: handleLine().  <-- the important part
    3. Move the steppers towards their targets: run(), in loop().
       The servo needs nothing in loop(): a hardware timer repeats its pulse by itself.

  Nothing in loop() is allowed to wait, because each call to run() makes at most
  one step: if the loop stops, the motors stop.

  BEFORE POWERING ON: put the mirror at rest by hand (base centred, head all the way down).
  The startup position of each stepper counts as 0. The servo goes straight to "flat".
*/

#include <AccelStepper.h>
#include <Adafruit_NeoPixel.h>

// ============================== CONFIG ==============================
// --- Pins ---
const int PIN_X_IN1 = 2, PIN_X_IN2 = 3, PIN_X_IN3 = 4, PIN_X_IN4 = 5;  // Stepper X driver: rotation
const int PIN_Y_IN1 = 7, PIN_Y_IN2 = 8, PIN_Y_IN3 = 11, PIN_Y_IN4 = 12; // Stepper Y driver: tilt
const int PIN_SERVO = 9;                                                // Servo signal (orange wire): convexity. Must stay D9 (see servoBegin())
const int PIN_LEDS = 6;                                                 // LED strip data, through a 330 ohm resistor

// --- Degrees to steps. The motor alone needs 4096 half-steps per turn: 4096 / 360 = 11.38 ---
const float STEPS_PER_DEG_X = 30;     // Steps per degree of rotation. TODO CALIBRATE (docs/calibration.md, step 2). Negative = opposite direction.
const float STEPS_PER_DEG_Y = 11.38;  // Steps per degree of tilt. TODO CALIBRATE (docs/calibration.md, step 2). Negative = opposite direction.

// --- Safety limits: never past these, whatever arrives. Keep them the same as in mirror.pde ---
const float X_MIN_DEG = -100, X_MAX_DEG = 100;// Degrees. TODO CALIBRATE
const float Y_MIN_DEG = 0, Y_MAX_DEG = 30;    // Degrees. 0 = head at rest, all the way down. Y_MAX_DEG: TODO CALIBRATE

// --- Stepper motion: higher = more reactive, but too high and the motor skips steps ---
const float MAX_SPEED = 800;   // Steps per second. The 28BYJ-48 reaches at most about 1024. TODO CALIBRATE (docs/calibration.md, step 5)
const float ACCEL = 2000;      // Steps per second, per second. TODO CALIBRATE (docs/calibration.md, step 5)

// --- Saving power ---
const unsigned long IDLE_DISABLE_MS = 2000;  // Milliseconds stopped before the coils switch off.
const bool KEEP_Y_POWERED = false;           // true = Y coils always on. TODO CALIBRATE: set it if the mirror sinks when they are off.

// --- Convexity servo. A servo reads a pulse length: about 1500 microseconds is its centre ---
const int SERVO_FLAT_US = 1500;      // Pulse for a flat mirror (c = 0). TODO CALIBRATE
const int SERVO_RANGE_US = 500;      // Pulse change from flat to c = +1 or -1. TODO CALIBRATE. Negative = opposite direction.
const int SERVO_DEAD_BAND_US = 10;   // Ignore changes smaller than this, so the servo never trembles.

// --- LEDs ---
const int NUM_LEDS = 75;         // Number of LEDs. TODO CALIBRATE: set it to the final strip.
const int MAX_BRIGHTNESS = 60;   // 0 to 255. Keeps the LEDs inside the power budget.
const int LED_CHANGE_MIN = 3;    // A solid colour is redrawn only when a channel changes by this much (see showSolid()).
// ====================================================================

// IN1, IN3, IN2, IN4 is not a typo: it is the coil order these 4-wire unipolar steppers need.
AccelStepper stepperX(AccelStepper::HALF4WIRE, PIN_X_IN1, PIN_X_IN3, PIN_X_IN2, PIN_X_IN4);
AccelStepper stepperY(AccelStepper::HALF4WIRE, PIN_Y_IN1, PIN_Y_IN3, PIN_Y_IN2, PIN_Y_IN4);
Adafruit_NeoPixel strip(NUM_LEDS, PIN_LEDS, NEO_GRB + NEO_KHZ800);  // WS2812 read colours as green, red, blue.

char line[48];       // The line being received.
int lineLength = 0;

int servoUs = SERVO_FLAT_US;
int ledRed = -1, ledGreen = -1, ledBlue = -1;   // The solid colour on the strip. -1 = nothing shown yet.

bool coilsOnX = true, coilsOnY = true;
unsigned long lastMoveX = 0, lastMoveY = 0;

void setup() {
  Serial.begin(115200);

  stepperX.setMaxSpeed(MAX_SPEED);
  stepperX.setAcceleration(ACCEL);
  stepperY.setMaxSpeed(MAX_SPEED);
  stepperY.setAcceleration(ACCEL);

  servoBegin(servoUs);

  strip.begin();
  strip.setBrightness(MAX_BRIGHTNESS);
  strip.show();

  Serial.println("mirror ready");
}

void loop() {
  readSerial();

  manageCoils(stepperX, coilsOnX, lastMoveX);
  if (!KEEP_Y_POWERED) {
    manageCoils(stepperY, coilsOnY, lastMoveY);
  }
  stepperX.run();
  stepperY.run();
}

// Take the characters that have already arrived, without waiting for the others.
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

// THE IMPORTANT PART: each value of the line goes to its part.
void handleLine() {
  float values[8];
  if (!parseLine(values, 8)) {
    Serial.println("line discarded");
    return;
  }

  // Rotation and tilt: degrees -> steps.
  stepperX.moveTo(constrain(values[0], X_MIN_DEG, X_MAX_DEG) * STEPS_PER_DEG_X);
  stepperY.moveTo(constrain(values[1], Y_MIN_DEG, Y_MAX_DEG) * STEPS_PER_DEG_Y);

  // Convexity: -1..+1 -> a pulse length around "flat". Tiny changes are ignored.
  int newServoUs = SERVO_FLAT_US + constrain(values[5], -1, 1) * SERVO_RANGE_US;
  if (abs(newServoUs - servoUs) >= SERVO_DEAD_BAND_US) {
    servoUs = newServoUs;
    servoWrite(servoUs);
  }

  // LEDs. Drawing them here, right after a line, is on purpose: strip.show() switches interrupts
  // off for a moment (about 30 microseconds per LED), and now no characters are arriving.
  int red = constrain(values[2], 0, 255), green = constrain(values[3], 0, 255), blue = constrain(values[4], 0, 255);
  float mix = constrain(values[7], 0, 1);
  if (mix > 0) {
    showRainbow(red, green, blue, values[6], mix);
  } else {
    showSolid(red, green, blue);
  }
}

// One solid colour on every LED. It is redrawn only when the colour has really changed.
void showSolid(int red, int green, int blue) {
  if (abs(red - ledRed) < LED_CHANGE_MIN && abs(green - ledGreen) < LED_CHANGE_MIN && abs(blue - ledBlue) < LED_CHANGE_MIN) {
    return;
  }
  ledRed = red;
  ledGreen = green;
  ledBlue = blue;
  for (int i = 0; i < NUM_LEDS; i++) {
    strip.setPixelColor(i, red, green, blue);
  }
  strip.show();
}

// A rainbow around the strip, blended with the solid colour by `mix`.
// Each LED gets a hue by its place along the strip, plus the turn. Hues go from 0 to 65535 in the
// NeoPixel library, and gamma32() makes the colours look even to the eye.
void showRainbow(int red, int green, int blue, float turn, float mix) {
  for (int i = 0; i < NUM_LEDS; i++) {
    float hue = fmod((float)i / NUM_LEDS + turn, 1.0);  // fmod keeps it between 0 and 1.
    uint32_t rainbow = strip.gamma32(strip.ColorHSV((uint16_t)(hue * 65535)));
    // A colour is packed as 0xRRGGBB: shifting and masking takes each part out.
    int r = red + (((rainbow >> 16) & 0xFF) - red) * mix;
    int g = green + (((rainbow >> 8) & 0xFF) - green) * mix;
    int b = blue + ((rainbow & 0xFF) - blue) * mix;
    strip.setPixelColor(i, r, g, b);
  }
  strip.show();
  ledRed = -1;  // The solid colour was mixed away, so the next one must be redrawn.
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

// Switch the coils off after a while without moving: it saves power and heat, and the gearbox
// holds the position. They come back on by themselves with the motor's next step.
void manageCoils(AccelStepper& motor, bool& coilsOn, unsigned long& lastMove) {
  if (motor.distanceToGo() != 0) {
    coilsOn = true;
    lastMove = millis();
  } else if (coilsOn && millis() - lastMove > IDLE_DISABLE_MS) {
    motor.disableOutputs();
    coilsOn = false;
  }
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
