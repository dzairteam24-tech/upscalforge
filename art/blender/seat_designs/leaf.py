"""Forest: the Leaf Seat. A big green leaf floating like a magic carpet on a puffy moss cushion: its sides
curled gently up, a lighter middle vein and side veins, its front tip curling up like a sled with a Cubeling
face on it (on the leaf's paler underside, facing forward), its stem curling up at the back like a little
hook and a glossy dewdrop resting on it."""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from seatkit import FACE_COLORS, ball, blob, face, finish, front_marker, placed, tube

NAME = "Leaf"
TITLE = "Leaf Seat"
ZONE = 3
ORDER = 2
TOP = 1.1  # the leaf's top in the middle
COLORS = {
    **FACE_COLORS,
    "leaf": (0.1, 0.52, 0.05),
    "under": (0.32, 0.72, 0.18),
    "vein": (0.62, 0.9, 0.28),
    "stem": (0.08, 0.32, 0.04),
    "moss": (0.2, 0.26, 0.05),
    "glass": (0.6, 0.86, 1.0),
}

HALF_W = 1.55  # the leaf's half width
HALF_L = 1.8  # its half length (front to back, before the tip curls)
MID_Y = -0.12  # the middle of its outline
THICK = 0.13  # its half thickness in the middle
Z0 = TOP - THICK  # the leaf's middle sheet
CURL_Y = -1.15  # where the front starts to curl up
CURL_R = 0.5  # how tight it curls
FACE_ARC = 0.45  # how far round the curl the face sits (along the leaf)


def bend(x, y, z):
    """Lays the flat leaf (x, y across, z its thickness) into its shape: the sides curled up a little, the back
    edge lifted, the middle at Z0 and the front rolled up round a curl like a sled's tip."""
    z += 0.24 * max(abs(x) - 0.95, 0) ** 2 / 0.25
    z += 0.3 * max(y - 1.0, 0) ** 2
    if y >= CURL_Y:
        return Vector((x, y, Z0 + z))
    phi = (CURL_Y - y) / CURL_R
    cy, cz = CURL_Y - CURL_R * math.sin(phi), Z0 + CURL_R * (1 - math.cos(phi))
    return Vector((x, cy + z * math.sin(phi), cz + z * math.cos(phi)))


def taper(y):
    """How much the leaf's outline is pulled in at y: pointed toward the front tip, a bit toward the back."""
    t = (MID_Y - y) / HALF_L  # 0 in the middle, 1 at the front tip, -1 at the back
    k = 1 - 0.45 * max(t, 0) ** 1.1
    if t < -0.4:
        k *= 1 - 0.25 * ((-t - 0.4) / 0.6) ** 2
    return k


def half_width(y):
    """The leaf's half width at y."""
    return HALF_W * math.sqrt(max(1 - ((y - MID_Y) / HALF_L) ** 2, 0)) * taper(y)


def flat_leaf():
    """The leaf before bending: a flattened sphere drawn to a leaf outline, rounded at the back and pointed at
    the front."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=56, ring_count=36, radius=1, location=(0, MID_Y, 0))
    obj = bpy.context.active_object
    obj.name = "Leaf"
    obj.scale = (HALF_W, HALF_L, THICK)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    for v in obj.data.vertices:
        v.co.x *= taper(v.co.y)
        # a little heart-shaped notch at the back where the stem joins
        if (MID_Y - v.co.y) / HALF_L < -0.85:
            v.co.y -= 0.25 * (1 - abs(v.co.x) / 0.6) if abs(v.co.x) < 0.6 else 0
    return obj


def surface_z(leaf, x, y):
    """The flat leaf's top at (x, y) (before bending), found by a ray straight down."""
    hit, loc, _, _ = leaf.ray_cast(Vector((x, y, 5)), Vector((0, 0, -1)))
    return loc.z if hit else 0.0


