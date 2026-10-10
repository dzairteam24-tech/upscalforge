"""Desert: the Camel Seat. A small, cute camel lying down with its legs folded under it, sandy beige and soft,
a red saddle blanket with teal stripes and gold tassels draped over its back where the rider sits, its one
hump at the back as a backrest, a little tufted tail, and its long neck curving up in front to a round head
with a cream muzzle and Cubeling eyes."""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from seatkit import FACE_COLORS, ball, blob, face, finish, front_marker, tube

NAME = "Camel"
TITLE = "Camel Seat"
ZONE = 6
ORDER = 3
TOP = 1.06  # the blanket's top over the camel's back, where the rider sits
COLORS = {
    **FACE_COLORS,
    "body": (0.8, 0.52, 0.24),
    "muzzle": (0.98, 0.82, 0.58),
    "blanket": (0.72, 0.04, 0.06),
    "stripe": (0.0, 0.48, 0.46),
    "gold": (1.0, 0.7, 0.15),
    "tuft": (0.42, 0.22, 0.08),
}

BACK = 1.0  # the camel's back, flattened under the blanket
BLANKET = 0.05  # the blanket's thickness
HEAD = Vector((0, -1.64, 1.24))  # the head's middle, out in front of the rider's legs


def drape(body, name, x0, x1, y0, y1, lift, step=0.05):
    """A cloth laid over the body: a grid over x0..x1 / y0..y1 dropped onto the body's surface (straight down),
    `lift` above it, BLANKET thick. The parts of the grid that miss the body are left out."""
    bm = bmesh.new()
    nx, ny = round((x1 - x0) / step), round((y1 - y0) / step)
    verts = {}
    for i in range(nx + 1):
        for j in range(ny + 1):
            x, y = x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny
            hit, loc, _, _ = body.ray_cast(Vector((x, y, 5)), Vector((0, 0, -1)))
            if hit and loc.z > 0.35:
                verts[i, j] = bm.verts.new((x, y, loc.z + lift))
    for i in range(nx):
        for j in range(ny):
            quad = [verts.get(k) for k in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
            if all(quad):
                bm.faces.new(quad)
    ext = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.z += BLANKET
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build():
    parts = []

    # The camel, all one soft melted body: a long resting torso, four legs folded under its sides (knees poking
    # forward), the hump at the back, and the neck curving up and forward to the head
    puffs = [
        (1, (0, 0.14, 0.55), (1.3, 1.24, 0.5)),  # torso
        (1, (0, -0.55, 0.5), (1.05, 0.6, 0.45)),  # chest
        (0.46, (0, 1.24, 0.96), (1.15, 0.78, 0.95)),  # hump
    ]
    for sx in (-1, 1):
        puffs += [
            (1, (sx * 1.2, -0.6, 0.2), (0.32, 0.5, 0.2)),  # front legs folded
            (0.2, (sx * 1.08, -1.06, 0.2), (1, 1, 0.9)),  # front knees
            (1, (sx * 1.22, 0.7, 0.22), (0.34, 0.62, 0.22)),  # back legs folded
            (0.22, (sx * 1.15, 1.28, 0.22), (1, 1, 0.9)),  # back knees
        ]
    neck = [(0, -1.0, 0.6), (0, -1.26, 0.76), (0, -1.44, 0.94), (0, -1.56, 1.08)]
    for i, p in enumerate(neck):
        puffs.append((0.3 - 0.025 * i, p, (1, 1, 1)))
    puffs += [
        (0.4, tuple(HEAD), (1, 1, 0.92)),  # head
        (0.1, (-0.33, -1.56, 1.52), (1.3, 0.8, 0.7)),  # ears
        (0.1, (0.33, -1.56, 1.52), (1.3, 0.8, 0.7)),
    ]
    body = blob("Camel", puffs, voxel=0.06, keep=9000)
    # The back pressed into a broad, flat saddle area for the blanket
    for v in body.data.vertices:
        if abs(v.co.y) < 0.95 and v.co.z > BACK - 0.15 and v.co.y > -0.95:
            v.co.z = BACK - 0.15 + 0.15 * math.tanh((v.co.z - BACK + 0.15) / 0.15)
    parts.append(finish(body, "body"))

    # The saddle blanket: red over the back, teal stripes where it hangs down the sides, gold tassels along its
    # lower edges
    parts.append(finish(drape(body, "Blanket", -0.95, 0.95, -0.82, 0.82, 0.005), "blanket"))
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.95, sx * 1.24))
        parts.append(finish(drape(body, "Stripe", x0, x1, -0.82, 0.82, 0.005), "stripe"))
        for y in (-0.7, -0.35, 0.0, 0.35, 0.7):
            hit, loc, _, _ = body.ray_cast(Vector((sx * 1.24, y, 5)), Vector((0, 0, -1)))
            p = loc + Vector((sx * 0.06, 0, -0.02))
            parts.append(finish(tube("Cord", [tuple(loc + Vector((0, 0, 0.03))), tuple(p)], 0.018), "gold"))
            parts.append(finish(ball("Tassel", 0.055, tuple(p - Vector((0, 0, 0.04))), (1, 1, 1.4)), "gold"))
    # a gold band across the blanket's front and back edges
    for y0, y1 in ((-0.82, -0.72), (0.72, 0.82)):
        parts.append(finish(drape(body, "Band", -1.24, 1.24, y0, y1, 0.012, 0.025), "gold"))

    # The cream muzzle and nostrils on the front of the head
    snout = HEAD + Vector((0, -0.32, -0.14))
    parts.append(finish(ball("Muzzle", 0.22, tuple(snout), (1.35, 0.85, 0.85)), "muzzle"))
    for sx in (-1, 1):
        parts.append(finish(ball("Nostril", 0.035, tuple(snout + Vector((sx * 0.11, -0.18, 0.04))), (1.2, 0.6, 0.8)), "mouth"))
    smile = [(-0.08, -0.17, -0.07), (-0.04, -0.19, -0.1), (0.0, -0.195, -0.11), (0.04, -0.19, -0.1), (0.08, -0.17, -0.07)]
    parts.append(finish(tube("Mouth", [tuple(snout + Vector(p)) for p in smile], 0.016), "mouth"))
    # inner ears
    for sx in (-1, 1):
        parts.append(finish(ball("EarIn", 0.06, (sx * 0.35, -1.635, 1.53), (1.3, 0.4, 0.7)), "muzzle"))
    # Cubeling eyes and blush above the muzzle (the kit's mouth is left off: the muzzle has its own)
    eyes = face(Matrix.Translation((0, HEAD.y - 0.33, HEAD.z + 0.06)), 0.72)
    mouth = eyes.pop()
    bpy.data.objects.remove(mouth)
    parts += eyes

    # A little tail with a dark tuft at the back
    tail = [(0, 1.42, 0.6), (0, 1.56, 0.5), (0, 1.6, 0.38)]
    parts.append(finish(tube("Tail", tail, 0.05), "body"))
    parts.append(finish(ball("Tuft", 0.09, (0, 1.61, 0.32), (1, 1, 1.4)), "tuft"))
    # and a dark tuft on top of the head
    parts.append(finish(ball("HeadTuft", 0.12, tuple(HEAD + Vector((0, 0.05, 0.36))), (1.1, 1, 0.55)), "tuft"))

    parts.append(front_marker(2 * 2.06))
    return parts
