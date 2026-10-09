"""Pixel Zone: the Pixel Heart Seat. A classic 8-bit heart lying flat, point to the front, built as a thick slab
of slightly beveled voxels three high: red on top with lighter highlight pixels and a white shine on the left
lobe, darker outline pixels round its edge and down its sides, and a small pixel face on the step above its
point."""

from seatkit import FACE_COLORS, box, finish, front_marker, join

NAME = "Heart"
TITLE = "Pixel Heart Seat"
ZONE = 10
ORDER = 2
COLORS = {
    **FACE_COLORS,
    "red": (1.0, 0.06, 0.16),
    "light": (1.0, 0.45, 0.55),
    "dark": (0.3, 0.0, 0.05),
    "deep": (0.7, 0.02, 0.1),
    "pixel": (0.02, 0.02, 0.03),
}
LIGHT = (1.0, 0.45, 0.55)

# The sprite, back (the lobes) to front (the point); its middle row and column sit on the seat's middle
SPRITE = (
    ".XX...XX.",
    "XXXX.XXXX",
    "XXXXXXXXX",
    "XXXXXXXXX",
    "XXXXXXXXX",
    ".XXXXXXX.",
    "..XXXXX..",
    "...XXX...",
    "....X....",
)
HIGHLIGHT = {(1, 1): "light", (1, 2): "light", (2, 1): "light", (3, 1): "light"}  # (row, column)
SHINE = {(2, 2)}  # (row, column) of the white pixel
CELL = 0.4  # voxel width and depth
LAYER = 0.34  # voxel height
LAYERS = 3
BOTTOM = 0.05
TOP = BOTTOM + LAYERS * LAYER  # the flat top, where the rider sits
PIX = 0.1  # the face's pixel size


def cell(row, col, layer):
    n = len(SPRITE)
    return ((col - (n - 1) / 2) * CELL, ((n - 1) / 2 - row) * CELL, BOTTOM + (layer + 0.5) * LAYER)


def filled(row, col):
    return 0 <= row < len(SPRITE) and 0 <= col < len(SPRITE[row]) and SPRITE[row][col] == "X"


def pixels(name, cells, origin, size, role):
    """A group of tiny cubes on a plane facing -Y: `cells` are (column, row) from `origin`, row up."""
    ox, oy, oz = origin
    objs = [box(name, (size * 0.96, size, size * 0.96), (ox + c * size, oy, oz + r * size), bevel=size * 0.12, segments=2)
            for c, r in cells]
    return finish(join(objs), role)


def build():
    parts = []
    groups = {"red": [], "light": [], "dark": [], "deep": [], "shine": []}
    last = len(SPRITE) - 1
    for row, line in enumerate(SPRITE):
        for col in range(len(line)):
            if not filled(row, col):
                continue
            edge = not all(filled(row + dr, col + dc) for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            for layer in range(LAYERS):
                top = layer == LAYERS - 1
                if not top and not edge:
                    continue  # hidden inside the slab
                if edge:
                    role = "dark" if top else "deep"  # the outline round the top's edge, and the sides below it
                elif (row, col) in SHINE:
                    role = "shine"
                else:
                    role = HIGHLIGHT.get((row, col), "red")
                groups[role].append(box("Voxel", (CELL, CELL, LAYER), cell(row, col, layer), bevel=0.05, segments=2))
    for role, objs in groups.items():
        if objs:
            parts.append(finish(join(objs), role))
    # a core inside the slab, so no light shows through the seams between the voxels
    inner = [box("Core", (CELL - 0.08, CELL - 0.08, LAYERS * LAYER - 0.08), (cell(r, c, 0)[0], cell(r, c, 0)[1], BOTTOM + LAYERS * LAYER / 2), bevel=0)
             for r, line in enumerate(SPRITE) for c in range(len(line)) if filled(r, c)]
    parts.append(finish(join(inner), "deep"))

    # The face: pixel eyes and blush on the three-wide step's front either side of the point, and a small
    # smile on the point's tip just below them
    fy = cell(last - 1, 4, 0)[1] - CELL / 2 - PIX * 0.3
    fz = BOTTOM + LAYER * 1.9  # the eyes' bottom
    eye = [(0, 0), (1, 0), (0, 1), (1, 1), (0, 2)]  # (1, 2) is the shine
    for sx in (-1, 1):
        ox = sx * 0.38 - PIX / 2
        parts.append(pixels("Eye", eye, (ox, fy, fz), PIX, "pixel"))
        parts.append(pixels("Shine", [(1, 2)], (ox, fy - 0.01, fz), PIX, "shine"))
        parts.append(pixels("Blush", [(0, 0), (1, 0)], (sx * 0.38 - PIX / 2, fy, fz - PIX * 1.6), PIX, "blush"))
    my = cell(last, 4, 0)[1] - CELL / 2 - PIX * 0.3
    smile = [(-1, 1), (0, 0), (1, 1)]
    parts.append(pixels("Mouth", smile, (0, my, fz - PIX * 1.3), PIX, "pixel"))

    parts.append(front_marker(len(SPRITE) * CELL))
    return parts
