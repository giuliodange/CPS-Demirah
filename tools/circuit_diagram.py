"""
circuit_diagram.py: draws docs/images/circuit.svg, the schematic of the mirror.

Plain Python, no libraries: every symbol, wire and label below is one line of SVG.
Change a pin or a part here, run `python3 tools/circuit_diagram.py`, and the schematic updates.

Conventions, as in a normal schematic:
  - every +5V symbol is the same net, and every ground symbol is the same GND;
  - each part has a reference (U1, M1, R1...) that matches the table in docs/hardware.md.
"""

from pathlib import Path

INK = "#111111"
svg = []


def text(x, y, content, size=12, weight="normal", anchor="start"):
    svg.append(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" '
               f'text-anchor="{anchor}" fill="{INK}">{content}</text>')


def wire(points, width=1.5, dashed=False):
    path = " ".join(f"{x},{y}" for x, y in points)
    dash = ' stroke-dasharray="7,5"' if dashed else ""
    svg.append(f'<polyline points="{path}" fill="none" stroke="{INK}" stroke-width="{width}"{dash}/>')


def part(x, y, w, h, reference, name, notes=()):
    """A part drawn as a box: its reference above it, its name and notes inside."""
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#ffffff" stroke="{INK}" stroke-width="2"/>')
    text(x, y - 7, reference, 13, "bold")
    text(x + w / 2, y + h / 2 - 6 * len(notes) + 2, name, 12, "bold", "middle")
    for i, note in enumerate(notes):
        text(x + w / 2, y + h / 2 - 6 * len(notes) + 18 + 14 * i, note, 10, anchor="middle")


def pin(x, y, name, side, length=20):
    """A pin: a short stub outside the box and its name inside. side = the edge it is on."""
    dx, dy = {"left": (-1, 0), "right": (1, 0), "top": (0, -1), "bottom": (0, 1)}[side]
    wire([(x, y), (x + dx * length, y + dy * length)])
    if side in ("left", "right"):
        text(x - dx * 6, y + 4, name, 10, anchor="start" if side == "left" else "end")
    else:
        text(x, y - dy * 13 + 4, name, 10, anchor="middle")
    return x + dx * length, y + dy * length


def supply(x, y):
    """The +5V symbol, pointing up from (x, y)."""
    wire([(x, y), (x, y - 14)])
    wire([(x - 9, y - 14), (x + 9, y - 14)], 2)
    text(x, y - 19, "+5V", 10, "bold", "middle")


def ground(x, y):
    """The ground symbol, pointing down from (x, y)."""
    wire([(x, y), (x, y + 10)])
    for i, half in enumerate((10, 6, 2)):
        wire([(x - half, y + 10 + 4 * i), (x + half, y + 10 + 4 * i)])


def junction(x, y):
    svg.append(f'<circle cx="{x}" cy="{y}" r="3" fill="{INK}"/>')


def resistor(x, y, reference, value, length=60):
    """A horizontal resistor (zigzag) from (x, y) to (x + length, y)."""
    step = (length - 20) / 6
    points = [(x, y), (x + 10, y)]
    for i in range(6):
        points.append((x + 10 + step * (i + 0.5), y + (-6 if i % 2 == 0 else 6)))
    points += [(x + length - 10, y), (x + length, y)]
    wire(points)
    text(x + length / 2, y - 12, f"{reference}  {value}", 10, anchor="middle")


def capacitor(x, y1, y2, reference, value):
    """A vertical polarised capacitor between (x, y1), the + side, and (x, y2)."""
    middle = (y1 + y2) / 2
    wire([(x, y1), (x, middle - 4)])
    wire([(x - 10, middle - 4), (x + 10, middle - 4)], 2)
    wire([(x - 10, middle + 4), (x + 10, middle + 4)], 2)
    wire([(x, middle + 4), (x, y2)])
    text(x - 14, middle - 6, "+", 11, anchor="end")
    text(x + 16, middle - 1, reference, 10)
    text(x + 16, middle + 12, value, 10)


