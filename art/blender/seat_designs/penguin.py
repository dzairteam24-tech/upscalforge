"""Snow Peak: the Penguin Seat. A chubby round penguin lying on its belly so the rider sits on its dark navy back:
its round head at the front with a white face, a Cubeling face and a little orange beak, a white belly round the
bottom, flippers sticking out at the sides, orange feet and a stubby tail at the back, and a tiny blue scarf
round its neck with its ends hanging down one side."""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from seatkit import FACE_COLORS, ball, blob, box, cone, finish, front_marker, placed, torus, apply_modifiers, subdivide

NAME = "Penguin"
TITLE = "Penguin Seat"
ZONE = 7
ORDER = 3
TOP = 1.08  # the middle of its back, where the rider sits
COLORS = {
    **FACE_COLORS,
    "body": (0.025, 0.04, 0.16),
    "belly": (0.95, 0.96, 1.0),
    "beak": (1.0, 0.42, 0.04),
    "scarf": (0.06, 0.4, 1.0),
    "stripe": (0.75, 0.9, 1.0),
}

HEAD = Vector((0, -1.42, 0.62))  # the head's middle
HEAD_R = 0.6
BELLY_Z = 0.36  # where the white belly starts, at the middle (it rises toward the front)
DEPTH = 3.8  # beak to feet


def split_where(obj, test, name):
    """Splits off the faces whose middle passes `test(center)` into a new object (like seatkit.split_below)."""
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


def surface_y(objs, x, z):
    """Where the penguin's front surface is at (x, z), looking from the front."""
    bpy.context.view_layer.update()
    best = HEAD.y - HEAD_R
    found = []
    for obj in objs:
        inv = obj.matrix_world.inverted()
        hit, loc, _, _ = obj.ray_cast(inv @ Vector((x, -6, z)), inv.to_3x3() @ Vector((0, 1, 0)))
        if hit:
            found.append((obj.matrix_world @ loc).y)
    return min(found) if found else best


