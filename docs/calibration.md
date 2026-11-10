# Calibration

Do the steps **in order**: each one relies on the ones before. Every value to measure is marked `TODO CALIBRATE` in the code, with the number of its step.

**Tool:** upload [`tools/calibration/calibration.ino`](../tools/calibration/calibration.ino), then open the Serial Monitor at **115200 baud** with the line ending set to **New Line**.

| Command | Action |
|---|---|
| `x 100` / `y 100` | Move stepper X or Y by 100 steps. A negative number moves the other way |
| `p` | Print both stepper positions |
| `z` | Call the current positions 0 |
| `s 1500` | Send the servo a 1500 µs pulse |
| `l 255 0 0` | Set all LEDs to red, green, blue. `l 0 0 0` turns them off |
| `d` | Switch the stepper coils off |

**This sketch has no limits.** Start with small moves (100 steps, or 50 µs on the servo).

## Step 1: Safe range

1. Put the mirror at rest by hand: base centred, head all the way down (cord slack).
2. Type `z`, so that position becomes zero.
3. Move each axis in small steps up to the furthest safe position, without pulling the cord too far or twisting the cables. Read the position with `p` and note it down.
   - **X** goes both ways from 0: find a limit on each side.
   - **Y** goes one way only, from 0 (down) to the highest safe tilt. Positive `y` must lift the head; if it does not, make `STEPS_PER_DEG_Y` negative.
4. For the servo, find the furthest safe pulse in each direction with `s`.

## Step 2: Scale (commanded degrees = real degrees)

| Value (`mirror.ino`) | How |
|---|---|
| `STEPS_PER_DEG_X` | Mark the base with tape, type `x 1000` and measure the angle it turns. Then 1000 ÷ angle |
| `STEPS_PER_DEG_Y` | Type `y 300` and measure the tilt change with a phone inclinometer. Then 300 ÷ angle |
| `X_MIN_DEG`, `X_MAX_DEG`, `Y_MAX_DEG` | Positions from step 1 ÷ `STEPS_PER_DEG`. Use **the same values in `mirror.pde`**. `Y_MIN_DEG` stays 0 |
| `Y_LEVEL_DEG` (`mirror.pde`) | The tilt, from 0, where the mirror looks straight ahead (inclinometer at 0°). Idle rests here |

**Check:** upload `mirror.ino`, then send `30,0,0,0,0,0,0,0` from the Serial Monitor. The base must turn 30°. Then send `0,0,0,0,0,0,0,0`: it must return to the tape mark. If it doesn't, it is losing steps, so lower `MAX_SPEED` and `ACCEL`.

## Step 3: Directions

1. **Motor matches the twin.** Run `mirror.pde` with `INPUT = "mouse"` and `SIMULATION_ONLY = false`. If a real axis moves opposite to the twin, make its `STEPS_PER_DEG` negative. Tilt 0 is all the way down, positive tilt is up.
2. **The loop corrects towards you.** Set `INPUT = "mirror camera"` and stand to one side. If the mirror turns away and runs to a limit, flip `INVERT_X`. Check `INVERT_Y` the same way, standing higher, then lower.

## Step 4: Camera field of view

Hold the camera 1 m from a wall and measure the width it sees. Then `CAMERA_HFOV_DEG` = 2 × atan(width ÷ 2 ÷ 1 m). Do the same with the height for `CAMERA_VFOV_DEG`.

In a closed loop this only changes the **speed**, not where the mirror stops: too high makes it nervous, too low makes it slow. The starting values, 55° and 42°, are typical for the OV2640.

## Step 5: Reactivity (rotation and tilt)

Change one value at a time:

1. **`MAX_SPEED`, `ACCEL`** (`mirror.ino`): raise them until a quick move skips steps, then go back about 20%.
2. **`CLOSED_LOOP_GAIN`** (`mirror.pde`): start at 0.3. Take a quick step sideways, and raise the gain by 0.1 at a time until the mirror overshoots and swings back. Then go back 0.1-0.2.
3. **`DEAD_ZONE_DEG`:** stand still. If the mirror keeps correcting, raise it by 0.5 at a time until it stays still.
4. **`XY_SMOOTHING`:** 0.3 is reactive. If the motion is jerky, use 0.2.

## Step 6: Convexity (calm, never trembling)

| Value | How |
|---|---|
| `SERVO_FLAT_US` (`mirror.ino`) | With `s`, the pulse that leaves the mirror flat |
| `SERVO_RANGE_US` | Flat pulse minus the pulse for the deepest curve. It is negative if the deepest curve needs the longer pulse |
| `MAX_SAG_MM` (`mirror.pde`) | Depth of the deepest curve, in mm |
| `DISTANCE_CALIB_K` | Stand exactly 1 m from the camera and read `size` on the HUD's `CONVEXITY` line |

**If the servo trembles,** try these one at a time: raise `CONVEXITY_DEAD_ZONE` to 0.1, lower `SIZE_SMOOTHING` to 0.03, or raise `SERVO_DEAD_BAND_US` to 20.

## Step 7: LEDs and power

1. Type `l 255 255 255` and check that all 75 LEDs light up evenly.
2. Run the full system for a few minutes and watch for:
   - the ESP32-CAM restarting (`Brownout` in its Serial Monitor),
   - weak motors,
   - the Power Board reaching its current limit.

   Any of these means the 5 V supply is sagging, so lower `MAX_BRIGHTNESS`.

`KEEP_Y_POWERED`: lift the head and type `d`. If the head sinks, set `KEEP_Y_POWERED = true`.
