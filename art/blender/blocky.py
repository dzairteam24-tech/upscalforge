"""Blocky animals, in Steal an Egg's style: real animals (a dog, a cat, a bunny, a bear...) built from chunky
bevelled blocks, with Lego studs on the upward faces. A species spec with "style": "blocky" names one of the
animals below ("animal") and its colors; cubelings.build() hands it here, and everything else (renders, the
.glb, the Roblox export with its part roles and moving pieces) works the same as for the cube creatures.

Space: front is -Y, up is +Z, the feet stand on z = 0. Roles are the color keys ("body", "belly", "eye"...);
the anim tags are the game's moving pieces ("leg" -> legFL/legFR/legBL/legBR by position, "tail").
"""

import math

import bpy

STUD_R = 0.1
STUD_H = 0.06
STUD_STEP = 0.36
EDGE = 0.045  # bevel on every block


class Animal:
    def __init__(self, cubelings, spec, mat):
        self.c = cubelings
        self.spec = spec
        self.mat = mat
        self.parts = []

    def block(self, role, size, center, anim="", studs=False, rotation=(0, 0, 0)):
        obj = self.c.rounded_box("Block", size, center, min(EDGE, min(size) * 0.25), segments=2, rotation=rotation)
        obj["anim"] = anim
        self.parts.append(self.c.finish(obj, self.mat[role], angle=30))
        if studs:
            self.studs(role, size, center, anim)
        return obj

    def studs(self, role, size, center, anim=""):
        """Lego studs on the top face of an unrotated block."""
        sx, sy, sz = size
        nx = max(1, int((sx - 0.1) / STUD_STEP))
        ny = max(1, int((sy - 0.1) / STUD_STEP))
        x0 = center[0] - (nx - 1) * STUD_STEP / 2
        y0 = center[1] - (ny - 1) * STUD_STEP / 2
        top = center[2] + sz / 2
        for i in range(nx):
            for j in range(ny):
                bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=STUD_R, depth=STUD_H, location=(x0 + i * STUD_STEP, y0 + j * STUD_STEP, top + STUD_H / 2))
                stud = bpy.context.active_object
                stud["anim"] = anim
                self.parts.append(self.c.finish(stud, self.mat[role], smooth=False))

    def pair(self, role, size, center, anim="", studs=False, rotation=(0, 0, 0)):
        """The same block on both sides (x and -x), the rotation mirrored."""
        for s in (-1, 1):
            rx, ry, rz = rotation
            self.block(role, size, (center[0] * s, center[1], center[2]), anim, studs, (rx, ry * s, rz * s))

    def eyes(self, x, y, z, size=0.26):
        """Square black eyes with a white glint, on a face at y (front)."""
        for s in (-1, 1):
            self.block("eye", (size, 0.06, size * 1.15), (x * s, y - 0.02, z))
            self.block("shine", (size * 0.38, 0.03, size * 0.38), (x * s - size * 0.18, y - 0.06, z + size * 0.22))

    def legs(self, width, x, y_front, y_back, height, role="legs"):
        for y in (y_front, y_back):
            self.pair(role, (width, width, height), (x, y, height / 2), anim="leg")


# ---------------------------------------------------------------------------------------------------------------
# The animals. Each draws itself from blocks; sizes are about the cube creatures' (2 studs wide).


def dog(a):
    # A sandy pup: long body, big square head with a muzzle and a black nose, floppy ears, tail up
    a.legs(0.42, 0.42, -0.62, 0.62, 0.62)
    a.block("body", (1.25, 1.9, 1.0), (0, 0.05, 1.12), studs=True)
    a.block("belly", (1.05, 1.5, 0.12), (0, 0.05, 0.6))
    a.block("body", (1.3, 1.2, 1.15), (0, -1.05, 1.85), studs=True)  # head
    a.block("belly", (0.78, 0.5, 0.5), (0, -1.78, 1.58))  # muzzle
    a.block("nose", (0.3, 0.14, 0.2), (0, -2.06, 1.74))
    a.block("mouth", (0.34, 0.04, 0.06), (0, -2.04, 1.42))
    a.eyes(0.33, -1.66, 2.05)
    a.pair("ear", (0.24, 0.5, 0.8), (0.74, -0.95, 1.95), rotation=(0, 0, 0))
    a.block("body", (0.26, 0.26, 0.7), (0, 1.12, 1.55), anim="tail", rotation=(math.radians(-30), 0, 0))
    a.block("ear", (0.2, 0.2, 0.22), (0, 1.32, 1.92), anim="tail")


def cat(a):
    # A ginger cat: slim body with darker stripes, pointed ears, white muzzle, long raised tail
    a.legs(0.34, 0.38, -0.6, 0.6, 0.6)
    a.block("body", (1.05, 1.8, 0.9), (0, 0.05, 1.03), studs=True)
    for y in (-0.35, 0.15, 0.6):
        a.block("stripe", (1.08, 0.18, 0.5), (0, y, 1.3))
    a.block("body", (1.25, 1.05, 1.0), (0, -0.98, 1.75), studs=True)  # head
    a.block("belly", (0.6, 0.3, 0.38), (0, -1.6, 1.5))  # muzzle
    a.block("nose", (0.2, 0.08, 0.14), (0, -1.76, 1.64))
    a.eyes(0.3, -1.52, 1.95, size=0.24)
    for s in (-1, 1):
        a.block("body", (0.34, 0.24, 0.42), (0.38 * s, -0.95, 2.42), rotation=(0, math.radians(14 * s), 0))
        a.block("ear_inner", (0.18, 0.06, 0.26), (0.38 * s, -1.08, 2.4), rotation=(0, math.radians(14 * s), 0))
    a.block("body", (0.22, 0.22, 0.9), (0, 1.05, 1.6), anim="tail", rotation=(math.radians(-25), 0, 0))
    a.block("stripe", (0.24, 0.24, 0.3), (0, 1.25, 2.12), anim="tail", rotation=(math.radians(-25), 0, 0))


