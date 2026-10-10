"""Mushroom Cave: the Glow Mushroom Seat. A cluster of cave mushrooms: one big blue cap, flat on top where the
rider sits, with glowing cyan spots and glowing gills underneath, on a chubby indigo stem with a Cubeling face;
three little glowing mushrooms branch off its back, standing up behind it like a glowing crown."""

import math

from mathutils import Matrix, Vector

from seatkit import FACE_COLORS, apply_modifiers, ball, face, finish, front_marker, placed, split_below, tube

NAME = "GlowShroom"
TITLE = "Glow Mushroom Seat"
ZONE = 5
ORDER = 2
TOP = 1.21  # the big cap's flat top, where the rider sits
COLORS = {
    **FACE_COLORS,
    "cap": (0.06, 0.26, 0.9),
    "glow": (0.25, 0.95, 1.0),
    "stem": (0.17, 0.11, 0.5),
}
GLOW = ("glow",)
LIGHT = (0.3, 0.9, 1.0)

# The big cap: a rounded "squircle" dome round CENTER (flat-topped, with round shoulders), squashed underneath
RX, RY, RZ = 1.6, 1.4, 0.54
CENTER = Vector((0, 0, 0.67))
ROUND = 3.2  # the dome's superellipse power: 2 is a plain ellipsoid, higher is flatter on top
UNDER = 0.12  # how much the undersides are squashed up (nearly flat gills, so the stem shows)


def dome_point(direction, center, radii, power):
    """Where a direction from a dome's middle meets its surface: a superellipse in profile."""
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


def spot(polar, azimuth, radius):
    """A round glowing spot lying on the big cap, a flat lens turned to face out along the surface."""
    p, n = on_cap(polar, azimuth)
    lens = ball("Spot", radius, (0, 0, 0), (1, 1, 0.15))
    rot = Vector((0, 0, 1)).rotation_difference(n).to_matrix().to_4x4()
    return placed(lens, Matrix.Translation(p - n * 0.005) @ rot)


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
    # The big cap, its underside split off as the glowing gills
    cap = mushroom_cap("Cap", CENTER, (RX, RY, RZ), ROUND)
    gills = split_below(cap, CENTER.z - 0.02, "Gills")
    parts.append(finish(cap, "cap"))
    parts.append(finish(gills, "glow"))
    # glowing spots: a ring round the shoulder and smaller ones lower down between them
    for a in range(0, 360, 60):
        parts.append(finish(spot(52, a + 30, 0.22), "glow"))
    for a in (0, 60, 120, 180, 240, 300):
        parts.append(finish(spot(75, a, 0.14), "glow"))

    # The chubby bulb of a stem, with the face on its front under the cap's glowing rim
    parts.append(finish(ball("Stem", 1, (0, 0, 0.46), (0.9, 0.82, 0.46)), "stem"))
    parts += face(Matrix.Translation((0, -0.8, 0.38)) @ Matrix.Rotation(math.radians(-8), 4, "X"), 0.8)

    # Three little glowing mushrooms branching off the stem's back and standing up behind the big cap, a
    # glowing crown of different heights clear of the rider
    for name, (x, y), h, size in (
        ("Left", (-0.72, 1.45), 1.45, 0.42),
        ("Right", (0.8, 1.4), 1.12, 0.36),
        ("Middle", (0.08, 1.75), 0.86, 0.28),
    ):
        d = Vector((x, y, 0)).normalized()
        tip = Vector((x, y, h)) + d * 0.1
        stalk = [(x * 0.45, 0.62, 0.3), (x * 0.9, y - 0.12, 0.42), (x, y, 0.55 + (h - 0.55) * 0.5), tuple(tip)]
        parts.append(finish(tube(name + "Stalk", stalk, 0.16), "stem"))
        axis = Vector((0, 0, 1)).lerp(d, 0.2).normalized()
        rot = Vector((0, 0, 1)).rotation_difference(axis).to_matrix().to_4x4()
        small = mushroom_cap(name + "Cap", (0, 0, 0), (size, size, size * 0.85), 2.2)
        parts.append(finish(placed(small, Matrix.Translation(tip) @ rot), "glow"))

    parts.append(front_marker(2 * RY))
    return parts
