"""Frozen Lake: the Ice Block Seat. A chunky glossy ice block with chamfered (faceted) edges, a puffy snow cap
on top where the rider sits, little icicles hanging from the cap's lip, pale shards frozen into its sides and
a Cubeling face on the front."""

import math

from mathutils import Matrix

from seatkit import FACE_COLORS, blob, box, cone, face, finish, front_marker, join, placed

NAME = "Ice"
TITLE = "Ice Block Seat"
ZONE = 9
ORDER = 1
TOP = 1.05  # the snow cap's top in the middle
COLORS = {
    **FACE_COLORS,
    "ice": (0.42, 0.72, 0.96),
    "shard": (0.78, 0.93, 1.0),
    "snow": (0.95, 0.97, 1.0),
}
LIGHT = (0.7, 0.92, 1.0)

WIDTH = 3.3  # the block, side to side
DEPTH = 2.9  # front to back
BLOCK_TOP = 0.95  # where the block ends and the snow begins


def crystal(name, length, radius, matrix):
    """A long six-sided shard with pointed ends, along its +Z."""
    c = cone(name, radius, 0.0, length * 0.5, (0, 0, length * 0.25), vertices=6)
    d = cone(name, 0.0, radius, length * 0.5, (0, 0, -length * 0.25), vertices=6)
    obj = join([c, d])
    return placed(obj, matrix)


def build():
    parts = []
    hw, hd = WIDTH / 2, DEPTH / 2

    # The block: a box with its edges cut off in one flat chamfer and its corners nudged a little off true, so
    # it reads as a hewn chunk of ice; drawn flat-shaded so every facet catches the light on its own
    block = box("Block", (WIDTH, DEPTH, BLOCK_TOP), (0, 0, 0.05 + BLOCK_TOP / 2), bevel=0.3, segments=1)
    for v in block.data.vertices:
        t = 1 - (v.co.z - 0.05) / BLOCK_TOP  # 0 at the top, 1 at the bottom
        v.co.x *= 1 - 0.08 * t
        v.co.y *= 1 - 0.08 * t
        if 0.1 < v.co.z < BLOCK_TOP - 0.05:  # leave the bottom flat and the top level for the snow
            v.co.x += 0.06 * math.sin(v.co.y * 5.1 + v.co.z * 3.0)
            v.co.y += 0.06 * math.sin(v.co.x * 4.3 + v.co.z * 2.0)
    parts.append(finish(block, "ice"))
    for poly in block.data.polygons:
        poly.use_smooth = False

    # Pale shards frozen into the block: flat six-sided crystals lying in its side and back faces, just proud
    # of the surface. (position, which face, tilt in the face, length, width)
    shards = [
        ((-hw + 0.08, 0.5, 0.5), "x", 30, 0.7, 0.16),
        ((-hw + 0.1, -0.45, 0.42), "x", -25, 0.45, 0.12),
        ((hw - 0.08, 0.25, 0.48), "x", -35, 0.75, 0.16),
        ((hw - 0.1, -0.7, 0.4), "x", 20, 0.42, 0.11),
        ((-0.75, hd - 0.08, 0.5), "y", 30, 0.7, 0.16),
        ((0.55, hd - 0.08, 0.46), "y", -25, 0.55, 0.13),
        ((1.25, -hd + 0.12, 0.42), "y", -20, 0.4, 0.1),
    ]
    for (x, y, z), axis, tilt, length, width in shards:
        shard = crystal("Shard", length, width, Matrix.Scale(0.6, 4, (1, 0, 0)))  # flattened along its X
        if axis == "x":
            m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(tilt), 4, "X")
        else:
            m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(tilt), 4, "Y") @ Matrix.Rotation(math.pi / 2, 4, "Z")
        parts.append(finish(placed(shard, m), "shard"))

    # The snow cap: a flat pillow of snow over the block's top, its edge rolled into soft lumps that spill a
    # little over the sides, with a few longer drips; flattened and dipped where the rider sits
    puffs = []
    for gx in (-1.0, -0.33, 0.33, 1.0):
        for gy in (-0.85, 0.0, 0.85):
            puffs.append((0.5, (gx * (hw - 0.55), gy * (hd - 0.6) / 0.85, BLOCK_TOP + 0.06), (1.25, 1.25, 0.28)))
    n = 30
    for i in range(n):
        a = 2 * math.pi * i / n
        # points round a rounded rectangle just inside the block's top edge
        cx, cy = math.cos(a), math.sin(a)
        k = 1 / max(abs(cx) / (hw - 0.2), abs(cy) / (hd - 0.2))
        x, y = cx * k, cy * k
        x = math.copysign(min(abs(x), hw - 0.2), x)
        y = math.copysign(min(abs(y), hd - 0.2), y)
        r = 0.21 if i % 2 == 0 else 0.18
        puffs.append((r, (x, y, BLOCK_TOP + 0.02), (1, 1, 0.8)))
    # drips running down the block's front and sides
    for x, y, z, r in ((-0.95, -hd + 0.06, 0.82, 0.13), (0.3, -hd + 0.07, 0.86, 0.11), (1.0, -hd + 0.06, 0.8, 0.12),
                       (-hw + 0.06, -0.9, 0.83, 0.12), (-hw + 0.06, 0.9, 0.8, 0.13), (hw - 0.06, -0.2, 0.82, 0.13),
                       (hw - 0.06, 1.0, 0.85, 0.11), (-0.2, hd - 0.06, 0.82, 0.13)):
        puffs.append((r, (x, y, z), (1, 1, 1.3)))
    snow = blob("Snow", puffs, voxel=0.06, keep=6000)
    for v in snow.data.vertices:
        if v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.3
        rr = math.hypot(v.co.x / 1.1, v.co.y / 1.0)
        if v.co.z > TOP - 0.12 and rr < 1:
            v.co.z -= 0.06 * (1 - rr * rr)
    parts.append(finish(snow, "snow"))

    # Icicles hanging from the snow's lip at the front corners and along the sides
    icicles = [(-1.32, -hd - 0.03, 0.42), (-1.08, -hd - 0.03, 0.26), (1.15, -hd - 0.03, 0.3), (1.36, -hd - 0.03, 0.4),
               (-hw - 0.03, -0.3, 0.36), (-hw - 0.03, 0.05, 0.24),
               (hw + 0.03, -0.45, 0.28), (hw + 0.03, 0.55, 0.38), (0.9, hd + 0.03, 0.32), (-0.2, hd + 0.03, 0.26)]
    for x, y, length in icicles:
        top_z = BLOCK_TOP + 0.02
        parts.append(finish(cone("Icicle", 0.01, 0.1, length, (x, y, top_z - length / 2), vertices=12), "shard"))

    # The face on the block's front, under the snow
    fz = 0.5
    front_y = -hd * (1 - 0.07 * (1 - (fz - 0.05) / BLOCK_TOP))
    parts += face(Matrix.Translation((0, front_y - 0.02, fz)), size=1.35)

    parts.append(front_marker(DEPTH))
    return parts