def bunny(a):
    # A white bunny: round chunky body, tall ears with pink inside, pink nose, a cotton tail
    a.legs(0.38, 0.4, -0.45, 0.55, 0.42)
    a.block("body", (1.25, 1.45, 1.05), (0, 0.15, 0.95), studs=True)
    a.block("belly", (0.9, 0.12, 0.7), (0, -0.62, 0.9))
    a.block("body", (1.15, 1.0, 1.0), (0, -0.7, 1.75), studs=True)  # head
    a.block("belly", (0.55, 0.22, 0.32), (0, -1.25, 1.55))  # muzzle
    a.block("nose", (0.2, 0.08, 0.14), (0, -1.38, 1.68))
    a.eyes(0.3, -1.22, 1.92, size=0.24)
    for s in (-1, 1):
        a.block("body", (0.3, 0.2, 1.05), (0.28 * s, -0.6, 2.75), rotation=(math.radians(-8), math.radians(8 * s), 0))
        a.block("ear_inner", (0.16, 0.05, 0.8), (0.28 * s, -0.71, 2.72), rotation=(math.radians(-8), math.radians(8 * s), 0))
    a.block("tail", (0.42, 0.3, 0.42), (0, 0.95, 1.1), anim="tail")


def bear(a):
    # A big brown bear: heavy body, thick legs, round ears, a light muzzle and a black nose
    a.legs(0.55, 0.52, -0.65, 0.7, 0.66)
    a.block("body", (1.6, 2.0, 1.25), (0, 0.05, 1.27), studs=True)
    a.block("belly", (1.25, 0.12, 0.9), (0, -0.98, 1.15))
    a.block("body", (1.45, 1.2, 1.25), (0, -1.0, 2.15), studs=True)  # head
    a.block("belly", (0.75, 0.42, 0.5), (0, -1.75, 1.9))  # muzzle
    a.block("nose", (0.32, 0.12, 0.2), (0, -1.98, 2.06))
    a.block("mouth", (0.3, 0.04, 0.06), (0, -1.97, 1.74))
    a.eyes(0.36, -1.62, 2.38)
    for s in (-1, 1):
        a.block("body", (0.4, 0.26, 0.38), (0.55 * s, -0.95, 2.93), studs=True)
        a.block("ear_inner", (0.22, 0.06, 0.2), (0.55 * s, -1.09, 2.9))
    a.block("body", (0.3, 0.26, 0.3), (0, 1.12, 1.45), anim="tail")


def chicken(a):
    # A white hen: a chunky body, a red comb and wattle, a yellow beak, little yellow legs, tail feathers up
    a.legs(0.16, 0.26, -0.05, 0.25, 0.5)
    a.block("body", (1.1, 1.3, 0.95), (0, 0.15, 0.95), studs=True)
    a.pair("wing", (0.14, 0.8, 0.55), (0.6, 0.2, 0.98))
    a.block("body", (0.8, 0.75, 0.85), (0, -0.55, 1.75), studs=True)  # head
    a.block("beak", (0.3, 0.3, 0.2), (0, -1.05, 1.72))
    a.block("comb", (0.16, 0.5, 0.32), (0, -0.55, 2.32))
    a.block("comb", (0.16, 0.12, 0.24), (0, -0.98, 1.5))  # wattle
    a.eyes(0.22, -0.94, 1.92, size=0.18)
    a.block("body", (0.7, 0.3, 0.55), (0, 0.9, 1.45), anim="tail", rotation=(math.radians(-20), 0, 0))


def pig(a):
    # A pink pig: round body, a big snout with nostrils, floppy ears, a curly tail
    a.legs(0.38, 0.4, -0.55, 0.6, 0.45)
    a.block("body", (1.35, 1.8, 1.1), (0, 0.05, 1.0), studs=True)
    a.block("body", (1.2, 0.95, 1.0), (0, -1.0, 1.55), studs=True)  # head
    a.block("snout", (0.6, 0.25, 0.42), (0, -1.58, 1.4))
    for s in (-1, 1):
        a.block("nose", (0.1, 0.04, 0.14), (0.12 * s, -1.72, 1.42))
        a.block("ear", (0.32, 0.12, 0.34), (0.42 * s, -1.3, 2.05), rotation=(math.radians(25), 0, 0))
    a.eyes(0.3, -1.48, 1.78, size=0.2)
    a.block("snout", (0.16, 0.16, 0.3), (0, 1.0, 1.35), anim="tail", rotation=(0, math.radians(35), 0))


