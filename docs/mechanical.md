# Mechanical design

We did not start from a kit. We designed the whole structure and ordered only the parts we needed. The robot has three degrees of freedom, each driven by its own actuator.

![Model](media/model.jpg)

| Motion | Actuator | Mechanism | Why |
|---|---|---|---|
| Rotation of the body (X) | Stepper, 12 V | The body sits on a large ball bearing that we made: steel balls running between two printed rings, as in a salad spinner | A wide bearing carries the weight of the body and head without wobbling, and turns with very little friction, so a small stepper is enough |
| Tilt of the head (Y) | Stepper, 5 V | The stepper sits in the base and pulls a cord. The cord runs over **two pulleys** inside the body, up to the head | The motor's weight stays low, which keeps the body light and stable. The pulleys only **redirect** the cord around the curve of the body. They add no mechanical advantage. Gravity pulls the head back down, so the cord only needs to pull |
| Concavity of the mirror | Servo SG90 | The servo drives a **horizontal rack** that pushes against the back wall of the mirror | Pushing at the centre while the frame holds the rim bends the mirror into a curve. A servo holds its position without feedback from us |

## Structure

| Part | Material | Notes |
|---|---|---|
| Base | 3D print | Hides the rotation stepper, the bearing and the electronics |
| Body | 3D print | An organic, curved shape. Its openings house the two pulleys and keep it light |
| Head | 3D print | Carries the mirror, the rack, the servo and the ESP32-CAM |
| Mirror frame | Laser-cut acrylic ring | Holds the mirror at its rim and hides the 75 LEDs |
| Mirror | TODO | Not fitted yet |

## Design decisions

- **Camera on the head:** the camera turns with the mirror, so the mirror can centre the face without knowing the exact gear ratios or the camera's field of view (see [software.md](software.md)).
- **Weight kept low:** both steppers are low in the structure. Only the servo, the rack, the camera and the LEDs move with the head.
- **No end stops:** the startup position counts as zero, and software limits stop the motion (see [calibration.md](calibration.md)).

## Not documented yet

| Item | Status |
|---|---|
| Photos of the bearing, pulleys and rack | TODO, see [media](media/README.md) |
| Ball bearing: number and size of the balls | TODO |
| Rack and pinion: module and travel | TODO |
| CAD files | Not included in this repository |
