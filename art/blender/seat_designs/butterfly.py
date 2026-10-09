"""Flower Field: the Butterfly Seat. A chubby fuzzy butterfly lying lengthwise, the rider sitting on its back:
a soft apricot body with dark purple bands on its abdomen, a cream fluff collar, its round head at the front with a Cubeling face and two curly
antennae with pink ball tips, and four big rounded wings (sky-blue upper, lilac lower) with a dark purple rim
and pink and yellow spots, raised a little like a V so they stay clear of the rider's knees."""

import math

from mathutils import Matrix

import bmesh
import bpy

from seatkit import FACE_COLORS, ball, blob, face, finish, front_marker, placed, tube

NAME = "Butterfly"
TITLE = "Butterfly Seat"
ZONE = 2
ORDER = 2
TOP = 1.1  # the flattened back where the rider sits
COLORS = {
    **FACE_COLORS,
    "body": (1.0, 0.56, 0.3),
    "fuzz": (1.0, 0.93, 0.8),
    "upper": (0.42, 0.74, 1.0),
    "lower": (0.8, 0.6, 1.0),
    "rim": (0.3, 0.13, 0.62),
    "spot": (1.0, 0.42, 0.68),
    "dot": (1.0, 0.85, 0.2),
    "tip": (1.0, 0.45, 0.7),
}

HEAD_Y = -1.36  # the head's middle (it sits in front of the rider's legs)
HEAD_R = 0.58
WING_TILT = 34  # the wings rise this much from their roots (degrees)


def wing_frame(sx, sweep, root):
    """A wing's frame: its local +X runs out from the root, raised by WING_TILT and swept back by `sweep`
    degrees (negative sweeps it forward); `sx` is the side."""
    angle = math.radians(sweep) if sx > 0 else math.pi - math.radians(sweep)
    return Matrix.Translation(root) @ Matrix.Rotation(angle, 4, "Z") @ Matrix.Rotation(math.radians(-WING_TILT), 4, "Y")


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


def dot(radius, location, scale):
    """A small low-poly ball (spots and dots don't need many faces)."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=7, radius=radius, location=location, scale=scale)
    obj = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj


def wing(parts, frame, length, width, color, spots):
    """A rounded wing lying in its frame's XY plane: a dark rim, the colored wing a little smaller and thicker
    (so it shows through the rim on both faces) and round spots on its top."""
    half = length / 2
    rim = ball("WingRim", 1, (half, 0, 0), (half, width / 2, 0.06))
    inner = ball("Wing", 1, (half + 0.02, 0, 0), (half * 0.86, width / 2 * 0.84, 0.075))
    for obj in (rim, inner):
        # a fuller, rounder outer end than at the root
        for v in obj.data.vertices:
            t = (v.co.x + (half if obj is rim else half + 0.02)) / length  # 0 at the root, 1 at the tip
            v.co.y *= 0.7 + 0.45 * math.sin(math.pi * min(t * 0.8 + 0.1, 1))
    parts.append(finish(placed(rim, frame), "rim"))
    parts.append(finish(placed(inner, frame), color))
    for x, y, r, role in spots:
        parts.append(finish(placed(dot(r, (x * length, y * width / 2, 0.06), (1, 1, 0.3)), frame), role))


def build():
    parts = []
    # The chubby body: a long soft back (thorax and abdomen melted together), a rounded tail end at the back
    puffs = [
        (1.0, (0, 0.1, 0.6), (1.2, 1.15, 0.6)),
        (0.72, (0, -0.55, 0.62), (1.25, 1.0, 0.8)),
        (0.6, (0, 0.85, 0.55), (1.3, 1.2, 0.85)),
        (0.4, (0, 1.32, 0.5), (1.1, 1.0, 0.9)),
    ]
    body = blob("ButterflyBody", puffs, voxel=0.07)
    for v in body.data.vertices:
        if v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.3
        # a soft dip where the rider sits
        rr = math.hypot(v.co.x / 0.8, v.co.y / 0.85)
        if v.co.z > TOP - 0.2 and rr < 1:
            v.co.z -= 0.06 * (1 - rr * rr)
    # The abdomen behind the rider gets dark purple fuzzy bands (split off by front-to-back position)
    parts.append(finish(split_where(body, lambda c: c.y > 0.5 and int((c.y - 0.5) / 0.3) % 2 == 0, "Bands"), "rim"))
    parts.append(finish(body, "body"))
    # A fluffy cream collar of puffs between the body and the head
    collar = [(0.2, (math.cos(a) * 0.68, -0.98, 0.6 + math.sin(a) * 0.36), (1, 0.85, 1)) for a in [2 * math.pi * i / 12 for i in range(12)]]
    parts.append(finish(blob("Collar", collar, voxel=0.07, keep=2500), "fuzz"))

    # The round head in front, with its face looking forward
    parts.append(finish(ball("Head", HEAD_R, (0, HEAD_Y, 0.66), (1.05, 1.0, 0.98)), "body"))
    parts.extend(face(Matrix.Translation((0, HEAD_Y - HEAD_R + 0.04, 0.63)), 0.82))
    # Two curly antennae from the top of the head, curling outward with ball tips
    for sx in (-1, 1):
        pts = [(sx * 0.16, HEAD_Y + 0.05, 1.12), (sx * 0.24, HEAD_Y - 0.1, 1.35), (sx * 0.36, HEAD_Y - 0.25, 1.58), (sx * 0.52, HEAD_Y - 0.3, 1.72),
               (sx * 0.66, HEAD_Y - 0.24, 1.73), (sx * 0.72, HEAD_Y - 0.14, 1.64), (sx * 0.66, HEAD_Y - 0.12, 1.55), (sx * 0.58, HEAD_Y - 0.18, 1.56)]
        parts.append(finish(tube("Antenna", pts, 0.04), "rim"))
        parts.append(finish(ball("Tip", 0.1, pts[-1]), "tip"))

    # Four wings rising from the body's sides: big upper ones swept forward, smaller lower ones swept back
    for sx in (-1, 1):
        wing(parts, wing_frame(sx, -22, (sx * 0.9, -0.2, 0.86)), 1.38, 1.75, "upper",
             [(0.62, 0.05, 0.2, "spot"), (0.85, -0.42, 0.11, "dot"), (0.86, 0.45, 0.1, "dot"), (0.35, -0.4, 0.08, "dot")])
        wing(parts, wing_frame(sx, 40, (sx * 0.9, 0.6, 0.8)), 1.12, 1.3, "lower",
             [(0.6, 0.0, 0.15, "dot"), (0.85, -0.4, 0.08, "spot"), (0.85, 0.4, 0.08, "spot")])

    parts.append(front_marker(3.6))
    return parts
