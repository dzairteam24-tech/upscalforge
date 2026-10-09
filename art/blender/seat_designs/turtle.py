"""Beach: the Turtle Seat. A chubby sea turtle: a low dark-green domed shell, flattened on top where the rider
sits, covered in raised light-green hexagon plates; a cream belly rim round its edge, four teal flippers out at
the sides, a round teal head with a Cubeling face at the front and a little pointed tail at the back."""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from seatkit import FACE_COLORS, apply_modifiers, bake, ball, face, finish, front_marker, placed

NAME = "Turtle"
TITLE = "Turtle Seat"
ZONE = 4
ORDER = 3
TOP = 1.13  # the top plate, where the rider sits
COLORS = {
    **FACE_COLORS,
    "shell": (0.03, 0.25, 0.16),
    "plate": (0.33, 0.72, 0.36),
    "skin": (0.25, 0.75, 0.66),
    "belly": (1.0, 0.9, 0.66),
}

# The shell dome: an ellipsoid round CENTER, flattened above FLAT
RX, RY, RZ = 1.55, 1.32, 0.76
CENTER = Vector((0, 0.05, 0.5))
FLAT = TOP - 0.06
PLATE_UP = 0.05  # how far the plates stand out of the dome


def on_dome(direction):
    """The dome's surface point and outward normal for a direction on the unit sphere (in the dome's
    un-squashed space)."""
    s = direction.normalized()
    p = CENTER + Vector((s.x * RX, s.y * RY, s.z * RZ))
    n = Vector((s.x / RX, s.y / RY, s.z / RZ)).normalized()
    return p, n


def plate(name, polar, azimuth, size):
    """A hexagon plate laid onto the dome: a subdivided flat hexagon made solid, then wrapped onto the curved
    surface so it hugs it everywhere, its top face a touch smaller than its foot for a soft bevel. `polar` is
    degrees from the top, `azimuth` degrees round from +X, `size` its radius in the unit sphere's angle."""
    bm = bmesh.new()
    mid = bm.verts.new((0, 0, 0))
    corners = [bm.verts.new((math.cos(math.radians(30 + 60 * i)), math.sin(math.radians(30 + 60 * i)), 0)) for i in range(6)]
    for i in range(6):
        bm.faces.new((mid, corners[i], corners[(i + 1) % 6]))
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 1.0
    sol.offset = -1
    apply_modifiers(obj)
    # the plate's frame on the unit sphere: its middle direction and two tangents
    pa, az = math.radians(polar), math.radians(azimuth)
    d = Vector((math.sin(pa) * math.cos(az), math.sin(pa) * math.sin(az), math.cos(pa)))
    t1 = Vector((-math.sin(az), math.cos(az), 0))
    t2 = d.cross(t1)
    for v in obj.data.vertices:
        u, w, h = v.co.x, v.co.y, v.co.z  # h: 0 on top, -1 underneath
        shrink = 0.88 if h > -0.5 else 1.0
        p, n = on_dome(d + (t1 * u + t2 * w) * size * shrink)
        v.co = p + n * (PLATE_UP if h > -0.5 else -0.04)
    return obj


def flipper(name, length, width, at, yaw, droop):
    """A flat paddle flipper, rounded at the root and tapering to a curved tip, pointing out along its +X."""
    f = bake(ball(name, 1, (length * 0.5, 0, 0), (length * 0.5, width, 0.09)))
    for v in f.data.vertices:
        t = max(v.co.x / length, 0)
        v.co.y *= 1 - 0.55 * t * t
        v.co.y -= 0.18 * t * t * width  # the tip sweeps back a little
        v.co.z -= droop * t * t
    return placed(f, Matrix.Translation(at) @ Matrix.Rotation(math.radians(yaw), 4, "Z"))


def build():
    parts = []
    # The shell dome, flattened on top for the seat
    dome = bake(ball("Dome", 1, CENTER, (RX, RY, RZ)))
    sub = dome.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    apply_modifiers(dome)
    for v in dome.data.vertices:
        if v.co.z > FLAT:
            v.co.z = FLAT + (v.co.z - FLAT) * 0.15
        if v.co.z < CENTER.z:  # its underside tucked up into the belly
            v.co.z = CENTER.z - (CENTER.z - v.co.z) * 0.4
    parts.append(finish(dome, "shell"))

    # Plates: one big flat hexagon on top (the seat), a ring of six round it and a row of small marginal
    # plates near the edge, all raised and lighter than the shell between them
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.78, depth=0.12, location=(0, CENTER.y, TOP - 0.06))
    top = bpy.context.active_object
    top.rotation_euler = (0, 0, math.radians(30))
    bake(top)
    bev = top.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.05
    bev.segments = 3
    apply_modifiers(top)
    parts.append(finish(top, "plate"))
    for i in range(6):
        parts.append(finish(plate("Plate", 56, 90 + 60 * i, 0.3), "plate"))
    for i in range(12):
        parts.append(finish(plate("Rim", 81, 75 + 30 * i, 0.18), "plate"))

    # The cream belly showing as a rim under the shell's edge
    belly = bake(ball("Belly", 1, (0, CENTER.y, 0.4), (RX + 0.08, RY + 0.08, 0.32)))
    parts.append(finish(belly, "belly"))

    # Four flippers: big ones at the front sweeping forward, small ones at the back
    for sx in (-1, 1):
        parts.append(finish(flipper("FrontFlipper", 0.82, 0.36, (sx * 1.15, -0.6, 0.42), -20 if sx > 0 else 200, 0.12), "skin"))
        parts.append(finish(flipper("BackFlipper", 0.6, 0.26, (sx * 1.05, 0.95, 0.36), 35 if sx > 0 else 145, 0.06), "skin"))

    # The head out at the front on a short neck, with its face, and the little tail at the back
    hy, hz = -RY - 0.24, 0.66
    parts.append(finish(ball("Neck", 1, (0, -RY + 0.1, 0.48), (0.36, 0.45, 0.28)), "skin"))
    parts.append(finish(ball("Head", 1, (0, hy, hz), (0.54, 0.48, 0.47)), "skin"))
    parts += face(Matrix.Translation((0, hy - 0.46, hz - 0.02)), 0.95)
    tail = bake(ball("Tail", 1, (0, 0.22, 0), (0.14, 0.26, 0.1)))
    for v in tail.data.vertices:
        v.co.x *= 1 - 0.8 * max(v.co.y / 0.48, 0)
    parts.append(finish(placed(tail, Matrix.Translation((0, RY + 0.02, 0.38)) @ Matrix.Rotation(math.radians(-10), 4, "X")), "skin"))

    parts.append(front_marker(2 * RY + 0.9))
    return parts
