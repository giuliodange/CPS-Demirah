"""
pipeline_diagram.py: draws docs/images/pipeline.svg, the block diagram of the data flow.

Plain Python, no libraries, in the same style as the schematic (tools/circuit_diagram.py).
Run `python3 tools/pipeline_diagram.py` after changing a block or a label.
"""

from pathlib import Path

INK = "#111111"
svg = []


def text(x, y, content, size=12, weight="normal", anchor="middle"):
    svg.append(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" '
               f'text-anchor="{anchor}" fill="{INK}">{content}</text>')


def block(x, y, w, h, title, notes=()):
    """A box with a bold title and smaller lines under it."""
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#ffffff" stroke="{INK}" stroke-width="2"/>')
    top = y + h / 2 - 7 * len(notes) + 4
    text(x + w / 2, top, title, 13, "bold")
    for i, note in enumerate(notes):
        text(x + w / 2, top + 16 + 14 * i, note, 10)


def arrow(points, labels_above=(), labels_below=(), label_x=None, label_y=None, dashed=False):
    """A line through the points, ending in an arrow head, with optional labels."""
    path = " ".join(f"{x},{y}" for x, y in points)
    dash = ' stroke-dasharray="7,5"' if dashed else ""
    svg.append(f'<polyline points="{path}" fill="none" stroke="{INK}" stroke-width="1.5"{dash} marker-end="url(#head)"/>')
    for i, label in enumerate(reversed(labels_above)):
        text(label_x, label_y - 8 - 13 * i, label, 10)
    for i, label in enumerate(labels_below):
        text(label_x, label_y + 16 + 13 * i, label, 10)


W, H = 1440, 470
svg.append('<defs><marker id="head" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto">'
           f'<path d="M0,0 L10,4 L0,8 Z" fill="{INK}"/></marker></defs>')
svg.append(f'<rect x="10" y="10" width="{W - 20}" height="{H - 20}" fill="#ffffff" stroke="{INK}" stroke-width="2"/>')
text(30, 44, "DEMIRAH: DATA FLOW", 18, "bold", "start")

# The three programs that run on the laptop.
svg.append(f'<rect x="287" y="75" width="640" height="330" fill="none" stroke="{INK}" stroke-width="1.5" stroke-dasharray="7,5"/>')
text(300, 396, "LAPTOP", 11, "bold", "start")

block(40, 200, 180, 80, "ESP32-CAM", ("camera on the mirror head",))
block(300, 200, 190, 80, "face_tracker.py", ("Python, MediaPipe", "face position, 15 scores"))
block(540, 100, 180, 80, "Wekinator", ("k-NN classifier", "4 expression classes"))
block(730, 200, 185, 80, "mirror.pde", ("Processing", "states, motion, light"))
block(1040, 200, 180, 80, "mirror.ino", ("Arduino Nano Every", "executes within limits"))

arrow([(220, 240), (300, 240)], ("Wi-Fi",), ("MJPEG",), 253, 240, dashed=True)
arrow([(395, 200), (395, 140), (540, 140)], ("OSC /wek/inputs", "15 blendshape scores"), (), 468, 140)
arrow([(720, 140), (822, 140), (822, 200)], ("OSC /wek/outputs", "class 1 to 4"), (), 800, 140)
arrow([(490, 240), (730, 240)], ("OSC /face",), ("present, cx, cy, size",), 610, 240)
arrow([(915, 240), (1040, 240)], ("USB serial",), ("115200 baud",), 984, 240)
text(984, 271, "x,y,r,g,b,c,", 10)
text(984, 284, "phase,mix", 10)

# The four outputs.
for y, title, note in ((70, "Stepper X", "base rotation"), (160, "Stepper Y", "head tilt"),
                       (250, "Servo", "mirror curvature"), (340, "75 LEDs", "WS2812B ring")):
    block(1280, y, 140, 60, title, (note,))
    arrow([(1250, y + 30), (1280, y + 30)])
svg.append(f'<polyline points="1220,240 1250,240" fill="none" stroke="{INK}" stroke-width="1.5"/>')
svg.append(f'<polyline points="1250,100 1250,370" fill="none" stroke="{INK}" stroke-width="1.5"/>')

text(30, 440, "The camera turns with the mirror, so the loop from camera to motors is closed: the mirror moves until the face is at the centre of the image.", 10, anchor="start")

document = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" '
            f'font-family="Menlo, Consolas, monospace">'
            f'<rect width="100%" height="100%" fill="#ffffff"/>' + "".join(svg) + "</svg>")
output = Path(__file__).resolve().parent.parent / "docs" / "images" / "pipeline.svg"
output.write_text(document, encoding="utf-8")
print("Written", output)
