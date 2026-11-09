"""
circuit_diagram.py: draws docs/circuit.svg, the wiring diagram of the mirror.

Plain Python, no libraries: every box, wire and label below is one line of SVG.
Change a pin or a part here, run `python3 tools/circuit_diagram.py`, and the diagram updates.

Power is drawn with labels instead of long wires, as in a normal schematic:
every "+5V" is connected together, every "+12V" too, and every ground symbol is the same GND.
"""

from pathlib import Path

SIGNAL, V5, V12, GND, CABLE = "#1f6feb", "#d1242f", "#e36209", "#24292f", "#6e7781"
svg = []


def text(x, y, content, size=13, weight="normal", anchor="start", colour="#24292f"):
    svg.append(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" '
               f'text-anchor="{anchor}" fill="{colour}">{content}</text>')


def box(x, y, w, h, title, notes=(), fill="#f6f8fa"):
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="#57606a" stroke-width="1.5"/>')
    text(x + w / 2, y + 20, title, 14, "bold", "middle")
    for i, note in enumerate(notes):
        text(x + w / 2, y + 38 + 16 * i, note, 12, anchor="middle", colour="#57606a")


def wire(points, colour, width=2, dashed=False):
    path = " ".join(f"{x},{y}" for x, y in points)
    dash = ' stroke-dasharray="6,5"' if dashed else ""
    svg.append(f'<polyline points="{path}" fill="none" stroke="{colour}" stroke-width="{width}"{dash}/>')


def pin(x, y, name, side):
    """A small labelled pin on the edge of a box. side = 'left' or 'right' of the label."""
    svg.append(f'<circle cx="{x}" cy="{y}" r="3" fill="#24292f"/>')
    text(x + (8 if side == "right" else -8), y + 4, name, 11, anchor="start" if side == "right" else "end")


def power(x, y, label, colour):
    """A power label: everything with the same label is connected."""
    wire([(x, y), (x, y + 14)], colour)
    svg.append(f'<rect x="{x - 24}" y="{y + 14}" width="48" height="18" rx="3" fill="{colour}"/>')
    text(x, y + 27, label, 11, "bold", "middle", "#ffffff")


def ground(x, y):
    """The ground symbol: every one is the same GND."""
    wire([(x, y), (x, y + 12)], GND)
    for i, half in enumerate((10, 6, 2)):
        wire([(x - half, y + 12 + 4 * i), (x + half, y + 12 + 4 * i)], GND)


def resistor(x, y, label):
    svg.append(f'<rect x="{x}" y="{y - 6}" width="34" height="12" fill="#ffffff" stroke="{SIGNAL}" stroke-width="2"/>')
    text(x + 17, y - 10, label, 11, anchor="middle")


# --- Computer and camera ---
box(30, 70, 200, 70, "Mac", ["Python, Wekinator, Processing"])
box(30, 330, 200, 90, "ESP32-CAM", ["on the mirror head", "streams the image over Wi-Fi"])
wire([(130, 330), (130, 140)], CABLE, dashed=True)
text(138, 240, "Wi-Fi (phone hotspot)", 11, colour=CABLE)
power(80, 420, "+5V", V5)
ground(180, 420)

# --- Arduino ---
box(300, 70, 230, 510, "Arduino Nano Every", ["executes the serial line", "x,y,r,g,b,c,phase,mix"])
wire([(230, 105), (300, 105)], CABLE, 4)
text(265, 98, "USB", 11, anchor="middle", colour=CABLE)
for y, name in [(130, "D2"), (150, "D3"), (170, "D4"), (190, "D5"),
                (290, "D7"), (310, "D8"), (330, "D11"), (350, "D12"),
                (440, "D9"), (530, "D6")]:
    pin(530, y, name, "left")
pin(415, 580, "GND", "right")
ground(415, 580)
text(415, 625, "5V pin: NOT connected to the Power Board", 11, anchor="middle", colour=V5)

# --- Stepper X: rotation of the base ---
box(660, 100, 170, 110, "Driver X", ["Seeed ULN2003"])
for y in (130, 150, 170, 190):
    wire([(530, y), (660, y)], SIGNAL)
