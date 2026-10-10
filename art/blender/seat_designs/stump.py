"""Forest: the Stump Seat. A cut tree stump: light wood on top (the sitting surface) with darker tree rings,
brown bark sides with chunky vertical ridges and a rounded bark rim, roots spreading out at the bottom, green
moss patches over the rim and side, a little red-capped mushroom with white dots and a face on the front bark."""

import math

import bmesh
import bpy
from mathutils import Matrix

from seatkit import FACE_COLORS, bake, ball, blob, cylinder, face, finish, front_marker, petal_matrix, placed, torus

NAME = "Stump"
TITLE = "Stump Seat"
ZONE = 3
ORDER = 1
TOP = 1.05  # the cut wood top
COLORS = {
    **FACE_COLORS,
    "bark": (0.32, 0.16, 0.07),
    "wood": (0.96, 0.7, 0.38),
    "ring": (0.72, 0.44, 0.2),
    "moss": (0.22, 0.55, 0.12),
    "cap": (0.92, 0.12, 0.1),
    "stem": (1.0, 0.94, 0.82),
}

RADIUS = 1.28  # the trunk's radius (between the ridges)
RIDGES = 9  # chunky vertical bark ridges round the trunk
FACE_ANGLE = -90  # the front
CAP = 0.3  # the mushroom cap's radius


def bark_radius(angle, z):
    """The trunk's outline: round ridges (one valley right at the front, under the face) and a flare at the
    bottom where the roots start."""
    a = angle - math.radians(FACE_ANGLE) + math.pi / RIDGES
    ridge = 0.1 * max(math.cos(RIDGES * a), 0) ** 0.6
    flare = 0.22 * max(1 - z / 0.45, 0) ** 2
    return RADIUS + ridge + flare


def trunk():
    """The bark trunk as a lathe of rings, each ring following the ridged outline, closed at both ends."""
    bm = bmesh.new()
    n, rows = 96, 12
    top_z = TOP - 0.06
    rings = []
    for j in range(rows + 1):
        z = top_z * j / rows
        rings.append([bm.verts.new((math.cos(2 * math.pi * i / n) * bark_radius(2 * math.pi * i / n, z), math.sin(2 * math.pi * i / n) * bark_radius(2 * math.pi * i / n, z), z)) for i in range(n)])
    for j in range(rows):
        for i in range(n):
            k = (i + 1) % n
            bm.faces.new((rings[j][i], rings[j][k], rings[j + 1][k], rings[j + 1][i]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    mesh = bpy.data.meshes.new("Trunk")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Trunk", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build():
    parts = []
    parts.append(finish(trunk(), "bark"))
    # A rounded bark rim round the cut top, and the light wood disc inside it, its top the sitting surface
    rim = torus("Rim", RADIUS + 0.0, 0.085, (0, 0, TOP - 0.06), segments=72)
    for v in rim.data.vertices:
        # follow the ridges a little
        a = math.atan2(v.co.y, v.co.x)
        s = bark_radius(a, TOP) / RADIUS
        v.co.x *= s
        v.co.y *= s
    parts.append(finish(rim, "bark"))
    wood = cylinder("Wood", RADIUS - 0.02, 0.14, (0, 0, TOP - 0.07), vertices=64, bevel=0.04)
    parts.append(finish(wood, "wood"))
    # Tree rings: thin darker rings just proud of the wood, a little wobbly like real growth rings
    for r in (0.28, 0.55, 0.8, 1.04):
        bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.024, major_segments=40 + int(r * 24), minor_segments=6, location=(0, 0, TOP - 0.008))
        ring = bpy.context.active_object
        for v in ring.data.vertices:
            a = math.atan2(v.co.y, v.co.x)
            s = 1 + 0.035 * math.sin(3 * a + r * 4)
            v.co.x *= s
            v.co.y *= s
        ring.scale = (1, 1, 0.5)
        bake(ring)
        parts.append(finish(ring, "ring"))
    # (a tiny darker heart in the middle, flush with the wood)
    parts.append(finish(ball("Heart", 0.08, (0.05, 0.03, TOP - 0.02), (1, 1, 0.25)), "ring"))

    # Roots spreading out at the bottom: long rounded ridges running down into the ground, the front left clear
    for angle, length in ((-30, 0.62), (25, 0.55), (80, 0.65), (135, 0.6), (195, 0.62), (245, 0.55)):
        m = petal_matrix(angle, RADIUS + 0.05, 0.23, -3)
        root = ball("Root", 1, (0, 0, 0), (0.3, length, 0.22))
        for v in root.data.vertices:
            t = v.co.y / length
            # a chunky rounded toe: a little narrower and lower toward its end, the inner end rising up the trunk
            v.co.x *= 1 - 0.25 * max(t, 0)
            v.co.z *= 1 - 0.2 * max(t, 0)
            v.co.z += 0.25 * max(-t, 0)
        parts.append(finish(placed(root, m), "bark"))

    # Moss patches draped over the rim at the back left and over the side at the right
    for angle, z0 in ((125, TOP - 0.02), (20, 0.5), (55, TOP - 0.04), (215, 0.35)):
        a = math.radians(angle)
        balls = []
        for k, (da, dz, r) in enumerate(((0, 0, 0.22), (0.17, -0.08, 0.19), (-0.15, -0.12, 0.18), (0.08, -0.27, 0.17), (-0.06, 0.06, 0.15), (0.22, -0.3, 0.13))):
            rr = bark_radius(a + da, z0) + (0.0 if z0 > TOP - 0.1 else 0.02)
            balls.append((r, (math.cos(a + da) * rr, math.sin(a + da) * rr, z0 + dz), (1, 1, 0.75)))
        parts.append(finish(blob("Moss", balls, voxel=0.05, keep=2500), "moss"))

    # A little mushroom growing at the front right of the trunk's foot: cream stem, red cap with white dots
    ma = math.radians(-48)
    mx, my = math.cos(ma) * (RADIUS + 0.3), math.sin(ma) * (RADIUS + 0.3)
    stem = cylinder("Stem", 0.11, 0.4, (mx, my, 0.2), vertices=16, bevel=0.03)
    for v in stem.data.vertices:
        v.co.x += 0.05 * (v.co.z / 0.4)
    parts.append(finish(stem, "stem"))
    cap = ball("Cap", CAP, (mx + 0.04, my, 0.42), (1, 1, 0.75))
    for v in cap.data.vertices:
        if v.co.z < 0:  # (its points are around its own middle) a flatter underside
            v.co.z *= 0.35
    parts.append(finish(cap, "cap"))
    for dx, dy in ((0.0, 0.0), (-0.17, -0.08), (0.17, -0.06), (0.03, -0.2), (-0.08, 0.16), (0.13, 0.14)):
        dz = CAP * 0.75 * math.sqrt(max(1 - (dx * dx + dy * dy) / CAP ** 2, 0))  # on the cap's surface
        parts.append(finish(ball("Dot", 0.05, (mx + 0.04 + dx, my + dy, 0.42 + dz), (1, 1, 0.45)), "stem"))

    # The face on the front bark, in the valley between two ridges
    fy = -bark_radius(math.radians(FACE_ANGLE), 0.55)
    parts.extend(face(Matrix.Translation((0, fy + 0.02, 0.55)), 1.05))

    parts.append(front_marker(2 * (RADIUS + 0.3)))
    return parts
