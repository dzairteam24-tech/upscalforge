"""Forest: the Nest Seat. A round bird nest woven from twigs in three browns, wrapped round and round a bowl
with a few twig ends sticking out, a soft cream feather-down cushion inside where the rider sits, a pale blue
speckled egg tucked in at the back, two little feathers poking out of the rim and a face on the front."""

import math

import bpy
from mathutils import Matrix, Vector

from seatkit import FACE_COLORS, ball, blob, face, finish, front_marker, placed

NAME = "Nest"
TITLE = "Nest Seat"
ZONE = 3
ORDER = 3
TOP = 1.0  # the down cushion's top
COLORS = {
    **FACE_COLORS,
    "twig": (0.17, 0.075, 0.025),
    "twiglight": (0.36, 0.18, 0.06),
    "twigdark": (0.07, 0.03, 0.012),
    "down": (1.0, 0.95, 0.84),
    "egg": (0.62, 0.86, 0.98),
    "speck": (0.24, 0.3, 0.42),
    "feather": (1.0, 0.38, 0.36),
}
TONES = ("twig", "twiglight", "twigdark")

# The nest wall's outer radius by height: narrow foot, fat belly, rim leaning back in a little
PROFILE = ((0.12, 0.95), (0.3, 1.35), (0.55, 1.62), (0.8, 1.7), (1.02, 1.66), (1.2, 1.56), (1.3, 1.44))


def wall_radius(z):
    for (z0, r0), (z1, r1) in zip(PROFILE, PROFILE[1:]):
        if z <= z1:
            t = min(max((z - z0) / (z1 - z0), 0), 1)
            t = t * t * (3 - 2 * t)
            return r0 + (r1 - r0) * t
    return PROFILE[-1][1]


