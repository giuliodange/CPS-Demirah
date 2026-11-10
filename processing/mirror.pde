/*
  mirror: BEHAVIOUR. It decides what the mirror does. Change the experience here:
  the Arduino does not need re-uploading.

  The mirror has 5 states, and moves between them by itself:

    idle      nobody there: it rests, the curve pulses in and out, a rainbow turns around the LEDs
       | a face appears
    greeting  a happy celebration: the head draws a circle, the LEDs fade to HAPPY_COLOR
       | the celebration ends
    tracking  it follows the face (closed loop). The colour shows the emotion from Wekinator:
              neutral, happy, sad, angry, or a wink (green, and the head nods a little).
              The curve keeps the face at the same zoom.
       | a second face appears (if TWO_PEOPLE)          ^ only one face again
    shy       embarrassed: it looks at the two faces in turn, the curve pulses, the LEDs turn pink
       | no face for NO_FACE_TIMEOUT_S (from tracking or shy)
    sad       it slowly looks down, the LEDs turn SAD_COLOR and fade to dark, then back to idle
              (if a face comes back while sad, it celebrates again)

  Every change of colour and shape is smoothed, so moving from one state to the next never jumps.

  draw() is the whole program, 60 times per second:
    1. Input:  readInput() gets the faces from the camera, or from the mouse.
    2. Decide: updateState() picks the state, then updateMotion(), updateLights() and
               updateConvexity() decide what the mirror does in that state.  <-- the important part
    3. Send:   sendToArduino() writes everything as one line of text.
    4. Show:   the 3D drawing and the text, in the "twin" tab. You can ignore that tab
               to understand the logic.

  Needs the oscP5 library (Sketch > Import Library > Manage Libraries).
*/

import oscP5.*;
import processing.serial.*;

// ============================== CONFIG ==============================
// --- Modes ---
final boolean SIMULATION_ONLY = false; // true = no serial port, everything happens on screen.
final String INPUT = "laptop camera";  // Where the faces come from:
                                       //   "mirror camera" = the ESP32-CAM on the mirror (start "Avvia camera specchio")
                                       //   "laptop camera" = the computer's camera, for testing (start "Avvia webcam computer")
                                       //   "mouse"         = no camera. Mouse = face, wheel = size, p = present,
                                       //                     t = a second person (mirrored), 1-5 = emotion (neutral, happy, sad, angry, wink)
final boolean INVERT_X = false;         // Flip if the mirror turns AWAY from the face and runs to a limit (docs/calibration.md, step 3).
final boolean INVERT_Y = false;        // Same, for the tilt.

// --- Rotation and tilt: tuned to be reactive ---
final float CAMERA_HFOV_DEG = 55;      // Degrees the camera on the mirror sees across its width. TODO CALIBRATE (docs/calibration.md, step 4)
final float CAMERA_VFOV_DEG = 42;      // Degrees it sees across its height. TODO CALIBRATE (docs/calibration.md, step 4)
final float CLOSED_LOOP_GAIN = 0.5;    // 0 to 1. Share of the face's offset corrected at each camera frame. Too high = it wobbles. (docs/calibration.md, step 5)
final float DEAD_ZONE_DEG = 2;         // Degrees. A face this close to the centre counts as centred. (docs/calibration.md, step 5)
final float XY_SMOOTHING = 0.3;        // 0 to 1. Fraction of the remaining distance covered each frame: higher = more reactive. (docs/calibration.md, step 5)
final float X_MIN_DEG = -100;          // Degrees. TODO CALIBRATE: keep the same as in mirror.ino.
final float X_MAX_DEG = 100;           // Degrees. TODO CALIBRATE
final float Y_MIN_DEG = 0;             // Degrees. 0 = the head at rest, all the way down (cord slack). Keep it 0.
final float Y_MAX_DEG = 30;            // Degrees. Highest tilt the cord can pull the head to. TODO CALIBRATE: keep the same as in mirror.ino.
final float Y_LEVEL_DEG = 15;          // Degrees. The tilt where the mirror looks straight ahead: idle rests here. TODO CALIBRATE (docs/calibration.md, step 2)

