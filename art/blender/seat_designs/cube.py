"""Pixel Zone: the Pixel Cube Seat. A chunky voxel block built from 6 x 6 x 2 slightly beveled little cubes in
bright rainbow diagonals, flat on top where the rider sits, with an 8-bit face on the front made of tiny
black, white and pink pixel cubes, and pixel sparkles standing on its four top corners."""

import math

from mathutils import Matrix

from seatkit import FACE_COLORS, box, finish, front_marker, join, placed

NAME = "Cube"
TITLE = "Pixel Cube Seat"
ZONE = 10
ORDER = 1
COLORS = {
    **FACE_COLORS,
    "red": (1.0, 0.12, 0.2),
    "orange": (1.0, 0.42, 0.04),
    "yellow": (1.0, 0.82, 0.05),
    "green": (0.15, 0.8, 0.25),
    "blue": (0.1, 0.45, 1.0),
    "purple": (0.5, 0.15, 0.95),
    "pixel": (0.02, 0.02, 0.03),
    "sparkle": (1.0, 0.95, 0.45),
}
GLOW = ("sparkle",)
LIGHT = (1.0, 0.85, 1.0)

N = 6  # cubes along each side
LAYERS = 2  # cubes stacked up
CELL = 0.55  # each little cube's size
BOTTOM = 0.05
TOP = BOTTOM + LAYERS * CELL  # the flat top, where the rider sits
RAINBOW = ("red", "orange", "yellow", "green", "blue", "purple")
PIX = 0.15  # the face's pixel size


def cell_center(i, j, k):
    return ((i - (N - 1) / 2) * CELL, (j - (N - 1) / 2) * CELL, BOTTOM + (k + 0.5) * CELL)


def pixels(name, cells, origin, size, role, depth=None):
    """A group of tiny cubes on a plane facing -Y: `cells` are (column, row) from `origin`, row up."""
    ox, oy, oz = origin
    objs = [box(name, (size * 0.96, depth or size, size * 0.96), (ox + c * size, oy, oz + r * size), bevel=size * 0.12, segments=2)
            for c, r in cells]
    return finish(join(objs), role)


def build():
    parts = []
    # The little cubes, one mesh per color: rainbow stripes running diagonally across the top and down the
    # sides
    groups = {role: [] for role in RAINBOW}
    for i in range(N):
        for j in range(N):
            for k in range(LAYERS):
                # only the outside shows; the inside is filled by the core below
                if 0 < i < N - 1 and 0 < j < N - 1 and k < LAYERS - 1:
                    continue
                role = RAINBOW[(i - j + k + 2 * N) % len(RAINBOW)]
                groups[role].append(box("Voxel", (CELL, CELL, CELL), cell_center(i, j, k), bevel=0.06, segments=2))
    for role, objs in groups.items():
        parts.append(finish(join(objs), role))
    # a core inside, so no light shows through the seams between the cubes
    parts.append(finish(box("Core", (N * CELL - 0.1, N * CELL - 0.1, LAYERS * CELL - 0.03), (0, 0, BOTTOM + LAYERS * CELL / 2), bevel=0), "purple"))

    # The 8-bit face on the front: 2 x 3 pixel eyes with a white shine pixel, pink blush pixels and a smile,
    # standing a little proud of the front cubes
    fy = -N * CELL / 2 - PIX * 0.3
    fz = BOTTOM + CELL * 1.05  # the face's middle height
    eye = [(0, 0), (1, 0), (0, 1), (1, 1), (0, 2)]  # (1, 2) is the shine
    for sx in (-1, 1):
        ox = sx * 0.6 - PIX / 2
        parts.append(pixels("Eye", eye, (ox, fy, fz - PIX * 0.5), PIX, "pixel"))
        parts.append(pixels("Shine", [(1, 2)], (ox, fy - 0.01, fz - PIX * 0.5), PIX, "shine"))
        parts.append(pixels("Blush", [(0, 0), (1, 0)], (sx * 1.05 - PIX / 2, fy, fz - PIX * 1.2), PIX, "blush"))
    smile = [(-2, 1), (-1, 0), (0, 0), (1, 0), (2, 1)]
    parts.append(pixels("Mouth", smile, (0, fy, fz - PIX * 2.6), PIX, "pixel"))

    # Pixel sparkles: a plus of tiny glowing cubes standing on each top corner, turned to face out diagonally
    s = 0.11
    plus = [(0, 0), (0, 1), (0, 2), (-1, 1), (1, 1)]
    for cx in (-1, 1):
        for cy in (-1, 1):
            spark = pixels("Sparkle", plus, (0, 0, s / 2), s, "sparkle", depth=s)
            corner = (cx * (N - 1) / 2 * CELL, cy * (N - 1) / 2 * CELL, TOP)
            angle = math.atan2(cy, cx) + math.pi / 2
            parts.append(placed(spark, Matrix.Translation(corner) @ Matrix.Rotation(angle, 4, "Z")))

    parts.append(front_marker(N * CELL))
    return parts
