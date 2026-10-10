"""Desert: the Cactus Seat. A round, chubby barrel cactus with soft vertical ribs, its top pressed flat into a
seat with a pale green ring round it, a pink flower blooming at the back of the top, two short arms at the
sides, little cream spine dots along the ribs, a terracotta pot band at the bottom and a face on the front."""

import math

import bpy
from mathutils import Matrix

from seatkit import FACE_COLORS, ball, face, finish, front_marker, petal_matrix, placed, torus, tube, cylinder

NAME = "Cactus"
TITLE = "Cactus Seat"
ZONE = 6
ORDER = 1
TOP = 1.13  # the flattened top, where the rider sits
FLAT = 1.17  # the height the top eases toward (it settles a little under it)
COLORS = {
    **FACE_COLORS,
    "cactus": (0.16, 0.55, 0.2),
    "ring": (0.5, 0.82, 0.3),
    "spine": (1.0, 0.93, 0.72),
    "flower": (1.0, 0.36, 0.62),
    "pollen": (1.0, 0.78, 0.15),
    "pot": (0.8, 0.32, 0.15),
}

RX, RY = 1.32, 1.18  # the barrel's half width and half depth
MID = 0.7  # the barrel's widest height
HALF = 0.8  # the barrel's half height (before its top is flattened)
RIBS = 14  # vertical ribs round the barrel
RIB = 0.06  # how far the ribs stand out (fraction of the radius)
SOFT = 0.26  # the top rounds off into its flat seat over this height


def rib_angle(k):
    """The angle (radians, round from +X) of rib k's ridge; a groove sits right at the front (the face)."""
    return -math.pi / 2 + (k + 0.5) * 2 * math.pi / RIBS


def rib_depth(theta):
    """The ribs fade out on a smooth patch at the front, where the face is."""
    d = math.atan2(math.sin(theta + math.pi / 2), math.cos(theta + math.pi / 2))
    return RIB * (1 - 0.85 * math.exp(-((d / 0.42) ** 2)))


def barrel_point(theta, z):
    """A point on the barrel's surface (ignoring the flattened top) at angle theta and height z."""
    s = math.sqrt(max(1 - ((z - MID) / HALF) ** 2, 0))
    rib = 1 + rib_depth(theta) * math.cos(RIBS * (theta - rib_angle(0)))
    return math.cos(theta) * RX * s * rib, math.sin(theta) * RY * s * rib


def dot(x, y, z, r):
    """A small round dot (a low-poly ball, there are many of them)."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r, location=(x, y, z))
    return bpy.context.active_object


def build():
    parts = []

    # The barrel: a sphere squashed wide, its sides ribbed, its top eased flat (with a slight dip) at FLAT
    bpy.ops.mesh.primitive_uv_sphere_add(segments=RIBS * 6, ring_count=28, radius=1, location=(0, 0, 0))
    body = bpy.context.active_object
    body.name = "Barrel"
    for v in body.data.vertices:
        x, y, z = v.co.x, v.co.y, v.co.z
        theta = math.atan2(y, x)
        rib = 1 + rib_depth(theta) * math.cos(RIBS * (theta - rib_angle(0))) * math.sqrt(x * x + y * y)
        x, y, z = x * RX * rib, y * RY * rib, MID + z * HALF
        edge = FLAT - SOFT
        if z > edge:
            z = edge + SOFT * math.tanh((z - edge) / SOFT)
        rr = math.hypot(x / 0.8, y / 0.8)
        if z > FLAT - 0.1 and rr < 1:
            z -= 0.04 * (1 - rr * rr)
        v.co = (x, y, max(z, 0.06))
    parts.append(finish(body, "cactus"))

    # The pale green seat ring round the flat top
    parts.append(finish(torus("Ring", 0.9, 0.07, (0, 0, FLAT - 0.035), 64), "ring"))

    # The terracotta pot band round the bottom, with a rolled rim
    pot = cylinder("Pot", 1.3, 0.4, (0, 0, 0.2), 48, 0.06)
    for v in pot.data.vertices:
        f = 0.86 + 0.14 * (v.co.z + 0.2) / 0.4  # tapering down a little
        v.co.x *= f
        v.co.y *= f * RY / RX
    parts.append(finish(pot, "pot"))
    rim = torus("PotRim", 1.3, 0.1, (0, 0, 0.42), 48)
    for v in rim.data.vertices:
        v.co.y *= RY / RX
    parts.append(finish(rim, "pot"))

    # Two short arms, out at the sides and curving up, with rounded tips
    for sx in (-1, 1):
        pts = [(sx * 1.1, 0.05, 0.62), (sx * 1.45, 0.05, 0.64), (sx * 1.66, 0.05, 0.76), (sx * 1.72, 0.05, 1.02)]
        parts.append(finish(tube("Arm", pts, 0.19), "cactus"))
        parts.append(finish(ball("ArmTip", 0.19, (sx * 1.72, 0.05, 1.02), (1, 1, 0.9)), "cactus"))
        for z in (0.82, 1.0):
            parts.append(finish(dot(sx * 1.92, 0.05, z, 0.035), "spine"))
        parts.append(finish(dot(sx * 1.48, 0.05, 0.85, 0.035), "spine"))

    # Spine dots along each rib's ridge (none on the two ribs either side of the face)
    for k in range(RIBS):
        theta = rib_angle(k)
        if k in (0, RIBS - 1):
            continue
        for z in (0.62, 0.9, 1.08):
            x, y = barrel_point(theta, z)
            if abs(x) > 1.0 and abs(z - 0.7) < 0.12:
                continue  # where the arms join
            parts.append(finish(dot(x * 1.01, y * 1.01, z, 0.04), "spine"))

    # A pink flower at the back of the top, behind the rider, tipped back a little
    fc = (0, 1.12, FLAT - 0.06)
    tilt = Matrix.Translation(fc) @ Matrix.Rotation(math.radians(-45), 4, "X")
    for i in range(6):
        petal = ball("Petal", 1, (0, 0, 0), (0.15, 0.27, 0.06))
        for v in petal.data.vertices:
            v.co.z += 0.1 * (v.co.y / 0.27) ** 2  # the petals cup up toward their tips
        parts.append(finish(placed(petal, tilt @ petal_matrix(60 * i + 30, 0.22, 0.04, 20)), "flower"))
    parts.append(finish(placed(ball("Bud", 0.13, (0, 0, 0.08), (1, 1, 0.7)), tilt), "pollen"))

    # The face on the barrel's front
    fz = 0.72
    _, fy = barrel_point(-math.pi / 2, fz)
    parts += face(Matrix.Translation((0, fy + 0.02, fz)), 1.0)

    parts.append(front_marker(2 * RY))
    return parts
