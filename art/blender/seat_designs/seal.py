"""Frozen Lake: the Seal Seat. A chubby white baby harp seal lying on its belly, the rider on its back: a round
head resting at the front with big Cubeling eyes, a tiny dark nose on a puffy muzzle and whiskers, front
flippers out at the sides, rear flippers fanned up at the back, and a few pale grey spots."""

import math

from mathutils import Matrix, Vector

from seatkit import FACE_COLORS, ball, blob, finish, front_marker, placed, split_below, tube

NAME = "Seal"
TITLE = "Seal Seat"
ZONE = 9
ORDER = 3
TOP = 1.08  # the seal's back in the middle
COLORS = {
    **FACE_COLORS,
    "body": (0.96, 0.96, 0.98),
    "belly": (0.8, 0.84, 0.95),
    "spot": (0.76, 0.78, 0.86),
    "flipper": (0.78, 0.8, 0.9),
    "nose": (0.06, 0.04, 0.05),
    "whisker": (0.45, 0.45, 0.52),
}
LIGHT = (0.85, 0.92, 1.0)

BODY = ((0, 0.08, 0.56), (1.25, 1.32, 0.56))  # the body's middle and half-sizes
HEAD = ((0, -1.14, 0.6), (0.74, 0.55, 0.5))  # the head's middle and half-sizes


def on_ellipsoid(shape, x, z, side=-1):
    """The point on an ellipsoid's surface at (x, z), on its front (side -1) or back, and the surface normal."""
    (cx, cy, cz), (rx, ry, rz) = shape
    u, w = (x - cx) / rx, (z - cz) / rz
    t = math.sqrt(max(1 - u * u - w * w, 0.0))
    p = Vector((x, cy + side * ry * t, z))
    n = Vector((u / rx, side * t / ry, w / rz)).normalized()
    return p, n


def spot(at, normal, size):
    """A flat grey spot lying on the surface at `at`."""
    obj = ball("Spot", size, (0, 0, 0), (1.25, 1, 0.22))
    m = Matrix.Translation(at - normal * 0.015) @ normal.to_track_quat("Z", "Y").to_matrix().to_4x4()
    return finish(placed(obj, m), "spot")