def sheep(a):
    # A fluffy sheep: a wool body (studded all over the top), a dark face and legs, little side ears
    a.legs(0.3, 0.38, -0.5, 0.55, 0.55)
    a.block("body", (1.45, 1.8, 1.15), (0, 0.05, 1.12), studs=True)
    a.block("body", (1.25, 0.35, 1.0), (0, -0.85, 1.25))  # wool front
    a.block("face", (0.8, 0.8, 0.85), (0, -1.15, 1.7))
    a.block("body", (0.95, 0.6, 0.35), (0, -1.05, 2.25), studs=True)  # wool on the head
    for s in (-1, 1):
        a.block("face", (0.36, 0.18, 0.18), (0.55 * s, -1.15, 1.85), rotation=(0, 0, math.radians(-20 * s)))
    a.eyes(0.2, -1.56, 1.82, size=0.18)
    a.block("nose", (0.22, 0.04, 0.1), (0, -1.57, 1.5))
    a.block("body", (0.35, 0.3, 0.35), (0, 1.0, 1.4), anim="tail")


def horse(a):
    # A chestnut horse: long legs and body, a tall neck and long head, a dark mane and tail, a blaze on the nose
    a.legs(0.34, 0.42, -0.75, 0.75, 1.0)
    a.block("body", (1.15, 2.3, 0.95), (0, 0.05, 1.45), studs=True)
    a.block("body", (0.75, 0.6, 1.0), (0, -1.0, 2.2))  # neck
    a.block("body", (0.8, 1.2, 0.7), (0, -1.5, 2.85), studs=True)  # head
    a.block("blaze", (0.3, 0.04, 0.5), (0, -2.12, 2.8))
    a.block("nose", (0.62, 0.3, 0.3), (0, -2.0, 2.62))
    a.block("mane", (0.2, 0.9, 1.1), (0, -0.85, 2.55))
    for s in (-1, 1):
        a.block("body", (0.18, 0.16, 0.36), (0.28 * s, -1.2, 3.35))
    a.eyes(0.42, -1.9, 3.0, size=0.18)
    a.block("mane", (0.24, 0.24, 0.95), (0, 1.25, 1.35), anim="tail", rotation=(math.radians(-20), 0, 0))
    for y in (-0.75, 0.75):
        a.pair("hoof", (0.36, 0.36, 0.14), (0.42, y, 0.07))


def bee(a):
    # A plump bee: a striped yellow body, gauzy wings, a stinger, little antennae over a smiling face
    a.legs(0.14, 0.25, -0.3, 0.35, 0.4)
    a.block("body", (1.0, 1.25, 0.95), (0, 0.1, 0.95), studs=True)
    for y in (-0.12, 0.38):
        a.block("stripe", (1.04, 0.2, 0.9), (0, y, 0.95))
    a.block("body", (0.7, 0.6, 0.7), (0, -0.85, 1.0), studs=True)  # head
    a.eyes(0.18, -1.16, 1.1, size=0.18)
    a.pair("legs", (0.08, 0.08, 0.4), (0.18, -0.85, 1.55), rotation=(math.radians(-15), 0, 0))
    a.pair("stripe", (0.14, 0.14, 0.14), (0.18, -0.97, 1.78))
    a.pair("wing", (0.55, 0.8, 0.08), (0.45, 0.25, 1.55), rotation=(0, math.radians(-20), 0))
    a.block("stripe", (0.22, 0.3, 0.22), (0, 0.85, 0.95), rotation=(math.radians(50), 0, 0))  # stinger


def ladybug(a):
    # A round red ladybug: a domed shell split down the middle, black spots, a dark little face, antennae
    a.legs(0.12, 0.3, -0.3, 0.3, 0.3)
    a.block("body", (1.15, 1.3, 0.6), (0, 0.05, 0.6), studs=True)
    a.block("body", (0.95, 1.1, 0.35), (0, 0.05, 1.05))  # the dome
    a.block("wing", (0.08, 1.2, 0.1), (0, 0.05, 1.26))  # the split between the wing cases
    for x, y in ((-0.3, -0.25), (0.3, -0.25), (-0.28, 0.35), (0.28, 0.35)):
        a.block("spot", (0.2, 0.2, 0.06), (x, y, 1.24))
    a.block("spot", (0.5, 0.3, 0.4), (0, -0.72, 0.5))  # face
    a.eyes(0.3, -0.62, 0.85, size=0.16)
    a.pair("legs", (0.07, 0.07, 0.3), (0.15, -0.6, 1.0), rotation=(math.radians(-20), 0, 0))


def butterfly(a):
    # A butterfly: a slim violet body and a small head, two great patterned wings either side
    a.legs(0.1, 0.15, -0.25, 0.3, 0.5)
    a.block("body", (0.42, 1.1, 0.42), (0, 0.05, 1.0), studs=True)
    a.block("body", (0.55, 0.5, 0.55), (0, -0.72, 1.55), studs=True)  # head
    a.eyes(0.15, -0.99, 1.62, size=0.16)
    a.pair("legs", (0.06, 0.06, 0.45), (0.16, -0.7, 1.98), rotation=(math.radians(-20), 0, 0))
    a.pair("spot", (0.13, 0.13, 0.13), (0.16, -0.8, 2.22))
    a.pair("wing", (0.95, 0.75, 0.07), (0.62, 0.0, 1.3), rotation=(0, math.radians(-18), math.radians(10)))
    a.pair("wing", (0.7, 0.55, 0.07), (0.5, 0.42, 0.82), rotation=(0, math.radians(-18), math.radians(-8)))
    a.pair("spot", (0.2, 0.2, 0.09), (0.72, -0.05, 1.34))


