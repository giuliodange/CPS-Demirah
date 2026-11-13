# Calibration and troubleshooting

## Calibration

Needed once for a new build. Upload [`arduino/calibration`](../arduino/calibration/calibration.ino) and open the Serial Monitor at **115200 baud**, line ending **New Line**. This sketch has no limits: start with small moves.

| Command | Action |
|---|---|
| `x 100`, `y 100` | Move stepper X or Y by 100 steps (negative = other way). The position is printed when it stops |
| `z` | Call the current position 0 |
| `v 700` | Set the top speed, in steps per second |
| `s 1500` | Send the servo a 1500 µs pulse |
| `l 255 0 0` | Set all LEDs to a colour |

1. **Range.** Put the mirror at rest by hand (base centred, head down) and type `z`. Move each axis to its furthest safe position and note the steps.
2. **Scale.** Type `x 1000` and measure the angle with tape on the base: `STEPS_PER_DEG_X` = 1000 ÷ angle. Do the same for Y with a phone inclinometer. If positive `y` lowers the head, make `STEPS_PER_DEG_Y` negative.
3. **Limits.** `X_MIN_DEG`, `X_MAX_DEG`, `Y_MAX_DEG` = the positions from step 1 ÷ steps per degree.
4. **Speed.** Raise `v` by 100 until a motor buzzes without moving or misses its mark, then use 20% less as `MAX_SPEED_X` and `MAX_SPEED_Y`. Test Y while it lifts the head.
5. **Servo.** With `s`, find the pulse that leaves the mirror flat (`SERVO_FLAT_US`) and the change to the deepest curve (`SERVO_RANGE_US`).
6. **Copy to Processing.** Write these values in the `CALIBRATE` block of `mirror.ino` and upload it. When Processing connects, the console shows `[Arduino] mirror ready. Copy to mirror.pde: ...`: copy those five numbers into `mirror.pde`. Also set `Y_LEVEL_DEG`, the tilt at which the mirror looks straight ahead.
7. **Tracking.** Stand to one side. If the mirror turns away from you, flip `INVERT_X` (or `INVERT_Y` for the tilt). If it overshoots, lower `CLOSED_LOOP_GAIN` by 0.1. If it moves too often, enlarge `CENTRE_BOX_W` and `CENTRE_BOX_H`.

## Troubleshooting

Follow the data from the camera to the motors. The first check that fails is where the fault is.

| Check | Where | If it fails |
|---|---|---|
| The camera streams | `http://<camera-ip>:81/stream` in a browser (close it afterwards: one viewer only) | Hotspot off, wrong IP in `face_tracker.py`, or weak 5 V at the camera |
| Python sees the face | Green dots in the tracker's preview | Lighting, focus, or `ROTATE_MIRROR_CAMERA` |
| Wekinator classifies | "OSC In" light green, the class follows your face | Project not in Run, or not 15 inputs |
| Processing receives | `RECEIVED` and `EMOTION` lines on screen | `INPUT` setting, or OSC port 12000 in use |
| The simulation moves correctly | The 3D view | A behaviour setting in `mirror.pde` |
| The Arduino receives | `SENT` line, and `SERIAL` is not "off" | `SERIAL_PORT_NAME`, `SIMULATION_ONLY`, or the Arduino IDE's Serial Monitor is open |

If the simulation is right and the real mirror is not, the fault is in the calibration or the hardware:

| Symptom | Fix |
|---|---|
| An axis moves the wrong way | Make its `STEPS_PER_DEG` negative |
| The mirror runs away from the face | Flip `INVERT_X` or `INVERT_Y` |
| It overshoots the face | Check `X_MAX_DEG_PER_S` and `Y_MAX_DEG_PER_S` against the Arduino's line, then lower `CLOSED_LOOP_GAIN` |
| The head buzzes but does not lift | Lower `MAX_SPEED_Y` and `ACCEL_Y`, and `Y_MAX_DEG_PER_S` with them |
| It points wrong after a while | A motor lost steps: put the mirror at rest by hand and press reset on the Arduino |
| The servo does not reach flat, or strains at the end | Adjust `SERVO_FLAT_US`, reduce `SERVO_RANGE_US` |
| The camera restarts (`Brownout`) | The 5 V supply sags: lower `MAX_BRIGHTNESS` |
