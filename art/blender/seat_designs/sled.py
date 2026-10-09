"""Snow Peak: the Sled Seat. A little wooden sled: a deck of warm two-tone slats on red runners that curl up and
back over themselves at the front, a red plaid cushion where the rider sits, a red crossbar between the curls
with a pull rope looped from it, snow puffs on the deck's corners and a Cubeling face on the front board."""

import math

from mathutils import Matrix

from seatkit import FACE_COLORS, ball, blob, box, cylinder, face, finish, front_marker, subdivide, tube

NAME = "Sled"
TITLE = "Sled Seat"
ZONE = 7
ORDER = 2
TOP = 1.02  # the cushion's top, where the rider sits
COLORS = {
    **FACE_COLORS,
    "wood": (0.62, 0.3, 0.1),
    "woodlight": (0.85, 0.52, 0.24),
    "runner": (0.82, 0.06, 0.06),
    "cushion": (0.75, 0.05, 0.06),
    "plaid": (0.04, 0.2, 0.08),
    "plaidthin": (1.0, 0.85, 0.45),
    "rope": (0.75, 0.55, 0.28),
    "snow": (0.95, 0.97, 1.0),
}

DECK_W = 2.9  # the slats' length, side to side
DECK_D = 2.9  # front to back over all the slats
DECK_Z = 0.68  # the slats' middle height
RUNNER_X = 1.52  # the runners' distance from the middle
RUNNER_R = 0.085  # the runners' thickness
DEPTH = 3.6  # the whole sled, front curl to back


def runner_path(sx):
    """A runner's middle line: a little flick up at the back, flat along the bottom, then up and curling back
    over itself at the front (y, z pairs)."""
    yz = [
        (1.6, 0.3), (1.52, 0.16), (1.38, 0.1), (1.0, 0.09), (0.0, 0.09), (-1.0, 0.09), (-1.3, 0.12),
        (-1.52, 0.22), (-1.68, 0.4), (-1.76, 0.62), (-1.74, 0.82), (-1.62, 0.96), (-1.46, 0.98),
        (-1.36, 0.88), (-1.38, 0.76), (-1.48, 0.72), (-1.55, 0.78),
    ]
    # round the corners a bit by easing each inner point toward its neighbours' middle
    smooth = [yz[0]]
    for a, b, c in zip(yz, yz[1:], yz[2:]):
        smooth.append(((a[0] + 2 * b[0] + c[0]) / 4, (a[1] + 2 * b[1] + c[1]) / 4))
    smooth.append(yz[-1])
    return [(sx * RUNNER_X, y, z) for y, z in smooth]