// --- States ---
final float NO_FACE_TIMEOUT_S = 3;     // Seconds without a face before it gets sad.
final float GREETING_S = 2;            // Seconds the celebration lasts.
final float GREETING_TURNS = 1;        // How many happy circles the head draws in that time.
final float GREETING_RADIUS_DEG = 10;  // Degrees. Size of the happy circles.
final float SHY_SWITCH_S = 2.5;        // Seconds it looks at one face before turning to the other.
final float SHY_EXIT_S = 4;            // Seconds with only one face before it stops being shy. Keep it above SHY_SWITCH_S.
final float SAD_S = 2;                 // Seconds it stays sad before going idle. Its blue fades to dark over this time.
final float SAD_TILT_DEG = 0;          // Degrees. Where it looks when sad: 0 = all the way down.
final float GENTLE_SMOOTHING = 0.04;   // 0 to 1. Like XY_SMOOTHING, but slower: used when getting sad and going back to idle.
final float WINK_NOD_DEG = 3;          // Degrees. How far the head nods up and down after a wink: very little.
final float WINK_NOD_PERIOD_S = 0.8;   // Seconds for one nod.
final float EMOTION_HOLD_S = 0.3;      // Seconds Wekinator must say the same emotion before it shows, so it does not flicker.
final boolean TWO_PEOPLE = true;       // false = ignore a second face: no shy state.
final float PULSE_PERIOD_S = 4;        // Seconds for one in-and-out pulse of the curve (idle and shy).
final float PULSE_AMOUNT = 0.6;        // 0 to 1. How far the pulse goes, both convex and concave.
final float PULSE_FADE_IN_S = 3;       // Seconds for the pulse to grow from nothing, so it starts smoothly.
final float RAINBOW_TURNS_PER_S = 0.2; // How fast the idle rainbow turns around the ring.

// --- Lights ---
final color NEUTRAL_COLOR = #FFE0B0;   // Emotion "neutral".
final color HAPPY_COLOR = #FFA000;     // Emotion "happy", and when greeting.
final color SAD_COLOR = #2040FF;       // Emotion "sad", and when sad.
final color ANGRY_COLOR = #FF0000;     // Emotion "angry".
final color WINK_COLOR = #00FF40;      // Emotion "wink".
final color SHY_COLOR = #FF6FA8;       // Two people: embarrassed pink.
final float LIGHT_SMOOTHING = 0.03;    // 0 to 1. Lower = slower, smoother fades between colours and to and from the rainbow.

// --- Convexity: tuned to be calm, never trembling ---
final float DISTANCE_CALIB_K = 0.2;    // TODO CALIBRATE (docs/calibration.md, step 6): stand exactly 1 m from the camera and write here the "size" on screen.
final float ZOOM = 3;                  // Magnification to keep, above 1. Higher = closer to the focus, so the image gets less sharp.
final float MAX_SAG_MM = 30;           // Millimetres. Deepest curve the mirror can make (convexity -1 or +1). TODO CALIBRATE (docs/calibration.md, step 6)
final float SIZE_SMOOTHING = 0.05;     // 0 to 1. Smooths the face size first: it is the noisiest number.
final float CONVEXITY_DEAD_ZONE = 0.05; // Changes of convexity smaller than this are ignored while tracking.
final float CONVEXITY_SMOOTHING = 0.03; // 0 to 1. Lower = slower and calmer changes of shape.

// --- Connections ---
final int OSC_PORT = 12000;            // UDP port to listen on. Must match PROCESSING_PORT in face_tracker.py.
final String SERIAL_PORT_NAME = "/dev/cu.usbmodem1101";  // The Arduino's port, from the list printed in the console.
final int SEND_RATE_HZ = 30;           // Maximum messages per second to the Arduino.
// ====================================================================

// What we receive. Face 1 is the largest (closest) face, face 2 the second one.
boolean present = true, present2 = false;  // In "mouse" mode, p and t switch them.
float faceX = 0.5, faceY = 0.5, size = 0.2;  // Face 1 in the camera image, 0 to 1.
float face2X = 0.5, face2Y = 0.5;          // Face 2 in the camera image.
int lastFaceMs = -100000, lastFace2Ms = -100000;  // When we last saw each one. Long ago, so it starts idle.
boolean newFace = false;                   // A new camera frame has arrived since the last draw().
// Wekinator is a classifier with 5 classes, numbered from 1 in this order.
final String[] EMOTIONS = {"neutral", "happy", "sad", "angry", "wink"};
String heardEmotion = "neutral";           // What Wekinator says right now.
int heardSinceMs = 0;                      // Since when it has said it.