def snail(a):
    # A slow snail: a low green body, its head up front, and a great spiral shell riding on its back
    a.block("body", (0.85, 1.6, 0.4), (0, 0.15, 0.42))
    a.block("body", (0.6, 0.55, 0.75), (0, -0.78, 0.75), studs=True)  # head
    a.pair("body", (0.09, 0.09, 0.55), (0.16, -0.85, 1.35))  # eye stalks
    a.pair("eye", (0.16, 0.16, 0.16), (0.16, -0.85, 1.68))
    a.block("shell", (1.05, 1.05, 1.0), (0, 0.42, 1.05), studs=True)
    a.block("spot", (0.55, 0.1, 0.55), (0, 0.98, 1.06))  # the spiral, drawn on its back face
    a.block("spot", (0.28, 0.1, 0.28), (0, 0.98, 1.06))


def frog(a):
    # A bright frog: a squat studded body, big eyes on bumps, wide back haunches and a dark smile
    a.pair("legs", (0.3, 0.55, 0.3), (0.55, 0.35, 0.15))
    a.pair("legs", (0.18, 0.18, 0.35), (0.35, -0.5, 0.18))
    a.block("body", (1.25, 1.15, 0.75), (0, 0, 0.72), studs=True)
    a.block("belly", (0.95, 0.1, 0.5), (0, -0.56, 0.6))
    a.pair("body", (0.34, 0.34, 0.3), (0.33, -0.35, 1.22))  # eye bumps
    a.eyes(0.33, -0.53, 1.28, size=0.2)
    a.block("spot", (0.5, 0.04, 0.06), (0, -0.59, 0.82))  # mouth
    a.block("spot", (0.2, 0.2, 0.06), (-0.35, 0.15, 1.11))
    a.block("spot", (0.16, 0.16, 0.06), (0.3, -0.2, 1.11))


def duckling(a):
    # A fluffy duckling: a round yellow body, little wings, an orange beak and a tail that wags
    a.legs(0.14, 0.26, -0.1, 0.25, 0.4)
    a.block("body", (1.05, 1.25, 0.85), (0, 0.12, 0.82), studs=True)
    a.block("belly", (0.8, 0.1, 0.55), (0, -0.53, 0.75))
    a.pair("wing", (0.12, 0.7, 0.45), (0.56, 0.15, 0.85))
    a.block("body", (0.72, 0.65, 0.68), (0, -0.62, 1.5), studs=True)  # head
    a.block("beak", (0.42, 0.3, 0.18), (0, -1.05, 1.42))
    a.eyes(0.19, -0.96, 1.58, size=0.16)
    a.block("wing", (0.5, 0.25, 0.3), (0, 0.82, 1.0), anim="tail", rotation=(math.radians(-20), 0, 0))


def fox(a):
    # A sly fox: a ginger body with a white chest, a sharp muzzle, dark-tipped ears and a great bushy tail
    a.legs(0.32, 0.36, -0.55, 0.6, 0.6)
    a.block("body", (1.05, 1.8, 0.9), (0, 0.05, 1.02), studs=True)
    a.block("belly", (0.65, 0.14, 0.62), (0, -0.86, 0.95))  # chest
    a.block("body", (1.15, 0.95, 0.95), (0, -0.95, 1.72), studs=True)  # head
    a.block("belly", (0.55, 0.45, 0.35), (0, -1.5, 1.5))  # muzzle
    a.block("nose", (0.22, 0.12, 0.16), (0, -1.74, 1.6))
    a.eyes(0.29, -1.44, 1.88, size=0.22)
    for s in (-1, 1):
        a.block("body", (0.32, 0.22, 0.45), (0.38 * s, -0.9, 2.35), rotation=(0, math.radians(14 * s), 0))
        a.block("ear", (0.2, 0.14, 0.2), (0.38 * s, -0.9, 2.62), rotation=(0, math.radians(14 * s), 0))
    a.block("body", (0.4, 0.4, 1.0), (0, 1.05, 1.5), anim="tail", rotation=(math.radians(-25), 0, 0))
    a.block("tail", (0.42, 0.42, 0.35), (0, 1.28, 2.05), anim="tail", rotation=(math.radians(-25), 0, 0))  # white tip


def deer(a):
    # A gentle deer: a slim body on long legs, a tall neck, a pale muzzle and the first small antlers
    a.legs(0.3, 0.34, -0.6, 0.65, 0.85)
    a.block("body", (1.1, 1.9, 0.95), (0, 0.05, 1.3), studs=True)
    a.block("belly", (0.75, 0.12, 0.6), (0, -0.92, 1.2))
    a.block("body", (0.6, 0.5, 0.8), (0, -0.95, 1.95))  # neck
    a.block("body", (0.72, 0.95, 0.62), (0, -1.3, 2.5), studs=True)  # head
    a.block("belly", (0.5, 0.35, 0.3), (0, -1.82, 2.38))  # muzzle
    a.block("nose", (0.24, 0.14, 0.14), (0, -2.0, 2.44))
    a.eyes(0.37, -1.79, 2.56, size=0.16)
    a.pair("ear", (0.3, 0.14, 0.24), (0.48, -1.2, 2.62))
    for s in (-1, 1):
        a.block("antler", (0.12, 0.12, 0.55), (0.3 * s, -1.25, 3.05), rotation=(0, math.radians(20 * s), 0))
        a.block("antler", (0.1, 0.35, 0.1), (0.42 * s, -1.18, 3.28), rotation=(0, 0, math.radians(-30 * s)))
    a.block("tail", (0.28, 0.25, 0.3), (0, 1.05, 1.35), anim="tail")


