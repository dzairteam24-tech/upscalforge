"""Desert: the Magic Carpet Seat. A flying carpet rippling in gentle waves, its rich red field framed by a gold
border band, a purple medallion and corner motifs raised on top, gold tassels at its four corners and its
front edge curling up. A plump teal floor cushion with gold piping and a gold button sits in the middle for
the rider, with a small face on its front."""

import math

import bmesh
import bpy
from mathutils import Matrix

from seatkit import FACE_COLORS, ball, cone, face, finish, front_marker, placed, torus

NAME = "Carpet"
TITLE = "Magic Carpet Seat"
ZONE = 6
ORDER = 2
TOP = 1.0  # the cushion's top, where the rider sits
COLORS = {
    **FACE_COLORS,
    "carpet": (0.42, 0.015, 0.05),
    "border": (1.0, 0.66, 0.12),
    "pattern": (0.32, 0.06, 0.52),
    "cushion": (0.04, 0.42, 0.48),
    "gold": (1.0, 0.7, 0.15),
}

WIDTH = 3.6  # side to side
DEPTH = 2.88  # front to back
BASE = 0.2  # the carpet's middle height
THICK = 0.05  # the carpet's thickness
BAND = 0.24  # the gold border's width
STEP = 0.06  # the carpet's grid size


def wave(x, y):
    """How far the carpet ripples up or down at (x, y), its front edge curling up."""
    z = 0.045 * math.sin(2.3 * x + 0.6) * math.cos(1.7 * y) + 0.03 * math.sin(1.9 * y - 0.4)
    t = max(0.0, (-DEPTH / 2 + 0.36 - y) / 0.36)
    return z + 0.13 * t * t


def layer(name, mask, lift):
    """A piece of carpet cut from the grid where mask(x, y) holds, thickened, lifted by `lift` above the field
    and rippled with the waves (so raised patterns follow the carpet)."""
    bm = bmesh.new()
    nx, ny = round(WIDTH / STEP), round(DEPTH / STEP)
    verts = {}

    def vert(i, j):
        if (i, j) not in verts:
            verts[i, j] = bm.verts.new((-WIDTH / 2 + i * STEP, -DEPTH / 2 + j * STEP, 0))
        return verts[i, j]

    for i in range(nx):
        for j in range(ny):
            cx, cy = -WIDTH / 2 + (i + 0.5) * STEP, -DEPTH / 2 + (j + 0.5) * STEP
            if mask(cx, cy):
                bm.faces.new((vert(i, j), vert(i + 1, j), vert(i + 1, j + 1), vert(i, j + 1)))
    ext = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.z = THICK
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for v in bm.verts:
        v.co.z += BASE - THICK / 2 + lift + wave(v.co.x, v.co.y)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def radial(name, shape, f0, f1, lift, center=(0, 0), rings=6, segments=96):
    """A raised flat pattern piece round `center`: the band between fractions f0 and f1 (f0 = 0 fills it) of
    the outline radius shape(angle), thickened, lifted and rippled with the carpet."""
    bm = bmesh.new()
    cx, cy = center
    grid = []
    for k in range(rings + 1):
        f = f0 + (f1 - f0) * k / rings
        grid.append([bm.verts.new((cx + math.cos(a) * shape(a) * f, cy + math.sin(a) * shape(a) * f, 0)) for a in (2 * math.pi * i / segments for i in range(segments))])
    for k in range(rings):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((grid[k][i], grid[k][j], grid[k + 1][j], grid[k + 1][i]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    ext = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.z = THICK
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for v in bm.verts:
        v.co.z += BASE - THICK / 2 + lift + wave(v.co.x, v.co.y)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def diamond(rx, ry, scallop=0.0):
    """A diamond outline's radius by angle, its sides optionally scalloped."""
    return lambda a: (1 + scallop * math.cos(12 * a)) / (abs(math.cos(a)) / rx + abs(math.sin(a)) / ry)


def build():
    parts = []
    hw, hd = WIDTH / 2, DEPTH / 2

    def edge_dist(x, y):
        return min(hw - abs(x), hd - abs(y))

    # The red field, the gold border band round it (a hair proud of it) and a thin gold line inside
    parts.append(finish(layer("Field", lambda x, y: edge_dist(x, y) > BAND - 0.01, 0), "carpet"))
    parts.append(finish(layer("Border", lambda x, y: edge_dist(x, y) < BAND or 0.4 < edge_dist(x, y) < 0.46, 0.012), "border"))

    # The purple medallion: a big scalloped diamond round the cushion with a gold outline inside its edge, and
    # little diamonds in the corners
    med = diamond(1.62, 1.3, 0.05)
    parts.append(finish(radial("Medallion", med, 0, 1, 0.012), "pattern"))
    for sx in (-1, 1):
        for sy in (-1, 1):
            corner = (sx * (hw - 0.72), sy * (hd - 0.7))
            parts.append(finish(radial("Corner", diamond(0.24, 0.24), 0, 1, 0.012, corner, 2, 32), "pattern"))
            parts.append(finish(radial("Dot", diamond(0.09, 0.09), 0, 1, 0.024, corner, 1, 16), "border"))
    parts.append(finish(radial("Line", med, 0.84, 0.9, 0.024, rings=1), "border"))

    # Gold tassels at the corners: a bead and a little flared tassel hanging out along the diagonal
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (hw + 0.02), sy * (hd + 0.02)
            z = BASE + wave(sx * hw, sy * hd)
            parts.append(finish(ball("Bead", 0.07, (x, y, z)), "gold"))
            tassel = cone("Tassel", 0.04, 0.1, 0.28, (0, 0, -0.14), 12)
            out = math.atan2(sy, sx)
            m = Matrix.Translation((x + math.cos(out) * 0.05, y + math.sin(out) * 0.05, z)) @ Matrix.Rotation(out, 4, "Z") @ Matrix.Rotation(math.radians(-40), 4, "Y")
            parts.append(finish(placed(tassel, m), "gold"))

    # The plump round floor cushion: a squashed sphere, its top eased flat and tufted in at the middle
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=20, radius=1, location=(0, 0, 0))
    cushion = bpy.context.active_object
    cushion.name = "Cushion"
    half = 0.42
    mid = TOP - half
    for v in cushion.data.vertices:
        # a boxier, plumper profile than a sphere: (1 - r^4)^(1/4) up and down
        r = math.hypot(v.co.x, v.co.y)
        side = math.copysign((1 - min(r, 1) ** 4) ** (1 / 4), v.co.z)
        x, y, z = v.co.x * 0.94, v.co.y * 0.86, mid + side * half
        rr = r / 0.45
        if rr < 1:
            z -= 0.05 * (1 - rr * rr) ** 2  # tufted in at the button
        v.co = (x, y, z)
    parts.append(finish(cushion, "cushion"))
    # gold piping along its upper and lower seams
    for dz in (0.3, -0.3):
        piping = torus("Piping", 1.0, 0.045, (0, 0, mid + dz), 64)
        for v in piping.data.vertices:
            v.co.x *= 0.94 * 0.945
            v.co.y *= 0.86 * 0.945
        parts.append(finish(piping, "gold"))
    parts.append(finish(ball("Button", 0.09, (0, 0, TOP - 0.065), (1, 1, 0.55)), "gold"))

    # A small face on the cushion's front, between the seams
    parts += face(Matrix.Translation((0, -0.84, mid - 0.04)), 0.62)

    parts.append(front_marker(DEPTH))
    return parts
