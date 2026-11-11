# Calibration

Do the steps **in order**: each one relies on the ones before.

**Where the values go**

| File | Block | Holds |
|---|---|---|
| `arduino/mirror/mirror.ino` | `1. CALIBRATE` | Steps per degree, limits, speeds, servo pulses |
| `processing/mirror.pde` | `2. CALIBRATE` | A copy of the limits and speeds, plus the camera and convexity values |

Five values live in both files: `X_MIN_DEG`, `X_MAX_DEG`, `Y_MAX_DEG`, `X_MAX_DEG_PER_S` and `Y_MAX_DEG_PER_S`. When Processing connects, the Arduino prints its own in the Processing console:

```
[Arduino] mirror ready. Copy to mirror.pde: X_MIN_DEG = -80, X_MAX_DEG = 80, Y_MAX_DEG = 30, X_MAX_DEG_PER_S = 16.0, Y_MAX_DEG_PER_S = 2.8
```

Copy that line's numbers into `mirror.pde` whenever you change `mirror.ino`.

**Tool:** upload [`tools/calibration/calibration.ino`](../tools/calibration/calibration.ino), then open the Serial Monitor at **115200 baud** with the line ending set to **New Line**.

| Command | Action |
|---|---|
| `x 100` / `y 100` | Move stepper X or Y by 100 steps. A negative number moves the other way. The new positions are printed when the move ends |
| `p` | Print both stepper positions |
| `z` | Call the current positions 0 |
| `v 700` | Set the top speed of both steppers, in steps per second (it starts at 300) |
| `s 1500` | Send the servo a 1500 µs pulse |
| `l 255 0 0` | Set all LEDs to red, green, blue. `l 0 0 0` turns them off |
| `d` | Switch the stepper coils off |

**This sketch has no limits.** Start with small moves (100 steps, or 50 µs on the servo).

## Step 1: Safe range

1. Put the mirror at rest by hand: base centred, head all the way down (cord slack).
2. Type `z`, so that position becomes zero.
3. Move each axis in small steps up to the furthest safe position, without pulling the cord too far or twisting the cables. Note the positions it prints.
   - **X** goes both ways from 0: find a limit on each side.
   - **Y** goes one way only, from 0 (down) to the highest safe tilt. Positive `y` must lift the head. If it lowers it, `STEPS_PER_DEG_Y` will be negative.
4. For the servo, find the pulse that leaves the mirror flat and the furthest safe pulse, with `s`.

## Step 2: Scale (commanded degrees = real degrees)

| Value (`mirror.ino`) | How |
|---|---|
| `STEPS_PER_DEG_X` | Mark the base with tape, type `x 1000` and measure the angle it turns. Then 1000 ÷ angle |
| `STEPS_PER_DEG_Y` | Type `y 2000` and measure the tilt change with a phone inclinometer. Then 2000 ÷ angle |
| `X_MIN_DEG`, `X_MAX_DEG`, `Y_MAX_DEG` | Positions from step 1 ÷ `STEPS_PER_DEG`. **Copy to `mirror.pde`** |

Then in `mirror.pde`, set `Y_LEVEL_DEG`: the tilt, in degrees from 0, where the mirror looks straight ahead (inclinometer at 0°). Idle rests there.

**Check:** upload `mirror.ino`, then send `30,0,0,0,0,0,0,0` from the Serial Monitor. The base must turn 30°. Then send `0,0,0,0,0,0,0,0`: it must return to the tape mark. If it doesn't, it is losing steps: see step 5.

## Step 3: Directions

1. **Motor matches the twin.** Run `mirror.pde` with `INPUT = "mouse"` and `SIMULATION_ONLY = false`. If a real axis moves opposite to the twin, make its `STEPS_PER_DEG` negative in `mirror.ino`. Tilt 0 is all the way down, positive tilt is up.
2. **The loop corrects towards you.** Set `INPUT = "mirror camera"` and stand to one side. If the mirror turns away and runs to a limit, flip `INVERT_X`. Check `INVERT_Y` the same way, standing higher, then lower.

## Step 4: Camera field of view

Hold the camera 1 m from a wall and measure the width it sees. Then `CAMERA_HFOV_DEG` = 2 × atan(width ÷ 2 ÷ 1 m). Do the same with the height for `CAMERA_VFOV_DEG`.

In a closed loop this only changes the **speed**, not where the mirror stops: too high makes it nervous, too low makes it slow. The starting values, 55° and 42°, are typical for the OV2640.

## Step 5: Speed and reactivity

Change one value at a time.

1. **Top speeds** (`mirror.ino`). With `calibration.ino`, start at `v 400` and go up by 100:
   - **X:** `x 2000`, then `x -2000`. It must return to the tape mark.
   - **Y:** with the mirror fitted, start at the bottom (`z` there), then `y 2500` (up) and `y -2500` (down). Lifting is the hard part: a stepper gets weaker as it speeds up.
   - The first speed where a motor buzzes without moving, or does not come back to its mark, is too fast. Use about 20% less for `MAX_SPEED_X` and `MAX_SPEED_Y`. If it still loses steps at the start of a move, lower `ACCEL_X` or `ACCEL_Y`.
2. **Copy the speeds to `mirror.pde`:** `X_MAX_DEG_PER_S` = `MAX_SPEED_X` ÷ `STEPS_PER_DEG_X`, and the same for Y. The Arduino prints both. If Processing believes the mirror is faster than it is, the tracking overshoots.
3. **`CLOSED_LOOP_GAIN`** (`mirror.pde`): start at 0.35. Take a quick step sideways. If the mirror overshoots and swings back, lower it by 0.1. If it follows lazily, raise it by 0.1.
4. **`DEAD_ZONE_DEG`:** stand still. If the mirror keeps correcting, raise it by 0.5 at a time until it stays still.
5. **`FAST_SMOOTHING`:** 0.3 is reactive. If the motion is jerky, use 0.2.

## Step 6: Convexity

| Value | How |
|---|---|
| `SERVO_FLAT_US` (`mirror.ino`) | With `s`, the pulse that leaves the mirror flat |
| `SERVO_RANGE_US` (`mirror.ino`) | Pulse for the deepest curve minus the flat pulse, without the sign. Make it negative if the curve goes the wrong way |
| `MAX_SAG_MM` (`mirror.pde`) | Depth of the deepest curve, in mm |
| `DISTANCE_CALIB_K` (`mirror.pde`) | Stand exactly 1 m from the camera and read `size` on the screen's `CONVEXITY` line |

**If the servo keeps moving while you stand still,** try these one at a time: raise `CONVEXITY_DEAD_ZONE` to 0.1, or lower `SIZE_SMOOTHING` to 0.03.

## Step 7: LEDs and power

1. Type `l 255 255 255` and check that all 75 LEDs light up evenly.
2. Run the full system for a few minutes and watch for:
   - the ESP32-CAM restarting (`Brownout` in its Serial Monitor),
   - weak motors,
   - the Power Board reaching its current limit.

   Any of these means the 5 V supply is sagging, so lower `MAX_BRIGHTNESS`.

Stepper Y keeps its coils on all the time, because gravity pulls the head down: it runs warm, which is normal. Stepper X rests 2 s after it stops.
