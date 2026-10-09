"""Pixel Zone: the Gamepad Seat. A big chunky retro game controller lying flat: a rounded purple body with two
grips toward the front, the rider sitting in its middle; a dark D-pad on the left lobe and four colored round
buttons on the right lobe (out past the rider's knees), start/select pills and shoulder buttons at the back,
a cable curling away behind, and a small face on its front."""

import math

import bpy  # noqa: I001 (bmesh only exists once bpy is loaded)
import bmesh
from mathutils import Matrix

from seatkit import FACE_COLORS, box, cylinder, face, finish, front_marker, join, placed, split_below, tube

NAME = "Gamepad"
TITLE = "Gamepad Seat"
ZONE = 10
ORDER = 3
TOP = 1.0  # the body's flat top, where the rider sits
COLORS = {
    **FACE_COLORS,
    "body": (0.42, 0.18, 0.9),
    "shade": (0.22, 0.08, 0.55),
    "dpad": (0.07, 0.06, 0.1),
    "red": (1.0, 0.1, 0.15),
    "yellow": (1.0, 0.78, 0.05),
    "green": (0.1, 0.8, 0.3),
    "blue": (0.1, 0.45, 1.0),
    "pill": (0.75, 0.72, 0.85),
    "cable": (0.1, 0.08, 0.14),
}
LIGHT = (0.75, 0.6, 1.0)

LOBE_X = 1.15  # the side lobes' middles
PAD_X = 1.45  # the D-pad's and the buttons' middles, out past the rider's knees
PAD_Y = -0.1


# The outline, as shapes whose union it is: (middle x, middle y, half-width, half-depth)
SHAPES = [(0, 0.02, 1.35, 0.98)] + [(sx * LOBE_X, 0.0, 0.85, 0.85) for sx in (-1, 1)] + [(sx * 1.27, -0.72, 0.56, 0.6) for sx in (-1, 1)]
BOTTOM = 0.05
EDGE_TOP = 0.2  # how round the top edge is
EDGE_BOTTOM = 0.32  # and the bottom edge


def outline(angle):
    """How far the outline reaches from the middle in a direction: the farthest exit from any of the shapes."""
    dx, dy = math.cos(angle), math.sin(angle)
    best = 0.0
    for cx, cy, a, b in SHAPES:
        # the ray t * d against the ellipse ((x - cx) / a)^2 + ((y - cy) / b)^2 = 1
        px, py, qx, qy = dx / a, dy / b, -cx / a, -cy / b
        A, B, C = px * px + py * py, 2 * (px * qx + py * qy), qx * qx + qy * qy - 1
        disc = B * B - 4 * A * C
        if disc >= 0:
            best = max(best, (-B + math.sqrt(disc)) / (2 * A))
    return best


def slab(name, steps=144):
    """The outline made into a slab: rings of points pulled in toward the top and bottom edges to round them."""
    rings = []
    for k in range(7):
        phi = -math.pi / 2 + (math.pi / 2) * k / 6
        rings.append((BOTTOM + EDGE_BOTTOM + EDGE_BOTTOM * math.sin(phi), EDGE_BOTTOM * (1 - math.cos(phi))))
    for k in range(7):
        phi = (math.pi / 2) * k / 6
        rings.append((TOP - EDGE_TOP + EDGE_TOP * math.sin(phi), EDGE_TOP * (1 - math.cos(phi))))
    reach = [outline(2 * math.pi * i / steps) for i in range(steps)]
    bm = bmesh.new()
    grid = []
    for z, inset in rings:
        row = []
        for i in range(steps):
            a = 2 * math.pi * i / steps
            r = max(reach[i] - inset, 0.05)
            row.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        grid.append(row)
    for lo, hi in zip(grid, grid[1:]):
        for i in range(steps):
            j = (i + 1) % steps
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bottom = bm.verts.new((0, 0, BOTTOM))
    top = bm.verts.new((0, 0, TOP))
    for i in range(steps):
        j = (i + 1) % steps
        bm.faces.new((grid[0][j], grid[0][i], bottom))
        bm.faces.new((grid[-1][i], grid[-1][j], top))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build():
    parts = []
    # The body: the controller's outline (a wide middle, two round lobes and two grips toward the front) made
    # into a thick slab with softly rounded edges, flat on top
    body = slab("Body")
    shade = split_below(body, 0.3, "Underside")
    parts.append(finish(body, "body"))
    parts.append(finish(shade, "shade"))

    # The D-pad on the left lobe: a raised plus of two rounded bars on a shallow round seat, with a dimple
    top = TOP + 0.02
    parts.append(finish(cylinder("PadSeat", 0.5, 0.06, (-PAD_X, PAD_Y, top), vertices=32, bevel=0.02), "shade"))
    # (the bars differ a hair in height so their tops don't fight where they cross)
    bars = [box("Bar", (0.78, 0.26, 0.12), (-PAD_X, PAD_Y, top + 0.06), bevel=0.05),
            box("Bar", (0.26, 0.78, 0.13), (-PAD_X, PAD_Y, top + 0.065), bevel=0.05)]
    parts.append(finish(join(bars), "dpad"))

    # Four round buttons on the right lobe in a diamond, each standing a little proud
    for role, (dx, dy) in (("yellow", (0, 0.26)), ("blue", (-0.26, 0)), ("red", (0.26, 0)), ("green", (0, -0.26))):
        parts.append(finish(cylinder("Button", 0.16, 0.14, (PAD_X + dx, PAD_Y + dy, top + 0.04), vertices=24, bevel=0.05), role))

    # Start and select: two little slanted pills behind the rider, and the shoulder buttons on the back corners
    for sx in (-1, 1):
        pill = box("Pill", (0.3, 0.11, 0.08), (0, 0, 0), bevel=0.05)
        parts.append(finish(placed(pill, Matrix.Translation((sx * 0.3, 0.8, TOP)) @ Matrix.Rotation(math.radians(25 * sx), 4, "Z")), "pill"))
        bumper = box("Bumper", (0.75, 0.3, 0.24), (0, 0, 0), bevel=0.11, segments=4)
        m = Matrix.Translation((sx * 1.2, 0.86, 0.74)) @ Matrix.Rotation(math.radians(-18 * sx), 4, "Z")
        parts.append(finish(placed(bumper, m), "shade"))

    # The cable: out of the back middle, then curling round in loops as it trails off to one side
    pts = [(0, 1.0, 0.5), (0, 1.25, 0.48)]
    for i in range(1, 41):
        t = i / 40
        a = t * 3.4 * math.pi
        x = 0.25 * math.sin(a) + 0.9 * t
        y = 1.32 + 0.22 * (1 - math.cos(a)) * (1 - 0.3 * t)
        pts.append((x, y, 0.48 - 0.33 * t + 0.08 * math.sin(a)))
    parts.append(finish(tube("Cable", pts, 0.075), "cable"))

    # A small face on the front, between the grips
    parts += face(Matrix.Translation((0, -0.96, 0.52)), size=1.05)

    parts.append(front_marker(3.3))
    return parts
