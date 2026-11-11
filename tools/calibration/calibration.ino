/*
  calibration: test the hardware by hand from the Serial Monitor, without Processing.
  Use it to find the values marked TODO CALIBRATE in mirror.ino. The README explains
  the procedure, step by step.

  Serial Monitor: 115200 baud, line ending "Newline". Type a letter, then any numbers.

    x 100       move stepper X (rotation) by 100 steps (negative = other way)
    y 100       move stepper Y (tilt) by 100 steps (positive should lift the head, negative = other way)
    p           print the current positions
    z           call the current positions 0
    s 1500      send the convexity servo a 1500 microsecond pulse (about 1000 to 2000)
    l 255 0 0   set all LEDs to red, green, blue (l 0 0 0 = off)
    d           switch the stepper coils off, until the next move
    v 700       set the top speed of both steppers, in steps per second (start: 300)

  CAREFUL: this sketch has NO limits. Start with small moves (100 steps, or 50
  microseconds on the servo), so nothing hits an end stop or twists the cables.
*/

#include <AccelStepper.h>
#include <Adafruit_NeoPixel.h>

// ============================== CONFIG ==============================
const int PIN_X_IN1 = 2, PIN_X_IN2 = 3, PIN_X_IN3 = 4, PIN_X_IN4 = 5;   // Stepper X driver: rotation
const int PIN_Y_IN1 = 7, PIN_Y_IN2 = 8, PIN_Y_IN3 = 11, PIN_Y_IN4 = 12; // Stepper Y driver: tilt
const int PIN_SERVO = 9;           // Servo signal: convexity. Must stay D9 (see servoBegin())
const int PIN_LEDS = 6;            // LED strip data
const float TEST_SPEED = 300;      // Steps per second. Slow on purpose.
const float TEST_ACCEL = 300;      // Steps per second, per second.
const int NUM_LEDS = 75;            // Number of LEDs. Set it to your strip.
const int MAX_BRIGHTNESS = 60;     // 0 to 255. Keeps the LEDs inside the power budget.
// ====================================================================

// IN1, IN3, IN2, IN4 is the coil order the 28BYJ-48 needs.
AccelStepper stepperX(AccelStepper::HALF4WIRE, PIN_X_IN1, PIN_X_IN3, PIN_X_IN2, PIN_X_IN4);
AccelStepper stepperY(AccelStepper::HALF4WIRE, PIN_Y_IN1, PIN_Y_IN3, PIN_Y_IN2, PIN_Y_IN4);
Adafruit_NeoPixel strip(NUM_LEDS, PIN_LEDS, NEO_GRB + NEO_KHZ800);

void setup() {
  Serial.begin(115200);
  stepperX.setMaxSpeed(TEST_SPEED);
  stepperX.setAcceleration(TEST_ACCEL);
  stepperY.setMaxSpeed(TEST_SPEED);
  stepperY.setAcceleration(TEST_ACCEL);
  servoBegin(1500);
  strip.begin();
  strip.setBrightness(MAX_BRIGHTNESS);
  strip.show();
  Serial.println("calibration ready");
}

void loop() {
  // Serial.parseInt() is the simple way to read numbers. It waits a moment,
  // which mirror.ino must never do, but here nobody is in a hurry.
  if (Serial.available() > 0) {
    char command = Serial.read();

    if (command == 'x') {
      stepperX.move(Serial.parseInt());
    } else if (command == 'y') {
      stepperY.move(Serial.parseInt());
    } else if (command == 'z') {
      stepperX.setCurrentPosition(0);
      stepperY.setCurrentPosition(0);
      Serial.println("x and y at position 0");
    } else if (command == 's') {
      int pulseUs = Serial.parseInt();
      servoWrite(pulseUs);
      Serial.print("Servo: ");
      Serial.print(pulseUs);
      Serial.println(" us");
    } else if (command == 'l') {
      int red = Serial.parseInt();
      int green = Serial.parseInt();
      int blue = Serial.parseInt();
      for (int i = 0; i < NUM_LEDS; i++) {
        strip.setPixelColor(i, red, green, blue);
      }
      strip.show();
    } else if (command == 'v') {
      int speed = Serial.parseInt();
      stepperX.setMaxSpeed(speed);
      stepperY.setMaxSpeed(speed);
      Serial.print("Top speed: ");
      Serial.print(speed);
      Serial.println(" steps/s");
    } else if (command == 'd') {
      stepperX.disableOutputs();
      stepperY.disableOutputs();
    } else if (command == 'p') {
      Serial.print("X: ");
      Serial.print(stepperX.currentPosition());
      Serial.print(" steps, Y: ");
      Serial.print(stepperY.currentPosition());
      Serial.println(" steps");
    }
  }

  stepperX.run();
  stepperY.run();
}

// The same servo pulse as mirror.ino (see the comment there), so calibrated values carry over:
// the timer TCA0 makes it in hardware on D9, one pulse every 20 ms, 4 microseconds per tick.
void servoBegin(int pulseUs) {
  pinMode(PIN_SERVO, OUTPUT);
  TCA0.SINGLE.PER = 5000 - 1;
  servoWrite(pulseUs);
  TCA0.SINGLE.CTRLB |= TCA_SINGLE_CMP0EN_bm;
}

void servoWrite(int pulseUs) {
  TCA0.SINGLE.CMP0BUF = pulseUs / 4;
}
