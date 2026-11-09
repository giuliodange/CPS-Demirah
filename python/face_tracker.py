"""
face_tracker.py: PERCEPTION. It measures the people and decides nothing.

Every camera frame goes through 4 steps:
  1. Read the frame.
  2. MediaPipe finds the faces, as lists of 478 points on each face.
  3. Reduce the two largest faces to 4 numbers each: present, cx, cy, size.  <-- the important part
  4. Send those numbers to Processing (/face and /face2), and the expression scores of the
     largest face to Wekinator (/wek/inputs). Show everything in a preview.

Run it with:  python face_tracker.py            (the camera on the mirror)
         or:  python face_tracker.py --laptop   (the computer's camera, for testing)
Press q in the preview window to quit.
"""

import sys
from pathlib import Path

import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions, vision
from pythonosc.udp_client import SimpleUDPClient

# ============================== CONFIG ==============================
MIRROR_CAMERA = "http://172.20.10.4:81/stream"  # The ESP32-CAM on the mirror. Its address is printed in its Serial Monitor.
LAPTOP_CAMERA = 0       # The computer's own camera. Used with --laptop; set INPUT = "laptop camera" in mirror.pde.
CAMERA_INDEX = LAPTOP_CAMERA if "--laptop" in sys.argv else MIRROR_CAMERA
MIRROR_IMAGE = True     # Flip the image like a selfie, so cx grows when the person moves to THEIR right.
MAX_FACES = 4           # How many faces MediaPipe looks for. The two largest are sent.
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

model_file = str(Path(__file__).with_name("face_landmarker.task"))
landmarker = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
    base_options=BaseOptions(model_asset_path=model_file),
    running_mode=vision.RunningMode.VIDEO,
    num_faces=MAX_FACES,
    output_face_blendshapes=True,
))
processing = SimpleUDPClient("127.0.0.1", PROCESSING_PORT)
wekinator = SimpleUDPClient("127.0.0.1", WEKINATOR_PORT)

camera = cv2.VideoCapture(CAMERA_INDEX)
if not camera.isOpened():
    sys.exit("Cannot open the camera. For the mirror camera, check its address and the hotspot. "
             "For the laptop camera, allow your terminal app in System Settings > Privacy & Security > Camera.")

timestamp_ms = 0

while True:
    # --- 1. Read a frame ---
    got_frame, frame = camera.read()
    if not got_frame:
        break
    if MIRROR_IMAGE:
        frame = cv2.flip(frame, 1)
    height, width = frame.shape[:2]
    scale = max(width / 1000, 0.3)  # Text and dots follow the frame size: the ESP32-CAM's frame is small.

    # --- 2. Find the faces ---
    # MediaPipe wants RGB colours (OpenCV uses BGR) and a timestamp that always grows.
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    timestamp_ms += 33
    result = landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), timestamp_ms)

    # --- 3. Reduce each face to 4 numbers. All positions go from 0 to 1 across the image ---
    faces = []
    for number, landmarks in enumerate(result.face_landmarks):
        xs = [point.x for point in landmarks]
        ys = [point.y for point in landmarks]
        faces.append({
            "number": number,
            "cx": (min(xs) + max(xs)) / 2,
            "cy": (min(ys) + max(ys)) / 2,
            "size": max(xs) - min(xs),     # The largest face is the closest person.
            "points": list(zip(xs, ys)),
        })
    faces.sort(key=lambda face: face["size"], reverse=True)

    # --- 4. Send: /face is the largest face, /face2 the second one. present = 0 when missing ---
    for address, index in (("/face", 0), ("/face2", 1)):
        if index < len(faces):
            face = faces[index]
            processing.send_message(address, [1, face["cx"], face["cy"], face["size"]])
        else:
            processing.send_message(address, [0, 0.5, 0.5, 0.0])

    # Expressions of the largest face only. Always the same order, because Wekinator knows its
    # inputs only by position. With no face we send nothing: zeros would look like a real, very blank, face.
    if faces:
        scores = {shape.category_name: shape.score for shape in result.face_blendshapes[faces[0]["number"]]}
        wekinator.send_message("/wek/inputs", [scores[name] for name in BLENDSHAPES_TO_SEND])

    # --- Preview: every other point MediaPipe found, green on the largest face, orange on the second ---
    for index, face in enumerate(faces[:2]):
        colour = (0, 255, 0) if index == 0 else (0, 165, 255)
        for x, y in face["points"][::2]:
            cv2.circle(frame, (int(x * width), int(y * height)), max(1, int(2 * scale)), colour, -1)
        cv2.circle(frame, (int(face["cx"] * width), int(face["cy"] * height)), int(8 * scale) + 2, (0, 255, 255), -1)

    def write(text, row, colour=(255, 255, 255)):
        cv2.putText(frame, text, (int(10 * scale) + 4, int((30 + 26 * row) * scale) + 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7 * scale, colour, max(1, int(2 * scale)))

    if faces:
        write(f"faces={len(faces)}  cx={faces[0]['cx']:.2f} cy={faces[0]['cy']:.2f} size={faces[0]['size']:.2f}", 0, (0, 255, 0))
        for row, name in enumerate(BLENDSHAPES_TO_SEND, start=1):
            write(f"{name} {scores[name]:.2f}", row)
    else:
        write("no face", 0, (0, 0, 255))

    cv2.imshow("face_tracker (q to quit)", frame)
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break