def build():
    parts = []
    leaf = flat_leaf()
    bpy.context.view_layer.update()

    # Veins: a middle vein from the back to near the tip and four pairs of side veins sweeping forward
    veins = [[(0, y) for y in [1.5 - 0.25 * i for i in range(13)]]]
    for y0 in (0.95, 0.4, -0.15, -0.65):
        for sx in (-1, 1):
            end = y0 - 0.5
            veins.append([(sx * 0.8 * half_width(end) * k / 5, y0 - 0.5 * (k / 5) ** 1.3) for k in range(6)])
    for i, pts in enumerate(veins):
        path = [bend(x, y, surface_z(leaf, x, y) - 0.008) for x, y in pts]
        parts.append(finish(tube("Vein", path, 0.04 if i == 0 else 0.028), "vein"))
    # The dewdrop on the back left of the leaf, with a little shine
    dx, dy = -0.85, 1.0
    drop_at = bend(dx, dy, surface_z(leaf, dx, dy)) + Vector((0, 0, 0.11))
    parts.append(finish(ball("Dew", 0.16, drop_at, (1, 1, 0.82)), "glass"))
    parts.append(finish(ball("DewShine", 0.045, drop_at + Vector((-0.06, -0.08, 0.08)), (1, 1, 0.7)), "shine"))

    # Bend the leaf into shape; its underside (pointing down before bending) is paler
    for v in leaf.data.vertices:
        v.co = bend(*v.co)
    bm = bmesh.new()
    bm.from_mesh(leaf.data)
    bm.normal_update()
    lower = [f for f in bm.faces if f.normal.z < -0.25 or (f.calc_center_median().y < CURL_Y and f.normal.y < -0.3)]
    sbm = bmesh.new()
    vmap = {}
    for f in lower:
        vs = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = sbm.verts.new(v.co)
            vs.append(vmap[v])
        sbm.faces.new(vs)
    under = bpy.data.meshes.new("LeafUnder")
    sbm.to_mesh(under)
    sbm.free()
    bmesh.ops.delete(bm, geom=lower, context="FACES")
    bm.to_mesh(leaf.data)
    bm.free()
    under_obj = bpy.data.objects.new("LeafUnder", under)
    bpy.context.collection.objects.link(under_obj)
    parts.append(finish(leaf, "leaf"))
    parts.append(finish(under_obj, "under"))

    # The stem: out of the notch at the back, curling up and over like a hook
    stem = [(0, 1.35, Z0 + 0.02), (0, 1.55, Z0 + 0.1), (0, 1.74, Z0 + 0.3), (0, 1.82, Z0 + 0.55), (0, 1.75, Z0 + 0.74),
            (0, 1.6, Z0 + 0.8), (0, 1.48, Z0 + 0.7), (0, 1.51, Z0 + 0.6)]
    parts.append(finish(tube("Stem", stem, 0.07), "stem"))
    parts.append(finish(ball("StemEnd", 0.075, stem[-1]), "stem"))

    # The puffy moss cushion it floats on: a soft lump under the middle, smaller than the leaf
    puffs = [(0.9, (0, 0, 0.52), (1.35, 1.4, 0.55))]
    for i in range(9):
        a = 2 * math.pi * (i + 0.3) / 9
        puffs.append((0.45, (math.cos(a) * 0.95, math.sin(a) * 0.95, 0.55 + 0.04 * (i % 2)), (1, 1, 0.95)))
    moss = blob("Moss", puffs, voxel=0.07, keep=4000)
    for v in moss.data.vertices:
        if v.co.z > Z0 - 0.04:
            v.co.z = Z0 - 0.04 + (v.co.z - Z0 + 0.04) * 0.3
    parts.append(finish(moss, "moss"))

    # The face on the curled-up front tip, on its underside facing forward and a little down
    phi = FACE_ARC / CURL_R
    at = bend(0, CURL_Y - FACE_ARC, -THICK * 0.92)
    frame = Matrix.Translation(at) @ Matrix.Rotation(math.pi / 2 - phi, 4, "X")
    parts.extend(face(frame, 0.82))

    parts.append(front_marker(3.6))
    return parts
