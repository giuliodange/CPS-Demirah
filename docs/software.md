# Software design

## Pipeline

| Step | Program | Input | Output |
|---|---|---|---|
| 1. Camera | ESP32-CAM, [`esp32_cam/CameraWebServer`](../esp32_cam/CameraWebServer) | Image | MJPEG stream over Wi-Fi: `http://<ip>:81/stream` |
| 2. Perception | [`python/face_tracker.py`](../python/face_tracker.py) with MediaPipe Face Landmarker | Stream | OSC `/face` and `/face2`: `present, cx, cy, size` of the two largest faces. OSC `/wek/inputs`: 15 expression scores of the largest face |
| 3. Classification | Wekinator, [`wekinator/5emotions`](../wekinator/5emotions) | 15 scores | OSC `/wek/outputs`: class 1-5 |
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
- **State machine.** idle, greeting, tracking, shy and sad (see the diagram at the top of `mirror.pde`). Every colour, rainbow and shape change is smoothed, so changing state never jumps.
- **Zoom-keeping convexity.** Distance is estimated as `k / face size`. A concave mirror magnifies by `f / (f − d)`, so to keep the zoom constant the focal length must be `f = zoom · d / (zoom − 1)`. The curve depth then follows from the sphere of radius `2f`.
- **Emotion hold.** An emotion counts only after Wekinator has repeated it for 0.3 s, so a one-frame mistake does not flash the LEDs.
- **Digital twin** (`twin.pde`). A 3D view of the mirror drawn from the same values that are sent to the Arduino, plus a text panel showing every stage of the pipeline.

## What we added beyond the provided examples

The course example passed one Wekinator class from Processing to the Arduino. On top of that we built:

| Part | Addition |
|---|---|
| Perception | A MediaPipe tracker that finds two faces and sends 15 blendshape scores, and a preview that scales to the frame size. The ESP32-CAM is mounted upside down, so its image is turned 180° first (`ROTATE_MIRROR_CAMERA`) |
| Two people | The shy state rests on one face for `SHY_HOLD_S`, then glances to the other over `SHY_GLANCE_S` on an ease-in-out curve, with slow smoothing, so it never jumps |
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

Every value you can change is in the `CONFIG` block at the top of each file, with its unit and purpose. Values still to be measured are marked `TODO CALIBRATE`, with the step of [calibration.md](calibration.md) that covers them.
