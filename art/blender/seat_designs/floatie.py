"""Beach: the Floatie Seat. An inflatable swim ring striped coral and white, a puffy pool-blue cushion inflated
inside it for the rider to sit on, a yellow duck head on a curved neck at the front (orange beak, Cubeling
eyes and blush) and a perky little duck tail at the back."""

import math

import bmesh
import bpy
from mathutils import Matrix

from seatkit import FACE_COLORS, apply_modifiers, bake, ball, face, finish, front_marker, placed, torus, tube

NAME = "Floatie"
TITLE = "Floatie Seat"
ZONE = 4
ORDER = 2
TOP = 1.0  # the cushion's top in the middle, where the rider sits
COLORS = {
    **FACE_COLORS,
    "ring": (1.0, 0.24, 0.2),
    "stripe": (0.97, 0.96, 0.95),
    "cushion": (0.25, 0.7, 0.95),
    "duck": (1.0, 0.8, 0.08),
    "beak": (1.0, 0.42, 0.04),
}

MAJOR = 1.16  # the ring's radius to the middle of its tube
MINOR = 0.43  # the tube's radius
STRIPES = 8  # coral and white segments round the ring (coral at the front, under the duck)


def ring_halves():
    """The swim ring, cut into STRIPES segments by angle: (coral, white) objects."""
    halves = []
    for keep in (0, 1):
        ring = torus("Ring", MAJOR, MINOR, (0, 0, MINOR + 0.03), segments=64)
        bm = bmesh.new()
        bm.from_mesh(ring.data)
        drop = []
        for f in bm.faces:
            c = f.calc_center_median()
            # angle from the front (-Y), half a segment turned so a coral segment is centred on the front
            a = (math.degrees(math.atan2(c.x, -c.y)) + 180 / STRIPES) % 360
            if int(a // (360 / STRIPES)) % 2 != keep:
                drop.append(f)
        bmesh.ops.delete(bm, geom=drop, context="FACES")
        bm.to_mesh(ring.data)
        bm.free()
        halves.append(bake(ring))
    return halves


def build():
    parts = []
    coral, white = ring_halves()
    parts.append(finish(coral, "ring"))
    parts.append(finish(white, "stripe"))

    # The inflated round cushion inside the ring, its edge tucked into the tube, flat-topped and dipped
    cushion = bake(ball("Cushion", 1, (0, 0, 0.76), (1.08, 1.08, 0.33)))
    sub = cushion.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    apply_modifiers(cushion)
    for v in cushion.data.vertices:
        if v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.3
        rr = math.hypot(v.co.x, v.co.y) / 0.8
        if v.co.z > TOP - 0.2 and rr < 1:
            v.co.z -= 0.05 * (1 - rr * rr)
    parts.append(finish(cushion, "cushion"))
    # the inflation plug on the ring's side
    parts.append(finish(ball("Plug", 0.09, (MAJOR + MINOR - 0.02, 0.35, MINOR + 0.12), (0.7, 1, 1)), "stripe"))

    # The duck's neck curving up off the ring's front, and its round head out in front of the rider's knees
    front_y = -MAJOR
    neck = [(0, front_y + 0.05, MINOR + 0.3), (0, front_y - 0.12, MINOR + 0.62), (0, front_y - 0.3, MINOR + 0.82)]
    parts.append(finish(tube("Neck", neck, 0.25), "duck"))
    hy, hz, hr = front_y - 0.52, MINOR + 1.0, 0.46
    parts.append(finish(ball("Head", hr, (0, hy, hz), (0.95, 0.9, 1)), "duck"))
    # a little tuft on top
    for sx, lean in ((-0.06, -20), (0.06, 20)):
        tuft = ball("Tuft", 0.07, (0, 0, 0.12), (0.8, 0.8, 2.0))
        parts.append(finish(placed(tuft, Matrix.Translation((sx, hy + 0.02, hz + hr - 0.08)) @ Matrix.Rotation(math.radians(lean), 4, "Y")), "duck"))
    # the face on the head's front (its mouth hidden by the beak), and the beak: a flat rounded bill
    fy = hy - hr * 0.9 + 0.01
    for p in face(Matrix.Translation((0, fy, hz + 0.06)) @ Matrix.Rotation(math.radians(-8), 4, "X"), 0.72):
        if p["role"] == "mouth":
            bpy.data.objects.remove(p)
        else:
            parts.append(p)
    beak = bake(ball("Beak", 1, (0, fy - 0.12, hz - 0.12), (0.2, 0.22, 0.07)))
    for v in beak.data.vertices:
        # a smiley upturn at the corners
        v.co.z += 0.5 * (v.co.x - 0) ** 2
    parts.append(finish(beak, "beak"))

    # The duck tail at the back: a pointy little flick up off the ring
    tail = bake(ball("Tail", 1, (0, 0, 0), (0.22, 0.32, 0.14)))
    for v in tail.data.vertices:
        t = max(v.co.y / 0.32, 0)
        v.co.x *= 1 - 0.7 * t
        v.co.z += 0.18 * t * t
    parts.append(finish(placed(tail, Matrix.Translation((0, MAJOR + MINOR - 0.05, MINOR + 0.38)) @ Matrix.Rotation(math.radians(35), 4, "X")), "duck"))

    parts.append(front_marker(2 * (MAJOR + MINOR) + 1.2))
    return parts