// What we decide
String state = "idle";                     // "idle", "greeting", "tracking", "shy" or "sad".
int stateStartMs = 0;                      // When the current state began.
float cx = 0.5, cy = 0.5, cx2 = 0.5, cy2 = 0.5;  // The faces as seen by a camera turning with the mirror.
float targetX = 0, targetY = 0;            // Where the mirror wants to go.
float angleX = 0, angleY = 0;              // Where it is now.
float nodAmount = 0, nodY = 0;             // The small wink nod: how much (0 to 1), and its degrees now. Added to angleY.
String emotion = "neutral";                // The emotion shown, once Wekinator has held it for EMOTION_HOLD_S.
float greetCenterX = 0, greetCenterY = 0;  // Where the happy circles are drawn around.
float[] shyX = {0, 0}, shyY = {0, 0};      // Where the two people are, in mirror degrees. [0] = left, [1] = right.
float ledRed = 0, ledGreen = 0, ledBlue = 0;  // The solid colour now: drawn and sent.
float rainbowPhase = 0;                    // 0 to 1: how far the rainbow has turned. Sent.
float rainbowMix = 1;                      // 0 = solid colour only, 1 = rainbow only. Sent.
float smoothSize = 0.2;                    // The face size, smoothed.
float distanceM = 1;                       // Estimated distance of the person, in metres.
float wantedConvexity = 0;                 // The convexity we are heading to.
float convexity = 0;                       // The convexity now: -1 = concave, +1 = convex. Drawn and sent.

OscP5 osc;
Serial port;                               // Stays null when SIMULATION_ONLY is true.
String lastSentLine = "";
int lastSendMs = 0;

void setup() {
  size(1100, 750, P3D);
  osc = new OscP5(this, OSC_PORT);

  println("Available serial ports:");
  printArray(Serial.list());
  if (!SIMULATION_ONLY) {
    port = new Serial(this, SERIAL_PORT_NAME, 115200);
    delay(2000);  // The board may restart when the port opens: give it time.
  }
}

void draw() {
  readInput();
  updateEmotion();
  updateState();
  updateMotion();
  updateLights();
  updateConvexity();
  sendToArduino();
  printArduinoMessages();
  drawTwin();
  drawHud();
}

// --------------------------- 1. INPUT ---------------------------

// Runs by itself whenever an OSC message arrives, on a separate thread from draw().
// So it only stores numbers: drawing or using the serial port from here can crash.
// All messages arrive on the same port: the address tells them apart.
void oscEvent(OscMessage message) {
  if (INPUT.equals("mouse")) {
    return;
  }
  if (message.checkAddrPattern("/face")) {
    present = message.get(0).intValue() == 1;
    if (present) {
      faceX = message.get(1).floatValue();
      faceY = message.get(2).floatValue();
      size = message.get(3).floatValue();
      lastFaceMs = millis();
      newFace = true;
    }
  }
  if (message.checkAddrPattern("/face2")) {
    present2 = message.get(0).intValue() == 1;
    if (present2) {
      face2X = message.get(1).floatValue();
      face2Y = message.get(2).floatValue();
      lastFace2Ms = millis();
    }
  }
  // Wekinator sends one number: the class, from 1 to 5.
  if (message.checkAddrPattern("/wek/outputs")) {
    hearEmotion(EMOTIONS[constrain(round(message.get(0).floatValue()) - 1, 0, EMOTIONS.length - 1)]);
  }
}

