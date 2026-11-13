# Software design

## Pipeline

| Step | Program | Input | Output |
|---|---|---|---|
| 1. Camera | ESP32-CAM, [`esp32_cam/CameraWebServer`](../esp32_cam/CameraWebServer) | Image | MJPEG stream over Wi-Fi: `http://<ip>:81/stream` |
| 2. Perception | [`python/face_tracker.py`](../python/face_tracker.py) with MediaPipe Face Landmarker | Stream | OSC `/face`: `present, cx, cy, size` of the largest (closest) face. OSC `/wek/inputs`: 15 expression scores of that face |
| 3. Classification | Wekinator, k-NN classifier (see [machine-learning.md](machine-learning.md)) | 15 scores | OSC `/wek/outputs`: class 1-4 |
| 4. Behaviour | Processing, [`processing/mirror.pde`](../processing/mirror.pde) | Faces and emotion | One serial line, 30 times per second |
| 5. Actuation | Arduino, [`arduino/mirror/mirror.ino`](../arduino/mirror/mirror.ino) | Serial line | Steppers, servo, LEDs |

All OSC traffic stays on the computer (`127.0.0.1`): Processing listens on port 12000, Wekinator on 6448.

The whole product runs from **one Arduino sketch**, `mirror.ino`, and one Processing sketch. Nothing is changed or re-uploaded between features: the states and expressions follow each other by themselves. (`tools/calibration` is a separate sketch used only while building, to measure the limits.)

### Why this pipeline

| Choice | Reason |
|---|---|
| MediaPipe in Python, before Wekinator | Wekinator works best with a few meaningful inputs. MediaPipe turns each image into 15 expression scores, so the model learns expressions, not pixels, and works with new faces and lighting |
| Wekinator only for the expression | Recognising an expression is the part that must be learned from examples. Finding where the face is does not need learning, so it goes straight to Processing and stays fast and exact |
| All behaviour in Processing | One place decides everything. The experience can be changed and tested on screen without touching the hardware |
| A simple Arduino | It only executes numbers within safety limits, so it never needs re-uploading and cannot be confused by a software change |
| OSC and one text line over serial | Both are easy to read and to test by hand: any stage can be replaced by typed values |
| The camera on the mirror, over Wi-Fi | It makes the tracking a closed loop, with no cable to the moving head |

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
- **Expressive surface.** Each expression has its own shape, driven by the servo: flat (neutral), concave (happy), one quick push (wink) and a slow pulse with rainbow LEDs (amazed). The speed of the change is part of the gesture, so the wink uses a faster smoothing.
- **Emotion hold.** An emotion counts only after Wekinator has repeated it for 0.3 s, so a one-frame mistake does not flash the LEDs.
- **On-screen simulation** (`twin.pde`). A 3D drawing of the mirror made from the same values that are sent to the Arduino, plus a text panel showing every stage of the pipeline. It is a development tool: the product is the physical mirror.

## What we added beyond the provided examples

The course example passed one Wekinator class from Processing to the Arduino. On top of that we built:

| Part | Addition |
|---|---|
| Perception | A MediaPipe tracker that picks the closest face and sends 15 blendshape scores, and a preview that scales to the frame size. The ESP32-CAM is mounted upside down, so its image is turned 180° first (`ROTATE_MIRROR_CAMERA`) |
| Calm tracking | A centre box in the image: the mirror rests while the face stays inside it |
| Machine learning | A classifier with 4 expression classes, trained on facial blendshapes instead of mouse position |
| Behaviour | The closed loop, the 4-state machine, a surface gesture for each expression, and smooth fades |
| Simulation | Three input modes (`mirror camera`, `laptop camera`, `mouse`) to test without hardware |
| Communication | An 8-value serial protocol with validation, and a non-blocking Arduino loop |
| Hardware support | A servo pulse made by a hardware timer so the LEDs cannot disturb it, a resting base stepper, and software limits |
| Tools | [`tools/calibration`](../tools/calibration), and a generated schematic |

## Sources

All the code in this repository is ours, except where listed here.

| Source | Used for | How we used it |
|---|---|---|
| [DE-Arm repository](https://github.com/IDE-GID-Cyberphysical-Systems/de-arm), `osc-routing` examples | The starting point given by the module: Wekinator's OSC output passed from Processing to the Arduino over serial | We kept the idea (OSC in, serial out) and wrote our own sketches |
| [Wekinator](http://www.wekinator.org/) by Rebecca Fiebrink | The machine learning model | Used unmodified, with our own training data |
| [MediaPipe Face Landmarker](https://ai.google.dev/edge/mediapipe/solutions/vision/face_landmarker) by Google | Face landmarks and blendshape scores (`face_landmarker.task`) | Library and pretrained model, used unmodified |
| [OpenCV](https://opencv.org/) and [python-osc](https://pypi.org/project/python-osc/) | Reading the video stream, sending OSC | Libraries |
| [oscP5](https://sojamo.de/libraries/oscP5/) by Andreas Schlegel | OSC in Processing | Library |
| [AccelStepper](https://www.airspayce.com/mikem/arduino/AccelStepper/) by Mike McCauley | Stepper acceleration and non-blocking steps | Library |
| [Adafruit NeoPixel](https://github.com/adafruit/Adafruit_NeoPixel) | Driving the WS2812B LEDs | Library |
| Espressif `CameraWebServer` example (ESP32 Arduino core) | The camera's video stream | Used as it is. Our only changes: the camera model (`AI_THINKER`) and the Wi-Fi details moved to `secrets.h` |
| [ATmega4809 datasheet](https://www.microchip.com/en-us/product/ATMEGA4809), timer TCA0 | The servo pulse | We wrote `servoBegin()` and `servoWrite()` from the datasheet. The Servo library is not used: updating the LEDs switches interrupts off for about 2 ms, which stretched its pulses and made the servo twitch |

## Settings

Every value you can change is at the top of each file, with its unit and purpose. In `mirror.ino` and `mirror.pde` they are grouped by how often you touch them: **setup** (every start), **calibrate** (measured once on the real mirror, see [calibration.md](calibration.md)) and **tune** (how the mirror behaves). Five calibrated values live in both files; when Processing connects, the Arduino prints its own so they can be compared.