def build():
    parts = []
    # The deck: seven slats across, alternating dark and light wood, with small gaps between them
    n = 7
    pitch = DECK_D / n
    for i in range(n):
        y = -DECK_D / 2 + pitch * (i + 0.5)
        slat = box("Slat", (DECK_W, pitch - 0.05, 0.12), (0, y, DECK_Z), bevel=0.045)
        parts.append(finish(slat, "wood" if i % 2 == 0 else "woodlight"))
    # two rails under the slats, front to back, holding them together
    for sx in (-1, 1):
        rail = box("Rail", (0.16, DECK_D - 0.1, 0.14), (sx * 1.2, 0, DECK_Z - 0.12), bevel=0.04)
        parts.append(finish(rail, "wood"))

    # The red runners with their curled fronts, and short red struts up to the deck
    for sx in (-1, 1):
        parts.append(finish(tube("Runner", runner_path(sx), RUNNER_R), "runner"))
        for y in (-0.95, 0.0, 0.95):
            strut = cylinder("Strut", 0.07, DECK_Z - 0.1, (sx * RUNNER_X, y, (DECK_Z + 0.1) / 2), vertices=16, bevel=0.0)
            parts.append(finish(strut, "runner"))
            # a rounded cap where the strut meets the deck's side
            parts.append(finish(ball("Cap", 0.1, (sx * RUNNER_X, y, DECK_Z), (1, 1, 0.8)), "runner"))
    # the crossbar between the two curls, at the front
    bar = tube("Bar", [(-RUNNER_X, -1.66, 0.62), (RUNNER_X, -1.66, 0.62)], 0.065)
    parts.append(finish(bar, "runner"))

    # The front board under the deck's front edge, carrying the face
    board = box("Board", (2.3, 0.12, 0.5), (0, -DECK_D / 2 + 0.02, DECK_Z - 0.32), bevel=0.05)
    parts.append(finish(board, "woodlight"))
    fy = -DECK_D / 2 - 0.04
    parts += face(Matrix.Translation((0, fy, DECK_Z - 0.3)), size=1.0, mouth="w")

    # The cushion: a soft rounded pad on the slats with a gentle dip where the rider sits, and plaid bands
    # (wide dark green, thin yellow beside them) wrapped round it both ways, a hair proud of it
    cw, cd, ch = 2.3, 2.25, 0.3
    cz = DECK_Z + 0.06 + ch / 2
    top = cz + ch / 2

    def pad(name, size, grow=0.0, dx=0.0, dy=0.0):
        obj = box(name, (size[0] + grow, size[1] + grow, ch + grow), (dx, 0.05 + dy, cz), bevel=0.13, segments=4)
        subdivide(obj, 1)
        for v in obj.data.vertices:
            rr = math.hypot(v.co.x / (cw * 0.42), (v.co.y - 0.05) / (cd * 0.42))
            if v.co.z > cz and rr < 1:
                v.co.z -= 0.04 * (1 - rr * rr)
        return obj

    parts.append(finish(pad("Cushion", (cw, cd)), "cushion"))
    for off in (-0.62, 0.62):
        for w, role, shift in ((0.2, "plaid", 0.0), (0.04, "plaidthin", 0.16), (0.04, "plaidthin", -0.16)):
            across = pad("Band", (w, cd), 0.016, dx=off + shift)  # front to back
            parts.append(finish(across, role))
            along = pad("Band", (cw, w), 0.024 if role == "plaid" else 0.032, dy=off + shift)  # side to side
            parts.append(finish(along, role))
    # a tuft button in each plaid square's corner
    for x in (-0.62, 0.62):
        for y in (-0.57, 0.67):
            parts.append(finish(ball("Tuft", 0.06, (x, y, top - 0.005), (1, 1, 0.5)), "plaidthin"))

    # The pull rope: knotted to the top of each front curl, sagging forward between them
    for sx in (-1, 1):
        parts.append(finish(ball("Knot", 0.1, (sx * RUNNER_X, -1.72, 0.84), (1.1, 1, 1)), "rope"))
    loop = []
    for i in range(21):
        t = i / 20
        a = math.pi * t
        loop.append((-RUNNER_X * math.cos(a), -1.72 - 0.3 * math.sin(a), 0.84 - 0.12 * math.sin(a) ** 2))
    parts.append(finish(tube("Rope", loop, 0.04), "rope"))

    # Snow puffs on the deck's corners and on top of each front curl
    for sx in (-1, 1):
        for y, z in ((-1.25, DECK_Z + 0.07), (1.28, DECK_Z + 0.07)):
            snow = blob("Snow", [(0.2, (sx * 1.27, y, z + 0.05), (1.1, 1, 0.65)),
                                 (0.14, (sx * 1.15, y + (0.13 if y < 0 else -0.13), z + 0.03), (1, 1, 0.6)),
                                 (0.12, (sx * 1.37, y + (0.08 if y < 0 else -0.1), z + 0.1), (1, 1, 0.8))], voxel=0.05, keep=900)
            parts.append(finish(snow, "snow"))
        cap = blob("CurlSnow", [(0.13, (sx * RUNNER_X, -1.62, 1.05), (1.1, 1.3, 0.55)),
                                (0.09, (sx * RUNNER_X, -1.47, 1.05), (1, 1, 0.6))], voxel=0.04, keep=700)
        parts.append(finish(cap, "snow"))

    parts.append(front_marker(DEPTH))
    return parts