def squirrel(a):
    # A quick squirrel: a small russet body, a pale belly, and a tail bigger than itself curled over its back
    a.legs(0.3, 0.32, -0.45, 0.5, 0.5)
    a.block("body", (0.95, 1.35, 0.85), (0, 0.08, 0.92), studs=True)
    a.block("belly", (0.65, 0.1, 0.55), (0, -0.6, 0.88))
    a.block("body", (0.85, 0.75, 0.8), (0, -0.72, 1.62), studs=True)  # head
    a.block("belly", (0.4, 0.25, 0.25), (0, -1.18, 1.45))  # muzzle
    a.block("nose", (0.16, 0.1, 0.12), (0, -1.34, 1.52))
    a.eyes(0.24, -1.13, 1.78, size=0.2)
    a.pair("ear", (0.2, 0.16, 0.3), (0.28, -0.68, 2.12))
    a.block("tail", (0.45, 0.45, 1.1), (0, 0.85, 1.35), anim="tail", rotation=(math.radians(-30), 0, 0))
    a.block("tail", (0.5, 0.5, 0.6), (0, 1.05, 2.05), anim="tail", rotation=(math.radians(-55), 0, 0))


def hedgehog(a):
    # A hedgehog: a low body under a studded shell of spikes, a pale pointed face peeking out in front
    a.legs(0.24, 0.3, -0.4, 0.45, 0.35)
    a.block("body", (1.2, 1.5, 0.8), (0, 0.15, 0.75))
    a.block("spike", (1.3, 1.45, 0.45), (0, 0.22, 1.12), studs=True)  # the spikes
    a.block("spike", (1.0, 0.9, 0.4), (0, 0.5, 0.95))
    a.block("face", (0.62, 0.5, 0.55), (0, -0.85, 0.78))
    a.block("nose", (0.18, 0.1, 0.14), (0, -1.15, 0.82))
    a.eyes(0.17, -1.11, 0.92, size=0.14)
    a.pair("face", (0.16, 0.1, 0.16), (0.3, -0.8, 1.1))


def owl(a):
    # A wise owl: an upright body with a pale belly and face disc, huge eyes, ear tufts and folded wings
    a.pair("legs", (0.22, 0.3, 0.18), (0.25, -0.35, 0.09))
    a.block("body", (1.15, 1.05, 1.45), (0, 0, 1.0), studs=True)
    a.block("belly", (0.8, 0.1, 0.95), (0, -0.52, 0.95))
    a.block("face", (0.85, 0.08, 0.8), (0, -0.56, 1.35))  # face disc
    a.eyes(0.22, -0.62, 1.38, size=0.24)
    a.block("beak", (0.2, 0.16, 0.14), (0, -0.62, 1.12))
    a.pair("body", (0.2, 0.18, 0.35), (0.42, -0.1, 1.85), rotation=(0, math.radians(-15), 0))  # ear tufts
    a.pair("wing", (0.14, 0.7, 0.9), (0.62, 0.05, 1.0), anim="wing")
    a.block("wing", (0.5, 0.25, 0.35), (0, 0.6, 0.45), anim="tail", rotation=(math.radians(25), 0, 0))


def raccoon(a):
    # A masked raccoon: a grey body, a dark mask across its eyes, and a thick tail ringed with black
    a.legs(0.34, 0.36, -0.5, 0.55, 0.55)
    a.block("body", (1.1, 1.6, 0.95), (0, 0.05, 1.02), studs=True)
    a.block("belly", (0.75, 0.12, 0.6), (0, -0.76, 0.95))
    a.block("body", (1.1, 0.9, 0.9), (0, -0.9, 1.7), studs=True)  # head
    a.block("mask", (0.85, 0.06, 0.3), (0, -1.36, 1.78))
    a.block("belly", (0.5, 0.3, 0.3), (0, -1.42, 1.48))  # muzzle
    a.block("nose", (0.2, 0.1, 0.14), (0, -1.6, 1.56))
    a.eyes(0.26, -1.4, 1.8, size=0.15)
    a.pair("ear", (0.3, 0.2, 0.3), (0.4, -0.85, 2.2))
    a.block("body", (0.35, 0.35, 0.95), (0, 1.0, 1.45), anim="tail", rotation=(math.radians(-25), 0, 0))
    a.block("stripe", (0.37, 0.37, 0.25), (0, 1.13, 1.8), anim="tail", rotation=(math.radians(-25), 0, 0))  # a ring
    a.block("stripe", (0.3, 0.3, 0.25), (0, 1.24, 2.1), anim="tail", rotation=(math.radians(-25), 0, 0))  # and its tip


