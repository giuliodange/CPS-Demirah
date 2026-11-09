# Hardware design

## Components

| Component | Task | Why we chose it |
|---|---|---|
| Arduino Nano Every | Receives one line of text from Processing and drives the motors, servo and LEDs | Small, 5 V logic, enough pins and memory, and supported by AccelStepper, Servo and NeoPixel |
| Stepper X, 12 V (TODO: model) + Seeed ULN2003 driver | Rotates the body | Open-loop position control with no encoder. It holds its position when stopped |
| Stepper Y, 28BYJ-48 5 V + Seeed ULN2003 driver | Pulls the tilt cord | Cheap and geared. Its gearbox holds the head when the coils are off |
| Servo SG90 | Pushes the rack: concavity | Small and light enough to sit in the head. It holds a position from a single signal |
| 75 × WS2812 LEDs | Colour around the mirror | Each LED is controlled separately over one data wire, which makes the rainbow and the fades possible |
| ESP32-CAM (OV2640) | Camera on the head, streaming over Wi-Fi | Light and wireless, so the camera can turn with the mirror without a USB cable |
| Power Board (custom) | Supplies 12 V and 5 V. Limits the current to 2 A | Keeps the motors and LEDs off the computer's USB port |
| 330 Ω resistor | On the LED data wire | Protects the first LED from voltage spikes on the data line |
| 1000 µF capacitor | Across the LEDs' 5 V and GND | Absorbs the current surge when the LEDs switch on |

## Wiring

![Circuit diagram](circuit.svg)

The diagram is drawn by [`tools/circuit_diagram.py`](../tools/circuit_diagram.py). Run it again after changing the wiring.

| Part | Arduino | Power |
|---|---|---|
| Driver X, IN1-IN4 | D2, D3, D4, D5 | `VM` to +12 V (TODO: confirm `VM`/`VCC` and the switch position), `GND` |
| Driver Y, IN1-IN4 | D7, D8, D11, D12 | `VM` and `VCC` to +5 V, `GND` |
| Servo signal (orange) | D9 | Red to +5 V, brown to GND |
| LED `Din`, through 330 Ω | D6 | `+5V` and `GND`, with the 1000 µF capacitor across them |
| ESP32-CAM | — | `5V` pin (not `VCC`, which is an output) and `GND` |

The Seeed driver's header reads `VM, VCC, GND, IN4, IN3, IN2, IN1`, so follow the printed labels rather than the order of the pins.

## Powering safely

- **Shared ground:** the Power Board, the Arduino and the ESP32-CAM share GND, so every signal has the same reference.
- **No back-feeding:** the Arduino's 5V pin is **not** connected to the Power Board. The Arduino is powered over USB, so the two supplies never push against each other.
- **Current limit:** the Power Board limits the current to 2 A.
- **LED brightness cap:** `MAX_BRIGHTNESS = 60` (out of 255) in `mirror.ino` caps the LED current.
- **Idle coils off:** each stepper's coils switch off 2 s after it stops, which reduces heat and current.

### Power budget

| Load | Supply | Estimated current |
|---|---|---|
| Stepper Y | 5 V | about 0.25 A |
| Servo SG90 | 5 V | 0.1-0.25 A moving, up to about 0.65 A if blocked |
| ESP32-CAM | 5 V | up to about 0.3 A at Wi-Fi peaks |
| 75 LEDs at `MAX_BRIGHTNESS = 60` | 5 V | worst case 75 × 60 mA × 60/255 ≈ **1.06 A** in full white. The rainbow uses about a third of that |
| Stepper X | 12 V | TODO: measure |
| **Total at 5 V, worst case** | | **about 2.2 A**, just above the 2 A limit |

The worst case needs everything at once: white LEDs and a blocked servo. The colours used by the mirror stay well below full white. If the board reaches its limit, lower `MAX_BRIGHTNESS`.

**TODO:** confirm the Power Board's input rating, its 12 V and 5 V outputs, and the current of stepper X.
