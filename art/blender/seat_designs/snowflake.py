"""Frozen Lake: the Snowflake Seat. A big six-armed snowflake lying flat (thick rounded arms with branching
side-spikes and a white frost line down each, glossy crystal balls at the tips), an icy hexagonal hub under its
middle, and a soft puffy white cushion on top where the rider sits, with a Cubeling face on its front."""

import math

from mathutils import Matrix

from seatkit import FACE_COLORS, ball, blob, cylinder, face, finish, front_marker, placed, tube

NAME = "Snowflake"
TITLE = "Snowflake Seat"
ZONE = 9
ORDER = 2
TOP = 1.08  # the cushion's top in the middle
COLORS = {
    **FACE_COLORS,
    "flake": (0.55, 0.78, 1.0),
    "frost": (0.93, 0.97, 1.0),
    "cushion": (0.98, 0.98, 1.0),
    "crystal": (0.72, 0.93, 1.0),
    "ice": (0.36, 0.62, 0.95),
}
LIGHT = (0.75, 0.9, 1.0)

ARM = 1.66  # how far each arm reaches from the middle (to its tip ball's middle)
FLAKE_Z = 0.42  # the flake's mid-height
FLAT = 0.7  # the arms' tubes are squashed to this much of their width in height


def flat_tube(name, pts, radius):
    """A round tube squashed in height so the flake reads as a thick flat star."""
    obj = tube(name, [(x, y, 0) for x, y in pts], radius)
    return placed(obj, Matrix.Translation((0, 0, FLAKE_Z)) @ Matrix.Scale(FLAT, 4, (0, 0, 1)))


def build():
    parts = []
    # Six arms pointing out at 0, 60, ... degrees (so two lie along X, making the flake wider than deep)
    for i in range(6):
        a = math.radians(60 * i)
        d = (math.cos(a), math.sin(a))
        n = (-d[1], d[0])

        def at(r, s=0.0):
            return (d[0] * r + n[0] * s, d[1] * r + n[1] * s)

        # the arm itself, and its branches: pairs of side-spikes swept out toward the tip
        parts.append(finish(flat_tube("Arm", [at(0.0), at(ARM)], 0.17), "flake"))
        for r0, length, rad in ((0.82, 0.52, 0.11), (1.22, 0.38, 0.095)):
            for side in (-1, 1):
                tip = at(r0 + length * 0.7, side * length * 0.72)
                parts.append(finish(flat_tube("Branch", [at(r0 - 0.05), tip], rad), "flake"))
                parts.append(finish(ball("BranchTip", rad * 1.05, (*tip, FLAKE_Z), (1, 1, FLAT)), "flake"))
        # a white frost line down the arm's top
        parts.append(finish(placed(tube("Frost", [(*at(0.9), 0), (*at(ARM - 0.12), 0)], 0.055),
                                   Matrix.Translation((0, 0, FLAKE_Z + 0.17 * FLAT - 0.02)) @ Matrix.Scale(0.7, 4, (0, 0, 1))), "frost"))
        # a glossy crystal ball at the tip
        parts.append(finish(ball("Tip", 0.16, (*at(ARM + 0.05), FLAKE_Z + 0.02)), "crystal"))

    # The hub under the middle: a chunky six-sided ice prism the arms grow from, reaching down to the ground
    hub = cylinder("Hub", 0.62, 0.42, (0, 0, 0.27), vertices=6, bevel=0.08)
    parts.append(finish(hub, "ice"))

    # The cushion: a round puffy pillow, one big puff ringed by six softer ones (between the arms), melted
    # together and flattened on top where the rider sits
    puffs = [(1.0, (0, 0, 0.83), (0.74, 0.74, 0.33))]
    for i in range(6):
        a = math.radians(30 + 60 * i)
        puffs.append((0.34, (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.76), (1, 1, 0.68)))
    cushion = blob("Cushion", puffs, voxel=0.06, keep=6000)
    for v in cushion.data.vertices:
        if v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.35
        rr = math.hypot(v.co.x, v.co.y) / 0.7
        if v.co.z > TOP - 0.15 and rr < 1:
            v.co.z -= 0.05 * (1 - rr * rr)
    parts.append(finish(cushion, "cushion"))

    # The face on the cushion's front puff (the one at -90 degrees)
    fy = -(0.62 + 0.34) + 0.02
    parts += face(Matrix.Translation((0, fy, 0.78)), size=0.95, mouth="w")

    parts.append(front_marker(2 * (ARM + 0.21) * math.sin(math.radians(60))))
    return parts
