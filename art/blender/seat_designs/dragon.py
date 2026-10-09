"""Volcano: the Dragon Seat. A baby dragon curled up: its chubby red body is the seat, its round head at the
front with a short snout, a Cubeling face and two little cream horns, a cream belly band round its bottom, small
front paws, little wings folded up at its sides, and its tail curling round the back as a backrest (gold spikes
along it) and down the left side to a gold spade tip."""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from seatkit import (
    FACE_COLORS,
    apply_modifiers,
    ball,
    blob,
    cone,
    finish,
    front_marker,
    placed,
    subdivide,
    tube,
)

NAME = "Dragon"
TITLE = "Dragon Seat"
ZONE = 8
ORDER = 3
TOP = 1.05  # the middle of its back, where the rider sits
COLORS = {
    **FACE_COLORS,
    "body": (0.75, 0.04, 0.03),
    "belly": (1.0, 0.8, 0.45),
    "horn": (1.0, 0.92, 0.7),
    "wing": (1.0, 0.32, 0.06),
    "gold": (1.0, 0.62, 0.08),
}

HEAD = Vector((0, -1.36, 0.62))
HEAD_R = 0.55
SNOUT = Vector((0, -1.72, 0.47))
BELLY_Z = 0.4  # the cream belly band's top edge at the middle (it rises toward the front)
DEPTH = 3.7  # snout to tail

# the tail's middle line, from inside the body at the back right, up round the back as a backrest, and down
# the left side toward the front, with its thickness at each point
TAIL = [
    ((0.75, 0.85, 0.5), 0.34), ((1.08, 1.2, 0.78), 0.3), ((0.65, 1.42, 1.1), 0.28), ((0.0, 1.48, 1.22), 0.26),
    ((-0.62, 1.4, 1.12), 0.23), ((-1.12, 1.12, 0.88), 0.19), ((-1.45, 0.6, 0.62), 0.16), ((-1.6, 0.05, 0.46), 0.13),
    ((-1.55, -0.45, 0.36), 0.11),
]


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


def bisect(obj, z, tilt):
    """Cuts the mesh along a clean plane (z at y = 0, rising `tilt` per stud toward the front)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, z),
                           plane_no=Vector((0, tilt, 1)).normalized())
    bm.to_mesh(obj.data)
    bm.free()


def surface_y(objs, x, z):
    """Where the dragon's front surface is at (x, z), looking from the front."""
    bpy.context.view_layer.update()
    found = []
    for obj in objs:
        inv = obj.matrix_world.inverted()
        hit, loc, _, _ = obj.ray_cast(inv @ Vector((x, -6, z)), inv.to_3x3() @ Vector((0, 1, 0)))
        if hit:
            found.append((obj.matrix_world @ loc).y)
    return min(found) if found else HEAD.y - HEAD_R


def tail_point(t):
    """A point and thickness along the tail, t from 0 (root) to 1 (tip), eased between the listed points."""
    f = t * (len(TAIL) - 1)
    i = min(int(f), len(TAIL) - 2)
    u = f - i
    u = u * u * (3 - 2 * u)
    (a, ra), (b, rb) = TAIL[i], TAIL[i + 1]
    return Vector(a).lerp(Vector(b), u), ra + (rb - ra) * u


