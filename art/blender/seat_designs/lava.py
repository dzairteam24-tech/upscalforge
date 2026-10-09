"""Volcano: the Lava Rock Seat. A chunky low-poly lump of dark volcanic rock, built of big faceted chunks with a
flat top to sit on, glowing orange cracks running down its sides, lighter boulders hunched round its foot with
hot glowing embers resting on them, and a flat-cut front with a Cubeling face whose eyes and smile glow."""

import math

import bpy
from mathutils import Matrix, Vector
from seatkit import (
    FACE_COLORS,
    apply_modifiers,
    face,
    finish,
    front_marker,
    join,
    placed,
    tube,
)

NAME = "Lava"
TITLE = "Lava Rock Seat"
ZONE = 8
ORDER = 1
TOP = 1.05  # the rock's flat top, where the rider sits
COLORS = {
    **FACE_COLORS,
    "rock": (0.03, 0.025, 0.03),
    "stone": (0.075, 0.06, 0.06),
    "crack": (1.0, 0.24, 0.01),
    "ember": (1.0, 0.7, 0.08),
    "eye": (1.0, 0.62, 0.06),
    "shine": (1.0, 0.97, 0.8),
    "mouth": (1.0, 0.45, 0.04),
    "blush": (1.0, 0.25, 0.12),
}
GLOW = ("crack", "ember", "eye", "mouth")
LIGHT = (1.0, 0.45, 0.12)

DEPTH = 3.1  # front to back
FACE_Y = -1.36  # the flat-cut front the face sits on
FACE_Z = 0.52


def rnd(i):
    """A repeatable pseudo-random number in 0..1 (no `random` module needed)."""
    return (math.sin(i * 12.9898 + 4.1414) * 43758.5453) % 1.0


def chunk(name, size, location, seed, subdiv=1, spin=True):
    """A lumpy low-poly rock chunk: an icosphere with its points nudged in and out."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=1, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = name
    for i, v in enumerate(obj.data.vertices):
        v.co *= 0.88 + 0.24 * rnd(seed * 31 + i)
    turn = Matrix.Rotation(rnd(seed) * 6.28, 4, "Z") if spin else Matrix()
    for v in obj.data.vertices:
        v.co = turn @ v.co
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    return placed(obj, Matrix.Translation(location))


def flat_shaded(obj):
    """Splits every edge so each facet shades flat, like cut stone (finish() smooths shading otherwise)."""
    split = obj.modifiers.new("Split", "EDGE_SPLIT")
    split.split_angle = 0.0
    apply_modifiers(obj)
    return obj


def side_point(obj, angle, z, inset):
    """Where a ray from far outside, aimed at the rock's middle at height z along `angle`, meets its side."""
    d = Vector((math.cos(angle), math.sin(angle), 0))
    hit, loc, normal, _ = obj.ray_cast(d * 6 + Vector((0, 0, z)), -d)
    return loc - normal * inset if hit else None


def build():
    parts = []
    # The rock: a big faceted core with chunks bulging out all round it
    pieces = [chunk("Core", (1.5, 1.32, 0.62), (0, 0, 0.56), 1, subdiv=2)]
    ring = [(0, 1.15, 0.5, 0.6), (40, 1.15, 0.46, 0.55), (90, 1.0, 0.56, 0.58), (140, 1.2, 0.48, 0.56),
            (180, 1.18, 0.52, 0.6), (220, 1.2, 0.42, 0.55), (320, 1.18, 0.44, 0.56)]
    for i, (deg, r, z, size) in enumerate(ring):
        a = math.radians(deg)
        pieces.append(chunk("Chunk", (size, size * 0.95, size * 0.9), (math.cos(a) * r, math.sin(a) * r * 0.85, z), i + 5))
    # the front chunk, flattened later for the face
    pieces.append(chunk("Front", (0.95, 0.5, 0.48), (0, -0.95, 0.52), 20, spin=False))
    rock = join(pieces)
    rock.name = "LavaRock"
    low = min(v.co.z for v in rock.data.vertices)
    for v in rock.data.vertices:
        v.co.z += 0.03 - low
        # the flat top to sit on
        v.co.z = min(v.co.z, TOP)
        # the flat-cut front for the face
        if v.co.y < FACE_Y and abs(v.co.x) < 1.0 and 0.1 < v.co.z < TOP - 0.08:
            v.co.y = FACE_Y
    flat_shaded(rock)
    parts.append(finish(rock, "rock"))
    bpy.context.view_layer.update()

    # Glowing cracks running down the sides from the top's edge (not across the face), each with a branch
    for k, deg in enumerate((-150, -32, 12, 58, 100, 142, 196)):
        pts = []
        for j in range(13):
            z = TOP - 0.03 - (TOP - 0.25) * j / 12
            # wandering side to side a little, in three bends
            a = math.radians(deg + (rnd(k * 17 + j // 4) - 0.5) * 14 + 4 * math.sin(j * 0.9 + k))
            p = side_point(rock, a, z, -0.005)
            if p:
                pts.append(p)
        if len(pts) > 2:
            parts.append(finish(tube("Crack", pts, 0.05), "crack"))
            a = math.radians(deg + (16 if k % 2 else -16))
            branch = [pts[5]]
            for j in range(1, 5):
                q = side_point(rock, a * j / 4 + math.radians(deg) * (1 - j / 4), pts[5].z - 0.07 * j, -0.005)
                if q:
                    branch.append(q)
            if len(branch) > 2:
                parts.append(finish(tube("Branch", branch, 0.035), "crack"))
            # the crack also runs a little way in over the top's rim
            d = Vector((math.cos(math.radians(deg)), math.sin(math.radians(deg)), 0))
            rim = pts[0] - d * 0.3
            rim.z = TOP
            edge = pts[0].copy()
            edge.z = TOP
            parts.append(finish(tube("Rim", [pts[0], edge, rim], 0.045), "crack"))

    # Lighter boulders hunched round its foot, each with a glowing ember resting on top
    boulders = [((-1.5, -0.85), (0.42, 0.38, 0.32)), ((1.55, -0.5), (0.36, 0.4, 0.3)),
                ((1.3, 1.05), (0.46, 0.4, 0.34)), ((-1.35, 1.05), (0.36, 0.34, 0.28)),
                ((0.95, -1.3), (0.26, 0.24, 0.22))]
    for i, ((x, y), size) in enumerate(boulders):
        b = chunk("Boulder", size, (x, y, size[2] * 1.05), i + 40)
        flat_shaded(b)
        parts.append(finish(b, "stone"))
        if i < 4:
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.11, location=(0, 0, 0))
            e = bpy.context.active_object
            for j, v in enumerate(e.data.vertices):
                v.co *= 0.85 + 0.3 * rnd(i * 7 + j)
            top = max(v.co.z for v in b.data.vertices)
            placed(e, Matrix.Translation((x + 0.05, y, top + 0.02)) @ Matrix.Diagonal((1, 0.9, 0.7, 1)))
            flat_shaded(e)
            parts.append(finish(e, "ember"))

    # The face on the flat-cut front: glowing eyes and smile
    parts += face(Matrix.Translation((0, FACE_Y, FACE_Z)), size=1.15)

    parts.append(front_marker(DEPTH))
    return parts
