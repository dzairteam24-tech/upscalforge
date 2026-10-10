"""Flower Field: the Bee Seat. A round fluffy bumblebee, yellow with dark brown stripes, flattened on top where
the rider sits: a Cubeling face on its yellow front, two little antennae with ball tips, a fluffy cream tuft,
two pairs of small glassy pale-blue wings at its back sides angled up and a tiny stinger behind."""

import math

import bmesh
import bpy
from mathutils import Matrix

from seatkit import FACE_COLORS, ball, blob, cone, face, finish, front_marker, placed, tube

NAME = "Bee"
TITLE = "Bee Seat"
ZONE = 2
ORDER = 3
TOP = 1.15  # the flattened top of the bee's back
COLORS = {
    **FACE_COLORS,
    "body": (1.0, 0.78, 0.08),
    "stripe": (0.2, 0.09, 0.04),
    "fuzz": (1.0, 0.95, 0.78),
    "glass": (0.6, 0.84, 1.0),
    "vein": (0.42, 0.66, 0.95),
}

HALF = (1.5, 1.48, 0.74)  # the body's half sizes: side to side, front to back, up
MIDZ = 0.76  # the body's middle height
STRIPES = ((-0.6, -0.24), (0.12, 0.48), (0.84, 1.2))  # the brown bands, front to back (y)


def split_where(obj, test, name):
    """Splits off the faces whose middle passes `test` into a new object (a differently colored area)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    picked = [f for f in bm.faces if test(f.calc_center_median())]
    sbm = bmesh.new()
    vmap = {}
    for f in picked:
        vs = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = sbm.verts.new(v.co)
            vs.append(vmap[v])
        sbm.faces.new(vs)
    mesh = bpy.data.meshes.new(name)
    sbm.to_mesh(mesh)
    sbm.free()
    bmesh.ops.delete(bm, geom=picked, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    part = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(part)
    return part


def body_shell():
    """The round body: a sphere whose rings run front to back (so the stripes split off along clean rings),
    squashed into a chubby bun and flattened on top."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=36, radius=1, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = "BeeBody"
    obj.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.scale = HALF
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for v in obj.data.vertices:
        # a fuller back half, a rounder front, then lifted to its height
        if v.co.y > 0:
            v.co.x *= 1 + 0.04 * v.co.y
        v.co.z += MIDZ
        if v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.12
        rr = math.hypot(v.co.x / 0.85, v.co.y / 0.85)
        if v.co.z > TOP - 0.15 and rr < 1:
            v.co.z -= 0.06 * (1 - rr * rr)
    return obj


def wing_frame(sx, sweep, tilt, root):
    """A wing's frame: local +X runs out from the root, swept back by `sweep` and raised by `tilt` (degrees)."""
    angle = math.radians(sweep) if sx > 0 else math.pi - math.radians(sweep)
    return Matrix.Translation(root) @ Matrix.Rotation(angle, 4, "Z") @ Matrix.Rotation(math.radians(-tilt), 4, "Y")


def build():
    parts = []
    body = body_shell()
    stripes = split_where(body, lambda c: any(a < c.y < b for a, b in STRIPES), "BeeStripes")
    parts.append(finish(body, "body"))
    parts.append(finish(stripes, "stripe"))

    # A little fluffy cream tuft on the front of the top, between the antennae (in front of the rider's legs)
    tuft = [(0.14, (x, -1.27, 1.04 + 0.05 * (x == 0)), (1, 0.9, 1)) for x in (-0.16, 0.0, 0.16)]
    parts.append(finish(blob("Tuft", tuft, voxel=0.05, keep=1500), "fuzz"))

    # The face on the yellow front
    front_y = -HALF[1]
    parts.extend(face(Matrix.Translation((0, front_y + 0.08, MIDZ - 0.02)), 1.15))
    # Two little antennae from the front of the top, bending forward, with brown ball tips
    for sx in (-1, 1):
        pts = [(sx * 0.32, -1.12, 1.08), (sx * 0.38, -1.3, 1.32), (sx * 0.48, -1.44, 1.48), (sx * 0.6, -1.54, 1.53)]
        parts.append(finish(tube("Antenna", pts, 0.04), "stripe"))
        parts.append(finish(ball("Tip", 0.1, pts[-1]), "stripe"))

    # Two pairs of small glassy wings at the back sides, angled up and back, with a thin vein down each
    for sx in (-1, 1):
        for sweep, tilt, root, length, width in ((48, 38, (sx * 1.12, 0.62, 1.05), 1.2, 0.72), (72, 28, (sx * 1.0, 0.95, 1.0), 0.92, 0.54)):
            frame = wing_frame(sx, sweep, tilt, root)
            w = ball("Wing", 1, (length / 2, 0, 0), (length / 2, width / 2, 0.05))
            for v in w.data.vertices:
                # narrow at the root, round at the tip
                t = v.co.x / length + 0.5  # (its points are around its own middle) 0 at the root, 1 at the tip
                v.co.y *= 0.6 + 0.45 * max(t, 0)
            parts.append(finish(placed(w, frame), "glass"))
            vein = [(0.05, 0, 0.045), (length * 0.45, 0.02, 0.052), (length * 0.85, -0.02, 0.045)]
            parts.append(finish(placed(tube("Vein", vein, 0.022), frame), "vein"))

    # A tiny stinger at the back, poking out of the last stripe
    sting = cone("Stinger", 0.16, 0.0, 0.42, (0, 0, 0), vertices=16)
    parts.append(finish(placed(sting, Matrix.Translation((0, HALF[1] + 0.08, MIDZ - 0.05)) @ Matrix.Rotation(-math.pi / 2 - 0.15, 4, "X")), "stripe"))

    parts.append(front_marker(3.4))
    return parts
