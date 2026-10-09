"""Snow Peak: the Snowman Seat. A big round snowball pressed flat on top for the rider, pale blue underneath,
with coal buttons down its front and stick arms out at its sides. Behind the rider a smaller snowball rises
to the snowman's head as a backrest: coal eyes, rosy cheeks, a little carrot nose, a red knitted hat with a green band
and a pompom and a red and green striped scarf wrapped round its neck, one end hanging down its back."""

import math

import bpy
from mathutils import Matrix, Vector

from seatkit import FACE_COLORS, ball, blob, cone, face, finish, front_marker, placed, torus, tube

NAME = "Snowman"
TITLE = "Snowman Seat"
ZONE = 7
ORDER = 1
TOP = 1.1  # the snowball's flattened top, where the rider sits
COLORS = {
    **FACE_COLORS,
    "snow": (0.95, 0.97, 1.0),
    "shade": (0.62, 0.74, 0.95),
    "red": (0.8, 0.04, 0.06),
    "green": (0.04, 0.42, 0.12),
    "coal": (0.05, 0.05, 0.07),
    "carrot": (1.0, 0.36, 0.04),
    "stick": (0.3, 0.15, 0.06),
}
LIGHT = (0.75, 0.88, 1.0)

RX, RY, RZ = 1.5, 1.32, 0.64  # the big snowball's half sizes
MID = 0.64  # its middle's height
HEAD = Vector((0, 1.48, 1.48))  # the head's middle, behind the rider
HEAD_R = 0.47


def surface_y(x, z):
    """The big snowball's front surface (its y, negative) at x and height z."""
    return -RY * math.sqrt(max(1 - (x / RX) ** 2 - ((z - MID) / RZ) ** 2, 0))


def build():
    parts = []

    # The big snowball and the smaller one behind it that carries the head, melted together
    body = blob("Snowball", [(1, (0, 0, MID), (RX, RY, RZ)), (0.56, (0, 1.22, 0.82), (1, 0.9, 1))], voxel=0.07, keep=7000)
    for v in body.data.vertices:
        if v.co.y < 0.95:
            edge = TOP - 0.16
            if v.co.z > edge:
                v.co.z = edge + 0.16 * math.tanh((v.co.z - edge) / 0.16)
            rr = math.hypot(v.co.x, v.co.y) / 0.8
            if rr < 1 and v.co.z > TOP - 0.2:
                v.co.z -= 0.04 * (1 - rr * rr)
    parts.append(finish(body, "snow"))
    # its pale blue underside: a slightly smaller snowball sunk a little lower, showing only underneath
    shade = ball("Shade", 1, (0, 0, 0), (RX - 0.04, RY - 0.04, RZ - 0.02))
    for v in shade.data.vertices:
        v.co.z = min(max(v.co.z + MID - 0.1, 0.03), 0.7)  # (its top is hidden inside, its bottom sits at 0)
    parts.append(finish(shade, "shade"))

    # The head, its face looking forward over the rider
    parts.append(finish(ball("Head", HEAD_R, tuple(HEAD), (1, 0.94, 1)), "snow"))
    front = HEAD.y - HEAD_R * 0.94
    parts += face(Matrix.Translation((0, front + 0.03, HEAD.z + 0.02)), 0.62)
    # a short carrot nose between the eyes and the smile, tipped up a little
    nose = cone("Nose", 0.065, 0.012, 0.16, (0, 0, 0.08), 16)
    parts.append(finish(placed(nose, Matrix.Translation((0, front + 0.03, HEAD.z - 0.02)) @ Matrix.Rotation(math.radians(70), 4, "X")), "carrot"))

    # The knitted hat: a red cap on the head's crown, a ribbed band round its edge and a white pompom
    # (the cap is the top of a slightly bigger ball, a little taller than round, tipped back)
    tip = Matrix.Translation(HEAD + Vector((0, 0.03, 0.18))) @ Matrix.Rotation(math.radians(-10), 4, "X")
    cap = ball("Cap", 1, (0, 0, 0))
    for v in cap.data.vertices:
        v.co = (v.co.x * HEAD_R * 0.97, v.co.y * HEAD_R * 0.95, max(v.co.z, 0) * HEAD_R * 1.1)
    parts.append(finish(placed(cap, tip), "red"))
    band = torus("Band", HEAD_R * 0.93, 0.08, (0, 0, 0), 48)
    for v in band.data.vertices:
        v.co.y *= 0.98
    parts.append(finish(placed(band, tip), "green"))
    parts.append(finish(placed(ball("Pompom", 0.14, (0, 0, HEAD_R * 1.1 + 0.08)), tip), "snow"))

    # The scarf: a fat ring round the neck, striped red and green, one end hanging down the back
    stripes = 14
    for i in range(stripes):
        a0, a1 = 2 * math.pi * i / stripes, 2 * math.pi * (i + 1) / stripes
        pts = [(math.cos(a0 + (a1 - a0) * k / 4) * 0.5, math.sin(a0 + (a1 - a0) * k / 4) * 0.46, 0) for k in range(5)]
        seg = tube("Scarf", pts, 0.11)
        seg.scale = (1, 1, 0.75)
        parts.append(finish(placed(seg, Matrix.Translation(HEAD + Vector((0, -0.02, -0.4)))), "red" if i % 2 == 0 else "green"))
    tail = [Vector((0.32, 1.72, 1.02)), Vector((0.38, 1.8, 0.82)), Vector((0.42, 1.76, 0.62))]
    for i in range(len(tail) - 1):
        parts.append(finish(tube("ScarfEnd", [tuple(tail[i]), tuple(tail[i + 1])], 0.09), "red" if i % 2 == 0 else "green"))
    for k in range(5):
        parts.append(finish(tube("Fringe", [tuple(tail[-1] + Vector((-0.06 + 0.03 * k, 0, 0))), tuple(tail[-1] + Vector((-0.06 + 0.03 * k, 0, -0.16)))], 0.016), "green"))

    # Coal buttons down the front
    for z in (0.9, 0.62, 0.36):
        y = surface_y(0, z)
        parts.append(finish(ball("Button", 0.08, (0, y - 0.01, z), (1, 0.55, 1)), "coal"))

    # Stick arms out at the sides, each with a little twig fork
    for sx in (-1, 1):
        start = (sx * 1.3, 0.15, 0.82)
        elbow = (sx * 1.62, 0.25, 1.04)
        hand = (sx * 1.86, 0.32, 1.36)
        parts.append(finish(tube("Arm", [start, elbow, hand], 0.045), "stick"))
        parts.append(finish(tube("Twig", [elbow, (sx * 1.86, 0.1, 1.08)], 0.03), "stick"))
        parts.append(finish(tube("Twig", [hand, (sx * 1.98, 0.28, 1.46)], 0.025), "stick"))
        parts.append(finish(tube("Twig", [hand, (sx * 1.84, 0.42, 1.5)], 0.025), "stick"))

    parts.append(front_marker(2 * RY))
    return parts