def motor(x, y, reference, name):
    """A stepper drawn as a circle with an M, joined to its driver by its 5-wire cable."""
    svg.append(f'<circle cx="{x}" cy="{y}" r="30" fill="#ffffff" stroke="{INK}" stroke-width="2"/>')
    text(x, y + 6, "M", 18, "bold", "middle")
    text(x - 30, y - 38, reference, 13, "bold")
    text(x + 40, y - 4, name, 11, "bold")
    text(x + 40, y + 11, "28BYJ-48, 5 V, unipolar", 10)


def cable(x1, x2, y, label):
    """Several wires drawn as one line, with a slash and their count."""
    wire([(x1, y), (x2, y)], 3)
    middle = (x1 + x2) / 2
    wire([(middle - 5, y + 8), (middle + 5, y - 8)])
    text(middle, y - 12, label, 10, anchor="middle")


# ---------------------------- Frame and title ----------------------------
W, H = 1400, 900
svg.append(f'<rect x="10" y="10" width="{W - 20}" height="{H - 20}" fill="#ffffff" stroke="{INK}" stroke-width="2"/>')
text(30, 44, "DEMIRAH: ELECTRICAL SCHEMATIC", 18, "bold")
text(30, 62, "All supplies 5 V DC from the module's power bank and power board", 11)

# ---------------------------- Power ----------------------------
part(50, 120, 190, 60, "BT1", "Power bank", ("5 V USB, provided",))
part(50, 250, 190, 110, "PS1", "Power board", ("provided by the module", "5 V out, 2 A limit"))
wire([(145, 180), (145, 250)], 3)
text(153, 220, "USB", 10)
x, y = pin(240, 285, "+5V", "right")
supply(x, y)
x, y = pin(240, 330, "GND", "right")
ground(x, y)

# ---------------------------- Computer and camera ----------------------------
part(50, 450, 190, 70, "PC1", "Laptop", ("Python, Wekinator,", "Processing"))
part(50, 620, 190, 90, "U4", "ESP32-CAM", ("OV2640 camera", "on the mirror head"))
wire([(145, 520), (145, 620)], dashed=True)
text(153, 575, "Wi-Fi: MJPEG video", 10)
x, y = pin(240, 645, "5V", "right")
supply(x, y)
x, y = pin(240, 690, "GND", "right")
ground(x, y)

# ---------------------------- Arduino ----------------------------
AX, AW = 420, 180
part(AX, 120, AW, 640, "U1", "Arduino", ("Nano Every", "ATmega4809"))
x, y = pin(AX, 485, "USB", "left")
wire([(240, 485), (x, y)], 3)
text(320, 477, "USB: serial", 10, anchor="middle")
text(320, 501, "115200 baud", 10, anchor="middle")
x, y = pin(AX, 300, "5V", "left")
wire([(x - 6, y - 6), (x + 6, y + 6)])
wire([(x - 6, y + 6), (x + 6, y - 6)])
text(x - 10, y + 4, "not connected", 10, anchor="end")
x, y = pin(AX + AW / 2, 760, "GND", "bottom")
ground(x, y)
RIGHT = AX + AW

# ---------------------------- Stepper X: base rotation ----------------------------
part(800, 150, 170, 150, "U2", "ULN2003 driver", ("Seeed gear stepper", "driver pack"))
for arduino_pin, driver_pin, y in (("D2", "IN1", 180), ("D3", "IN2", 210), ("D4", "IN3", 240), ("D5", "IN4", 270)):
    x1, _ = pin(RIGHT, y, arduino_pin, "right")
    x2, _ = pin(800, y, driver_pin, "left")
    wire([(x1, y), (x2, y)])
x, y = pin(840, 150, "VCC", "top")
supply(x, y)
x, y = pin(930, 300, "GND", "bottom")
ground(x, y)
x, y = pin(970, 225, "OUT", "right")
cable(x, 1090, 225, "5 wires")
motor(1120, 225, "M1", "Stepper X: base rotation")

