# Demirah: an interactive mirror

**Cyber Physical Systems, IDE 2026-27 (Imperial College London / Royal College of Art)**  
*Ruoxin Chen, Indiana Gothard, Giulio d'Angelantonio*

Demirah is a motorised mirror controlled by the user's face. A camera on the mirror tracks the face, and a machine learning model classifies its expression. The mirror rotates and tilts to keep the face centred, and changes the curvature of its surface and the colour of its LED ring according to the expression.

| Spinning view | Exploded view |
|---|---|
| ![Spinning view](docs/media/product/spin.gif) | ![Exploded view](docs/media/product/exploded.gif) |

## The product

| Front | Right | Left | Back |
|---|---|---|---|
| ![Front](docs/media/product/product-front.jpg) | ![Right](docs/media/product/product-right.jpg) | ![Left](docs/media/product/product-left.jpg) | ![Back](docs/media/product/product-back.jpg) |

**Video of the demo:** TODO, add the link.

## Concept

**Input:** the position and the expression of the user's face, read by a camera mounted on the mirror.
**Output:** mechanical movement on three axes (rotation, tilt, surface curvature), plus the colour of 75 LEDs.

The input and the output are on the same object: the user looks at the mirror, the camera on the mirror reads the face, and the response appears in the reflection. No other controller or instruction is needed, and the user stays within 1 m of the mirror.

### Interaction

| User input | System response | Justification |
|---|---|---|
| A face enters the camera image | The head traces one circle (2 s). LEDs turn yellow | Confirms that the face was detected before tracking starts |
| The face moves | The mirror rotates and tilts until the face is centred in the image. It does not move while the face stays inside a centre box (30% of the image) | Keeps the user in the reflection. The centre box prevents continuous small corrections |
| Neutral expression | White LEDs, flat surface | The reference state: an ordinary flat mirror |
| Smile | Yellow LEDs, the surface becomes concave | A concave mirror magnifies the reflection, so the response is visible in the image itself |
| Wink | Green LEDs, one short push of the surface (0.35 s) | A short input gets a short, single response |
| Amazed expression (raised eyebrows) | Rainbow LEDs, the surface oscillates between concave and convex (4 s period) | The largest expression gets the largest movement of the surface |
| No face for 3 s | The head tilts fully down, the LEDs fade from blue to off, and the mirror returns to idle | Shows that tracking has stopped, and resets the system for the next user |

An expression is shown after the classifier has reported it for 0.3 s. Every response can be repeated without resetting anything.

### Materials and construction

| Choice | Reason |
|---|---|
| Round mirror on a narrow neck, wide base | Low centre of mass: both steppers and all electronics are in the base, so the head can move without tipping the object |
| 3D-printed curved body | The cord for the tilt runs inside it, so no mechanism or cable is visible from the front |
| Flexible mirror sheet, pushed at its centre by a rack | The surface is itself an actuator: its curvature changes the reflection optically, with no screen |
| LEDs behind a laser-cut acrylic ring | The ring clamps the rim of the mirror and diffuses the LEDs into an even band of light |
| Camera mounted on the head | The camera moves with the mirror, which makes the tracking a closed loop (see below) |

## How it works

![Data flow](docs/pipeline.svg)

The camera turns with the mirror. The offset of the face from the centre of the image is therefore the pointing error, and the mirror moves until that error is zero. This is a **closed loop**: errors in the motors and in the calibration are corrected automatically.

| State | When | What the mirror does |
|---|---|---|
| idle | No face | The head is level. The surface oscillates slowly and a rainbow rotates around the LEDs |
| greeting | A face appears | The head traces one circle. LEDs turn yellow |
| tracking | After greeting | Follows the face when it leaves the centre box. LEDs and surface show the expression |
| sad | No face for 3 s | The head tilts fully down. LEDs fade from blue to off, then back to idle |

## Documentation

| Document | Contents | Rubric criterion |
|---|---|---|
| This page | Purpose, interaction, materials, photos | Overall concept |
| [docs/mechanical.md](docs/mechanical.md) | Mechanisms, materials, fabrication, design process | Mechanical design |
| [docs/assembly.md](docs/assembly.md) | Assembly in 10 steps | Mechanical design |
| [docs/hardware.md](docs/hardware.md) | Components, schematic, power | Hardware design |
| [docs/software.md](docs/software.md) | Pipeline, code, sources | Software design |
| [docs/machine-learning.md](docs/machine-learning.md) | Data, model, evaluation, improvements | Machine learning |
| [docs/calibration.md](docs/calibration.md) | Calibration, step by step | Hardware and software |
| [docs/debugging.md](docs/debugging.md) | Finding a fault, step by step | Hardware and software |

## Repository

| Folder | Contents |
|---|---|
| [`python/`](python) | `face_tracker.py`: camera, MediaPipe, OSC |
| [`processing/`](processing) | `mirror.pde` (behaviour) and `twin.pde` (on-screen simulation) |
| [`arduino/mirror/`](arduino/mirror) | `mirror.ino`: the one sketch that runs the mirror |
| [`esp32_cam/`](esp32_cam) | The ESP32-CAM streaming sketch |
| [`tools/`](tools) | A hardware calibration sketch, and the script that draws the schematic |
| [`docs/`](docs) | Documentation and media |

## Running it

1. **Install:**
   ```bash
   python3 -m venv .venv && .venv/bin/pip install -r python/requirements.txt
   ```
   Then install the Processing library **oscP5**, and the Arduino libraries **AccelStepper** and **Adafruit NeoPixel**.
2. **Upload once:** put `arduino/mirror/mirror.ino` on the Arduino Nano Every. For the camera, copy `esp32_cam/CameraWebServer/secrets.example.h` to `secrets.h`, fill in the Wi-Fi details, then upload the sketch to the ESP32-CAM.
3. **Start, in this order:**
   1. Put the mirror at rest by hand (base centred, head down), then switch on the power board.
   2. Wekinator: open the trained project and click **Run** (see [machine-learning.md](docs/machine-learning.md)).
   3. Processing: run `processing/mirror.pde`.
   4. The tracker:
      ```bash
      .venv/bin/python python/face_tracker.py
      ```

After this the system runs without intervention: all states and responses are handled by the one Arduino sketch and the one Processing sketch.

### Digital simulation

The Processing sketch also draws a 3D simulation of the mirror from the same values it sends to the Arduino. We used it to develop and test the behaviour without the hardware. It is a development tool, not the product. To use it, set `SIMULATION_ONLY = true` and `INPUT = "mouse"` in `mirror.pde`: the mouse is the face, and the keys 1-4 are the expressions.

| Simulation: idle | Simulation: tracking a smiling face |
|---|---|
| ![Idle](docs/media/twin/twin-idle.jpg) | ![Tracking](docs/media/twin/twin-tracking.jpg) |