def build():
    parts = []
    # Body and head melted into one chubby seal: a big oval body, a neck puff, the round head at the front
    # and a tapering tail end at the back
    (bx, by, bz), (brx, bry, brz) = BODY
    (hx, hy, hz), (hrx, hry, hrz) = HEAD
    puffs = [
        (1.0, (bx, by, bz), (brx, bry, brz)),
        (1.0, (hx, hy, hz), (hrx, hry, hrz)),
        (0.55, (0, -0.68, 0.55), (1.15, 1, 0.9)),  # neck, filling in between
        (0.44, (0, 1.25, 0.42), (1.1, 1, 0.8)),  # tail end
    ]
    seal = blob("Seal", puffs, voxel=0.065, keep=7000)
    # a flat back where the rider sits
    for v in seal.data.vertices:
        if v.co.z > TOP - 0.04 and v.co.y > -0.9:
            v.co.z = TOP - 0.04 + (v.co.z - TOP + 0.04) * 0.4
    belly = split_below(seal, 0.16, "Belly")
    parts.append(finish(seal, "body"))
    parts.append(finish(belly, "belly"))

    # The muzzle: two puffy cheeks under the nose on the head's front
    for sx in (-1, 1):
        p, n = on_ellipsoid(HEAD, sx * 0.11, hz - 0.17)
        parts.append(finish(ball("Cheek", 0.14, p + n * 0.02, (1.1, 0.8, 0.85)), "body"))

    # The face: big glossy eyes set into the round head, pink blush, a tiny dark nose and whiskers
    for sx in (-1, 1):
        p, n = on_ellipsoid(HEAD, sx * 0.33, hz + 0.1)
        parts.append(finish(ball("Eye", 0.15, p + n * 0.01, (1, 0.5, 1.2)), "eye"))
        parts.append(finish(ball("Shine", 0.05, p + n * 0.07 + Vector((-0.05 * sx - 0.0, 0, 0.09)), (1, 0.5, 1)), "shine"))
        parts.append(finish(ball("Shine", 0.025, p + n * 0.07 + Vector((0.05 * sx, 0, -0.06)), (1, 0.5, 1)), "shine"))
        p, n = on_ellipsoid(HEAD, sx * 0.55, hz - 0.08)
        parts.append(finish(ball("Blush", 0.11, p + n * 0.005, (1.2, 0.35, 0.7)), "blush"))
    p, n = on_ellipsoid(HEAD, 0, hz - 0.08)
    parts.append(finish(ball("Nose", 0.075, p + Vector((0, -0.02, 0)), (1.35, 0.8, 0.9)), "nose"))
    # a tiny "w" mouth under the nose, across the cheeks
    p, n = on_ellipsoid(HEAD, 0, hz - 0.17)
    my = p.y - 0.13
    mz = p.z - 0.07
    w = [(-0.1, my + 0.01, mz + 0.03), (-0.05, my, mz - 0.01), (0, my - 0.005, mz + 0.02), (0.05, my, mz - 0.01), (0.1, my + 0.01, mz + 0.03)]
    parts.append(finish(tube("Mouth", w, 0.018), "mouth"))
    # three whiskers each side, springing out of the cheeks
    for sx in (-1, 1):
        for dz in (0.04, -0.02, -0.08):
            p, n = on_ellipsoid(HEAD, sx * 0.2, hz - 0.15 + dz * 0.5)
            start = p + n * 0.08
            mid = start + Vector((sx * 0.18, -0.03, dz * 0.6))
            end = start + Vector((sx * 0.36, 0.02, dz * 1.6))
            parts.append(finish(tube("Whisker", [tuple(start), tuple(mid), tuple(end)], 0.012), "whisker"))

    # Front flippers out at the sides, lying flat and pointing out and back a little
    for sx in (-1, 1):
        f = ball("Flipper", 1, (0, 0, 0), (0.44, 0.24, 0.09))
        for v in f.data.vertices:  # a rounder root and a narrower tip
            v.co.y *= 1 - 0.3 * max(sx * v.co.x, 0) / 0.44
        m = Matrix.Translation((sx * 1.3, -0.45, 0.26)) @ Matrix.Rotation(math.radians(-sx * 25), 4, "Z") @ Matrix.Rotation(math.radians(sx * -12), 4, "Y")
        parts.append(finish(placed(f, m), "flipper"))

    # Rear flippers fanned out and tipped up at the back of the tail
    for sx in (-1, 1):
        f = ball("Tail", 1, (0, 0, 0), (0.22, 0.4, 0.08))
        for v in f.data.vertices:  # wider at the end, with a soft notch
            t = max(v.co.y, 0) / 0.4
            v.co.x *= 1 + 0.45 * t
            v.co.z += 0.02 * math.cos(v.co.x * 20) * t
        m = (Matrix.Translation((sx * 0.24, 1.45, 0.44)) @ Matrix.Rotation(math.radians(-sx * 28), 4, "Z")
             @ Matrix.Rotation(math.radians(30), 4, "X"))
        parts.append(finish(placed(f, m), "flipper"))

    # Pale grey spots on the body's sides and rump (kept off the top where the rider sits)
    for x, y, z, s in ((-1.05, 0.5, 0.62, 0.14), (-0.85, 0.95, 0.85, 0.1), (1.08, 0.35, 0.7, 0.13), (0.95, -0.2, 0.85, 0.09),
                       (-0.4, 1.25, 0.78, 0.11), (0.5, 1.18, 0.8, 0.13)):
        (cx, cy, cz), (rx, ry, rz) = BODY
        d = Vector(((x - cx) / rx, (y - cy) / ry, (z - cz) / rz))
        d.normalize()
        p = Vector((cx + d.x * rx, cy + d.y * ry, cz + d.z * rz))
        n = Vector((d.x / rx, d.y / ry, d.z / rz)).normalized()
        parts.append(spot(p, n, s))

    parts.append(front_marker(3.4))
    return parts