def build():
    parts = []
    # The body: one chubby egg lying flat, front to back, melted into the round head at the front
    body = blob("PenguinBody", [
        (1.0, (0, 0.15, 0.6), (1.32, 1.2, 0.55)),
        (0.8, (0, -0.3, 0.56), (1.25, 0.95, 0.66)),
        (HEAD_R, tuple(HEAD), (1, 1, 1)),
        (0.42, (0, -1.0, 0.52), (1.2, 1, 1.0)),  # the neck, filling in between head and body
    ], voxel=0.065, keep=7000)
    # flatten its back where the rider sits, with a slight dip in the middle
    for v in body.data.vertices:
        if v.co.y > -0.9 and v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.3
        rr = math.hypot(v.co.x / 0.95, (v.co.y - 0.15) / 0.95)
        if v.co.z > TOP - 0.2 and rr < 1 and v.co.y > -0.9:
            v.co.z -= 0.05 * (1 - rr * rr)
    # White belly round the bottom: cut the body along a clean plane rising toward the front, and split off
    # everything under it
    bm = bmesh.new()
    bm.from_mesh(body.data)
    tilt = 0.08
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, BELLY_Z),
                           plane_no=Vector((0, tilt, 1)).normalized())
    bm.to_mesh(body.data)
    bm.free()
    belly = split_where(body, lambda c: c.z < BELLY_Z - tilt * c.y, "PenguinBelly")
    parts.append(finish(body, "body"))
    parts.append(finish(belly, "belly"))
    # The white face: two round patches standing just proud of the head's front, overlapping in the middle so
    # the navy dips down between them like a heart's top
    skin = [body, belly]
    for sx in (-1, 1):
        patch = ball("Mask", 1, (sx * 0.15, HEAD.y - 0.22, HEAD.z + 0.0), (0.3, 0.4, 0.36))
        parts.append(finish(patch, "belly"))
        skin.append(patch)

    # The face on the white front of the head: eyes, shines, blush, and the beak below the eyes
    fz = HEAD.z + 0.03
    for sx in (-1, 1):
        x = sx * 0.21
        y = surface_y(skin, x, fz + 0.04)
        parts.append(finish(ball("Eye", 0.1, (x, y + 0.01, fz + 0.04), (1, 0.45, 1.25)), "eye"))
        parts.append(finish(ball("Shine", 0.033, (x - 0.03, y - 0.035, fz + 0.1), (1, 0.5, 1)), "shine"))
        bx = sx * 0.37
        by = surface_y(skin, bx, fz - 0.1)
        parts.append(finish(ball("Blush", 0.08, (bx, by + 0.025, fz - 0.1), (1.25, 0.35, 0.7)), "blush"))
    by = surface_y(skin, 0, fz - 0.1)
    beak = cone("Beak", 0.12, 0.015, 0.2, (0, 0, 0), vertices=16)
    for v in beak.data.vertices:
        v.co.x *= 1.3
        v.co.y *= 0.75
    subdivide(beak, 1)
    parts.append(finish(placed(beak, Matrix.Translation((0, by - 0.06, fz - 0.1)) @ Matrix.Rotation(math.radians(90), 4, "X")), "beak"))

    # A little tuft of three curly feathers on top of the head
    for dx, lean in ((-0.07, -25), (0.0, 0), (0.07, 25)):
        f = cone("Tuft", 0.06, 0.01, 0.2, (0, 0, 0.1), vertices=12)
        m = Matrix.Translation((dx, HEAD.y - 0.05, HEAD.z + HEAD_R - 0.06)) @ Matrix.Rotation(math.radians(lean), 4, "Y") @ Matrix.Rotation(math.radians(-20), 4, "X")
        parts.append(finish(placed(f, m), "body"))

    # The flippers: flat paddles sticking out at the sides, tips drooping a little
    for sx in (-1, 1):
        fl = ball("Flipper", 1, (0, 0, 0), (0.5, 0.26, 0.09))
        for v in fl.data.vertices:
            t = v.co.x / 0.5  # 0 at the root .. 1 at the tip
            v.co.y *= 1 - 0.35 * max(t, 0)
            v.co.y += 0.12 * max(t, 0) ** 2  # swept back toward the tip
            v.co.z -= 0.08 * max(t, 0) ** 2
        m = Matrix.Translation((sx * 1.25, -0.15, 0.56)) @ Matrix.Rotation(0 if sx > 0 else math.pi, 4, "Z") @ Matrix.Rotation(math.radians(-12), 4, "Y")
        if sx < 0:
            m = Matrix.Translation((sx * 1.25, -0.15, 0.56)) @ Matrix.Scale(-1, 4, (1, 0, 0)) @ Matrix.Rotation(math.radians(-12), 4, "Y")
        parts.append(finish(placed(fl, m), "body"))

    # Orange feet at the back, toes pointing back, each with three round toes
    for sx in (-1, 1):
        foot = []
        for dx in (-0.1, 0.0, 0.1):
            foot.append((0.1, (sx * 0.45 + dx, 1.45 + (0.03 if dx == 0 else 0), 0.14), (1, 1.5, 0.55)))
        foot.append((0.15, (sx * 0.45, 1.28, 0.17), (1.1, 1.0, 0.55)))
        parts.append(finish(blob("Foot", foot, voxel=0.035, keep=800), "beak"))
    # a stubby tail between them
    tail = cone("Tail", 0.22, 0.03, 0.4, (0, 0, 0), vertices=16)
    for v in tail.data.vertices:
        v.co.x *= 1.3
        v.co.y *= 0.5
    subdivide(tail, 1)
    parts.append(finish(placed(tail, Matrix.Translation((0, 1.32, 0.48)) @ Matrix.Rotation(math.radians(-75), 4, "X")), "body"))

    # The scarf: a soft ring round the neck, with two ends hanging down its right side (white stripes on them)
    ring = torus("Scarf", 1, 0.12, (0, 0, 0), segments=40)
    for v in ring.data.vertices:
        v.co.x *= 0.56
        v.co.y *= 0.46
        v.co.z *= 1.0
    m = Matrix.Translation((0, -1.0, 0.52)) @ Matrix.Rotation(math.radians(90), 4, "X") @ Matrix.Rotation(math.radians(-8), 4, "X")
    parts.append(finish(placed(ring, m), "scarf"))
    parts.append(finish(ball("Knot", 0.14, (0.55, -1.04, 0.66), (0.8, 1, 1)), "scarf"))
    for i, (dy, ang) in enumerate(((-0.08, 18), (0.1, -6))):
        end = box("ScarfEnd", (0.07, 0.22, 0.5), (0, 0, -0.25), bevel=0.03)
        m = Matrix.Translation((0.6, -1.04 + dy, 0.64)) @ Matrix.Rotation(math.radians(ang), 4, "X") @ Matrix.Rotation(math.radians(-14), 4, "Y")
        parts.append(finish(placed(end, m), "scarf"))
        for z in (-0.18, -0.36):
            band = box("ScarfStripe", (0.085, 0.235, 0.06), (0, 0, z), bevel=0.02)
            parts.append(finish(placed(band, m), "stripe"))

    parts.append(front_marker(DEPTH))
    return parts
