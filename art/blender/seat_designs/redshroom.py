"""Mushroom Cave: the Mushroom Seat. A big red toadstool cap with round white dots and a Cubeling face on its
front, flattened on top where the rider sits, over a short chubby cream stem with a frilly ring, peach gills under its
edge, and a tiny baby mushroom sprouting at the stem's foot."""

import math

from mathutils import Matrix, Vector

from seatkit import FACE_COLORS, apply_modifiers, bake, ball, face, finish, front_marker, placed, split_below, torus

NAME = "RedShroom"
TITLE = "Mushroom Seat"
ZONE = 5
ORDER = 1
TOP = 1.21  # the cap's flattened top, where the rider sits
COLORS = {
    **FACE_COLORS,
    "cap": (0.92, 0.06, 0.07),
    "dot": (1.0, 0.97, 0.94),
    "gill": (1.0, 0.72, 0.55),
    "stem": (1.0, 0.9, 0.72),
}

# The cap: a rounded "squircle" dome round CENTER (flat-topped, with full round shoulders), squashed underneath
RX, RY, RZ = 1.72, 1.58, 0.58
CENTER = Vector((0, 0, 0.63))
ROUND = 3.2  # the dome's superellipse power: 2 is a plain ellipsoid, higher is flatter on top
UNDER = 0.12  # how much the underside is squashed up (nearly flat gills, so the stem shows)


def dome_point(direction, center, radii, power):
    """Where a direction from the dome's middle meets its surface: a superellipse in profile."""
    d = direction.normalized()
    r = math.hypot(d.x, d.y)
    e = 2 / power
    out = r**e / r if r > 1e-6 else 0.0
    up = math.copysign(abs(d.z) ** e, d.z)
    return Vector((center[0] + d.x * out * radii[0], center[1] + d.y * out * radii[1], center[2] + up * radii[2]))


def on_cap(polar, azimuth):
    """A point on the big cap's dome and its outward normal; `polar` degrees from the top."""
    def at(pa, az):
        pa, az = math.radians(pa), math.radians(az)
        return dome_point(Vector((math.sin(pa) * math.cos(az), math.sin(pa) * math.sin(az), math.cos(pa))), CENTER, (RX, RY, RZ), ROUND)

    p = at(polar, azimuth)
    n = (at(polar + 0.5, azimuth) - p).cross(at(polar, azimuth + 0.5) - p).normalized()
    if n.dot(p - CENTER) < 0:
        n = -n
    return p, n


def dot(polar, azimuth, radius):
    """A round white spot lying on the cap, a flat lens turned to face out along the surface."""
    p, n = on_cap(polar, azimuth)
    spot = ball("Dot", radius, (0, 0, 0), (1, 1, 0.15))
    rot = Vector((0, 0, 1)).rotation_difference(n).to_matrix().to_4x4()
    return placed(spot, Matrix.Translation(p - n * 0.005) @ rot)


def mushroom_cap(name, center, radii, power):
    """A dome (see dome_point) whose lower half is squashed up into a shallow underside."""
    cap = ball(name, 1, (0, 0, 0))
    sub = cap.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    apply_modifiers(cap)
    for v in cap.data.vertices:
        p = dome_point(v.co, center, radii, power)
        if p.z < center[2]:
            p.z = center[2] - (center[2] - p.z) * UNDER
        v.co = p
    return cap


def build():
    parts = []
    # The big cap, its underside split off as the peach gills
    cap = mushroom_cap("Cap", CENTER, (RX, RY, RZ), ROUND)
    gills = split_below(cap, CENTER.z - 0.02, "Gills")
    parts.append(finish(cap, "cap"))
    parts.append(finish(gills, "gill"))

    # White dots: a ring of big ones round the shoulder, smaller ones lower down between them (none on the
    # flat top, which is the seat, and none on the front, which has the face)
    for i in range(6):
        parts.append(finish(dot(52, 60 * i, 0.27), "dot"))
    for a in (30, 90, 150, 210, 330):
        parts.append(finish(dot(74, a, 0.18), "dot"))

    # The short chubby stem, a barrel, with a frilly ring just under the cap
    parts.append(finish(ball("Stem", 1, (0, 0, 0.36), (0.74, 0.7, 0.36)), "stem"))
    frill = torus("Frill", 0.66, 0.06, (0, 0, 0.52), segments=64)
    for v in frill.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        out = math.hypot(v.co.x, v.co.y) - 0.66  # across the tube: flare its outer side down
        v.co.z += 0.035 * math.sin(14 * a) - 0.25 * max(out, 0)
    parts.append(finish(bake(frill), "stem"))

    # The face on the cap's front, turned part way up the slope so it reads from the front and from above
    p, n = on_cap(77, -90)
    tilt = math.atan2(n.z, -n.y) * 0.5
    parts += face(Matrix.Translation(p + n * 0.01) @ Matrix.Rotation(-tilt, 4, "X"), 0.95)

    # A baby mushroom sprouting at the stem's foot, front right
    bx, by = 0.64, -0.46
    parts.append(finish(ball("BabyStem", 1, (bx, by, 0.16), (0.13, 0.13, 0.16)), "stem"))
    parts.append(finish(ball("BabyFoot", 1, (bx * 0.8, by * 0.8, 0.07), (0.27, 0.22, 0.08)), "stem"))
    baby = mushroom_cap("BabyCap", (bx + 0.02, by - 0.02, 0.32), (0.25, 0.25, 0.18), 2.4)
    parts.append(finish(baby, "cap"))
    p = Vector((bx + 0.02 - 0.08, by - 0.02 - 0.15, 0.32 + 0.18 * 0.78))
    parts.append(finish(placed(ball("BabyDot", 0.06, (0, 0, 0), (1, 1, 0.3)), Matrix.Translation(p) @ Matrix.Rotation(math.radians(55), 4, "X")), "dot"))

    parts.append(front_marker(2 * RY))
    return parts