def twig(name, points, radius, closed=False):
    """A thin twig tube with a low-poly round section (nests have lots of them)."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 1
    curve.use_fill_caps = not closed
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1)
    spline.use_cyclic_u = closed
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    return bpy.context.view_layer.objects.active


def build():
    parts = []
    # The bowl underneath it all (dark, so gaps between twigs read as shadow): a lathe of the wall profile
    bowl = ball("Bowl", 1, (0, 0, 0), (1, 1, 1))
    for v in bowl.data.vertices:
        z = 0.08 + (v.co.z + 1) / 2 * 1.2
        r = wall_radius(z) - 0.06
        k = math.hypot(v.co.x, v.co.y)
        a = math.atan2(v.co.y, v.co.x)
        if v.co.z > 0 and k < 0.9:
            # the top cap drops to a floor inside the nest (hidden under the down)
            z, r = 0.6, r * k * 0.8
        else:
            r *= min(k * 1.6, 1)
        v.co = Vector((math.cos(a) * r, math.sin(a) * r, z))
    parts.append(finish(bowl, "twigdark"))

    # Twigs wound round the wall: wobbly rings at rising heights, each tone in turn, each a little tilted
    twigs = {tone: [] for tone in TONES}
    n = 44
    for j in range(15):
        z0 = 0.16 + j * 0.077
        phase, tilt, wob = j * 1.7, 0.05 + 0.03 * (j % 3), 0.025 * (1 + j % 2)
        pts = []
        for i in range(n):
            a = 2 * math.pi * i / n
            z = z0 + tilt * math.sin(a + phase) + wob * math.sin(5 * a + phase * 2)
            r = wall_radius(z) + 0.03 + 0.02 * math.sin(7 * a + j)
            pts.append((math.cos(a) * r, math.sin(a) * r, z))
        twigs[TONES[j % 3]].append(twig("Twig", pts, 0.065 + 0.01 * (j % 2), closed=True))
    # A fat woven rim on top, two twigs twisted round each other
    for k in range(2):
        pts = []
        for i in range(72):
            a = 2 * math.pi * i / 72
            d = 0.08 * math.sin(9 * a + k * math.pi)
            r = 1.38 + d
            pts.append((math.cos(a) * r, math.sin(a) * r, 1.3 + 0.06 * math.cos(9 * a + k * math.pi)))
        twigs[TONES[k]].append(twig("RimTwig", pts, 0.09, closed=True))
    # Loose twig ends sticking out here and there
    for angle, z, length, tone in ((30, 1.0, 0.5, 0), (150, 0.7, 0.45, 1), (215, 1.15, 0.55, 2), (330, 0.55, 0.4, 1), (95, 1.2, 0.45, 0)):
        a = math.radians(angle)
        r = wall_radius(z)
        start = Vector((math.cos(a) * (r - 0.1), math.sin(a) * (r - 0.1), z))
        along = Vector((-math.sin(a), math.cos(a), 0.35)).normalized()
        out = Vector((math.cos(a), math.sin(a), 0))
        end = start + along * length + out * 0.25
        twigs[TONES[tone]].append(twig("Stick", [start, (start + end) / 2 + out * 0.05, end], 0.045))
    for tone, objs in twigs.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        parts.append(finish(bpy.context.view_layer.objects.active, tone))

    # The soft feather-down cushion filling the nest, puffy round its edge and flat where the rider sits
    puffs = [(1.0, (0, 0, TOP - 0.27), (1.3, 1.3, 0.3))]
    for i in range(10):
        a = 2 * math.pi * (i + 0.5) / 10
        puffs.append((0.3, (math.cos(a) * 1.05, math.sin(a) * 1.05, TOP - 0.18), (1, 1, 0.75)))
    down = blob("Down", puffs, voxel=0.06, keep=4500)
    for v in down.data.vertices:
        if v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.4
        rr = math.hypot(v.co.x, v.co.y) / 0.8
        if v.co.z > TOP - 0.15 and rr < 1:
            v.co.z -= 0.05 * (1 - rr * rr)
    parts.append(finish(down, "down"))

    # A pale blue speckled egg tucked into the down at the back right, leaning back
    egg_frame = Matrix.Translation((0.45, 1.2, TOP + 0.08)) @ Matrix.Rotation(math.radians(-25), 4, "X") @ Matrix.Rotation(math.radians(-15), 4, "Y")
    egg = ball("Egg", 1, (0, 0, 0), (0.27, 0.27, 0.36))
    for v in egg.data.vertices:
        # narrower at the top
        v.co.x *= 1 - 0.18 * max(v.co.z / 0.32, 0)
        v.co.y *= 1 - 0.18 * max(v.co.z / 0.32, 0)
    parts.append(finish(placed(egg, egg_frame), "egg"))
    for i, (a, h) in enumerate(((20, 0.15), (95, -0.05), (160, 0.12), (230, 0.0), (300, 0.2), (60, 0.25), (200, -0.15), (340, -0.1))):
        ar = math.radians(a)
        k = math.sqrt(max(1 - (h / 0.32) ** 2, 0)) * (1 - 0.18 * max(h / 0.32, 0))
        p = (math.cos(ar) * 0.27 * k, math.sin(ar) * 0.27 * k, h * 1.12)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=5, radius=0.035 + 0.01 * (i % 2), location=p, scale=(1, 1, 0.6))
        speck = bpy.context.active_object
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        parts.append(finish(placed(speck, egg_frame), "speck"))

    # Two small feathers poking out of the rim at the back left, fanned apart
    for yaw, tilt, at in ((160, 68, (-1.2, 0.75, 1.15)), (125, 55, (-0.85, 1.1, 1.15))):
        frame = Matrix.Translation(at) @ Matrix.Rotation(math.radians(yaw - 90), 4, "Z") @ Matrix.Rotation(math.radians(tilt), 4, "X")
        vane = ball("Feather", 1, (0, 0.45, 0), (0.15, 0.45, 0.03))
        for v in vane.data.vertices:
            # a pointed tip and a slight curve
            t = (v.co.y + 0.45) / 0.9  # (its points are around its own middle) 0 at the quill, 1 at the tip
            v.co.x *= 1 - 0.5 * max(t - 0.4, 0) / 0.6
            v.co.z += 0.14 * t * t
        parts.append(finish(placed(vane, frame), "feather"))
        parts.append(finish(placed(twig("Quill", [(0, -0.1, 0.0), (0, 0.45, 0.06), (0, 0.8, 0.12)], 0.018), frame), "down"))

    # The face on the front of the nest, standing just proud of the twigs
    fz = 0.68
    parts.extend(face(Matrix.Translation((0, -wall_radius(fz) - 0.17, fz)), 1.1))

    parts.append(front_marker(3.4))
    return parts