void readInput() {
  if (INPUT.equals("mouse")) {
    if (!mousePressed) {  // While dragging, the mouse rotates the view instead.
      faceX = mouseX / float(width);
      faceY = mouseY / float(height);
      face2X = 1 - faceX;  // The second person stands mirrored across the centre.
      face2Y = faceY;
    }
    if (present) {
      lastFaceMs = millis();
      newFace = true;
    }
    if (present2) {
      lastFace2Ms = millis();
    }
  }

  // The closed loop needs a camera that turns with the mirror. The mouse and the laptop camera
  // stay still, so we pretend: the faces move in the "image" by however much the mirror has turned.
  if (INPUT.equals("mirror camera")) {
    cx = faceX;
    cy = faceY;
    cx2 = face2X;
    cy2 = face2Y;
  } else {
    cx = constrain(faceX - angleX / (CAMERA_HFOV_DEG * signX()), 0, 1);
    cy = constrain(faceY - angleY / (CAMERA_VFOV_DEG * signY()), 0, 1);
    cx2 = constrain(face2X - angleX / (CAMERA_HFOV_DEG * signX()), 0, 1);
    cy2 = constrain(face2Y - angleY / (CAMERA_VFOV_DEG * signY()), 0, 1);
  }
}

float signX() {
  return INVERT_X ? -1 : 1;
}

// Positive tilt is up, but in the image y grows downwards: hence the -1.
float signY() {
  return INVERT_Y ? 1 : -1;
}

void mouseWheel(MouseEvent event) {
  if (INPUT.equals("mouse")) {
    size = constrain(size - event.getCount() * 0.01, 0.02, 1);
  }
}

void keyPressed() {
  if (!INPUT.equals("mouse")) {
    return;
  }
  if (key == 'p') present = !present;
  if (key == 't') present2 = !present2;
  if (key >= '1' && key <= '5') hearEmotion(EMOTIONS[key - '1']);
}

void hearEmotion(String newEmotion) {
  if (!newEmotion.equals(heardEmotion)) {
    heardEmotion = newEmotion;
    heardSinceMs = millis();
  }
}

// --------------------------- 2. DECIDE --------------------------

// A classifier can flicker between classes for a frame or two, so an emotion only counts
// once Wekinator has said it for EMOTION_HOLD_S.
void updateEmotion() {
  if (millis() - heardSinceMs > EMOTION_HOLD_S * 1000) {
    emotion = heardEmotion;
  }
}

// THE IMPORTANT PART, step 1: which state are we in? See the diagram at the top.
void updateState() {
  boolean faceNow = millis() - lastFaceMs < 300;                        // Seen in the last moment.
  boolean faceLost = millis() - lastFaceMs > NO_FACE_TIMEOUT_S * 1000;  // Gone for a while.
  boolean twoNow = TWO_PEOPLE && faceNow && millis() - lastFace2Ms < 300;
  boolean oneOnly = millis() - lastFace2Ms > SHY_EXIT_S * 1000;
  float secondsInState = (millis() - stateStartMs) / 1000.0;

  if ((state.equals("idle") || state.equals("sad")) && faceNow) {
    greetCenterX = angleX;
    greetCenterY = angleY;
    changeState("greeting");
  } else if (state.equals("greeting") && secondsInState > GREETING_S) {
    changeState("tracking");
  } else if (state.equals("tracking") && twoNow) {
    rememberBothFaces();
    changeState("shy");
  } else if (state.equals("shy") && oneOnly) {
    changeState("tracking");
  } else if ((state.equals("tracking") || state.equals("shy")) && faceLost) {
    changeState("sad");
  } else if (state.equals("sad") && secondsInState > SAD_S) {
    changeState("idle");
  }
}

void changeState(String newState) {
  state = newState;
  stateStartMs = millis();
}