# ---------------------------- Stepper Y: head tilt ----------------------------
part(800, 380, 170, 150, "U3", "ULN2003 driver", ("Seeed gear stepper", "driver pack"))
for arduino_pin, driver_pin, y in (("D7", "IN1", 410), ("D8", "IN2", 440), ("D11", "IN3", 470), ("D12", "IN4", 500)):
    x1, _ = pin(RIGHT, y, arduino_pin, "right")
    x2, _ = pin(800, y, driver_pin, "left")
    wire([(x1, y), (x2, y)])
x, y = pin(840, 380, "VCC", "top")
supply(x, y)
x, y = pin(930, 530, "GND", "bottom")
ground(x, y)
x, y = pin(970, 455, "OUT", "right")
cable(x, 1090, 455, "5 wires")
motor(1120, 455, "M2", "Stepper Y: head tilt")

# ---------------------------- Servo: mirror curvature ----------------------------
part(1000, 580, 170, 70, "M3", "Servo, 180°", ("mirror curvature",))
x1, _ = pin(RIGHT, 615, "D9", "right")
x2, _ = pin(1000, 615, "SIG", "left")
wire([(x1, 615), (x2, 615)])
text(810, 607, "50 Hz pulse, timer TCA0", 10, anchor="middle")
x, y = pin(1170, 600, "V+", "right")
wire([(x, y), (x + 30, y)])
supply(x + 30, y)
x, y = pin(1170, 635, "GND", "right")
wire([(x, y), (x + 70, y)])
ground(x + 70, y)

# ---------------------------- LED ring ----------------------------
part(1000, 700, 170, 90, "D1-D75", "75 × WS2812B", ("LED ring in the", "mirror frame"))
x1, _ = pin(RIGHT, 725, "D6", "right")
resistor(700, 725, "R1", "330 Ω")
wire([(x1, 725), (700, 725)])
x2, _ = pin(1000, 725, "DIN", "left")
wire([(760, 725), (x2, 725)])
x, y = pin(1170, 720, "+5V", "right")
wire([(x, y), (x + 90, y)])
supply(x + 90, y)
junction(x + 40, y)
x, y = pin(1170, 770, "GND", "right")
wire([(x, y), (x + 90, y)])
ground(x + 90, y)
junction(x + 40, y)
capacitor(x + 40, 720, 770, "C1", "1000 µF")

# ---------------------------- Notes and title block ----------------------------
text(50, 800, "NOTES", 11, "bold")
for i, note in enumerate((
    "1. Every +5V symbol is one net, fed by PS1. Every ground symbol is one net: PS1, U1 and U4 share GND.",
    "2. U1 is powered by the laptop over USB. Its 5V pin is not connected, so the two supplies never meet.",
    "3. R1 protects the first LED's data input. C1 absorbs the surge when the LEDs switch on.",
)):
    text(50, 818 + 16 * i, note, 10)

TX, TY = 1000, 815
svg.append(f'<rect x="{TX}" y="{TY}" width="370" height="60" fill="#ffffff" stroke="{INK}" stroke-width="1.5"/>')
wire([(TX, TY + 30), (TX + 370, TY + 30)])
wire([(TX + 240, TY + 30), (TX + 240, TY + 60)])
text(TX + 10, TY + 20, "Demirah, interactive mirror: schematic", 12, "bold")
text(TX + 10, TY + 49, "Cyber Physical Systems, IDE 2026-27", 10)
text(TX + 250, TY + 49, "Sheet 1 of 1", 10)

document = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" '
            f'font-family="Menlo, Consolas, monospace">'
            f'<rect width="100%" height="100%" fill="#ffffff"/>' + "".join(svg) + "</svg>")
output = Path(__file__).resolve().parent.parent / "docs" / "images" / "circuit.svg"
output.write_text(document, encoding="utf-8")
print("Written", output)