def wolf(a):
    # A grey wolf: a heavy body with a pale ruff, a long muzzle, upright ears and a thick straight tail
    a.legs(0.36, 0.4, -0.6, 0.65, 0.65)
    a.block("body", (1.2, 1.95, 1.0), (0, 0.05, 1.1), studs=True)
    a.block("belly", (1.3, 0.35, 0.9), (0, -0.72, 1.75))  # ruff
    a.block("belly", (0.8, 0.12, 0.65), (0, -0.94, 1.02))  # chest
    a.block("body", (1.25, 1.0, 1.0), (0, -1.0, 1.85), studs=True)  # head
    a.block("belly", (0.6, 0.5, 0.4), (0, -1.62, 1.62))  # muzzle
    a.block("nose", (0.26, 0.14, 0.18), (0, -1.88, 1.72))
    a.eyes(0.32, -1.52, 2.0, size=0.22)
    a.pair("ear", (0.3, 0.2, 0.4), (0.42, -0.95, 2.45))
    a.block("tail", (0.35, 0.35, 0.9), (0, 1.1, 1.5), anim="tail", rotation=(math.radians(-20), 0, 0))


def moose(a):
    # A great moose: a humped body on long legs, a drooping snout with a dewlap, and broad flat antlers
    a.legs(0.36, 0.4, -0.65, 0.7, 0.95)
    a.block("body", (1.3, 2.1, 1.1), (0, 0.05, 1.5), studs=True)
    a.block("body", (1.1, 0.8, 0.4), (0, -0.55, 2.15))  # hump
    a.block("body", (0.7, 0.55, 0.8), (0, -1.05, 2.0))  # neck
    a.block("body", (0.8, 0.9, 0.75), (0, -1.42, 2.55), studs=True)  # head
    a.block("snout", (0.66, 0.6, 0.5), (0, -1.95, 2.3))
    a.block("nose", (0.3, 0.16, 0.16), (0, -2.28, 2.4))
    a.block("snout", (0.25, 0.2, 0.5), (0, -1.6, 1.95))  # dewlap
    a.eyes(0.41, -1.88, 2.62, size=0.16)
    a.pair("antler", (0.75, 0.14, 0.55), (0.62, -1.35, 2.95), rotation=(0, math.radians(-20), math.radians(10)))
    a.pair("body", (0.28, 0.16, 0.24), (0.52, -1.35, 2.6))  # ears
    a.block("body", (0.25, 0.22, 0.25), (0, 1.15, 1.6), anim="tail")


def lynx(a):
    # A spotted lynx: a sandy body with dark spots, white cheek ruffs, and black tufts on its ear tips
    a.legs(0.34, 0.38, -0.55, 0.6, 0.62)
    a.block("body", (1.1, 1.8, 0.92), (0, 0.05, 1.05), studs=True)
    a.pair("spot", (0.06, 0.25, 0.25), (0.57, 0.1, 1.2))
    a.block("spot", (0.25, 0.25, 0.06), (-0.25, -0.3, 1.52))
    a.block("spot", (0.22, 0.22, 0.06), (0.3, 0.35, 1.52))
    a.block("belly", (0.7, 0.12, 0.6), (0, -0.86, 0.98))  # chest
    a.block("body", (1.15, 0.95, 0.95), (0, -0.95, 1.78), studs=True)  # head
    a.pair("belly", (0.18, 0.4, 0.5), (0.6, -1.1, 1.6))  # cheek ruffs
    a.block("belly", (0.55, 0.42, 0.35), (0, -1.5, 1.56))  # muzzle
    a.block("nose", (0.2, 0.1, 0.14), (0, -1.72, 1.66))
    a.eyes(0.29, -1.44, 1.94, size=0.22)
    a.pair("body", (0.3, 0.2, 0.42), (0.4, -0.9, 2.32))
    a.pair("ear", (0.12, 0.12, 0.28), (0.4, -0.9, 2.6))  # black ear tufts
    a.block("body", (0.3, 0.3, 0.45), (0, 1.02, 1.3), anim="tail", rotation=(math.radians(-25), 0, 0))
    a.block("ear", (0.3, 0.3, 0.18), (0, 1.12, 1.52), anim="tail", rotation=(math.radians(-25), 0, 0))  # black tail tip


def stag(a):
    # A proud stag: a big body and tall neck, and a crown of branching antlers over a calm face
    a.legs(0.34, 0.38, -0.65, 0.7, 1.0)
    a.block("body", (1.25, 2.1, 1.05), (0, 0.05, 1.45), studs=True)
    a.block("belly", (0.8, 0.12, 0.65), (0, -1.0, 1.35))
    a.block("body", (0.68, 0.55, 0.95), (0, -1.05, 2.15))  # neck
    a.block("body", (0.8, 1.05, 0.7), (0, -1.45, 2.75), studs=True)  # head
    a.block("belly", (0.55, 0.4, 0.32), (0, -2.0, 2.6))  # muzzle
    a.block("nose", (0.26, 0.14, 0.16), (0, -2.2, 2.66))
    a.eyes(0.41, -1.97, 2.82, size=0.17)
    a.pair("ear", (0.32, 0.15, 0.26), (0.55, -1.35, 2.85))
    for s in (-1, 1):
        a.block("antler", (0.13, 0.13, 0.85), (0.34 * s, -1.4, 3.35), rotation=(0, math.radians(25 * s), 0))
        a.block("antler", (0.1, 0.45, 0.1), (0.5 * s, -1.32, 3.5), rotation=(0, 0, math.radians(-35 * s)))
        a.block("antler", (0.1, 0.4, 0.1), (0.62 * s, -1.25, 3.62), rotation=(0, 0, math.radians(-50 * s)))
    a.block("tail", (0.3, 0.26, 0.32), (0, 1.15, 1.5), anim="tail")


