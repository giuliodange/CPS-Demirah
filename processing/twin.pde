/*
  twin: the 3D drawing and the text on screen. It only reads the decided values
  (angleX, angleY, convexity, colours...) and changes nothing, so the mirror works the same without it.

  drawTwin() is the important part. Each part is drawn after the rotations it must
  follow: the base has none, the column follows X, the head follows X and Y.

  Sizes are in millimetres, and only affect the drawing. In Processing, negative y is up.
*/

// ============================== CONFIG ==============================
final float MIRROR_RADIUS = 180;     // Project measurement.
final float MIRROR_THICKNESS = 8;    // Only affects the drawing.
final float BASE_HEIGHT = 40;        // Fixed part of the column. Only affects the drawing.
final float JOINT_HEIGHT = 480;      // Height of the head's joint: its rotation point.
final float JOINT_Z = 0;             // Forward position of the head's joint: its rotation point.
final float LED_RING_WIDTH = 14;     // Only affects the drawing.
final float LED_RING_DEPTH = 10;     // Thickness of the LED ring, backwards from the mirror's front. Only affects the drawing.
final float MIRROR_OFFSET = 150;     // From the joint to the mirror's rim. Far enough forward that the mirror clears the column when it looks down.
final color BACKGROUND = color(250, 250, 230);
final float PERSON_DISTANCE = 600;   // How far away the red ball is drawn. Only affects the drawing.

// The column's outline from the floor up, as {height, radius} in millimetres. Edit it to change
// the shape: the drawing passes smoothly through every point. The last height is JOINT_HEIGHT.
// Above about 220 mm it must stay thin: when the mirror looks down, its lower edge swings back
// and down towards the column. With these values and MIRROR_OFFSET = 150 it stays about 9 mm
// clear at the full 30 degrees down. Check again if you change either.
final float[][] COLUMN_PROFILE = {
  {0, 125}, {40, 120}, {110, 98}, {160, 85}, {195, 60}, {225, 22}, {260, 14}, {400, 12}, {480, 14}
};
// ====================================================================

float viewYaw = 0.5, viewPitch = -0.2;

void mouseDragged() {
  viewYaw += (mouseX - pmouseX) * 0.01;
  viewPitch -= (mouseY - pmouseY) * 0.01;
}

void drawTwin() {
  background(BACKGROUND);
  ambientLight(100, 100, 105);
  directionalLight(170, 170, 165, 0, 0.3, -1);
  noStroke();

  // Place the whole scene in the window, and apply the view chosen with the mouse.
  pushMatrix();
  translate(width * 0.56, height * 0.82, -300);
  scale(0.7);
  rotateX(viewPitch);
  rotateY(viewYaw);
  drawFloor();
  drawPerson();

  // Base: no rotation.
  drawColumn(0, BASE_HEIGHT, color(70, 72, 78), color(70, 72, 78));

  // Column: axis X turns everything drawn after this line.
  rotateY(radians(angleX));
  drawColumn(BASE_HEIGHT, JOINT_HEIGHT, color(150, 118, 88), color(205, 180, 150));

  // Head: move to the joint, tilt with axis Y, and draw from there.
  // The minus sign makes positive angles look down.
  translate(0, -JOINT_HEIGHT, JOINT_Z);
  rotateX(-radians(angleY + nodY));
  fill(110, 110, 115);
  sphere(22);
  drawRod(MIRROR_OFFSET - MIRROR_THICKNESS - MAX_SAG_MM);
  drawMirror(convexity * MAX_SAG_MM);
  drawLedRing();

  // A yellow line showing where the mirror points.
  stroke(255, 220, 80);
  line(0, 0, 0, 0, 0, PERSON_DISTANCE);
  noStroke();
  popMatrix();
}

// ---------------------------- Column ----------------------------

// The column is a "lathe" shape: its outline (COLUMN_PROFILE) spun around the vertical axis.
// It is drawn as rings, each one a strip of quads, coloured from bottomColor to topColor.
void drawColumn(float fromHeight, float toHeight, color bottomColor, color topColor) {
  float step = 6;
  for (float h = fromHeight; h < toHeight; h += step) {
    float h2 = min(h + step, toHeight);
    fill(lerpColor(bottomColor, topColor, h / JOINT_HEIGHT));
    beginShape(QUAD_STRIP);
    for (int i = 0; i <= 48; i++) {
      float angle = TWO_PI * i / 48;
      columnVertex(h2, angle);
      columnVertex(h, angle);
    }
    endShape();
  }
}

