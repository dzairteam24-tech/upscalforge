"""Spawn Meadow and Forest: a round puffy tree. A cauliflower canopy of big round puffs in bright lime green
(the lower ones a shade darker) on a short, thick brown trunk that flares into three chunky roots."""

import math

from seatkit import bake, ball, cone, finish

NAME = "Tree"
ZONES = (1, 3)
WEIGHT = 3
COLORS = {
    "leaf": (0.3, 0.72, 0.06),
    "leafdark": (0.16, 0.5, 0.05),
    "trunk": (0.3, 0.14, 0.05),
}

HEIGHT = 16
CANOPY_Z = 10.5  # the canopy's middle
CANOPY_R = 4.4  # its puffs' size


def build():
    parts = []
    # The canopy: distinct round puffs, a big one on top, a ring round it and smaller ones underneath (the
    # lower ones a shade darker, so the canopy reads round)
    top = [(CANOPY_R * 1.0, (0, 0, CANOPY_Z + 1.4))]
    ring = []
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.3
        ring.append((CANOPY_R * 0.72, (math.cos(a) * 3.7, math.sin(a) * 3.7, CANOPY_Z - 0.2 + (0.7 if i % 2 else 0))))
    under = []
    for i in range(4):
        a = 2 * math.pi * i / 4 + 0.8
        under.append((CANOPY_R * 0.55, (math.cos(a) * 2.4, math.sin(a) * 2.4, CANOPY_Z - 2.5)))
    for r, at in top + ring:
        parts.append(finish(ball("Puff", r, at, (1, 1, 0.92)), "leaf"))
    for r, at in under:
        parts.append(finish(ball("Puff", r, at, (1, 1, 0.9)), "leafdark"))

    # The trunk: thick and tapered, flaring wide at the ground into three chunky roots
    height = CANOPY_Z - 1.5
    trunk = cone("Trunk", 1.6, 1.1, height, (0, 0, height / 2), vertices=20)
    parts.append(finish(trunk, "trunk"))
    flare = cone("Flare", 2.5, 1.6, 1.6, (0, 0, 0.8), vertices=20)
    parts.append(finish(flare, "trunk"))
    for i in range(3):
        a = 2 * math.pi * i / 3 + 0.5
        root = ball("Root", 1.0, (math.cos(a) * 2.0, math.sin(a) * 2.0, 0.45), (1.6, 0.95, 0.75))
        root.rotation_euler = (0, 0, a)
        parts.append(finish(bake(root), "trunk"))
    return parts
