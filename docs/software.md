# Software design

## Pipeline

| Step | Program | Input | Output |
|---|---|---|---|
| 1. Camera | ESP32-CAM, [`esp32_cam/CameraWebServer`](../esp32_cam/CameraWebServer) | Image | MJPEG stream over Wi-Fi: `http://<ip>:81/stream` |
| 2. Perception | [`python/face_tracker.py`](../python/face_tracker.py) with MediaPipe Face Landmarker | Stream | OSC `/face`: `present, cx, cy, size` of the largest (closest) face. OSC `/wek/inputs`: 15 expression scores of that face |
| 3. Classification | Wekinator, [`wekinator/5emotions`](../wekinator/5emotions) | 13 scores | OSC `/wek/outputs`: class 1-5 |
| 4. Behaviour | Processing, [`processing/mirror.pde`](../processing/mirror.pde) | Faces and emotion | One serial line, 30 times per second |
| 5. Actuation | Arduino, [`arduino/mirror/mirror.ino`](../arduino/mirror/mirror.ino) | Serial line | Steppers, servo, LEDs |

All OSC traffic stays on the computer (`127.0.0.1`): Processing listens on port 12000, Wekinator on 6448.

**Serial line** (Processing to Arduino, 115200 baud), for example `12.5,-3.0,255,180,40,-0.25,0.420,0.00`:

| Value | Meaning |
|---|---|
| `x`, `y` | Rotation and tilt, in degrees. Tilt goes from 0 (head all the way down, at rest) to `Y_MAX_DEG` (up) |
| `r`, `g`, `b` | Solid LED colour, 0-255 |
| `c` | Convexity, from -1 (concave) to +1 (convex) |
| `phase`, `mix` | Rainbow position (0-1), and the blend between the solid colour (0) and the rainbow (1) |

The Arduino discards any line that has the wrong number of values or anything that is not a number.

## Responsibilities

| Layer | Decides | Never does |
|---|---|---|
| Python | What is in the image | Decide what the mirror does |
| Wekinator | Which emotion | Know where the face is |
| Processing | Everything about behaviour: states, angles, colours, curve | Drive hardware directly |
| Arduino | Nothing: executes numbers within safety limits | Know about people |

To change the experience you edit only Processing, and nothing needs re-uploading to the Arduino.

## Key algorithms (in `mirror.pde`)

- **Closed-loop tracking.** The camera turns with the mirror, so the face's offset from the image centre is the pointing error. At each new camera frame, the target becomes the current angle plus `CLOSED_LOOP_GAIN` × the error. The mirror stops by itself when the face is centred. Each frame is used only once, because the Wi-Fi image arrives late.
- **Centre box.** While the face stays inside a box in the middle of the image (`CENTRE_BOX_W` × `CENTRE_BOX_H`), the mirror does not move. When the face leaves the box, the mirror re-centres it to within `DEAD_ZONE_DEG`, then rests again. This keeps the mirror still while a person shifts a little, and the twin shows the box and the face in a small camera view.
- **State machine.** idle, greeting, tracking and sad (see the diagram at the top of `mirror.pde`). Every colour, rainbow and shape change is smoothed, so changing state never jumps.
- **Expressive surface.** Each emotion has its own shape, driven by the fast servo: flat (neutral), concave (happy), one quick push (wink), a 4 Hz shake (angry) and a slow push to convex (blow). The speed of the change is part of the gesture, so each uses its own smoothing.
- **Emotion hold.** An emotion counts only after Wekinator has repeated it for 0.3 s, so a one-frame mistake does not flash the LEDs.
- **Digital twin** (`twin.pde`). A 3D view of the mirror drawn from the same values that are sent to the Arduino, plus a text panel showing every stage of the pipeline.

## What we added beyond the provided examples

The course example passed one Wekinator class from Processing to the Arduino. On top of that we built:

| Part | Addition |
|---|---|
| Perception | A MediaPipe tracker that picks the closest face and sends 13 blendshape scores, and a preview that scales to the frame size. The ESP32-CAM is mounted upside down, so its image is turned 180° first (`ROTATE_MIRROR_CAMERA`) |
| Calm tracking | A centre box in the image: the mirror rests while the face stays inside it |
| Machine learning | A 5-class classifier trained on facial blendshapes instead of mouse position |
| Behaviour | The closed loop, the 5-state machine, optics-based convexity, and smooth fades |
| Simulation | Three input modes (`mirror camera`, `laptop camera`, `mouse`) to test without hardware |
| Communication | An 8-value serial protocol with validation, and a non-blocking Arduino loop |
| Hardware support | LED timing chosen so it does not disturb the serial port, coils switched off when idle, and software limits |
| Tools | [`tools/calibration`](../tools/calibration), and a generated circuit diagram |

## Third-party code

- **ESP32-CAM:** Espressif's `CameraWebServer` example. The only changes are the camera model (`AI_THINKER`) and the Wi-Fi credentials, which are moved to `secrets.h`.
- **Libraries:** MediaPipe Face Landmarker model (`face_landmarker.task`), oscP5, AccelStepper and Adafruit NeoPixel. The servo pulse is made by the Arduino's timer TCA0, not the Servo library: `strip.show()` switches interrupts off for about 2 ms, which stretched pulses from the Servo library and made the servo twitch during the idle rainbow.

## Settings

Every value you can change is at the top of each file, with its unit and purpose. In `mirror.ino` and `mirror.pde` they are grouped by how often you touch them: **setup** (every start), **calibrate** (measured once on the real mirror, see [calibration.md](calibration.md)) and **tune** (how the mirror behaves). Five calibrated values live in both files; when Processing connects, the Arduino prints its own so they can be compared.