// One point of the column. The normal leans with the outline's slope, so the light shows the curves.
void columnVertex(float h, float angle) {
  float r = columnRadius(h);
  float slope = (columnRadius(h + 1) - columnRadius(h - 1)) / 2;
  normal(cos(angle), slope, sin(angle));
  vertex(r * cos(angle), -h, r * sin(angle));
}

// The radius at any height: a smooth curve through the profile points.
// curvePoint() is Processing's Catmull-Rom curve, which passes exactly through each point.
float columnRadius(float h) {
  int last = COLUMN_PROFILE.length - 1;
  h = constrain(h, 0, COLUMN_PROFILE[last][0]);
  int i = 0;
  while (i < last - 1 && h > COLUMN_PROFILE[i + 1][0]) {
    i++;
  }
  float t = (h - COLUMN_PROFILE[i][0]) / (COLUMN_PROFILE[i + 1][0] - COLUMN_PROFILE[i][0]);
  return curvePoint(COLUMN_PROFILE[max(i - 1, 0)][1], COLUMN_PROFILE[i][1],
                    COLUMN_PROFILE[i + 1][1], COLUMN_PROFILE[min(i + 2, last)][1], t);
}

// ---------------------------- Mirror ----------------------------

// The short arm from the joint forward to the back of the mirror.
void drawRod(float length) {
  fill(110, 110, 115);
  beginShape(QUAD_STRIP);
  for (int i = 0; i <= 16; i++) {
    float angle = TWO_PI * i / 16;
    normal(cos(angle), sin(angle), 0);
    vertex(10 * cos(angle), 10 * sin(angle), length);
    vertex(10 * cos(angle), 10 * sin(angle), 0);
  }
  endShape();
}

// The mirror as a shell of a sphere: the rim stays still and the centre moves by `sag` mm,
// towards the person if positive. Three parts: the front, the back and the edge between them.
void drawMirror(float sag) {
  float curve = 2 * sag / (MIRROR_RADIUS * MIRROR_RADIUS + sag * sag);  // 1 / the sphere's radius. 0 = flat.

  for (int ring = 0; ring < 24; ring++) {
    float inner = MIRROR_RADIUS * ring / 24;
    float outer = MIRROR_RADIUS * (ring + 1) / 24;

    // Front: coloured by depth, so the curve shows as a gradient.
    beginShape(QUAD_STRIP);
    for (int i = 0; i <= 64; i++) {
      float angle = TWO_PI * i / 64;
      mirrorPoint(inner, angle, sag, curve, 0, true);
      mirrorPoint(outer, angle, sag, curve, 0, true);
    }
    endShape();

    // Back: the same shape, MIRROR_THICKNESS behind. Outer before inner, so that it faces backwards.
    beginShape(QUAD_STRIP);
    for (int i = 0; i <= 64; i++) {
      float angle = TWO_PI * i / 64;
      mirrorPoint(outer, angle, sag, curve, -MIRROR_THICKNESS, false);
      mirrorPoint(inner, angle, sag, curve, -MIRROR_THICKNESS, false);
    }
    endShape();
  }

  // Edge: a thin band joining the front rim to the back rim.
  fill(90, 95, 100);
  beginShape(QUAD_STRIP);
  for (int i = 0; i <= 64; i++) {
    float angle = TWO_PI * i / 64;
    normal(cos(angle), sin(angle), 0);
    vertex(MIRROR_RADIUS * cos(angle), MIRROR_RADIUS * sin(angle), MIRROR_OFFSET);
    vertex(MIRROR_RADIUS * cos(angle), MIRROR_RADIUS * sin(angle), MIRROR_OFFSET - MIRROR_THICKNESS);
  }
  endShape();
}

// One point of the mirror. The height is the usual formula for a point on a sphere, written so
// that it also works when flat. The front's colour moves from silver towards orange (bulging out)
// or towards blue (hollow), more strongly where the surface is further from the rim.
// sqrt() makes even a small curve clearly visible, and a full curve reaches the full colour.
void mirrorPoint(float radius, float angle, float sag, float curve, float shift, boolean front) {
  float x = radius * cos(angle);
  float y = radius * sin(angle);
  float height = sag - curve * radius * radius / (1 + sqrt(1 - curve * curve * radius * radius));
  if (front) {
    float amount = constrain(sqrt(abs(height) / MAX_SAG_MM), 0, 1);
    fill(lerpColor(color(205, 215, 225), height > 0 ? color(255, 110, 0) : color(0, 90, 255), amount));
    normal(curve * x, curve * y, 1);
  } else {
    fill(60, 62, 66);
    normal(-curve * x, -curve * y, -1);
  }
  vertex(x, y, MIRROR_OFFSET + height + shift);
}

