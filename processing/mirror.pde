/*
  mirror: BEHAVIOUR. It decides what the mirror does. Change the experience here:
  the Arduino does not need re-uploading.

  The mirror has 5 states, and moves between them by itself:

    idle      nobody there: it looks straight ahead, the curve pulses, a rainbow turns around the LEDs
       | a face appears
    greeting  a happy celebration: the head draws a circle, the LEDs fade to HAPPY_COLOR
       | the celebration ends
    tracking  it follows the face (closed loop). The colour shows the emotion from Wekinator:
              neutral, happy, sad, angry, or a wink (green, and the head nods a little).
              The curve keeps the face at the same zoom.
       | a second face appears (if TWO_PEOPLE)          ^ only one face again
    shy       embarrassed: it sweeps slowly between the two faces, the curve pulses, the LEDs turn pink
       | no face for NO_FACE_TIMEOUT_S (from tracking or shy)
    sad       it slowly looks down, the LEDs turn SAD_COLOR and fade to dark, then back to idle
              (if a face comes back while sad, it celebrates again)

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

// ================= 1. SETUP: check these every time you start =================
final boolean SIMULATION_ONLY = false;  // true = no Arduino: everything happens on screen.
final String INPUT = "mirror camera";   // Where the faces come from:
                                        //   "mirror camera" = the ESP32-CAM on the mirror (start "Avvia camera specchio")
                                        //   "laptop camera" = the computer's camera, for testing (start "Avvia webcam computer")
                                        //   "mouse"         = no camera. Mouse = face, wheel = size, p = present,
                                        //                     t = a second person (mirrored), 1-5 = emotion (neutral, happy, sad, angry, wink)
final String SERIAL_PORT_NAME = "/dev/cu.usbmodem1101";  // The Arduino's port, from the list printed in the console.

// ================= 2. CALIBRATE: measured on the real mirror (docs/calibration.md) =================
// Copied from mirror.ino. When Processing connects, the Arduino prints its own values in the
// console ("[Arduino] mirror ready. Copy to mirror.pde: ..."): these five must match that line.
final float X_MIN_DEG = -80, X_MAX_DEG = 80;  // Degrees the base can turn, each way from the centre.
final float Y_MAX_DEG = 30;             // Degrees. Tilt goes from 0 (head all the way down) to this.
final float X_MAX_DEG_PER_S = 16;       // Fastest the base turns: MAX_SPEED_X / STEPS_PER_DEG_X.
final float Y_MAX_DEG_PER_S = 2.8;      // Fastest the head tilts: MAX_SPEED_Y / STEPS_PER_DEG_Y.

// Measured here, with the whole system running.
final float Y_LEVEL_DEG = 15;           // The tilt where the mirror looks straight ahead. Idle rests here.
final boolean INVERT_X = false;         // Flip if the mirror turns AWAY from the face and runs to a limit.
final boolean INVERT_Y = false;         // Same, for the tilt.
final float CAMERA_HFOV_DEG = 55;       // Degrees the mirror camera sees across its width.
final float CAMERA_VFOV_DEG = 42;       // Degrees it sees across its height.
final float DISTANCE_CALIB_K = 0.2;     // Stand exactly 1 m from the camera and write here the "size" shown on screen.
final float MAX_SAG_MM = 30;            // Millimetres. Deepest curve the mirror can make (convexity -1 or +1).

// ================= 3. TUNE: how the mirror behaves =================
// --- Following a face ---
final float CLOSED_LOOP_GAIN = 0.35;    // 0 to 1. Share of the way to the face covered at each camera frame. Too high = it overshoots.
final float DEAD_ZONE_DEG = 2;          // Degrees. A face this close to the centre counts as centred, so the mirror rests.
final float FAST_SMOOTHING = 0.3;       // 0 to 1. Share of the remaining distance covered each frame, while greeting and tracking.
final float GENTLE_SMOOTHING = 0.04;    // The same, in the calm states: idle, shy and sad.

// --- States ---
final boolean TWO_PEOPLE = true;        // false = ignore a second face: no shy state.
final float NO_FACE_TIMEOUT_S = 3;      // Seconds without a face before it gets sad.
final float GREETING_S = 2;             // Seconds the celebration lasts: one happy circle.
final float GREETING_RADIUS_DEG = 10;   // Degrees. Size of the happy circle.
final float SHY_SWEEP_S = 7;            // Seconds to sweep from one face to the other and back. Longer = softer.
final float SHY_EXIT_S = 4;             // Seconds without a second face before it stops being shy.
final float SAD_S = 2;                  // Seconds it stays sad before going idle. Its blue fades to dark over this time.
final float WINK_NOD_DEG = 3;           // Degrees. How far the head nods up and down after a wink: very little.
final float EMOTION_HOLD_S = 0.3;       // Seconds Wekinator must say the same emotion before it shows, so it does not flicker.

// --- Lights ---
final color NEUTRAL_COLOR = #FFE0B0;    // Emotion "neutral".
final color HAPPY_COLOR = #FFA000;      // Emotion "happy", and when greeting.
final color SAD_COLOR = #2040FF;        // Emotion "sad", and when sad.
final color ANGRY_COLOR = #FF0000;      // Emotion "angry".
final color WINK_COLOR = #00FF40;       // Emotion "wink".
final color SHY_COLOR = #FF6FA8;        // Two people: embarrassed pink.
final float LIGHT_SMOOTHING = 0.03;     // 0 to 1. Lower = slower fades between colours, and to and from the rainbow.
final float RAINBOW_TURNS_PER_S = 0.2;  // How fast the idle rainbow turns around the ring.

// --- Convexity: tuned to be calm ---
final float ZOOM = 3;                   // Magnification to keep while tracking, above 1.
final float PULSE_PERIOD_S = 4;         // Seconds for one in-and-out pulse of the curve (idle and shy).
final float PULSE_AMOUNT = 0.6;         // 0 to 1. How far the pulse goes, both convex and concave.
final float SIZE_SMOOTHING = 0.05;      // 0 to 1. Smooths the face size first: it is the noisiest number.
final float CONVEXITY_DEAD_ZONE = 0.05; // Changes of convexity smaller than this are ignored while tracking.
final float CONVEXITY_SMOOTHING = 0.03; // 0 to 1. Lower = slower and calmer changes of shape.

final int OSC_PORT = 12000;             // UDP port to listen on. Must match PROCESSING_PORT in face_tracker.py.
// ====================================================================

// Degrees for one image width or height, with the sign that turns the mirror TOWARDS the face.
// In the image y grows downwards, but tilt grows upwards: hence the minus.
final float DEG_PER_IMAGE_X = CAMERA_HFOV_DEG * (INVERT_X ? -1 : 1);
final float DEG_PER_IMAGE_Y = -CAMERA_VFOV_DEG * (INVERT_Y ? -1 : 1);

// What we receive. Face 1 is the largest (closest) face, face 2 the second one.
boolean present = true, present2 = false;  // Only for "mouse" mode: p and t switch them.
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
float targetX = 0, targetY = 0;            // Where the mirror wants to go, in degrees.
float angleX = 0, angleY = 0;              // Where it is now. Both start at 0, like the motors.
float nodAmount = 0, nodY = 0;             // The small wink nod: how much (0 to 1), and its degrees now. Added to angleY.
String emotion = "neutral";                // The emotion shown, once Wekinator has held it for EMOTION_HOLD_S.
float greetCenterX = 0, greetCenterY = 0;  // Where the mirror was when the greeting began.
float[] shyX = {0, 0}, shyY = {0, 0};      // Where the two people are, in mirror degrees.
int lastMotionMs = 0;                      // When updateMotion() last ran, to limit the speed.
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
    delay(2000);       // The board may restart when the port opens: give it time.
    port.write("?\n"); // Ask the Arduino to print its settings, to compare with block 2 above.
  }
  lastMotionMs = millis();
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
  if (message.checkAddrPattern("/face") && message.get(0).intValue() == 1) {
    faceX = message.get(1).floatValue();
    faceY = message.get(2).floatValue();
    size = message.get(3).floatValue();
    lastFaceMs = millis();
    newFace = true;
  }
  if (message.checkAddrPattern("/face2") && message.get(0).intValue() == 1) {
    face2X = message.get(1).floatValue();
    face2Y = message.get(2).floatValue();
    lastFace2Ms = millis();
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
    cx = constrain(faceX - angleX / DEG_PER_IMAGE_X, 0, 1);
    cy = constrain(faceY - (angleY - Y_LEVEL_DEG) / DEG_PER_IMAGE_Y, 0, 1);
    cx2 = constrain(face2X - angleX / DEG_PER_IMAGE_X, 0, 1);
    cy2 = constrain(face2Y - (angleY - Y_LEVEL_DEG) / DEG_PER_IMAGE_Y, 0, 1);
  }
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

// How long the current state has lasted.
float secondsInState() {
  return (millis() - stateStartMs) / 1000.0;
}

// THE IMPORTANT PART, step 1: which state are we in? See the diagram at the top.
void updateState() {
  boolean faceNow = millis() - lastFaceMs < 300;                        // Seen in the last moment.
  boolean faceLost = millis() - lastFaceMs > NO_FACE_TIMEOUT_S * 1000;  // Gone for a while.
  boolean secondFaceNow = TWO_PEOPLE && faceNow && millis() - lastFace2Ms < 300;
  boolean secondFaceLost = millis() - lastFace2Ms > SHY_EXIT_S * 1000;

  String newState = state;
  if ((state.equals("idle") || state.equals("sad")) && faceNow) {
    greetCenterX = angleX;
    greetCenterY = angleY;
    newState = "greeting";
  } else if (state.equals("greeting") && secondsInState() > GREETING_S) {
    newState = "tracking";
  } else if (state.equals("tracking") && secondFaceNow) {
    // Remember where the two people are: [0] is the one it is looking at, so the sweep starts there.
    shyX[0] = faceAngleX(cx);
    shyY[0] = faceAngleY(cy);
    shyX[1] = faceAngleX(cx2);
    shyY[1] = faceAngleY(cy2);
    newState = "shy";
  } else if (state.equals("shy") && secondFaceLost) {
    newState = "tracking";
  } else if ((state.equals("tracking") || state.equals("shy")) && faceLost) {
    newState = "sad";
  } else if (state.equals("sad") && secondsInState() > SAD_S) {
    newState = "idle";
  }

  if (!newState.equals(state)) {
    state = newState;
    stateStartMs = millis();
  }
}

// THE IMPORTANT PART, step 2: where the head goes, in each state.
void updateMotion() {
  if (state.equals("tracking") && newFace) {
    // The closed loop. The camera turns with the mirror, so a face off the centre of the image
    // means the mirror is not pointing at it yet. At each new camera frame, aim part of the way
    // (CLOSED_LOOP_GAIN) from where the mirror is to where the face is. When the face is centred
    // there is nothing left to correct, and it stops by itself.
    // Only new frames count: the image is a little late, and reusing one would correct twice.
    if (abs(faceAngleX(cx) - angleX) > DEAD_ZONE_DEG) {
      targetX = lerp(angleX, faceAngleX(cx), CLOSED_LOOP_GAIN);
    }
    if (abs(faceAngleY(cy) - angleY) > DEAD_ZONE_DEG) {
      targetY = lerp(angleY, faceAngleY(cy), CLOSED_LOOP_GAIN);
    }
  } else if (state.equals("shy")) {
    // The positions are remembered, because while it looks at one person the other may be out
    // of the camera's view. Whoever is visible keeps their remembered position up to date.
    if (newFace) {
      rememberFace(cx, cy);
      if (millis() - lastFace2Ms < 300) {
        rememberFace(cx2, cy2);
      }
    }
    // A slow sweep from the first person (0) to the other (1) and back. The cosine makes it
    // slow down and linger at each person, and never jump.
    float towardsOther = (1 - cos(TWO_PI * secondsInState() / SHY_SWEEP_S)) / 2;
    targetX = lerp(shyX[0], shyX[1], towardsOther);
    targetY = lerp(shyY[0], shyY[1], towardsOther);
  } else if (state.equals("greeting")) {
    // One happy circle, starting and ending where it was. It goes up from the lower half of the
    // tilt range and down from the upper half, so it stays inside the limits.
    float turn = TWO_PI * min(secondsInState() / GREETING_S, 1);
    float upOrDown = greetCenterY < Y_MAX_DEG / 2 ? 1 : -1;
    targetX = greetCenterX + GREETING_RADIUS_DEG * sin(turn);
    targetY = greetCenterY + upOrDown * GREETING_RADIUS_DEG * (1 - cos(turn));
  } else if (state.equals("sad")) {
    targetY = 0;  // All the way down. The rotation stays where it was.
  } else if (state.equals("idle")) {
    targetX = 0;
    targetY = Y_LEVEL_DEG;
  }
  newFace = false;

  targetX = constrain(targetX, X_MIN_DEG, X_MAX_DEG);
  targetY = constrain(targetY, 0, Y_MAX_DEG);

  // Move towards the target: each frame, a share of the remaining distance.
  // But never faster than the motors can go. Otherwise the angle here runs ahead of the real
  // mirror, the camera still sees the face off-centre, the loop adds more correction, and it overshoots.
  boolean calm = state.equals("idle") || state.equals("shy") || state.equals("sad");
  float smoothing = calm ? GENTLE_SMOOTHING : FAST_SMOOTHING;
  float seconds = (millis() - lastMotionMs) / 1000.0;
  lastMotionMs = millis();
  angleX += constrain((targetX - angleX) * smoothing, -X_MAX_DEG_PER_S * seconds, X_MAX_DEG_PER_S * seconds);
  angleY += constrain((targetY - angleY) * smoothing, -Y_MAX_DEG_PER_S * seconds, Y_MAX_DEG_PER_S * seconds);

  // After a wink, a small up-and-down nod on top of the tilt, one nod every 0.8 s.
  // It fades in and out, so it never jumps.
  boolean winking = state.equals("tracking") && emotion.equals("wink");
  nodAmount += ((winking ? 1 : 0) - nodAmount) * 0.05;
  nodY = nodAmount * WINK_NOD_DEG * sin(TWO_PI * millis() / 800.0);
}

// Where a face is, in mirror degrees: where the mirror points, plus the face's offset from the
// centre of the image.
float faceAngleX(float x) {
  return angleX + (x - 0.5) * DEG_PER_IMAGE_X;
}

float faceAngleY(float y) {
  return angleY + (y - 0.5) * DEG_PER_IMAGE_Y;
}

// Shy: a visible face updates whichever remembered person it is closer to, gently, to ignore noise.
void rememberFace(float x, float y) {
  float a = faceAngleX(x);
  int nearest = abs(a - shyX[0]) < abs(a - shyX[1]) ? 0 : 1;
  shyX[nearest] += (a - shyX[nearest]) * 0.3;
  shyY[nearest] += (faceAngleY(y) - shyY[nearest]) * 0.3;
}

// The lights, in each state. Two things fade smoothly: the solid colour, and the mix between
// that colour and the rainbow. So every change, including to and from the rainbow, is a fade.
void updateLights() {
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
    wanted = lerpColor(SAD_COLOR, color(0), min(secondsInState() / SAD_S, 1));  // Blue, slowly fading to dark.
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
  smoothSize += (size - smoothSize) * SIZE_SMOOTHING;
  distanceM = DISTANCE_CALIB_K / max(smoothSize, 0.01);

  if (state.equals("idle") || state.equals("shy")) {
    float grow = min(secondsInState() / PULSE_PERIOD_S, 1);  // From 0 to 1 over the first pulse.
    wantedConvexity = PULSE_AMOUNT * grow * sin(TWO_PI * secondsInState() / PULSE_PERIOD_S);
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

// The message is plain text: x,y,r,g,b,c,rainbowPhase,rainbowMix
// for example "12.5,8.0,255,180,40,-0.25,0.420,0.00". At most 30 lines per second, and only
// when the text has changed.
void sendToArduino() {
  if (millis() - lastSendMs < 33) {
    return;
  }
  // Locale.US matters: on an Italian computer, the decimal point would otherwise be a comma.
  String line = String.format(java.util.Locale.US, "%.1f,%.1f,%d,%d,%d,%+.2f,%.3f,%.2f\n",
    angleX, constrain(angleY + nodY, 0, Y_MAX_DEG), round(ledRed), round(ledGreen), round(ledBlue), convexity, rainbowPhase, rainbowMix);
  if (line.equals(lastSentLine)) {
    return;
  }
  lastSentLine = line;
  lastSendMs = millis();
  if (port != null) {
    port.write(line);
  }
}

// Whatever the Arduino says ("mirror ready...", "line discarded") appears in the console.
void printArduinoMessages() {
  if (port != null) {
    String message = port.readStringUntil('\n');  // null until a whole line has arrived.
    if (message != null) {
      print("[Arduino] " + message);
    }
  }
}