def wing(sx):
    """A small folded wing: a flat membrane with a scalloped lower edge, stood up and angled out at a side."""
    # outline in the wing's own plane (u back along the body, v up), root at the origin
    outline = [(0.0, 0.0), (-0.12, 0.38), (0.05, 0.72), (0.32, 0.62), (0.38, 0.4), (0.55, 0.42), (0.6, 0.18),
               (0.78, 0.12), (0.5, -0.02), (0.25, 0.05)]
    bm = bmesh.new()
    t = 0.05
    front = [bm.verts.new((sx * -t, u, v)) for u, v in outline]
    back = [bm.verts.new((sx * t, u, v)) for u, v in outline]
    bm.faces.new(front if sx > 0 else front[::-1])
    bm.faces.new(back[::-1] if sx > 0 else back)
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        quad = (front[i], front[j], back[j], back[i])
        bm.faces.new(quad if sx > 0 else quad[::-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new("Wing")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Wing", mesh)
    bpy.context.collection.objects.link(obj)
    bev = obj.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.035
    bev.segments = 3
    apply_modifiers(obj)
    m = (Matrix.Translation((sx * 1.18, -0.05, 0.78)) @ Matrix.Rotation(math.radians(-sx * 50), 4, "Z")
         @ Matrix.Rotation(math.radians(sx * 30), 4, "Y") @ Matrix.Scale(1.2, 4))
    return placed(obj, m), m, outline


def build():
    parts = []
    # The body: a chubby round lump (the seat) melted into the neck and round head at the front, and the snout
    body = blob("DragonBody", [
        (1.0, (0, 0.12, 0.56), (1.32, 1.12, 0.55)),
        (0.8, (0, -0.3, 0.54), (1.22, 0.92, 0.64)),
        (0.4, (0, -0.98, 0.52), (1.2, 1, 1.0)),
        (HEAD_R, tuple(HEAD), (1, 1, 1)),
        (0.32, tuple(SNOUT), (1.2, 1.0, 0.82)),
    ], voxel=0.065, keep=7000)
    for v in body.data.vertices:
        if v.co.y > -0.9 and v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.3
        rr = math.hypot(v.co.x / 0.95, (v.co.y - 0.12) / 0.9)
        if v.co.z > TOP - 0.2 and rr < 1 and v.co.y > -0.9:
            v.co.z -= 0.05 * (1 - rr * rr)
    # the cream belly band: everything under a clean plane rising toward the front (not the snout's chin)
    tilt = 0.08
    bisect(body, BELLY_Z, tilt)
    belly = split_where(body, lambda c: c.z < BELLY_Z - tilt * c.y and c.y > HEAD.y, "DragonBelly")
    parts.append(finish(body, "body"))
    parts.append(finish(belly, "belly"))
    skin = [body, belly]

    # The tail: thick balls along its path melted into one tapering tail, with a gold spade at its tip
    balls = []
    for i in range(40):
        p, r = tail_point(i / 39)
        balls.append((r, tuple(p), (1, 1, 1)))
    tail = blob("Tail", balls, voxel=0.055, keep=4000)
    parts.append(finish(tail, "body"))
    tip, _ = tail_point(1.0)
    before, _ = tail_point(0.92)
    d = (tip - before).normalized()
    spade = bpy.data.meshes.new("Spade")
    bm = bmesh.new()
    th = 0.05
    outline = [(0, -0.03), (0.1, -0.27), (0.6, 0.0), (0.1, 0.27), (0, 0.03)]
    top = [bm.verts.new((u, w, th)) for u, w in outline]
    bot = [bm.verts.new((u, w, -th)) for u, w in outline]
    bm.faces.new(top)
    bm.faces.new(bot[::-1])
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        bm.faces.new((top[j], top[i], bot[i], bot[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(spade)
    bm.free()
    sp = bpy.data.objects.new("Spade", spade)
    bpy.context.collection.objects.link(sp)
    bev = sp.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.04
    bev.segments = 3
    apply_modifiers(sp)
    yaw = math.atan2(d.y, d.x)
    parts.append(finish(placed(sp, Matrix.Translation(tip - d * 0.06) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(math.radians(70), 4, "X")), "gold"))

    # Gold spikes along the top of the tail where it rises round the back (the back only)
    bpy.context.view_layer.update()
    for i in range(7):
        t = 0.14 + 0.09 * i
        p, r = tail_point(t)
        q, _ = tail_point(t + 0.01)
        along = (q - p).normalized()
        out = Vector((0, 0, 1)) - along * along.z
        # lean the spike outward from the seat a little
        flat = Vector((p.x, p.y, 0)).normalized()
        up = (out.normalized() * 0.8 + flat * 0.45).normalized()
        size = 0.17 + 0.06 * math.sin(math.pi * i / 6)
        spike = cone("Spike", size, 0.01, size * 2.0, (0, 0, size * 0.75), vertices=12)
        for v in spike.data.vertices:  # flattened sideways, a fin rather than a cone
            v.co.y *= 0.7
        # turn the fin's flat side across the tail's direction
        fin_x = along - up * along.dot(up)
        fin_x.normalize()
        fin_y = up.cross(fin_x)
        rot = Matrix(((fin_x.x, fin_y.x, up.x, 0), (fin_x.y, fin_y.y, up.y, 0), (fin_x.z, fin_y.z, up.z, 0), (0, 0, 0, 1)))
        rot = rot @ Matrix.Rotation(math.pi / 2, 4, "Z")
        parts.append(finish(placed(spike, Matrix.Translation(p + up * (r - 0.12)) @ rot), "gold"))

    # The face on the head's front, above the snout; nostrils and a smile on the snout
    fz = HEAD.z + 0.1
    for sx in (-1, 1):
        x = sx * 0.22
        y = surface_y(skin, x, fz)
        parts.append(finish(ball("Eye", 0.11, (x, y + 0.015, fz), (1, 0.45, 1.25)), "eye"))
        parts.append(finish(ball("Shine", 0.036, (x - 0.035, y - 0.035, fz + 0.07), (1, 0.5, 1)), "shine"))
        bx, bz = sx * 0.4, HEAD.z - 0.08
        by = surface_y(skin, bx, bz)
        parts.append(finish(ball("Blush", 0.085, (bx, by + 0.03, bz), (1.25, 0.35, 0.7)), "blush"))
        nx, nz = sx * 0.1, SNOUT.z + 0.08
        ny = surface_y(skin, nx, nz)
        parts.append(finish(ball("Nostril", 0.03, (nx, ny + 0.008, nz), (1.3, 0.5, 0.8)), "mouth"))
    smile = []
    for i in range(7):
        x = -0.12 + 0.24 * i / 6
        z = SNOUT.z - 0.08 - 0.045 * math.sin(math.pi * i / 6)
        smile.append((x, surface_y(skin, x, z) - 0.005, z))
    parts.append(finish(tube("Mouth", smile, 0.02), "mouth"))

    # Two little cream horns on top of the head, curving up and back-out; small cream ear fins below them
    for sx in (-1, 1):
        h = cone("Horn", 0.1, 0.02, 0.36, (0, 0, 0.18), vertices=16)
        for v in h.data.vertices:  # curve it back toward its tip
            tt = v.co.z / 0.36
            v.co.y += 0.12 * tt * tt
        subdivide(h, 1)
        m = (Matrix.Translation((sx * 0.27, HEAD.y + 0.05, HEAD.z + HEAD_R - 0.1))
             @ Matrix.Rotation(math.radians(sx * 22), 4, "Y") @ Matrix.Rotation(math.radians(-8), 4, "X"))
        parts.append(finish(placed(h, m), "horn"))
        fin = ball("Ear", 1, (0, 0, 0), (0.06, 0.22, 0.12))
        for v in fin.data.vertices:
            v.co.z += 0.12 * max(v.co.y / 0.22, 0) ** 2
        m = Matrix.Translation((sx * (HEAD_R - 0.04), HEAD.y + 0.12, HEAD.z + 0.12)) @ Matrix.Rotation(math.radians(sx * 25), 4, "Z")
        parts.append(finish(placed(fin, m), "wing"))

    # Little front paws under the head, with cream toe tips
    for sx in (-1, 1):
        parts.append(finish(ball("Paw", 0.2, (sx * 0.6, -1.12, 0.14), (1, 1.2, 0.7)), "body"))
        for dx in (-0.08, 0.0, 0.08):
            parts.append(finish(ball("Toe", 0.045, (sx * 0.6 + dx, -1.33, 0.1), (1, 1, 0.8)), "horn"))

    # The wings, folded up at the sides: membrane with a red arm along its top edge
    for sx in (-1, 1):
        w, m, outline = wing(sx)
        parts.append(finish(w, "wing"))
        arm = [m @ Vector((0, u, v)) for u, v in outline[:4]]
        parts.append(finish(tube("Arm", arm, 0.05), "body"))
        parts.append(finish(ball("Claw", 0.06, tuple(m @ Vector((0, 0.05, 0.74))), (1, 1, 1)), "horn"))

    parts.append(front_marker(DEPTH))
    return parts
