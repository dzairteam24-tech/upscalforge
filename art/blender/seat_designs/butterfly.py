"""Flower Field: the Butterfly Seat. A chubby fuzzy butterfly lying lengthwise, the rider sitting on its back:
a lilac body with a cream fluff collar, its round head at the front with a Cubeling face and two curly
antennae with pink ball tips, and four big rounded wings (sky-blue upper, lilac lower) with a dark purple rim
and pink and yellow spots, raised a little like a V so they stay clear of the rider's knees."""

import math

from mathutils import Matrix

from seatkit import FACE_COLORS, ball, blob, face, finish, front_marker, placed, tube

NAME = "Butterfly"
TITLE = "Butterfly Seat"
ZONE = 2
ORDER = 2
TOP = 1.1  # the flattened back where the rider sits
COLORS = {
    **FACE_COLORS,
    "body": (0.62, 0.42, 0.92),
    "fuzz": (1.0, 0.93, 0.8),
    "upper": (0.42, 0.74, 1.0),
    "lower": (0.8, 0.6, 1.0),
    "rim": (0.3, 0.13, 0.62),
    "spot": (1.0, 0.42, 0.68),
    "dot": (1.0, 0.85, 0.2),
    "tip": (1.0, 0.45, 0.7),
}

HEAD_Y = -1.38  # the head's middle (it sits in front of the rider's legs)
HEAD_R = 0.5
WING_TILT = 22  # the wings rise this much from their roots (degrees)


def wing_frame(sx, sweep, root):
    """A wing's frame: its local +X runs out from the root, raised by WING_TILT and swept back by `sweep`
    degrees (negative sweeps it forward); `sx` is the side."""
    angle = math.radians(sweep) if sx > 0 else math.pi - math.radians(sweep)
    return Matrix.Translation(root) @ Matrix.Rotation(angle, 4, "Z") @ Matrix.Rotation(math.radians(-WING_TILT), 4, "Y")


def wing(parts, frame, length, width, color, spots):
    """A rounded wing lying in its frame's XY plane: a dark rim, the colored wing a little smaller and thicker
    (so it shows through the rim on both faces) and round spots on its top."""
    half = length / 2
    rim = ball("WingRim", 1, (half, 0, 0), (half, width / 2, 0.05))
    inner = ball("Wing", 1, (half + 0.02, 0, 0), (half * 0.86, width / 2 * 0.84, 0.065))
    for obj in (rim, inner):
        # a fuller, rounder outer end than at the root
        for v in obj.data.vertices:
            t = v.co.x / length
            v.co.y *= 0.7 + 0.45 * math.sin(math.pi * min(t * 0.8 + 0.1, 1))
    parts.append(finish(placed(rim, frame), "rim"))
    parts.append(finish(placed(inner, frame), color))
    for x, y, r, role in spots:
        parts.append(finish(placed(ball("Spot", r, (x * length, y * width / 2, 0.05), (1, 1, 0.35)), frame), role))


def build():
    parts = []
    # The chubby body: a long soft back (thorax and abdomen melted together), a rounded tail end at the back
    puffs = [
        (1.0, (0, 0.05, 0.6), (1.05, 1.25, 0.56)),
        (0.7, (0, -0.65, 0.62), (1.2, 1.0, 0.8)),
        (0.62, (0, 0.85, 0.55), (1.25, 1.2, 0.8)),
        (0.42, (0, 1.42, 0.52), (1.1, 1.0, 0.85)),
    ]
    body = blob("ButterflyBody", puffs, voxel=0.07)
    for v in body.data.vertices:
        if v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.3
        # a soft dip where the rider sits
        rr = math.hypot(v.co.x / 0.8, v.co.y / 0.85)
        if v.co.z > TOP - 0.2 and rr < 1:
            v.co.z -= 0.06 * (1 - rr * rr)
    parts.append(finish(body, "body"))
    # Fuzzy segment rings round the abdomen and a fluffy cream collar behind the head
    for y, r in ((0.95, 0.66), (1.32, 0.48)):
        ring = blob("Seg", [(0.09, (math.cos(a) * r * 1.05, y, 0.55 + math.sin(a) * r * 0.62), (1, 1, 1)) for a in [math.pi * (i / 12 * 1.3 - 0.15) for i in range(13)]], voxel=0.05, keep=1500)
        parts.append(finish(ring, "fuzz"))
    collar = [(0.2, (math.cos(a) * 0.62, -1.0, 0.62 + math.sin(a) * 0.4), (1, 0.9, 1)) for a in [2 * math.pi * i / 12 for i in range(12)]]
    parts.append(finish(blob("Collar", collar, voxel=0.06, keep=3000), "fuzz"))

    # The round head in front, with its face looking forward
    parts.append(finish(ball("Head", HEAD_R, (0, HEAD_Y, 0.66), (1.05, 1.0, 0.98)), "body"))
    parts.extend(face(Matrix.Translation((0, HEAD_Y - HEAD_R + 0.04, 0.63)), 0.82))
    # Two curly antennae from the top of the head, curling outward with ball tips
    for sx in (-1, 1):
        pts = [(sx * 0.16, HEAD_Y + 0.05, 1.08), (sx * 0.24, HEAD_Y - 0.1, 1.35), (sx * 0.36, HEAD_Y - 0.25, 1.58), (sx * 0.52, HEAD_Y - 0.3, 1.72),
               (sx * 0.66, HEAD_Y - 0.24, 1.73), (sx * 0.72, HEAD_Y - 0.14, 1.64), (sx * 0.66, HEAD_Y - 0.12, 1.55), (sx * 0.58, HEAD_Y - 0.18, 1.56)]
        parts.append(finish(tube("Antenna", pts, 0.04), "rim"))
        parts.append(finish(ball("Tip", 0.1, pts[-1]), "tip"))

    # Four wings rising from the body's sides: big upper ones swept forward, smaller lower ones swept back
    for sx in (-1, 1):
        wing(parts, wing_frame(sx, -24, (sx * 0.85, -0.25, 0.85)), 1.25, 1.35, "upper",
             [(0.62, 0.05, 0.2, "spot"), (0.85, -0.42, 0.11, "dot"), (0.86, 0.45, 0.1, "dot"), (0.35, -0.4, 0.08, "dot")])
        wing(parts, wing_frame(sx, 38, (sx * 0.85, 0.45, 0.78)), 1.0, 1.0, "lower",
             [(0.6, 0.0, 0.15, "dot"), (0.85, -0.4, 0.08, "spot"), (0.85, 0.4, 0.08, "spot")])

    parts.append(front_marker(3.6))
    return parts
