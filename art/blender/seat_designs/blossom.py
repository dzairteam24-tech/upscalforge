"""Flower Field: the Blossom Seat. An open flower, its pink petals cupped up round a soft yellow middle with
pollen dots, green leaves and a curly stem under it, and a little face on the front petal."""

import math

from seatkit import FACE_COLORS, apply_modifiers, ball, finish, front_marker, petal_matrix, placed, tube

NAME = "Blossom"
TITLE = "Blossom Seat"
ZONE = 2
TOP = 1.1  # the yellow middle's top, where the rider sits
COLORS = {
    **FACE_COLORS,
    "petal": (1.0, 0.42, 0.62),
    "center": (1.0, 0.8, 0.18),
    "pollen": (1.0, 0.52, 0.08),
    "leaf": (0.3, 0.72, 0.22),
    "sepal": (0.14, 0.45, 0.14),
}
PETAL_TILT = 48  # the petals cup up this much (degrees)


def build():
    parts = []
    # Six petals cupped up round the middle; the front one points straight at the front
    petal_len, petal_w, petal_t = 0.82, 0.62, 0.13
    front = None
    for i in range(6):
        angle = -90 + 60 * i
        m = petal_matrix(angle, 1.18, 0.72, PETAL_TILT)
        petal = ball("Petal", 1, (0, 0, 0), (petal_w, petal_len, petal_t))
        # a slight cup across the petal, and a rounder, wider tip
        for v in petal.data.vertices:
            v.co.z += 0.1 * (v.co.x / petal_w) ** 2
            v.co.x *= 1 + 0.18 * (v.co.y / petal_len)
        parts.append(finish(placed(petal, m), "petal"))
        if i == 0:
            front = m

    # The soft yellow middle the rider sits on, dipped where they sit, with pollen dots round its rim
    center = ball("Center", 1, (0, 0, TOP - 0.42), (1.05, 1.05, 0.42))
    sub = center.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    apply_modifiers(center)
    for v in center.data.vertices:
        rr = math.hypot(v.co.x, v.co.y) / 0.75
        if v.co.z > TOP - 0.2 and rr < 1:
            v.co.z -= 0.1 * (1 - rr * rr)
    parts.append(finish(center, "center"))
    for i in range(14):
        a = 2 * math.pi * (i + 0.5) / 14
        r = 0.93
        z = TOP - 0.42 + 0.42 * math.sqrt(max(1 - (r / 1.05) ** 2, 0)) + 0.01
        parts.append(finish(ball("Pollen", 0.07, (math.cos(a) * r, math.sin(a) * r, z), (1, 1, 0.7)), "pollen"))

    # Green underneath: a cup of sepals, four leaves sticking out at the sides and back, a curly stem
    sepal = ball("Sepal", 1, (0, 0, 0.42), (1.0, 1.0, 0.36))
    parts.append(finish(sepal, "sepal"))
    for angle in (-10, 50, 130, 190):
        m = petal_matrix(angle, 1.55, 0.36, 8)
        leaf = ball("Leaf", 1, (0, 0, 0), (0.42, 0.85, 0.07))
        for v in leaf.data.vertices:
            # pointed tip, a crease down the middle and a droop toward the end
            t = v.co.y / 0.85
            v.co.x *= 1 - 0.55 * max(t, 0) ** 2
            v.co.z += 0.06 * abs(v.co.x) / 0.42 - 0.12 * max(t, 0) ** 2
        parts.append(finish(placed(leaf, m), "leaf"))
    stem = [(0, 0, 0.2), (0.05, 0.08, 0.06), (0.18, 0.1, 0.0), (0.27, 0.0, 0.05), (0.22, -0.08, 0.13), (0.14, -0.04, 0.12)]
    parts.append(finish(tube("Stem", stem, 0.06), "sepal"))

    # The face on the front petal's outer side (its underside, facing out and down a little): the petal's +Y
    # is up the face
    def on_petal(obj):
        return placed(obj, front)

    fz = -0.135
    for sx in (-1, 1):
        parts.append(finish(on_petal(ball("Eye", 0.1, (sx * 0.2, 0.2, fz), (1, 1.25, 0.45))), "eye"))
        parts.append(finish(on_petal(ball("Shine", 0.035, (sx * 0.2 - 0.03, 0.26, fz - 0.045), (1, 1, 0.5))), "shine"))
        parts.append(finish(on_petal(ball("Blush", 0.08, (sx * 0.4, 0.05, fz + 0.01), (1.3, 0.8, 0.35))), "blush"))
    smile = [(-0.09, 0.02, fz - 0.01), (-0.045, -0.03, fz - 0.025), (0.0, -0.045, fz - 0.03), (0.045, -0.03, fz - 0.025), (0.09, 0.02, fz - 0.01)]
    parts.append(finish(on_petal(tube("Mouth", smile, 0.022)), "mouth"))

    parts.append(front_marker(4.0))
    return parts