text(668, 134, "IN1", 10); text(668, 154, "IN2", 10); text(668, 174, "IN3", 10); text(668, 194, "IN4", 10)
box(960, 100, 210, 110, "Stepper X", ["base rotation", "on the steel-ball bearing", "12 V (TODO: model)"])
wire([(830, 155), (960, 155)], CABLE, 5)
text(895, 148, "motor cable", 11, anchor="middle", colour=CABLE)
power(720, 210, "+12V", V12)
text(752, 238, "VM", 10, colour=V12)
ground(800, 210)

# --- Stepper Y: tilt, by a cord over two pulleys ---
box(660, 265, 170, 110, "Driver Y", ["Seeed ULN2003"])
for y in (290, 310, 330, 350):
    wire([(530, y), (660, y)], SIGNAL)
text(668, 294, "IN1", 10); text(668, 314, "IN2", 10); text(668, 334, "IN3", 10); text(668, 354, "IN4", 10)
box(960, 265, 210, 110, "Stepper Y", ["head tilt", "pulls a cord over 2 pulleys", "28BYJ-48, 5 V"])
wire([(830, 320), (960, 320)], CABLE, 5)
power(720, 375, "+5V", V5)
text(752, 403, "VM, VCC", 10, colour=V5)
ground(800, 375)

# --- Servo: concavity ---
box(960, 410, 210, 75, "Servo SG90", ["pushes the rack on the", "back of the mirror: concavity"])
wire([(530, 440), (960, 440)], SIGNAL)
text(745, 433, "signal (orange wire)", 11, anchor="middle", colour=SIGNAL)
power(1010, 485, "+5V", V5)
ground(1120, 485)

# --- LED ring ---
box(960, 525, 210, 75, "75 × WS2812", ["LED ring in the mirror frame"])
wire([(530, 530), (720, 530)], SIGNAL)
resistor(720, 530, "330 Ω")
wire([(754, 530), (960, 530)], SIGNAL)
text(860, 523, "Din", 11, anchor="middle", colour=SIGNAL)
power(1000, 600, "+5V", V5)
ground(1130, 600)
# Capacitor across the LEDs' supply: two plates between the +5V and GND wires.
wire([(1000, 632), (1000, 645), (1050, 645)], V5)
svg.append(f'<line x1="1050" y1="633" x2="1050" y2="657" stroke="{GND}" stroke-width="3"/>')
svg.append(f'<line x1="1060" y1="633" x2="1060" y2="657" stroke="{GND}" stroke-width="3"/>')
wire([(1060, 645), (1130, 645), (1130, 612)], GND)
text(1055, 675, "1000 µF across +5V and GND, close to the LEDs", 11, anchor="middle")

# --- Power board ---
box(30, 470, 200, 150, "Power Board (custom)", ["USB-C in (TODO: rating)", "limits current to 2 A", "outputs:"])
power(70, 570, "+12V", V12)
power(130, 570, "+5V", V5)
ground(190, 570)

# --- Legend ---
for i, (colour, name) in enumerate([(SIGNAL, "signal"), (V5, "+5 V"), (V12, "+12 V"), (GND, "ground"), (CABLE, "cable / USB / Wi-Fi")]):
    wire([(30 + 150 * i, 715), (60 + 150 * i, 715)], colour, 3)
    text(68 + 150 * i, 719, name, 12)
text(30, 750, "Every +5V label is the same wire, every +12V label too, and every ground symbol is the same GND, "
              "shared by the Power Board, the Arduino and the ESP32-CAM.", 12, colour="#57606a")

width, height = 1200, 770
document = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" '
            f'font-family="Helvetica, Arial, sans-serif"><rect width="100%" height="100%" fill="#ffffff"/>'
            + "".join(svg) + "</svg>\n")
output = Path(__file__).resolve().parent.parent / "docs" / "circuit.svg"
output.parent.mkdir(exist_ok=True)
output.write_text(document, encoding="utf-8")
print(f"Wrote {output}")