def crab(a):
    # A red crab: a wide flat shell, two great claws up front, eyes on stalks and three legs a side
    for s in (-1, 1):
        for y in (-0.35, 0.05, 0.45):
            a.block("legs", (0.55, 0.16, 0.16), (0.85 * s, y, 0.3), anim="leg", rotation=(0, 0, math.radians(15 * s)))
    a.block("body", (1.7, 1.15, 0.55), (0, 0, 0.62), studs=True)
    a.block("belly", (1.3, 0.1, 0.35), (0, -0.55, 0.5))
    a.pair("claw", (0.55, 0.6, 0.5), (0.72, -0.72, 0.62))
    a.pair("claw", (0.3, 0.3, 0.3), (0.85, -1.0, 0.75))
    a.pair("legs", (0.09, 0.09, 0.4), (0.2, -0.4, 1.05))  # eye stalks
    a.pair("eye", (0.17, 0.17, 0.17), (0.2, -0.4, 1.3))
    a.pair("shine", (0.06, 0.06, 0.06), (0.16, -0.48, 1.36))
    a.block("legs", (0.3, 0.04, 0.06), (0, -0.59, 0.5))  # mouth


def starfish(a):
    # A cheerful starfish: five flat arms round a studded middle, dotted with pale spots, lying on the sand
    a.block("body", (0.85, 0.85, 0.35), (0, 0, 0.25), studs=True)
    for x, y, rz in ((0, -0.6, 0), (-0.57, -0.19, 55), (0.57, -0.19, -55), (-0.35, 0.51, 125), (0.35, 0.51, -125)):
        a.block("body", (0.42, 0.85, 0.3), (x, y, 0.22), rotation=(0, 0, math.radians(rz)))
    a.eyes(0.16, -0.44, 0.3, size=0.13)
    a.block("spot", (0.18, 0.18, 0.08), (0, 0, 0.46))
    a.pair("spot", (0.14, 0.14, 0.08), (0.35, -0.1, 0.42))


def turtle(a):
    # A sea turtle: a stacked shell with a patterned top, flippers for legs and a small head poking out
    a.pair("legs", (0.5, 0.7, 0.16), (0.72, -0.4, 0.12), rotation=(0, math.radians(10), 0))
    a.pair("legs", (0.4, 0.5, 0.16), (0.62, 0.55, 0.12))
    a.block("body", (1.05, 1.4, 0.5), (0, 0.05, 0.42))
    a.block("shell", (1.35, 1.65, 0.55), (0, 0.08, 0.78), studs=True)
    a.block("shell", (1.05, 1.3, 0.4), (0, 0.08, 1.18))
    a.block("spot", (0.5, 0.6, 0.12), (0, 0.08, 1.42))
    a.pair("spot", (0.3, 0.36, 0.1), (0.38, 0.08, 1.36))
    a.block("body", (0.55, 0.5, 0.45), (0, -0.95, 0.55), studs=True)  # head
    a.eyes(0.16, -1.21, 0.62, size=0.13)
    a.block("body", (0.2, 0.25, 0.15), (0, 0.85, 0.45), anim="tail")


def seagull(a):
    # A seagull: a white body with grey folded wings, a long orange beak and thin orange legs
    a.legs(0.12, 0.22, -0.05, 0.2, 0.45)
    a.block("body", (1.0, 1.35, 0.8), (0, 0.1, 0.85), studs=True)
    a.block("belly", (0.75, 0.1, 0.5), (0, -0.6, 0.8))
    a.pair("wing", (0.13, 0.85, 0.5), (0.55, 0.15, 0.9), anim="wing")
    a.block("body", (0.68, 0.6, 0.62), (0, -0.68, 1.55), studs=True)  # head
    a.block("beak", (0.2, 0.55, 0.14), (0, -1.12, 1.5))
    a.eyes(0.18, -0.99, 1.62, size=0.15)
    a.block("tail", (0.55, 0.45, 0.12), (0, 0.85, 0.95), anim="tail", rotation=(math.radians(20), 0, 0))


def octopus(a):
    # A pink octopus: a great domed head with a smiling face, and six short tentacles curled underneath
    a.block("body", (1.25, 1.25, 1.1), (0, 0, 0.95), studs=True)
    a.block("body", (0.95, 0.95, 0.45), (0, 0, 1.65))
    a.block("belly", (0.85, 0.1, 0.6), (0, -0.62, 0.85))
    a.eyes(0.28, -0.65, 1.05, size=0.2)
    a.block("spot", (0.18, 0.05, 0.1), (0, -0.64, 0.68))  # mouth
    a.pair("spot", (0.2, 0.2, 0.08), (0.35, -0.55, 1.35))
    a.block("spot", (0.22, 0.22, 0.08), (-0.2, 0.2, 1.9))
    for x, y in ((-0.45, -0.4), (0, -0.55), (0.45, -0.4), (-0.55, 0.25), (0.55, 0.25), (0, 0.6)):
        a.block("legs", (0.3, 0.42, 0.35), (x, y, 0.18), anim="leg")
        if y < 0:
            a.block("legs", (0.26, 0.3, 0.2), (x, y - 0.2, 0.1), anim="leg")  # curled tips in front


