"""Spawn Meadow: the Cloud Seat. A puffy white cloud cushion with a soft lavender underside, dipped on top
where the rider sits, a Cubeling face on its front (eyes with shines, pink blush, a small "w" mouth), two
little cat ears and gold stars."""

import math

import bpy
from mathutils import Vector

from seatkit import FACE_COLORS, ball, blob, finish, front_marker, split_below, star, tube, apply_modifiers

NAME = "Cloud"
TITLE = "Cloud Seat"
ZONE = 1
TOP = 1.15  # the seat's surface in the middle, above its bottom
COLORS = {
    **FACE_COLORS,
    "body": (0.97, 0.97, 1.0),
    "shade": (0.72, 0.74, 0.98),
    "earin": (1.0, 0.55, 0.7),
    "star": (1.0, 0.72, 0.1),
}

WIDTH = 3.6  # side to side
DEPTH = 3.0  # front to back
DIP = 0.2  # how much the top dips where the rider sits


def build():
    parts = []
    hw, hd = WIDTH / 2, DEPTH / 2
    # The cushion: a ring of big puffs round a lower middle, with smaller puffs filling in
    puffs = [(0.95, (0, 0, 0.62), (1.35, 1.2, 0.62))]
    for i in range(10):
        a = 2 * math.pi * i / 10
        x, y = math.cos(a) * (hw - 0.62), math.sin(a) * (hd - 0.58)
        r = 0.62 if i % 2 == 0 else 0.55
        puffs.append((r, (x, y, 0.62 + (0.06 if i % 2 == 0 else 0)), (1, 1, 0.9)))
    body = blob("CloudBody", puffs)
    # The seat's top: flatten what's above it, and dip it in the middle where the rider sits
    for v in body.data.vertices:
        if v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.35
        rr = math.hypot(v.co.x / (hw * 0.62), v.co.y / (hd * 0.62))
        if v.co.z > TOP - 0.25 and rr < 1:
            v.co.z -= DIP * (1 - rr * rr)
    # Underside: the lower part gets its own lavender mesh (split by height)
    shade = split_below(body, 0.4, "CloudShade")
    parts.append(finish(body, "body"))
    parts.append(finish(shade, "shade"))

    # The face on the front puff
    fy = -hd + 0.05  # the front surface
    fz = 0.62
    for sx in (-1, 1):
        parts.append(finish(ball("Eye", 0.17, (sx * 0.42, fy - 0.02, fz + 0.05), (1, 0.45, 1.2)), "eye"))
        parts.append(finish(ball("Shine", 0.055, (sx * 0.42 - 0.05, fy - 0.1, fz + 0.15), (1, 0.5, 1)), "shine"))
        parts.append(finish(ball("Blush", 0.14, (sx * 0.78, fy + 0.04, fz - 0.12), (1.2, 0.35, 0.7)), "blush"))
    w = [(-0.18, fy - 0.07, fz - 0.12), (-0.09, fy - 0.08, fz - 0.2), (0.0, fy - 0.08, fz - 0.13), (0.09, fy - 0.08, fz - 0.2), (0.18, fy - 0.07, fz - 0.12)]
    parts.append(finish(tube("Mouth", w, 0.028), "mouth"))

    # Two little cat ears on the front top, pink inside
    for sx in (-1, 1):
        bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.3, radius2=0.04, depth=0.5, location=(sx * 0.95, -hd + 0.75, TOP + 0.12))
        ear = bpy.context.active_object
        ear.rotation_euler = (math.radians(-15), math.radians(sx * 12), 0)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        b = ear.modifiers.new("Sub", "SUBSURF")
        b.levels = 1
        apply_modifiers(ear)
        parts.append(finish(ear, "body"))
        bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.17, radius2=0.03, depth=0.3, location=(sx * 0.95, -hd + 0.62, TOP + 0.12))
        inner = bpy.context.active_object
        inner.rotation_euler = (math.radians(-15), math.radians(sx * 12), 0)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        parts.append(finish(inner, "earin"))

    # Gold stars on the sides, facing out, standing a little proud of the puffs
    for a, z, r in ((200, 0.8, 0.21), (-20, 0.78, 0.23), (-60, 1.0, 0.16), (130, 0.95, 0.16)):
        d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
        at = Vector((d.x * (hw - 0.02), d.y * (hd - 0.02), z))
        s = star("Star", (0, 0, 0), r, -1)
        s.rotation_euler = (0, 0, math.atan2(d.x, -d.y))
        s.location = at
        bpy.context.view_layer.objects.active = s
        bpy.ops.object.select_all(action="DESELECT")
        s.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
        parts.append(finish(s, "star"))

    parts.append(front_marker(DEPTH))
    return parts