// THE IMPORTANT PART, step 2: where the head goes, in each state.
void updateMotion() {
  float secondsInState = (millis() - stateStartMs) / 1000.0;

  if (state.equals("tracking") && newFace) {
    // The closed loop. The camera turns with the mirror, so (cx - 0.5) says how far the mirror is
    // from pointing at the face: that is the error. At each new camera frame, aim where the mirror
    // is now plus part of that error. When the face is centred the error is 0, and it stops by itself.
    // Only new frames count: the image is a little late, and reusing one would correct twice.
    float errorX = (cx - 0.5) * CAMERA_HFOV_DEG * signX();
    float errorY = (cy - 0.5) * CAMERA_VFOV_DEG * signY();
    if (abs(errorX) > DEAD_ZONE_DEG) {
      targetX = angleX + errorX * CLOSED_LOOP_GAIN;
    }
    if (abs(errorY) > DEAD_ZONE_DEG) {
      targetY = angleY + errorY * CLOSED_LOOP_GAIN;
    }
  } else if (state.equals("shy")) {
    // Look at the left person, then the right one, in turn. Their positions are remembered,
    // because while it looks at one, the other may be out of the camera's view.
    if (newFace) {
      rememberFace(cx, cy);
      if (millis() - lastFace2Ms < 300) {
        rememberFace(cx2, cy2);
      }
    }
    int side = int(secondsInState / SHY_SWITCH_S) % 2;
    targetX = shyX[side];
    targetY = shyY[side];
  } else if (state.equals("greeting")) {
    // Happy circles, starting and ending where it was. They go up from the lower half of the
    // range and down from the upper half, so they stay inside the limits.
    float turn = TWO_PI * GREETING_TURNS * min(secondsInState / GREETING_S, 1);
    float upOrDown = greetCenterY < (Y_MIN_DEG + Y_MAX_DEG) / 2 ? 1 : -1;
    targetX = greetCenterX + GREETING_RADIUS_DEG * sin(turn);
    targetY = greetCenterY + upOrDown * GREETING_RADIUS_DEG * (1 - cos(turn));
  } else if (state.equals("sad")) {
    targetY = SAD_TILT_DEG;
  } else if (state.equals("idle")) {
    targetX = 0;
    targetY = Y_LEVEL_DEG;
  }
  newFace = false;

  targetX = constrain(targetX, X_MIN_DEG, X_MAX_DEG);
  targetY = constrain(targetY, Y_MIN_DEG, Y_MAX_DEG);

  // Each frame, cover a fraction of the remaining distance: quickly while following people,
  // slowly when it gets sad and when it goes back to rest, so those moves look calm.
  float smoothing = state.equals("sad") || state.equals("idle") ? GENTLE_SMOOTHING : XY_SMOOTHING;
  angleX += (targetX - angleX) * smoothing;
  angleY += (targetY - angleY) * smoothing;

  // After a wink, a small up-and-down nod on top of the tilt. It fades in and out, so it never jumps.
  boolean winking = state.equals("tracking") && emotion.equals("wink");
  nodAmount += ((winking ? 1 : 0) - nodAmount) * 0.05;
  nodY = nodAmount * WINK_NOD_DEG * sin(TWO_PI * millis() / 1000.0 / WINK_NOD_PERIOD_S);
}

// Where a face is, in mirror degrees: where the mirror points, plus the face's offset in the image.
float faceAngleX(float x) {
  return angleX + (x - 0.5) * CAMERA_HFOV_DEG * signX();
}

float faceAngleY(float y) {
  return angleY + (y - 0.5) * CAMERA_VFOV_DEG * signY();
}

// Both faces are visible: store them, the left one first.
void rememberBothFaces() {
  float a = faceAngleX(cx), b = faceAngleX(cx2);
  int left = a < b ? 0 : 1;
  shyX[left] = a;
  shyY[left] = faceAngleY(cy);
  shyX[1 - left] = b;
  shyY[1 - left] = faceAngleY(cy2);
}

// One face is visible: update whichever stored person it is closer to, gently, to ignore noise.
void rememberFace(float x, float y) {
  float a = faceAngleX(x);
  int nearest = abs(a - shyX[0]) < abs(a - shyX[1]) ? 0 : 1;
  shyX[nearest] += (a - shyX[nearest]) * 0.3;
  shyY[nearest] += (faceAngleY(y) - shyY[nearest]) * 0.3;
}

