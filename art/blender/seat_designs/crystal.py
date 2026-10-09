"""Mushroom Cave: the Crystal Seat. A big flat-topped violet crystal slab sitting on a faceted cave rock, with
clusters of pointed hexagonal crystals growing round it (tall at the back and far sides, small and low in
front), lilac highlights, a few softly glowing shards tucked in their roots, and a Cubeling face on the rock's
front."""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

from seatkit import FACE_COLORS, apply_modifiers, face, finish, front_marker, placed

NAME = "Crystal"
TITLE = "Crystal Seat"
ZONE = 5
ORDER = 3
TOP = 1.05  # the crystal slab's flat top, where the rider sits
COLORS = {
    **FACE_COLORS,
    "rock": (0.3, 0.24, 0.42),
    "crystal": (0.42, 0.16, 0.85),
    "lilac": (0.78, 0.6, 1.0),
    "glow": (0.95, 0.55, 1.0),
}
GLOW = ("glow",)
LIGHT = (0.7, 0.4, 1.0)

DEPTH = 3.0  # front to back
SLAB_R = 1.22  # the slab's corner radius (its flat sides are 1.06 from the middle)


def prism(name, radius, height, tip, sides=6):
    """A crystal: a low-poly prism standing on its base at the origin, along +Z, with a pointed tip."""
    bm = bmesh.new()
    base = [bm.verts.new((math.cos(2 * math.pi * i / sides) * radius, math.sin(2 * math.pi * i / sides) * radius, 0)) for i in range(sides)]
    ring = [bm.verts.new((v.co.x, v.co.y, height)) for v in base]
    point = bm.verts.new((0, 0, height + tip))
    bm.faces.new(base[::-1])
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((base[i], base[j], ring[j], ring[i]))
        bm.faces.new((ring[i], ring[j], point))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def hex_ring(name, outer, inner, thickness):
    """A flat hexagonal band (outer to inner radius), its bottom at z = 0."""
    bm = bmesh.new()
    rings = []
    for r, z in ((outer, 0), (outer, thickness), (inner, thickness), (inner, 0)):
        rings.append([bm.verts.new((math.cos(math.pi * i / 3) * r, math.sin(math.pi * i / 3) * r, z)) for i in range(6)])
    for k in range(4):
        a, b = rings[k], rings[(k + 1) % 4]
        for i in range(6):
            j = (i + 1) % 6
            bm.faces.new((a[i], a[j], b[j], b[i]))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def flat(obj, role):
    """Finished with flat facets (crystals and rock look cut, not smooth)."""
    finish(obj, role)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def crystal(x, y, z, radius, height, lean_x, lean_y, spin):
    """A crystal standing at (x, y, z), leaning out by lean_x / lean_y degrees, turned by spin degrees."""
    obj = prism("Crystal", radius, height, radius * 1.5)
    m = (
        Matrix.Translation((x, y, z))
        @ Matrix.Rotation(math.radians(lean_y), 4, "X")
        @ Matrix.Rotation(math.radians(lean_x), 4, "Y")
        @ Matrix.Rotation(math.radians(spin), 4, "Z")
    )
    return placed(obj, m)


def build():
    parts = []
    rnd = random.Random(5)

    # The cave rock under it all: a jittered, flattened icosphere, cut flat at the bottom
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=(0, 0, 0))
    rock = bpy.context.active_object
    rock.name = "Rock"
    for v in rock.data.vertices:
        j = 1 + rnd.uniform(-0.07, 0.07)
        v.co = Vector((v.co.x * 1.62 * j, v.co.y * 1.42 * j, v.co.z * 0.5 * j + 0.38))
        v.co.z = max(v.co.z, 0.04)
    parts.append(flat(rock, "rock"))

    # The seat: a wide hexagonal crystal slab, its top edge cut with a narrow lilac chamfer
    slab = prism("Slab", SLAB_R, TOP - 0.45, 0)
    bm = bmesh.new()
    bm.from_mesh(slab.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(slab.data)
    bm.free()
    slab = placed(slab, Matrix.Translation((0, 0, 0.45)) @ Matrix.Rotation(math.radians(30), 4, "Z"))
    bev = slab.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.07
    bev.segments = 1
    apply_modifiers(slab)
    parts.append(flat(slab, "crystal"))
    # a lilac sheen ring sitting just inside the top edge, flush on the slab
    rim = placed(hex_ring("Rim", SLAB_R - 0.04, SLAB_R - 0.2, 0.03), Matrix.Translation((0, 0, TOP - 0.01)) @ Matrix.Rotation(math.radians(30), 4, "Z"))
    parts.append(flat(rim, "lilac"))

    # Crystal clusters: (x, y, base z, radius, height, lean x, lean y, role). Tall at the back (y > 0.9) and
    # out at the far sides (|x| > 1.4); short and low in front so the rider's legs stay clear
    clusters = [
        # back middle: the tallest, like a crown behind the rider
        (0.0, 1.2, 0.4, 0.24, 1.15, 0, 14, "crystal"),
        (-0.42, 1.15, 0.4, 0.18, 0.85, -14, 12, "lilac"),
        (0.45, 1.12, 0.4, 0.19, 0.9, 16, 10, "crystal"),
        (-0.82, 1.0, 0.35, 0.15, 0.6, -22, 14, "crystal"),
        (0.85, 0.98, 0.35, 0.14, 0.55, 24, 12, "lilac"),
        (0.2, 1.35, 0.3, 0.13, 0.5, 10, 30, "lilac"),
        # far sides
        (-1.5, 0.3, 0.35, 0.2, 0.7, -26, 4, "crystal"),
        (-1.58, -0.15, 0.3, 0.14, 0.42, -32, -8, "lilac"),
        (-1.35, 0.65, 0.35, 0.13, 0.5, -16, 20, "lilac"),
        (1.52, 0.25, 0.35, 0.21, 0.75, 26, 6, "lilac"),
        (1.6, -0.2, 0.3, 0.14, 0.45, 32, -10, "crystal"),
        (1.35, 0.62, 0.35, 0.13, 0.48, 18, 22, "crystal"),
        # little ones at the front corners, below the seat
        (-1.15, -0.95, 0.3, 0.11, 0.28, -20, -24, "crystal"),
        (1.2, -0.9, 0.3, 0.1, 0.24, 22, -26, "lilac"),
    ]
    for x, y, z, r, h, lx, ly, role in clusters:
        parts.append(flat(crystal(x, y, z, r, h, lx, -ly, rnd.uniform(0, 60)), role))

    # Glowing shards tucked in the clusters' roots
    for x, y, z, r, h, lx, ly in (
        (-0.2, 1.3, 0.38, 0.09, 0.35, -8, 28),
        (0.68, 1.15, 0.36, 0.08, 0.3, 20, 22),
        (-1.55, 0.05, 0.3, 0.08, 0.32, -34, 0),
        (1.58, 0.45, 0.3, 0.08, 0.3, 34, 10),
        (-0.95, -1.0, 0.28, 0.06, 0.16, -14, -30),
        (0.92, -1.05, 0.28, 0.06, 0.16, 16, -30),
    ):
        parts.append(flat(crystal(x, y, z, r, h, lx, -ly, rnd.uniform(0, 60)), "glow"))

    # The face on the rock's front, under the slab
    parts += face(Matrix.Translation((0, -1.38, 0.36)), 0.95)

    parts.append(front_marker(DEPTH))
    return parts
