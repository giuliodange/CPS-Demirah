"""
face_tracker.py: PERCEPTION. It measures the people and decides nothing.

Every camera frame goes through 4 steps:
  1. Read the frame.
  2. MediaPipe finds the faces, as lists of 478 points on each face.
  3. Reduce the largest (closest) face to 4 numbers: present, cx, cy, size.  <-- the important part
  4. Send those numbers to Processing (/face), and the face's expression scores to
     Wekinator (/wek/inputs). Show everything in a preview.

Run it with:  python face_tracker.py            (the camera on the mirror)
         or:  python face_tracker.py --laptop   (the computer's camera, for testing)
Press q in the preview window to quit.
"""

import sys
import time
from pathlib import Path

import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions, vision
from pythonosc.udp_client import SimpleUDPClient

# ============================== CONFIG ==============================
MIRROR_CAMERA = "http://172.20.10.4:81/stream"  # The ESP32-CAM on the mirror. Its address is printed in its Serial Monitor.
ROTATE_MIRROR_CAMERA = True  # The ESP32-CAM is mounted upside down: turn its image 180 degrees before anything else.
MIRROR_IMAGE = True     # Flip the image like a selfie, so cx grows when the person moves to THEIR right.
MAX_FACES = 4           # How many faces MediaPipe looks for. Only the largest one is used.
PROCESSING_PORT = 12000 # UDP port Processing listens on. Must match OSC_PORT in the sketch.
WEKINATOR_PORT = 6448   # UDP port Wekinator listens on (its default).

# Blendshapes are MediaPipe's scores, from 0 to 1, for movements of the face. These help Wekinator
# tell neutral, happy, sad, angry and a wink apart. If you change this list, create a new Wekinator
# project with the same number of inputs (now 15) and train it again.
BLENDSHAPES_TO_SEND = [
    "mouthSmileLeft", "mouthSmileRight",       # happy
    "mouthFrownLeft", "mouthFrownRight",       # sad
    "mouthPressLeft", "mouthPressRight",       # sad, angry
    "browInnerUp",                             # sad
    "browDownLeft", "browDownRight",           # angry
    "noseSneerLeft", "noseSneerRight",         # angry
    "eyeBlinkLeft", "eyeBlinkRight",           # wink: one eye closed, the other open
    "eyeSquintLeft", "eyeSquintRight",         # wink
]
# ====================================================================

# With --laptop, use the computer's own camera (number 0) instead: set INPUT = "laptop camera" in mirror.pde.
USE_LAPTOP = "--laptop" in sys.argv
CAMERA = 0 if USE_LAPTOP else MIRROR_CAMERA

model_file = str(Path(__file__).with_name("face_landmarker.task"))
landmarker = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
    base_options=BaseOptions(model_asset_path=model_file),
    running_mode=vision.RunningMode.VIDEO,
    num_faces=MAX_FACES,
    output_face_blendshapes=True,
))
processing = SimpleUDPClient("127.0.0.1", PROCESSING_PORT)
wekinator = SimpleUDPClient("127.0.0.1", WEKINATOR_PORT)

camera = cv2.VideoCapture(CAMERA)
if not camera.isOpened():
    sys.exit("Cannot open the camera. For the mirror camera, check its address and the hotspot. "
             "For the laptop camera, allow your terminal app in System Settings > Privacy & Security > Camera.")

timestamp_ms = 0

while True:
    # --- 1. Read a frame ---
    got_frame, frame = camera.read()
    if not got_frame:
        # The Wi-Fi stream can drop for a moment: wait and connect again, instead of quitting.
        print("No image from the camera. Trying again...")
        camera.release()
        time.sleep(1)
        camera = cv2.VideoCapture(CAMERA)
        continue
    if ROTATE_MIRROR_CAMERA and not USE_LAPTOP:
        frame = cv2.rotate(frame, cv2.ROTATE_180)
    if MIRROR_IMAGE:
        frame = cv2.flip(frame, 1)
    height, width = frame.shape[:2]
    scale = max(width / 1000, 0.3)  # Text and dots follow the frame size: the ESP32-CAM's frame is small.

    # --- 2. Find the faces ---
    # MediaPipe wants RGB colours (OpenCV uses BGR) and a timestamp that always grows.
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    timestamp_ms += 33
    result = landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), timestamp_ms)

    # --- 3. Reduce the largest face to 4 numbers. All positions go from 0 to 1 across the image ---
    face = None
    for number, landmarks in enumerate(result.face_landmarks):
        xs = [point.x for point in landmarks]
        ys = [point.y for point in landmarks]
        size = max(xs) - min(xs)
        if face is None or size > face["size"]:   # The largest face is the closest person.
            face = {
                "number": number,
                "cx": (min(xs) + max(xs)) / 2,
                "cy": (min(ys) + max(ys)) / 2,
                "size": size,
                "points": list(zip(xs, ys)),
            }

    def write(text, row, colour=(255, 255, 255)):
        cv2.putText(frame, text, (int(10 * scale) + 4, int((30 + 26 * row) * scale) + 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7 * scale, colour, max(1, int(2 * scale)))

    # --- 4. Send, and show a preview ---
    if face is None:
        # present = 0. Nothing goes to Wekinator: zeros would look like a real, very blank, face.
        processing.send_message("/face", [0, 0.5, 0.5, 0.0])
        write("no face", 0, (0, 0, 255))
    else:
        processing.send_message("/face", [1, face["cx"], face["cy"], face["size"]])
        # The expression scores, always in the same order: Wekinator knows its inputs only by position.
        scores = {shape.category_name: shape.score for shape in result.face_blendshapes[face["number"]]}
        wekinator.send_message("/wek/inputs", [scores[name] for name in BLENDSHAPES_TO_SEND])

        # Preview: every other point MediaPipe found, the face's centre, and the numbers.
        for x, y in face["points"][::2]:
            cv2.circle(frame, (int(x * width), int(y * height)), max(1, int(2 * scale)), (0, 255, 0), -1)
        cv2.circle(frame, (int(face["cx"] * width), int(face["cy"] * height)), int(8 * scale) + 2, (0, 255, 255), -1)
        write(f"cx={face['cx']:.2f} cy={face['cy']:.2f} size={face['size']:.2f}", 0, (0, 255, 0))
        for row, name in enumerate(BLENDSHAPES_TO_SEND, start=1):
            write(f"{name} {scores[name]:.2f}", row)

    cv2.imshow("face_tracker (q to quit)", frame)
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break