// The LED ring around the mirror: a front face and an outer side, so it has some thickness.
// Emissive means it glows by itself, so the colour stays true whatever the lights do.
// Each piece blends the solid colour with its own rainbow hue, just like the real strip.
void drawLedRing() {
  float outer = MIRROR_RADIUS + LED_RING_WIDTH;
  fill(0);
  for (int i = 0; i < 64; i++) {
    colorMode(HSB, 1);
    color rainbow = color((float(i) / 64 + rainbowPhase) % 1, 1, 1);
    colorMode(RGB, 255);
    emissive(lerpColor(color(ledRed, ledGreen, ledBlue), rainbow, rainbowMix));

    float a1 = TWO_PI * i / 64;
    float a2 = TWO_PI * (i + 1) / 64;
    beginShape(QUADS);
    // Front face
    vertex(MIRROR_RADIUS * cos(a1), MIRROR_RADIUS * sin(a1), MIRROR_OFFSET);
    vertex(outer * cos(a1), outer * sin(a1), MIRROR_OFFSET);
    vertex(outer * cos(a2), outer * sin(a2), MIRROR_OFFSET);
    vertex(MIRROR_RADIUS * cos(a2), MIRROR_RADIUS * sin(a2), MIRROR_OFFSET);
    // Outer side, going back by LED_RING_DEPTH
    vertex(outer * cos(a1), outer * sin(a1), MIRROR_OFFSET);
    vertex(outer * cos(a1), outer * sin(a1), MIRROR_OFFSET - LED_RING_DEPTH);
    vertex(outer * cos(a2), outer * sin(a2), MIRROR_OFFSET - LED_RING_DEPTH);
    vertex(outer * cos(a2), outer * sin(a2), MIRROR_OFFSET);
    endShape();
  }
  emissive(0, 0, 0);
}

// ---------------------------- Others ----------------------------

// Red balls for the people. Tracking: where the mirror is heading, which sits on the yellow line
// when the face is centred. Shy: the two remembered people.
void drawPerson() {
  if (state.equals("tracking")) {
    drawBall(targetX, targetY);
  } else if (state.equals("shy")) {
    drawBall(shyX[0], shyY[0]);
    drawBall(shyX[1], shyY[1]);
  }
}

void drawBall(float degreesX, float degreesY) {
  pushMatrix();
  translate(0, -JOINT_HEIGHT, JOINT_Z);
  rotateY(radians(degreesX));
  rotateX(-radians(degreesY));
  translate(0, 0, PERSON_DISTANCE);
  fill(230, 70, 70);
  sphere(30);
  popMatrix();
}

void drawFloor() {
  stroke(200, 200, 185);
  for (int i = -500; i <= 500; i += 100) {
    line(i, 0, -500, i, 0, 500);
    line(-500, 0, i, 500, 0, i);
  }
  noStroke();
}

// The values at each stage of the chain, for debugging.
void drawHud() {
  noLights();
  hint(DISABLE_DEPTH_TEST);
  fill(40);
  textSize(15);
  text("STATE     " + state + "   (input: " + INPUT + ")"
    + "\nRECEIVED  face=" + nf(faceX, 0, 2) + "," + nf(faceY, 0, 2) + "  as seen from the mirror=" + nf(cx, 0, 2) + "," + nf(cy, 0, 2) + "  size=" + nf(size, 0, 2)
      + (millis() - lastFace2Ms < 300 ? "  + second face" : "")
    + "\nANGLES    x=" + nf(angleX, 0, 1) + "  y=" + nf(angleY + nodY, 0, 1)
    + "\nEMOTION   " + emotion + (heardEmotion.equals(emotion) ? "" : "  (hearing " + heardEmotion + ")")
    + "\nLIGHTS    colour=" + round(ledRed) + "," + round(ledGreen) + "," + round(ledBlue) + "  rainbow=" + nf(rainbowMix, 0, 2)
    + "\nCONVEXITY size=" + nf(smoothSize, 0, 3) + "  distance=" + nf(distanceM, 0, 2) + " m  c=" + nf(convexity, 0, 2)
    + "\nSENT      " + lastSentLine.trim()
    + "\nSERIAL    " + (port == null ? "off" : SERIAL_PORT_NAME), 20, 30);
  hint(ENABLE_DEPTH_TEST);
}