// The lights, in each state. Two things fade smoothly: the solid colour, and the mix between
// that colour and the rainbow. So every change, including to and from the rainbow, is a fade.
void updateLights() {
  float secondsInState = (millis() - stateStartMs) / 1000.0;
  rainbowPhase = (millis() / 1000.0 * RAINBOW_TURNS_PER_S) % 1;

  color wanted = color(0);
  float wantedMix = 0;
  if (state.equals("idle")) {
    wantedMix = 1;
  } else if (state.equals("greeting")) {
    wanted = HAPPY_COLOR;
  } else if (state.equals("shy")) {
    wanted = SHY_COLOR;
  } else if (state.equals("sad")) {
    wanted = lerpColor(SAD_COLOR, color(0), min(secondsInState / SAD_S, 1));  // Blue, slowly fading to dark.
  } else {
    wanted = emotionColor();
  }

  ledRed += (red(wanted) - ledRed) * LIGHT_SMOOTHING;
  ledGreen += (green(wanted) - ledGreen) * LIGHT_SMOOTHING;
  ledBlue += (blue(wanted) - ledBlue) * LIGHT_SMOOTHING;
  rainbowMix += (wantedMix - rainbowMix) * LIGHT_SMOOTHING;
}

// One colour per emotion. The fade in updateLights() makes the changes smooth.
color emotionColor() {
  if (emotion.equals("happy")) return HAPPY_COLOR;
  if (emotion.equals("sad")) return SAD_COLOR;
  if (emotion.equals("angry")) return ANGRY_COLOR;
  if (emotion.equals("wink")) return WINK_COLOR;
  return NEUTRAL_COLOR;
}

// The curve, in each state.
// Idle and shy: a slow pulse, convex then concave, growing from nothing so it starts smoothly.
// Greeting and tracking: keep the face at the same zoom, calm on purpose:
//   1. The closer a face, the bigger it looks, so distance = k / size.
//   2. A concave mirror magnifies by zoom = f / (f - distance), where f is its focal length.
//      So f = zoom * distance / (zoom - 1): a person further away needs a flatter mirror.
//   3. A mirror with focal length f is part of a sphere of radius 2f, and its centre sits
//      rimRadius^2 / (2 * sphereRadius) behind its rim. That is the depth we need.
// Sad: flat.
void updateConvexity() {
  float secondsInState = (millis() - stateStartMs) / 1000.0;
  smoothSize += (size - smoothSize) * SIZE_SMOOTHING;
  distanceM = DISTANCE_CALIB_K / max(smoothSize, 0.01);

  if (state.equals("idle") || state.equals("shy")) {
    float amount = PULSE_AMOUNT * min(secondsInState / PULSE_FADE_IN_S, 1);
    wantedConvexity = amount * sin(TWO_PI * secondsInState / PULSE_PERIOD_S);
  } else if (state.equals("sad")) {
    wantedConvexity = 0;
  } else {
    float focalMm = ZOOM * distanceM / (ZOOM - 1) * 1000;
    float sagMm = MIRROR_RADIUS * MIRROR_RADIUS / (2 * 2 * focalMm);
    float wanted = -min(sagMm / MAX_SAG_MM, 1);
    if (abs(wanted - wantedConvexity) > CONVEXITY_DEAD_ZONE) {  // Ignore small changes.
      wantedConvexity = wanted;
    }
  }
  convexity += (wantedConvexity - convexity) * CONVEXITY_SMOOTHING;
}

// ---------------------------- 3. SEND ---------------------------

// The message is plain text: x,y,r,g,b,c,rainbowPhase,rainbowMix,
// for example "12.5,-3.0,255,180,40,-0.25,0.420,0.00". It goes out only if the text has changed.
void sendToArduino() {
  if (millis() - lastSendMs < 1000 / SEND_RATE_HZ) {
    return;
  }
  // Locale.US matters: on an Italian computer, the decimal point would otherwise be a comma.
  String line = String.format(java.util.Locale.US, "%.1f,%.1f,%d,%d,%d,%+.2f,%.3f,%.2f\n",
    angleX, constrain(angleY + nodY, Y_MIN_DEG, Y_MAX_DEG), round(ledRed), round(ledGreen), round(ledBlue), convexity, rainbowPhase, rainbowMix);
  if (line.equals(lastSentLine)) {
    return;
  }
  lastSentLine = line;
  lastSendMs = millis();
  if (port != null) {
    port.write(line);
  }
}

void printArduinoMessages() {
  if (port != null) {
    String message = port.readStringUntil('\n');  // null until a whole line has arrived.
    if (message != null) {
      print("[Arduino] " + message);
    }
  }
}