def dolphin(a):
    # A dolphin leaping over its own wave: a long blue body, a beak, a dorsal fin and a wide tail fluke
    a.block("fin", (1.3, 2.4, 0.22), (0, 0.15, 0.11))  # its wave
    a.block("body", (0.95, 2.2, 0.85), (0, 0.15, 0.72), studs=True)
    a.block("belly", (0.65, 1.6, 0.14), (0, 0.1, 0.3))
    a.block("body", (0.7, 0.5, 0.5), (0, -1.05, 0.92))  # forehead
    a.block("body", (0.45, 0.6, 0.4), (0, -1.35, 0.68))  # beak
    a.pair("eye", (0.13, 0.06, 0.15), (0.49, -1.05, 0.78))
    a.pair("shine", (0.05, 0.03, 0.05), (0.5, -1.08, 0.83))
    a.block("fin", (0.12, 0.5, 0.55), (0, 0.1, 1.35), rotation=(math.radians(-15), 0, 0))  # dorsal fin
    a.pair("fin", (0.55, 0.35, 0.1), (0.6, -0.5, 0.4), anim="wing", rotation=(0, math.radians(25), math.radians(-20)))
    a.block("body", (0.4, 0.5, 0.35), (0, 1.25, 0.78))
    a.block("fin", (0.95, 0.4, 0.1), (0, 1.45, 0.82), anim="tail")  # fluke


def shark(a):
    # A shark cruising over its wave: a long grey body, a white grin of teeth, fins and a tall tail
    a.block("fin", (1.4, 2.7, 0.22), (0, 0.1, 0.11))  # its wave
    a.block("body", (1.05, 2.5, 0.95), (0, 0.1, 0.78), studs=True)
    a.block("belly", (0.75, 1.9, 0.14), (0, 0.05, 0.35))
    a.block("body", (0.7, 0.55, 0.55), (0, -1.45, 0.75))  # snout
    a.block("body", (0.6, 0.4, 0.25), (0, -1.6, 0.5))  # jaw
    a.block("teeth", (0.5, 0.08, 0.18), (0, -1.76, 0.58))
    a.pair("eye", (0.13, 0.06, 0.15), (0.54, -1.3, 0.9))
    a.pair("shine", (0.05, 0.03, 0.05), (0.55, -1.33, 0.95))
    a.pair("fin", (0.06, 0.08, 0.4), (0.54, -0.95, 0.8))  # gills
    a.block("fin", (0.13, 0.6, 0.7), (0, -0.1, 1.5), rotation=(math.radians(-12), 0, 0))  # dorsal fin
    a.pair("fin", (0.65, 0.4, 0.1), (0.68, -0.55, 0.45), anim="wing", rotation=(0, math.radians(25), math.radians(-15)))
    a.block("body", (0.35, 0.55, 0.4), (0, 1.5, 0.85))
    a.block("fin", (0.12, 0.45, 1.0), (0, 1.85, 1.05), anim="tail", rotation=(math.radians(10), 0, 0))  # tail fin


def whale(a):
    # A great blue whale: the biggest body of all, a wide mouth, small fins, a broad fluke and a spout
    a.block("fin", (1.9, 3.2, 0.22), (0, 0.1, 0.11))  # its wave
    a.block("body", (1.6, 2.9, 1.35), (0, 0.1, 0.92), studs=True)
    a.block("belly", (1.2, 2.2, 0.16), (0, 0.05, 0.28))
    a.block("body", (1.35, 0.7, 1.1), (0, -1.7, 0.9))  # head
    a.block("fin", (0.9, 0.06, 0.08), (0, -2.06, 0.65))  # mouth
    a.pair("eye", (0.14, 0.06, 0.16), (0.7, -1.75, 0.95))
    a.pair("shine", (0.05, 0.03, 0.05), (0.71, -1.78, 1.0))
    a.pair("fin", (0.7, 0.45, 0.12), (0.9, -0.9, 0.5), anim="wing", rotation=(0, math.radians(25), math.radians(-15)))
    a.block("body", (0.55, 0.7, 0.5), (0, 1.75, 0.95))
    a.block("fin", (1.5, 0.5, 0.12), (0, 2.25, 1.0), anim="tail")  # fluke
    a.block("spout", (0.14, 0.14, 0.4), (0, -1.6, 1.72))  # its spout
    a.pair("spout", (0.1, 0.1, 0.3), (0.18, -1.6, 1.66), rotation=(0, 0, math.radians(-20)))


ANIMALS = {
    "dog": dog, "cat": cat, "bunny": bunny, "bear": bear, "chicken": chicken, "pig": pig, "sheep": sheep, "horse": horse,
    "bee": bee, "ladybug": ladybug, "butterfly": butterfly, "snail": snail, "frog": frog, "duckling": duckling, "fox": fox, "deer": deer,
    "squirrel": squirrel, "hedgehog": hedgehog, "owl": owl, "raccoon": raccoon, "wolf": wolf, "moose": moose, "lynx": lynx, "stag": stag,
    "crab": crab, "starfish": starfish, "turtle": turtle, "seagull": seagull, "octopus": octopus, "dolphin": dolphin, "shark": shark, "whale": whale,
}


def build(cubelings, spec, mat):
    animal = Animal(cubelings, spec, mat)
    ANIMALS[spec["animal"]](animal)
    # The game finds the body (its middle and size) by the "body" role: the first body block is the torso
    return animal.parts
