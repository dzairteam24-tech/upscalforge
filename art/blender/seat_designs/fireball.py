"""Volcano: the Fire Cloud Seat. A puffy cloud made of fire: an orange cushion of melted puffs with a hotter
yellow layer on top where the rider sits and a red-orange underside, flame tongues licking up round its back
and sides (yellow ones inside the orange), and a Cubeling face on its front."""

import math

from mathutils import Matrix, Vector

from seatkit import FACE_COLORS, ball, blob, face, finish, front_marker, placed, split_below

NAME = "Fireball"
TITLE = "Fire Cloud Seat"
ZONE = 8
ORDER = 2
TOP = 1.01  # the yellow layer's top, where the rider sits
COLORS = {
    **FACE_COLORS,
    "fire": (0.95, 0.1, 0.004),  # (dim: the glow brightens it)
    "yellow": (1.0, 0.62, 0.03),
    "red": (0.55, 0.025, 0.008),
}
GLOW = ("fire", "yellow")
LIGHT = (1.0, 0.5, 0.15)

WIDTH = 3.5  # side to side
DEPTH = 3.0  # front to back


def flame(name, base, height, radius, lean=(0.0, 0.0), curl=0.0):
    """A flame tongue: a round bottom drawn up into a pointed tip, leaning by `lean` (x, y at the tip) and its
    tip flicking sideways by `curl`."""
    obj = ball(name, 1, (0, 0, 0))
    for v in obj.data.vertices:
        z = v.co.z
        ring = math.sqrt(max(1 - z * z, 1e-6))
        if z < 0:
            w = radius * ring  # the round bottom
            h = z * radius
        else:
            w = radius * (1 - z) ** 0.9 * (1 + 0.3 * math.sin(z * math.pi))  # swelling, then the point
            h = z * height
        t = max(h, 0) / height
        v.co.x = v.co.x / ring * w + lean[0] * t * t + curl * math.sin(t * math.pi) * 0.5 * t
        v.co.y = v.co.y / ring * w + lean[1] * t * t
        v.co.z = h
    return placed(obj, Matrix.Translation(base))


def build():
    parts = []
    hw, hd = WIDTH / 2, DEPTH / 2
    # The cushion: a ring of big puffs round a lower middle, smaller puffs filling in (like a cloud)
    puffs = [(0.95, (0, 0, 0.6), (1.35, 1.2, 0.6))]
    for i in range(10):
        a = 2 * math.pi * i / 10
        x, y = math.cos(a) * (hw - 0.62), math.sin(a) * (hd - 0.58)
        r = 0.6 if i % 2 == 0 else 0.53
        puffs.append((r, (x, y, 0.6 + (0.05 if i % 2 == 0 else 0)), (1, 1, 0.88)))
    body = blob("FireBody", puffs)
    # its top flattened a little below the seat: the yellow layer goes on top
    under = TOP - 0.32
    for v in body.data.vertices:
        if v.co.z > under:
            v.co.z = under + (v.co.z - under) * 0.35
    shade = split_below(body, 0.38, "FireUnder")
    parts.append(finish(body, "fire"))
    parts.append(finish(shade, "red"))

    # The yellow layer on top: a flat puffy pad with a scalloped, flame-like edge
    layer = [(1.0, (0, 0.05, TOP - 0.18), (1.08, 0.95, 0.24))]
    for i in range(9):
        a = 2 * math.pi * (i + 0.5) / 9
        layer.append((0.32, (math.cos(a) * 1.1, 0.05 + math.sin(a) * 0.92, TOP - 0.17), (1, 1, 0.6)))
    pad = blob("FireTop", layer, voxel=0.06, keep=4000)
    for v in pad.data.vertices:
        if v.co.z > TOP + 0.03:
            v.co.z = TOP + 0.03 + (v.co.z - TOP - 0.03) * 0.3
        rr = math.hypot(v.co.x / 0.85, (v.co.y - 0.05) / 0.75)
        if v.co.z > TOP - 0.1 and rr < 1:
            v.co.z -= 0.05 * (1 - rr * rr)
    parts.append(finish(pad, "yellow"))

    # Flame tongues licking up round the back and sides: big orange ones, a yellow one inside each
    tongues = [
        # (x, y, z, height, radius, lean x, lean y, curl)
        (0.0, 1.38, 0.75, 1.0, 0.5, 0.0, 0.25, 0.3),
        (-0.85, 1.25, 0.7, 0.8, 0.46, -0.15, 0.2, -0.3),
        (0.85, 1.25, 0.7, 0.8, 0.46, 0.15, 0.2, 0.3),
        (-1.5, 0.35, 0.65, 0.62, 0.42, -0.22, 0.1, -0.25),
        (1.5, 0.35, 0.65, 0.62, 0.42, 0.22, 0.1, 0.25),
    ]
    for x, y, z, h, r, lx, ly, c in tongues:
        parts.append(finish(flame("Flame", (x, y, z), h, r, (lx, ly), c), "fire"))
        # a flat yellow inner flame on its inward face (toward the seat's middle), the cartoon way
        d = Vector((x, y, 0)).normalized()
        turn = math.atan2(d.y, d.x) - math.pi / 2  # turns +Y onto d
        core = flame("Core", (0, 0, 0), h * 0.62, r * 0.62, (0, 0), c * 0.6)
        flat = Matrix.Rotation(turn, 4, "Z") @ Matrix.Diagonal((1, 0.4, 1, 1)) @ Matrix.Rotation(-turn, 4, "Z")
        at = Vector((x, y, z + 0.18)) - d * (r * 0.62)
        parts.append(finish(placed(core, Matrix.Translation(at) @ flat), "yellow"))
    # little licks round the front corners, kept low (the rider's knees are above them)
    for sx in (-1, 1):
        parts.append(finish(flame("Lick", (sx * 1.45, -0.7, 0.68), 0.42, 0.3, (sx * 0.15, -0.05), sx * 0.2), "fire"))

    # The face on the front puff
    fy = -hd + 0.06
    parts += face(Matrix.Translation((0, fy, 0.62)), size=1.3, mouth="w")

    parts.append(front_marker(DEPTH))
    return parts
