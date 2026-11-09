# Debugging

Follow the data from the camera to the motors. The first check that fails is where the problem is.

```
ESP32-CAM -> Python + MediaPipe -> Wekinator -> Processing -> Arduino -> motors, servo, LEDs
```

## 1. Does the camera stream?

**Check:** open `http://<camera-ip>:81/stream` in a browser. You should see the image. Close the tab afterwards, because the stream accepts only one viewer.

| If not | Fix |
|---|---|
| The page doesn't load | Turn on the phone hotspot, keep its settings screen open, and press reset on the ESP32-CAM. Read the new address in its Serial Monitor (115200 baud) |
| `Brownout detector was triggered` | Weak 5 V: power it from the Power Board's `5V` pin, not `VCC` |
| `Camera init failed` | Reseat the camera's ribbon cable |

## 2. Does Python see the face?

**Check:** run `.venv/bin/python python/face_tracker.py`. The preview should show green dots on your face and `faces=1`.

| If not | Fix |
|---|---|
| It waits 30 s, then can't open the stream | `MIRROR_CAMERA` has an old address, or the browser tab is still open |
| With `--laptop`: it can't open the camera | Allow the terminal app in System Settings > Privacy & Security > Camera |

## 3. Does Wekinator classify?

**Check:** with the project in **Run**, the **OSC In** light is green and the output class follows your face.

| If not | Fix |
|---|---|
| OSC In is off | The tracker isn't running, or the project isn't listening on port 6448 |
| Wekinator reports the wrong number of inputs | The project must have 15 inputs, matching `BLENDSHAPES_TO_SEND` |
| Wrong class | Record more examples of the confused classes, then train again (see [machine-learning.md](machine-learning.md)) |

## 4. Does Processing receive and decide?

**Check:** the HUD of `mirror.pde` shows every stage:

| HUD line | Expected |
|---|---|
| `STATE` | Changes as people arrive and leave |
| `RECEIVED` | Matches the Python preview |
| `EMOTION` | Matches Wekinator, about 0.3 s later |
| `ANGLES` | Moves towards the face |
| `SENT` | Changes as the mirror moves |

| If not | Fix |
|---|---|
| `RECEIVED` is frozen | Another program is using port 12000 |
| The twin turns away from the face | Wrong sign: see [calibration.md](calibration.md), step 3 |
| The twin wobbles around the face | `CLOSED_LOOP_GAIN` is too high (calibration step 5) |

## 5. Does the Arduino accept the line?

**Check:**
1. Stop Processing, then open the Arduino Serial Monitor (115200 baud, **New Line**).
2. You should see `mirror ready`.
3. Send `10,0,255,0,0,0,0,0`. The base turns and the LEDs turn red.

| If not | Fix |
|---|---|
| Processing stops with a port error | The Serial Monitor is still open, or `SERIAL_PORT_NAME` is wrong |
| `line discarded` once at the start | Normal: the first line is often cut |
| `line discarded` every time | The board has a different sketch: upload `arduino/mirror/mirror.ino` |

## 6. Do the motors, servo and LEDs work?

**Check:** use [`tools/calibration`](../tools/calibration/calibration.ino) to move each part by hand.

| Symptom | Fix |
|---|---|
| The driver's LEDs blink, but the motor doesn't turn | The motor cable isn't plugged into `J1`, the supply is too weak, or `MAX_SPEED` is too high |
| The driver's LEDs stay off | Check the shared GND, the `IN` wires and the driver's supply |
| The motor buzzes | The `IN` wires are in the wrong order, or the speed is too high |
| The base doesn't return to its mark | It is losing steps: lower `MAX_SPEED` and `ACCEL` |
| The servo trembles | Test it without the mirror. If it is still, it is the load. If it still trembles, it is the 5 V supply |
| The servo twitches when the LEDs change | `strip.show()` briefly stops interrupts. Expected occasionally in idle (the rainbow) |
| The LEDs are dark | The data wire must go to `Din`, not `DO`. Check the 330 Ω resistor and the shared GND |
