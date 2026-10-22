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


def bat(a):
    # A cave bat: a small dark body, tall ears, leathery wings spread wide and two tiny fangs
    a.legs(0.16, 0.22, -0.2, 0.25, 0.3)
    a.block("body", (0.85, 1.0, 0.8), (0, 0.05, 0.7), studs=True)
    a.block("belly", (0.6, 0.1, 0.5), (0, -0.46, 0.62))
    a.block("body", (0.7, 0.6, 0.62), (0, -0.62, 1.25), studs=True)  # head
    a.block("nose", (0.18, 0.1, 0.12), (0, -0.95, 1.18))
    a.eyes(0.17, -0.93, 1.3, size=0.15)
    a.pair("teeth", (0.07, 0.05, 0.14), (0.12, -0.9, 1.02))  # fangs
    a.pair("body", (0.2, 0.16, 0.5), (0.28, -0.55, 1.72), rotation=(0, math.radians(12), 0))  # ears
    a.pair("ear_inner", (0.1, 0.05, 0.3), (0.28, -0.64, 1.7), rotation=(0, math.radians(12), 0))
    a.pair("wing", (0.95, 0.6, 0.07), (0.85, 0.0, 1.05), anim="wing", rotation=(0, math.radians(-25), math.radians(8)))
    a.pair("wing", (0.6, 0.45, 0.07), (0.72, 0.32, 0.78), anim="wing", rotation=(0, math.radians(-25), math.radians(-10)))
    a.block("body", (0.2, 0.2, 0.25), (0, 0.6, 0.6), anim="tail")


def mole(a):
    # A digging mole: a low wide body, shovel paws up front, a pink snout and eyes shut against the dark
    a.legs(0.3, 0.4, -0.4, 0.45, 0.3)
    a.block("body", (1.2, 1.5, 0.7), (0, 0.1, 0.65), studs=True)
    a.block("belly", (0.85, 0.12, 0.45), (0, -0.68, 0.55))
    a.pair("claw", (0.5, 0.35, 0.16), (0.62, -0.55, 0.2), anim="leg")  # shovel paws
    a.block("body", (0.75, 0.6, 0.55), (0, -0.75, 0.85), studs=True)  # head
    a.block("snout", (0.45, 0.3, 0.3), (0, -1.12, 0.72))
    a.block("nose", (0.22, 0.12, 0.14), (0, -1.3, 0.78))
    a.eyes(0.18, -1.06, 0.98, size=0.1)
    a.pair("body", (0.18, 0.12, 0.2), (0.34, -0.7, 1.18))  # little ears
    a.block("snout", (0.14, 0.5, 0.14), (0, 0.95, 0.5), anim="tail", rotation=(math.radians(35), 0, 0))  # pink tail


def spider(a):
    # A cave spider: a fat round body, eight long legs bent over it and a face full of eyes
    for s in (-1, 1):
        for y in (-0.55, -0.2, 0.15, 0.5):
            a.block("legs", (0.75, 0.13, 0.13), (0.8 * s, y, 0.55), anim="leg", rotation=(0, 0, math.radians(20 * s)))
            a.block("legs", (0.13, 0.13, 0.55), (1.08 * s, y, 0.27), anim="leg")
    a.block("body", (1.05, 1.15, 0.85), (0, 0.3, 0.85), studs=True)
    a.block("spot", (0.4, 0.4, 0.08), (0, 0.3, 1.3))  # the marking on its back
    a.block("body", (0.7, 0.55, 0.6), (0, -0.75, 0.8), studs=True)  # head
    a.eyes(0.16, -1.04, 0.88, size=0.17)
    a.pair("eye", (0.09, 0.05, 0.09), (0.3, -1.03, 0.95))  # the little extra eyes
    a.pair("teeth", (0.08, 0.06, 0.16), (0.14, -1.0, 0.55))  # fangs


def newt(a):
    # A bright newt: a low orange body with dark spots, a wide smile and a long flat tail
    a.legs(0.2, 0.35, -0.5, 0.55, 0.3)
    a.block("body", (0.8, 1.7, 0.5), (0, 0.0, 0.55), studs=True)
    a.block("belly", (0.55, 1.3, 0.1), (0, 0.0, 0.3))
    a.block("spot", (0.18, 0.18, 0.06), (-0.2, -0.3, 0.82))
    a.block("spot", (0.15, 0.15, 0.06), (0.22, 0.25, 0.82))
    a.block("body", (0.72, 0.55, 0.42), (0, -0.95, 0.58), studs=True)  # head
    a.eyes(0.19, -1.24, 0.62, size=0.14)
    a.block("spot", (0.34, 0.04, 0.05), (0, -1.24, 0.42))  # its smile
    a.block("body", (0.5, 0.9, 0.18), (0, 1.2, 0.5), anim="tail", rotation=(math.radians(10), 0, 0))  # flat tail


def scorpion(a):
    # A rust-red scorpion: a low segmented body, two great claws, and its sting curled high over its back
    for s in (-1, 1):
        for y in (-0.3, 0.05, 0.4):
            a.block("legs", (0.6, 0.14, 0.14), (0.72 * s, y, 0.25), anim="leg", rotation=(0, 0, math.radians(18 * s)))
    a.block("body", (0.95, 1.5, 0.5), (0, 0.2, 0.55), studs=True)
    a.block("body", (0.8, 0.5, 0.42), (0, -0.55, 0.62), studs=True)  # front segment
    a.eyes(0.16, -0.82, 0.7, size=0.12)
    a.pair("claw", (0.45, 0.55, 0.4), (0.55, -0.85, 0.45))
    a.pair("claw", (0.25, 0.3, 0.25), (0.62, -1.18, 0.55))
    a.block("body", (0.3, 0.35, 0.3), (0, 1.05, 0.75), anim="tail")
    a.block("body", (0.26, 0.3, 0.3), (0, 0.95, 1.05), anim="tail", rotation=(math.radians(-25), 0, 0))
    a.block("body", (0.22, 0.26, 0.26), (0, 0.7, 1.3), anim="tail", rotation=(math.radians(-45), 0, 0))
    a.block("sting", (0.16, 0.16, 0.3), (0, 0.45, 1.45), anim="tail", rotation=(math.radians(-60), 0, 0))  # the sting


def panther(a):
    # A black panther: a long sleek body, pale green eyes and a tail that never stops moving
    a.legs(0.34, 0.38, -0.6, 0.65, 0.62)
    a.block("body", (1.05, 2.0, 0.9), (0, 0.05, 1.05), studs=True)
    a.block("body", (1.15, 0.95, 0.95), (0, -1.0, 1.8), studs=True)  # head
    a.block("belly", (0.55, 0.42, 0.35), (0, -1.55, 1.58))  # muzzle
    a.block("nose", (0.2, 0.1, 0.14), (0, -1.78, 1.68))
    a.eyes(0.29, -1.49, 1.96, size=0.2)
    a.pair("body", (0.3, 0.2, 0.38), (0.4, -0.95, 2.38))  # ears
    a.block("body", (0.2, 0.2, 0.85), (0, 1.12, 1.55), anim="tail", rotation=(math.radians(-25), 0, 0))


def golem(a):
    # A stone golem: a mountain of grey blocks, arms like pillars, a glowing crystal heart and a heavy brow
    a.legs(0.55, 0.5, -0.5, 0.55, 0.5)
    a.block("body", (1.7, 1.6, 1.5), (0, 0.05, 1.25), studs=True)
    a.block("rock", (1.4, 0.3, 0.5), (0, 0.1, 1.95))  # shoulders
    a.pair("rock", (0.45, 0.5, 1.35), (1.05, 0.05, 0.95), anim="leg")  # pillar arms (they swing as it lumbers)
    a.pair("rock", (0.5, 0.55, 0.35), (1.05, 0.05, 0.18))  # fists
    a.block("glow", (0.4, 0.12, 0.4), (0, -0.78, 1.3))  # its crystal heart
    a.block("rock", (1.15, 1.0, 0.9), (0, -0.75, 2.35), studs=True)  # head
    a.block("rock", (1.2, 0.25, 0.28), (0, -1.05, 2.62))  # brow
    a.eyes(0.28, -1.27, 2.42, size=0.16)
    a.block("rock", (0.5, 0.3, 0.25), (0, -1.2, 2.05))  # jaw
    a.block("moss", (0.5, 0.4, 0.12), (-0.4, 0.2, 2.85))  # moss on its crown


def dragon(a):
    # A young cave dragon: a green body with a horned head, leathery wings and a tail tipped like a spade
    a.legs(0.38, 0.42, -0.6, 0.65, 0.65)
    a.block("body", (1.2, 2.0, 1.05), (0, 0.1, 1.12), studs=True)
    a.block("belly", (0.8, 1.5, 0.12), (0, 0.05, 0.62))
    for y in (-0.55, 0.05, 0.65):
        a.block("spike", (0.18, 0.22, 0.32), (0, y, 1.78))  # back spikes
    a.block("body", (0.65, 0.55, 0.85), (0, -1.0, 1.75))  # neck
    a.block("body", (0.85, 1.0, 0.7), (0, -1.45, 2.3), studs=True)  # head
    a.block("belly", (0.6, 0.45, 0.35), (0, -2.0, 2.12))  # snout
    a.pair("nose", (0.09, 0.06, 0.09), (0.14, -2.24, 2.22))  # nostrils
    a.pair("teeth", (0.08, 0.05, 0.14), (0.2, -2.2, 1.95))  # fangs
    a.eyes(0.3, -1.97, 2.42, size=0.18)
    a.pair("horn", (0.14, 0.14, 0.5), (0.3, -1.3, 2.85), rotation=(math.radians(20), math.radians(15), 0))  # horns
    a.pair("wing", (0.9, 0.7, 0.08), (0.75, -0.25, 1.85), anim="wing", rotation=(0, math.radians(-30), math.radians(12)))
    a.pair("wing", (0.65, 0.5, 0.08), (0.62, 0.3, 1.6), anim="wing", rotation=(0, math.radians(-30), math.radians(-8)))
    a.block("body", (0.3, 0.9, 0.3), (0, 1.25, 1.15), anim="tail", rotation=(math.radians(-15), 0, 0))
    a.block("spike", (0.45, 0.35, 0.12), (0, 1.72, 1.32), anim="tail", rotation=(math.radians(-15), 0, 0))  # spade tip


def camel(a):
    # A patient camel: long legs, two humps, a long neck and a calm half-asleep face
    a.legs(0.32, 0.38, -0.65, 0.7, 1.0)
    a.block("body", (1.15, 2.1, 1.0), (0, 0.05, 1.5), studs=True)
    a.block("body", (0.8, 0.55, 0.55), (0, -0.45, 2.25))  # front hump
    a.block("body", (0.8, 0.55, 0.55), (0, 0.55, 2.25))  # back hump
    a.block("body", (0.55, 0.45, 0.95), (0, -1.05, 2.05))  # neck
    a.block("body", (0.62, 0.95, 0.55), (0, -1.5, 2.75), studs=True)  # head
    a.block("snout", (0.5, 0.4, 0.32), (0, -2.0, 2.58))
    a.block("nose", (0.24, 0.12, 0.12), (0, -2.22, 2.64))
    a.eyes(0.32, -1.99, 2.82, size=0.15)
    a.pair("body", (0.18, 0.14, 0.26), (0.26, -1.35, 3.1))  # ears
    a.block("body", (0.18, 0.18, 0.6), (0, 1.15, 1.6), anim="tail", rotation=(math.radians(-20), 0, 0))
    a.block("hair", (0.2, 0.2, 0.2), (0, 1.28, 1.28), anim="tail")  # tail tuft


def meerkat(a):
    # A meerkat on watch: standing tall on its hind legs, dark patches round its eyes, its tail on the sand
    a.pair("legs", (0.26, 0.34, 0.22), (0.28, -0.15, 0.11))
    a.block("body", (0.85, 0.8, 1.15), (0, 0.05, 0.75), studs=True)
    a.block("belly", (0.55, 0.1, 0.75), (0, -0.38, 0.72))
    a.pair("body", (0.18, 0.18, 0.5), (0.45, -0.2, 0.85))  # little arms
    a.block("body", (0.68, 0.6, 0.6), (0, -0.15, 1.62), studs=True)  # head
    a.block("patch", (0.6, 0.06, 0.3), (0, -0.47, 1.68))  # eye patches
    a.block("belly", (0.36, 0.22, 0.24), (0, -0.42, 1.42))  # muzzle
    a.block("nose", (0.16, 0.09, 0.1), (0, -0.55, 1.46))
    a.eyes(0.17, -0.5, 1.7, size=0.13)
    a.pair("body", (0.16, 0.12, 0.18), (0.26, -0.12, 1.98))  # ears
    a.block("body", (0.16, 0.7, 0.16), (0, 0.55, 0.3), anim="tail", rotation=(math.radians(55), 0, 0))  # tail on the ground
    a.block("patch", (0.17, 0.2, 0.17), (0, 0.92, 0.16), anim="tail")  # dark tail tip


def fennec(a):
    # A fennec fox: a tiny cream body under the biggest ears in the desert, and a tail near as big again
    a.legs(0.26, 0.3, -0.45, 0.5, 0.5)
    a.block("body", (0.95, 1.5, 0.8), (0, 0.05, 0.9), studs=True)
    a.block("belly", (0.6, 0.12, 0.5), (0, -0.72, 0.82))
    a.block("body", (0.95, 0.8, 0.8), (0, -0.8, 1.55), studs=True)  # head
    a.block("belly", (0.45, 0.35, 0.3), (0, -1.28, 1.36))  # muzzle
    a.block("nose", (0.16, 0.09, 0.12), (0, -1.48, 1.44))
    a.eyes(0.25, -1.22, 1.66, size=0.2)
    a.pair("body", (0.45, 0.22, 0.85), (0.42, -0.75, 2.25), rotation=(0, math.radians(10), 0))  # the great ears
    a.pair("ear_inner", (0.28, 0.06, 0.6), (0.42, -0.88, 2.22), rotation=(0, math.radians(10), 0))
    a.block("body", (0.32, 0.32, 0.85), (0, 0.85, 1.3), anim="tail", rotation=(math.radians(-25), 0, 0))
    a.block("tail", (0.34, 0.34, 0.3), (0, 1.05, 1.85), anim="tail", rotation=(math.radians(-25), 0, 0))  # dark tail tip


def vulture(a):
    # A vulture: a dark hunched body, a ruff of pale feathers, a bald pink head and a hooked beak
    a.legs(0.18, 0.28, -0.1, 0.25, 0.5)
    a.block("body", (1.15, 1.5, 1.0), (0, 0.12, 0.95), studs=True)
    a.pair("wing", (0.15, 0.95, 0.7), (0.62, 0.15, 1.0), anim="wing")
    a.block("ruff", (1.0, 0.5, 0.5), (0, -0.6, 1.35))  # feather ruff
    a.block("head", (0.55, 0.55, 0.55), (0, -0.85, 1.75), studs=True)  # bald head
    a.block("beak", (0.24, 0.3, 0.2), (0, -1.2, 1.68))
    a.block("beak", (0.2, 0.18, 0.2), (0, -1.28, 1.5), rotation=(math.radians(35), 0, 0))  # the hook
    a.eyes(0.15, -1.14, 1.85, size=0.13)
    a.block("body", (0.6, 0.4, 0.15), (0, 0.95, 1.05), anim="tail", rotation=(math.radians(20), 0, 0))


def cobra(a):
    # A cobra, reared up: coils on the sand, a wide hood spread, and a forked tongue tasting the air
    a.block("body", (1.35, 1.35, 0.35), (0, 0.35, 0.18), studs=True)  # the coil
    a.block("body", (1.05, 1.05, 0.3), (0, 0.3, 0.48))
    a.block("body", (0.55, 0.5, 1.1), (0, -0.25, 1.05), studs=True)  # reared body
    a.block("belly", (0.4, 0.1, 0.85), (0, -0.52, 1.0))
    a.block("hood", (1.35, 0.16, 0.95), (0, -0.18, 1.62))  # the hood
    a.pair("spot", (0.3, 0.05, 0.3), (0.35, -0.28, 1.7))  # hood marks
    a.block("body", (0.6, 0.55, 0.5), (0, -0.3, 1.95), studs=True)  # head
    a.eyes(0.16, -0.59, 2.02, size=0.13)
    a.block("tongue", (0.06, 0.3, 0.04), (0, -0.68, 1.82))  # tongue
    a.pair("tongue", (0.05, 0.18, 0.04), (0.06, -0.86, 1.82), rotation=(0, math.radians(20), 0))  # its fork


def hyena(a):
    # A laughing hyena: a sloping back, a spotted coat, round ears and a grin full of teeth
    a.legs(0.34, 0.38, -0.55, 0.6, 0.68)
    a.block("body", (1.1, 1.85, 0.95), (0, 0.05, 1.12), rotation=(math.radians(-6), 0, 0))  # sloped body
    a.pair("spot", (0.06, 0.25, 0.25), (0.57, 0.15, 1.25))
    a.block("spot", (0.22, 0.22, 0.06), (-0.28, 0.45, 1.55))
    a.block("spot", (0.2, 0.2, 0.06), (0.3, -0.15, 1.6))
    a.block("body", (1.1, 0.9, 0.95), (0, -0.95, 1.72), studs=True)  # head
    a.block("belly", (0.6, 0.5, 0.4), (0, -1.5, 1.5))  # muzzle
    a.block("nose", (0.26, 0.14, 0.16), (0, -1.74, 1.6))
    a.block("teeth", (0.44, 0.06, 0.12), (0, -1.68, 1.32))  # the grin
    a.eyes(0.28, -1.42, 1.86, size=0.2)
    a.pair("body", (0.34, 0.2, 0.34), (0.42, -0.9, 2.22))  # round ears
    a.block("mane", (0.18, 1.0, 0.4), (0, -0.35, 1.68))  # short mane ridge
    a.block("body", (0.22, 0.22, 0.6), (0, 1.05, 1.25), anim="tail", rotation=(math.radians(-30), 0, 0))


def lion(a):
    # A lion: a golden body and a mane like a sun round its head, a tail tipped with a dark tuft
    a.legs(0.4, 0.44, -0.6, 0.65, 0.7)
    a.block("body", (1.25, 2.0, 1.05), (0, 0.05, 1.15), studs=True)
    a.block("belly", (0.8, 1.4, 0.12), (0, 0.0, 0.68))
    a.block("mane", (1.55, 0.85, 1.5), (0, -0.85, 1.85))  # the mane
    a.block("mane", (1.3, 0.5, 0.4), (0, -0.9, 2.68))
    a.block("body", (0.95, 0.75, 0.9), (0, -1.05, 1.85), studs=True)  # face
    a.block("belly", (0.55, 0.4, 0.35), (0, -1.5, 1.62))  # muzzle
    a.block("nose", (0.24, 0.12, 0.14), (0, -1.72, 1.72))
    a.eyes(0.26, -1.44, 2.0, size=0.2)
    a.pair("mane", (0.3, 0.2, 0.3), (0.42, -0.95, 2.32))  # ears in the mane
    a.block("body", (0.2, 0.2, 0.85), (0, 1.12, 1.45), anim="tail", rotation=(math.radians(-20), 0, 0))
    a.block("mane", (0.3, 0.3, 0.3), (0, 1.32, 2.05), anim="tail")  # tail tuft


def anubis(a):
    # Anubis: a black jackal standing tall, ears to the sky, gold at its throat and brow
    a.legs(0.34, 0.38, -0.5, 0.55, 0.95)
    a.block("body", (1.0, 1.7, 1.15), (0, 0.05, 1.5), studs=True)
    a.block("gold", (0.85, 0.14, 0.5), (0, -0.82, 1.72))  # chest plate
    a.block("gold", (1.02, 0.3, 0.14), (0, 0.05, 2.0))  # collar
    a.block("body", (0.6, 0.45, 0.75), (0, -0.9, 2.25))  # neck
    a.block("body", (0.72, 0.85, 0.65), (0, -1.25, 2.85), studs=True)  # head
    a.block("body", (0.42, 0.55, 0.35), (0, -1.75, 2.68))  # long snout
    a.block("nose", (0.2, 0.12, 0.14), (0, -2.05, 2.76))
    a.block("gold", (0.74, 0.1, 0.16), (0, -1.3, 3.12))  # brow band
    a.eyes(0.19, -1.63, 2.92, size=0.15)
    a.pair("body", (0.24, 0.18, 0.85), (0.28, -1.2, 3.55), rotation=(0, math.radians(8), 0))  # the tall ears
    a.pair("gold", (0.12, 0.06, 0.4), (0.28, -1.3, 3.5), rotation=(0, math.radians(8), 0))
    a.block("body", (0.2, 0.2, 0.7), (0, 0.95, 1.7), anim="tail", rotation=(math.radians(-25), 0, 0))


def lemming(a):
    # A lemming: a tiny round bundle of ginger fur with dark stripes, made to scurry
    a.legs(0.18, 0.24, -0.25, 0.3, 0.28)
    a.block("body", (0.95, 1.15, 0.75), (0, 0.05, 0.62), studs=True)
    a.block("stripe", (0.97, 0.16, 0.6), (0, -0.2, 0.66))
    a.block("stripe", (0.97, 0.16, 0.55), (0, 0.3, 0.64))
    a.block("belly", (0.65, 0.1, 0.45), (0, -0.5, 0.52))
    a.block("body", (0.7, 0.55, 0.55), (0, -0.6, 0.95), studs=True)  # head
    a.block("belly", (0.4, 0.25, 0.25), (0, -0.92, 0.82))  # muzzle
    a.block("nose", (0.15, 0.08, 0.1), (0, -1.06, 0.88))
    a.eyes(0.18, -0.89, 1.05, size=0.13)
    a.pair("body", (0.16, 0.1, 0.16), (0.26, -0.55, 1.26))  # ears
    a.block("body", (0.18, 0.18, 0.18), (0, 0.68, 0.6), anim="tail")


def penguin(a):
    # A penguin: standing straight in its black coat, white shirt, orange beak and feet
    a.pair("feet", (0.34, 0.45, 0.12), (0.26, -0.2, 0.06))
    a.block("body", (1.0, 0.9, 1.5), (0, 0.05, 0.95), studs=True)
    a.block("belly", (0.7, 0.1, 1.05), (0, -0.42, 0.9))
    a.pair("body", (0.14, 0.55, 0.8), (0.56, 0.05, 0.95), anim="wing")  # flippers
    a.block("body", (0.68, 0.6, 0.6), (0, -0.05, 1.95), studs=True)  # head
    a.block("belly", (0.45, 0.08, 0.4), (0, -0.36, 1.88))  # face patch
    a.block("beak", (0.24, 0.28, 0.16), (0, -0.42, 1.82))
    a.eyes(0.16, -0.4, 2.02, size=0.13)
    a.block("body", (0.35, 0.3, 0.18), (0, 0.55, 0.75), anim="tail", rotation=(math.radians(25), 0, 0))


def seal(a):
    # A seal on the ice: a long grey sausage of a body, head up, whiskers out, tail flippers fanned
    a.block("body", (1.05, 2.0, 0.75), (0, 0.25, 0.5), studs=True)
    a.block("belly", (0.75, 1.5, 0.12), (0, 0.2, 0.16))
    a.pair("body", (0.5, 0.6, 0.16), (0.6, -0.55, 0.12), anim="leg", rotation=(0, math.radians(15), 0))  # front flippers
    a.block("body", (0.68, 0.6, 0.6), (0, -1.05, 0.78), studs=True)  # head
    a.block("belly", (0.45, 0.28, 0.3), (0, -1.38, 0.66))  # muzzle
    a.block("nose", (0.2, 0.1, 0.12), (0, -1.55, 0.72))
    a.eyes(0.18, -1.37, 0.86, size=0.14)
    a.pair("whisker", (0.22, 0.03, 0.03), (0.3, -1.5, 0.68), rotation=(0, math.radians(-25), 0))  # whiskers
    a.pair("body", (0.45, 0.55, 0.14), (0.28, 1.35, 0.3), anim="tail", rotation=(0, math.radians(30), math.radians(15)))  # tail flippers


def hare(a):
    # A snow hare: white as the drift it sits in, tall ears tipped with black, a pink twitch of a nose
    a.legs(0.36, 0.38, -0.45, 0.55, 0.5)
    a.block("body", (1.2, 1.4, 1.05), (0, 0.12, 0.98), studs=True)
    a.block("belly", (0.85, 0.12, 0.7), (0, -0.6, 0.92))
    a.block("body", (1.05, 0.95, 0.95), (0, -0.68, 1.8), studs=True)  # head
    a.block("belly", (0.5, 0.22, 0.3), (0, -1.2, 1.6))  # muzzle
    a.block("nose", (0.18, 0.08, 0.12), (0, -1.34, 1.72))
    a.eyes(0.28, -1.17, 1.96, size=0.2)
    for s in (-1, 1):
        a.block("body", (0.28, 0.18, 1.15), (0.27 * s, -0.55, 2.85), rotation=(math.radians(-6), math.radians(8 * s), 0))
        a.block("ear_tip", (0.29, 0.19, 0.3), (0.34 * s, -0.5, 3.42), rotation=(math.radians(-6), math.radians(8 * s), 0))
        a.block("ear_inner", (0.15, 0.05, 0.85), (0.27 * s, -0.66, 2.82), rotation=(math.radians(-6), math.radians(8 * s), 0))
    a.block("tail", (0.4, 0.3, 0.4), (0, 0.88, 1.1), anim="tail")


def yak(a):
    # A yak: a walking heap of shaggy brown fur, horns curving wide, a skirt of hair round its legs
    a.legs(0.4, 0.44, -0.6, 0.65, 0.55)
    a.block("fur", (1.5, 2.1, 0.75), (0, 0.05, 0.8))  # the shaggy skirt
    a.block("body", (1.4, 2.0, 1.0), (0, 0.05, 1.45), studs=True)
    a.block("body", (1.0, 0.7, 0.45), (0, -0.5, 2.05))  # hump
    a.block("body", (0.7, 0.5, 0.8), (0, -1.0, 1.75))  # neck
    a.block("body", (0.82, 0.9, 0.7), (0, -1.4, 2.0), studs=True)  # head
    a.block("fur", (0.7, 0.3, 0.35), (0, -1.9, 1.85))  # beardy muzzle
    a.block("nose", (0.28, 0.14, 0.14), (0, -2.08, 1.92))
    a.eyes(0.4, -1.87, 2.08, size=0.15)
    a.pair("horn", (0.55, 0.16, 0.16), (0.62, -1.35, 2.22), rotation=(0, 0, math.radians(-25)))  # horns wide
    a.pair("horn", (0.16, 0.16, 0.35), (0.95, -1.35, 2.36), rotation=(math.radians(-15), 0, 0))  # and their tips up
    a.block("fur", (0.3, 0.3, 0.7), (0, 1.15, 1.35), anim="tail", rotation=(math.radians(-20), 0, 0))


def walrus(a):
    # A walrus: a mountain of blubber on two long tusks, whiskers like a brush, flippers for feet
    a.pair("body", (0.55, 0.65, 0.2), (0.62, -0.45, 0.1), anim="leg", rotation=(0, math.radians(10), 0))  # front flippers
    a.pair("body", (0.5, 0.55, 0.18), (0.55, 0.75, 0.1), anim="tail", rotation=(0, math.radians(25), 0))  # back flippers
    a.block("body", (1.6, 2.1, 1.25), (0, 0.1, 1.05), studs=True)
    a.block("belly", (1.15, 0.14, 0.8), (0, -0.95, 0.9))
    a.block("body", (1.05, 0.85, 0.9), (0, -1.05, 1.85), studs=True)  # head
    a.block("muzzle", (0.8, 0.4, 0.5), (0, -1.55, 1.6))  # whisker muzzle
    a.block("nose", (0.3, 0.14, 0.14), (0, -1.78, 1.78))
    a.pair("whisker", (0.2, 0.05, 0.2), (0.22, -1.77, 1.55))
    a.pair("tusk", (0.13, 0.13, 0.85), (0.26, -1.68, 1.12))  # the great tusks
    a.eyes(0.3, -1.5, 2.05, size=0.15)


def narwhal(a):
    # A narwhal over its wave: a pale mottled body, a small smile, and one long spiral tusk ahead of it
    a.block("fin", (1.3, 2.4, 0.22), (0, 0.15, 0.11))  # its wave
    a.block("body", (1.0, 2.3, 0.9), (0, 0.15, 0.75), studs=True)
    a.block("belly", (0.7, 1.7, 0.14), (0, 0.1, 0.32))
    a.pair("spot", (0.2, 0.25, 0.06), (0.3, 0.3, 1.22))
    a.block("spot", (0.18, 0.2, 0.06), (-0.28, -0.4, 1.22))
    a.block("body", (0.72, 0.55, 0.55), (0, -1.3, 0.8))  # head
    a.pair("eye", (0.12, 0.06, 0.14), (0.38, -1.45, 0.85))
    a.pair("shine", (0.05, 0.03, 0.05), (0.39, -1.48, 0.9))
    a.block("tusk", (0.16, 0.9, 0.16), (0, -2.0, 0.82), rotation=(math.radians(90), 0, 0))  # the tusk, pointing ahead
    a.block("tusk", (0.1, 0.7, 0.1), (0, -2.75, 0.82), rotation=(math.radians(90), 0, 0))
    a.pair("fin", (0.55, 0.35, 0.1), (0.58, -0.45, 0.42), anim="wing", rotation=(0, math.radians(25), math.radians(-20)))
    a.block("body", (0.38, 0.5, 0.35), (0, 1.35, 0.8))
    a.block("fin", (0.9, 0.4, 0.1), (0, 1.55, 0.85), anim="tail")  # fluke


def yeti(a):
    # A yeti: a great white ape with arms to the ground, a blue-grey face under a heavy brow
    a.legs(0.5, 0.55, -0.5, 0.55, 0.6)
    a.block("body", (1.55, 1.5, 1.5), (0, 0.1, 1.35), studs=True)
    a.block("belly", (1.05, 0.14, 0.95), (0, -0.72, 1.25))
    a.pair("body", (0.42, 0.45, 1.5), (0.98, 0.05, 0.95), anim="leg")  # long arms (they swing as it lumbers)
    a.pair("face", (0.46, 0.48, 0.3), (0.98, 0.05, 0.15))  # hands
    a.block("body", (1.05, 0.9, 0.95), (0, -0.7, 2.45), studs=True)  # head
    a.block("face", (0.75, 0.35, 0.55), (0, -1.2, 2.3))  # face
    a.block("face", (0.85, 0.2, 0.25), (0, -0.85, 2.85))  # brow
    a.block("nose", (0.24, 0.12, 0.12), (0, -1.4, 2.36))
    a.block("teeth", (0.4, 0.06, 0.12), (0, -1.38, 2.08))
    a.eyes(0.22, -1.39, 2.52, size=0.15)
    a.block("body", (0.3, 0.3, 0.3), (0, 0.9, 1.5), anim="tail")


def gecko(a):
    # A gecko: flat on the warm rock, big round eyes, toes spread wide and a tail as long as itself
    a.pair("legs", (0.42, 0.3, 0.14), (0.52, -0.5, 0.1), anim="leg")
    a.pair("legs", (0.42, 0.3, 0.14), (0.52, 0.55, 0.1), anim="leg")
    a.block("body", (0.95, 1.8, 0.4), (0, 0.05, 0.42), studs=True)
    a.block("belly", (0.65, 1.4, 0.1), (0, 0.05, 0.22))
    a.pair("spot", (0.16, 0.2, 0.06), (0.25, 0.1, 0.64))
    a.block("spot", (0.14, 0.16, 0.06), (-0.22, -0.35, 0.64))
    a.block("body", (0.85, 0.6, 0.38), (0, -1.0, 0.45), studs=True)  # flat head
    a.pair("body", (0.24, 0.24, 0.2), (0.28, -1.05, 0.68))  # eye bumps
    a.eyes(0.28, -1.32, 0.7, size=0.15)
    a.block("body", (0.35, 0.85, 0.2), (0, 1.35, 0.38), anim="tail", rotation=(math.radians(-8), 0, 0))
    a.block("body", (0.22, 0.7, 0.16), (0, 2.05, 0.42), anim="tail", rotation=(math.radians(8), 0, 0))


def iguana(a):
    # An iguana: a green lizard with a crest of spikes down its back, a dewlap at its throat and a whip tail
    a.legs(0.3, 0.36, -0.55, 0.6, 0.4)
    a.block("body", (0.95, 1.9, 0.65), (0, 0.05, 0.72), studs=True)
    a.block("belly", (0.65, 1.5, 0.12), (0, 0.05, 0.42))
    for y in (-0.6, -0.1, 0.4, 0.85):
        a.block("spike", (0.14, 0.16, 0.3), (0, y, 1.18))  # back crest
    a.block("body", (0.7, 0.65, 0.55), (0, -1.05, 0.82), studs=True)  # head
    a.block("dewlap", (0.4, 0.12, 0.4), (0, -1.15, 0.42))  # throat fan
    a.pair("spike", (0.12, 0.12, 0.22), (0.2, -1.1, 1.18))  # head spikes
    a.eyes(0.36, -1.3, 0.92, size=0.13)
    a.block("body", (0.3, 1.0, 0.22), (0, 1.45, 0.6), anim="tail", rotation=(math.radians(-10), 0, 0))
    a.block("body", (0.18, 0.9, 0.16), (0, 2.3, 0.68), anim="tail", rotation=(math.radians(6), 0, 0))


def beetle(a):
    # A lava beetle: a dark violet shell hot at the seams, and a forked horn to flip its rivals
    a.legs(0.14, 0.32, -0.32, 0.32, 0.32)
    a.block("body", (1.25, 1.45, 0.65), (0, 0.05, 0.62), studs=True)
    a.block("body", (1.05, 1.2, 0.4), (0, 0.05, 1.1))  # the dome
    a.block("wing", (0.08, 1.3, 0.1), (0, 0.05, 1.32))  # the split between the wing cases
    a.pair("glow", (0.16, 0.16, 0.06), (0.32, -0.2, 1.28))  # ember spots
    a.block("body", (0.55, 0.35, 0.42), (0, -0.8, 0.55))  # head
    a.eyes(0.17, -0.99, 0.66, size=0.13)
    a.pair("legs", (0.07, 0.07, 0.35), (0.15, -0.92, 0.95), rotation=(math.radians(-20), 0, 0))  # antennae
    a.block("horn", (0.14, 0.14, 0.55), (0, -0.85, 1.05), rotation=(math.radians(-30), 0, 0))  # its horn
    a.pair("horn", (0.1, 0.3, 0.1), (0.12, -1.0, 1.32), rotation=(math.radians(-15), 0, 0))  # and its fork


def salamander(a):
    # A fire salamander: a black body burning with ember spots, low on the hot stone
    a.legs(0.22, 0.32, -0.5, 0.55, 0.3)
    a.block("body", (0.85, 1.7, 0.45), (0, 0.05, 0.52), studs=True)
    a.block("glow", (0.2, 0.25, 0.07), (-0.2, -0.35, 0.76))
    a.block("glow", (0.16, 0.2, 0.07), (0.24, 0.15, 0.76))
    a.block("glow", (0.18, 0.22, 0.07), (-0.05, 0.55, 0.76))
    a.block("body", (0.75, 0.55, 0.4), (0, -1.0, 0.55), studs=True)  # head
    a.eyes(0.2, -1.29, 0.6, size=0.13)
    a.block("body", (0.4, 0.9, 0.2), (0, 1.3, 0.48), anim="tail", rotation=(math.radians(-8), 0, 0))
    a.block("glow", (0.14, 0.3, 0.07), (0, 1.5, 0.56), anim="tail")  # an ember stripe down its tail


def phoenix(a):
    # A phoenix: a bird of living flame, crest ablaze, three long tail feathers streaming behind it
    a.legs(0.14, 0.24, -0.05, 0.2, 0.45)
    a.block("body", (1.0, 1.3, 0.9), (0, 0.1, 0.9), studs=True)
    a.block("belly", (0.7, 0.1, 0.6), (0, -0.58, 0.85))
    a.pair("wing", (0.13, 0.8, 0.6), (0.56, 0.1, 1.0), anim="wing")
    a.pair("flame", (0.1, 0.5, 0.35), (0.62, 0.35, 1.35), anim="wing", rotation=(0, math.radians(-20), 0))  # wingtip flames
    a.block("body", (0.66, 0.6, 0.62), (0, -0.68, 1.6), studs=True)  # head
    a.block("beak", (0.26, 0.3, 0.18), (0, -1.08, 1.52))
    a.eyes(0.18, -0.99, 1.66, size=0.15)
    a.block("flame", (0.16, 0.3, 0.5), (0, -0.6, 2.1), rotation=(math.radians(15), 0, 0))  # its crest
    a.pair("flame", (0.12, 0.24, 0.38), (0.18, -0.58, 2.02), rotation=(math.radians(15), math.radians(12), 0))
    a.block("flame", (0.22, 1.0, 0.14), (0, 1.15, 1.0), anim="tail", rotation=(math.radians(35), 0, 0))  # tail feathers
    a.pair("flame", (0.16, 0.8, 0.12), (0.25, 1.1, 0.9), anim="tail", rotation=(math.radians(45), 0, math.radians(10)))


def cerberus(a):
    # Cerberus: one great hellhound body and THREE heads, all of them watching, all of them hungry
    a.legs(0.4, 0.44, -0.6, 0.65, 0.7)
    a.block("body", (1.25, 2.05, 1.05), (0, 0.1, 1.15), studs=True)
    a.block("belly", (0.8, 1.4, 0.12), (0, 0.05, 0.68))
    for hx, hy in ((0, -1.05), (-0.62, -0.85), (0.62, -0.85)):
        a.block("body", (0.78, 0.7, 0.72), (hx, hy, 1.95), studs=True)  # a head
        a.block("belly", (0.45, 0.35, 0.3), (hx, hy - 0.5, 1.78))  # its muzzle
        a.block("nose", (0.18, 0.1, 0.12), (hx, hy - 0.7, 1.86))
        a.block("teeth", (0.34, 0.05, 0.1), (hx, hy - 0.62, 1.62))  # its fangs
        for s in (-1, 1):
            a.block("body", (0.2, 0.14, 0.32), (hx + 0.24 * s, hy + 0.05, 2.36))  # its ears
    a.eyes(0.2, -1.42, 2.06, size=0.16)  # the middle head's eyes
    for hx in (-0.62, 0.62):  # the side heads' eyes
        for s in (-1, 1):
            a.block("eye", (0.13, 0.05, 0.15), (hx + 0.18 * s, -1.23, 2.06))
            a.block("shine", (0.05, 0.03, 0.05), (hx + 0.18 * s - 0.03, -1.27, 2.11))
    a.block("body", (0.24, 0.24, 0.8), (0, 1.2, 1.5), anim="tail", rotation=(math.radians(-25), 0, 0))
    a.block("flame", (0.2, 0.2, 0.35), (0, 1.42, 2.0), anim="tail", rotation=(math.radians(-25), 0, 0))  # flame-tipped tail


def basilisk(a):
    # A basilisk: a serpent king on its coils, crest spiked like a crown, eyes that promise stone
    a.block("body", (1.6, 1.6, 0.4), (0, 0.35, 0.2), studs=True)  # the great coil
    a.block("body", (1.25, 1.25, 0.35), (0, 0.3, 0.55))
    a.block("body", (0.6, 0.55, 1.3), (0, -0.2, 1.25), studs=True)  # reared body
    a.block("belly", (0.44, 0.12, 1.0), (0, -0.5, 1.2))
    a.block("body", (0.72, 0.62, 0.58), (0, -0.28, 2.15), studs=True)  # head
    a.block("belly", (0.5, 0.3, 0.28), (0, -0.62, 2.0))  # jaw
    a.pair("teeth", (0.08, 0.05, 0.16), (0.16, -0.72, 1.9))  # fangs
    a.eyes(0.19, -0.62, 2.24, size=0.14)
    for dx in (-0.24, 0, 0.24):
        a.block("spike", (0.13, 0.13, 0.4), (dx, -0.22, 2.55), rotation=(math.radians(-12), 0, 0))  # crest crown
    a.pair("horn", (0.12, 0.12, 0.45), (0.3, -0.2, 2.45), rotation=(math.radians(25), math.radians(15), 0))
    a.block("tongue", (0.06, 0.32, 0.04), (0, -0.78, 1.98))
    a.pair("tongue", (0.05, 0.2, 0.04), (0.06, -0.98, 1.98), rotation=(0, math.radians(20), 0))
    a.block("body", (0.4, 0.8, 0.25), (0, 1.15, 0.45), anim="tail", rotation=(math.radians(20), 0, 0))  # tail off the coil


def hydra(a):
    # A hydra: one teal body, three necks, three horned heads — cut one off and two more glare at you
    a.legs(0.42, 0.46, -0.6, 0.65, 0.6)
    a.block("body", (1.35, 2.1, 1.1), (0, 0.15, 1.1), studs=True)
    a.block("belly", (0.9, 1.5, 0.12), (0, 0.1, 0.62))
    for y in (-0.5, 0.1, 0.7):
        a.block("spike", (0.16, 0.2, 0.3), (0, y, 1.78))  # back spikes
    for nx, nz in ((0, 2.0), (-0.55, 1.75), (0.55, 1.75)):
        a.block("body", (0.42, 0.42, 0.85), (nx, -0.95, nz))  # a neck
        hy = nz + 0.55
        a.block("body", (0.62, 0.75, 0.52), (nx, -1.3, hy), studs=True)  # its head
        a.block("belly", (0.42, 0.35, 0.26), (nx, -1.7, hy - 0.16))  # its snout
        for s in (-1, 1):
            a.block("teeth", (0.07, 0.05, 0.12), (nx + 0.11 * s, -1.82, hy - 0.3))
            a.block("horn", (0.1, 0.1, 0.35), (nx + 0.2 * s, -1.22, hy + 0.38), rotation=(math.radians(20), math.radians(12 * s), 0))
            a.block("eye", (0.12, 0.05, 0.14), (nx + 0.16 * s, -1.69, hy + 0.05))
            a.block("shine", (0.05, 0.03, 0.05), (nx + 0.16 * s - 0.03, -1.73, hy + 0.1))
    a.block("body", (0.32, 0.95, 0.32), (0, 1.35, 1.1), anim="tail", rotation=(math.radians(-15), 0, 0))
    a.block("spike", (0.14, 0.5, 0.14), (0, 1.75, 1.32), anim="tail", rotation=(math.radians(-30), 0, 0))  # tail spike


def puffin(a):
    # A puffin: a little black-and-white clown of the cliffs, with a beak painted like a sunset
    a.pair("feet", (0.3, 0.4, 0.12), (0.24, -0.15, 0.06))
    a.block("body", (0.95, 0.85, 1.25), (0, 0.05, 0.82), studs=True)
    a.block("belly", (0.65, 0.1, 0.9), (0, -0.4, 0.78))
    a.pair("body", (0.13, 0.5, 0.65), (0.53, 0.05, 0.82), anim="wing")  # flippers
    a.block("body", (0.64, 0.56, 0.56), (0, -0.05, 1.68), studs=True)  # head
    a.block("belly", (0.5, 0.08, 0.44), (0, -0.34, 1.62))  # white face
    a.block("beak", (0.3, 0.34, 0.3), (0, -0.44, 1.5))  # the great beak
    a.block("beak2", (0.32, 0.12, 0.32), (0, -0.45, 1.62))  # its red band
    a.eyes(0.15, -0.38, 1.74, size=0.11)
    a.block("body", (0.3, 0.28, 0.16), (0, 0.52, 0.6), anim="tail", rotation=(math.radians(25), 0, 0))


def otter(a):
    # An otter: a long brown ribbon of a body, whiskers everywhere, paws held ready for a stone
    a.legs(0.26, 0.3, -0.55, 0.6, 0.35)
    a.block("body", (0.95, 1.9, 0.6), (0, 0.1, 0.68), studs=True)
    a.block("belly", (0.6, 1.3, 0.1), (0, 0.05, 0.4))
    a.block("body", (0.68, 0.6, 0.55), (0, -0.95, 0.85), studs=True)  # head
    a.block("belly", (0.44, 0.28, 0.26), (0, -1.28, 0.72))  # muzzle
    a.block("nose", (0.18, 0.09, 0.11), (0, -1.44, 0.78))
    a.eyes(0.18, -1.26, 0.95, size=0.13)
    a.pair("whisker", (0.2, 0.03, 0.03), (0.28, -1.4, 0.74), rotation=(0, math.radians(-25), 0))  # whiskers
    a.pair("body", (0.16, 0.12, 0.16), (0.28, -0.9, 1.16))  # ears
    a.block("body", (0.34, 0.95, 0.3), (0, 1.25, 0.6), anim="tail", rotation=(math.radians(-12), 0, 0))  # the long tail


def snowleopard(a):
    # A snow leopard: a ghost-pale cat with grey rosettes and a tail thick as a scarf
    a.legs(0.36, 0.4, -0.55, 0.6, 0.6)
    a.block("body", (1.1, 1.85, 0.92), (0, 0.05, 1.02), studs=True)
    a.block("belly", (0.7, 0.12, 0.6), (0, -0.85, 0.95))
    a.pair("spot", (0.06, 0.22, 0.22), (0.57, -0.1, 1.2))
    a.block("spot", (0.22, 0.22, 0.06), (0.25, 0.3, 1.49))
    a.block("spot", (0.2, 0.2, 0.06), (-0.3, -0.35, 1.49))
    a.block("body", (1.1, 0.9, 0.9), (0, -0.92, 1.72), studs=True)  # head
    a.block("belly", (0.55, 0.42, 0.35), (0, -1.42, 1.52))  # muzzle
    a.block("nose", (0.18, 0.09, 0.12), (0, -1.62, 1.62))
    a.eyes(0.27, -1.38, 1.88, size=0.2)
    a.pair("body", (0.28, 0.18, 0.3), (0.4, -0.88, 2.22))  # round ears
    a.block("body", (0.34, 0.34, 1.0), (0, 1.05, 1.35), anim="tail", rotation=(math.radians(-20), 0, 0))
    a.block("spot", (0.2, 0.2, 0.08), (0.08, 1.3, 1.72), anim="tail")  # a spot on its tail


def polarbear(a):
    # A polar bear: the white giant of the ice — all bear, but bigger, with a black nose on the snow
    a.legs(0.58, 0.55, -0.68, 0.72, 0.7)
    a.block("body", (1.65, 2.05, 1.3), (0, 0.05, 1.32), studs=True)
    a.block("belly", (1.3, 0.12, 0.95), (0, -1.0, 1.2))
    a.block("body", (1.5, 1.25, 1.3), (0, -1.05, 2.22), studs=True)  # head
    a.block("belly", (0.78, 0.45, 0.52), (0, -1.82, 1.96))  # muzzle
    a.block("nose", (0.34, 0.13, 0.22), (0, -2.06, 2.12))
    a.block("mouth", (0.3, 0.04, 0.06), (0, -2.05, 1.8))
    a.eyes(0.37, -1.7, 2.45, size=0.24)
    a.pair("body", (0.4, 0.26, 0.38), (0.57, -1.0, 3.0))  # ears
    a.pair("ear_inner", (0.22, 0.06, 0.2), (0.57, -1.14, 2.97))
    a.block("body", (0.32, 0.28, 0.32), (0, 1.15, 1.5), anim="tail")


def sabertooth(a):
    # A sabertooth: a sandy hunting cat whose two great fangs hang below its chin
    a.legs(0.4, 0.44, -0.6, 0.65, 0.68)
    a.block("body", (1.2, 1.95, 1.0), (0, 0.05, 1.1), studs=True)
    a.block("belly", (0.75, 0.12, 0.65), (0, -0.92, 1.0))
    a.pair("spot", (0.06, 0.24, 0.24), (0.62, 0.2, 1.25))
    a.block("body", (1.2, 1.0, 1.0), (0, -1.0, 1.85), studs=True)  # head
    a.block("belly", (0.62, 0.5, 0.42), (0, -1.6, 1.64))  # muzzle
    a.block("nose", (0.24, 0.12, 0.16), (0, -1.84, 1.76))
    a.pair("fang", (0.11, 0.09, 0.55), (0.2, -1.78, 1.3))  # the sabers
    a.eyes(0.3, -1.52, 2.0, size=0.21)
    a.pair("body", (0.3, 0.2, 0.4), (0.42, -0.95, 2.42))  # ears
    a.block("body", (0.26, 0.26, 0.45), (0, 1.08, 1.35), anim="tail", rotation=(math.radians(-25), 0, 0))  # short tail


def mammoth(a):
    # A mammoth: a shaggy mountain with a trunk to the ground and tusks curving like moons
    a.legs(0.55, 0.55, -0.65, 0.7, 0.8)
    a.block("fur", (1.6, 2.2, 0.8), (0, 0.05, 0.9))  # shaggy skirt
    a.block("body", (1.55, 2.15, 1.25), (0, 0.05, 1.65), studs=True)
    a.block("body", (1.1, 0.8, 0.5), (0, -0.55, 2.35))  # dome hump
    a.block("body", (0.95, 0.9, 0.95), (0, -1.15, 2.2), studs=True)  # head
    a.block("fur", (0.5, 0.35, 1.15), (0, -1.75, 1.55))  # trunk, hanging down
    a.block("fur", (0.44, 0.32, 0.4), (0, -1.85, 0.95))  # trunk's end, curling
    a.pair("tusk", (0.14, 0.5, 0.14), (0.48, -1.7, 1.5), rotation=(math.radians(-35), 0, 0))  # tusks sweeping out
    a.pair("tusk", (0.13, 0.13, 0.55), (0.62, -1.95, 1.85), rotation=(math.radians(-20), math.radians(20), 0))  # and up
    a.eyes(0.34, -1.62, 2.35, size=0.17)
    a.pair("body", (0.3, 0.16, 0.3), (0.55, -1.1, 2.62))  # small ears in the fur
    a.block("fur", (0.3, 0.3, 0.55), (0, 1.2, 1.6), anim="tail", rotation=(math.radians(-20), 0, 0))


def frostwolf(a):
    # A frost wolf: the wolf of the endless winter, ice crystals growing from its back, eyes like cold stars
    a.legs(0.36, 0.4, -0.6, 0.65, 0.65)
    a.block("body", (1.2, 1.95, 1.0), (0, 0.05, 1.1), studs=True)
    a.block("belly", (1.3, 0.35, 0.9), (0, -0.72, 1.75))  # ruff
    a.block("belly", (0.8, 0.12, 0.65), (0, -0.94, 1.02))  # chest
    a.pair("crystal", (0.16, 0.16, 0.42), (0.3, 0.15, 1.72), rotation=(0, math.radians(-15), 0))  # back crystals
    a.block("crystal", (0.18, 0.18, 0.5), (0, -0.3, 1.75))
    a.block("body", (1.25, 1.0, 1.0), (0, -1.0, 1.85), studs=True)  # head
    a.block("belly", (0.6, 0.5, 0.4), (0, -1.62, 1.62))  # muzzle
    a.block("nose", (0.26, 0.14, 0.18), (0, -1.88, 1.72))
    a.eyes(0.32, -1.52, 2.0, size=0.22)
    a.pair("body", (0.3, 0.2, 0.4), (0.42, -0.95, 2.45))  # ears
    a.pair("crystal", (0.12, 0.12, 0.3), (0.42, -0.95, 2.68))  # crystal ear tips
    a.block("body", (0.35, 0.35, 0.9), (0, 1.1, 1.5), anim="tail", rotation=(math.radians(-20), 0, 0))


def frostdragon(a):
    # A frost dragon: the cave dragon's white-blue cousin, horns and spines of living ice
    a.legs(0.38, 0.42, -0.6, 0.65, 0.65)
    a.block("body", (1.2, 2.0, 1.05), (0, 0.1, 1.12), studs=True)
    a.block("belly", (0.8, 1.5, 0.12), (0, 0.05, 0.62))
    for y in (-0.55, 0.05, 0.65):
        a.block("crystal", (0.18, 0.22, 0.36), (0, y, 1.78))  # ice spines
    a.block("body", (0.65, 0.55, 0.85), (0, -1.0, 1.75))  # neck
    a.block("body", (0.85, 1.0, 0.7), (0, -1.45, 2.3), studs=True)  # head
    a.block("belly", (0.6, 0.45, 0.35), (0, -2.0, 2.12))  # snout
    a.pair("nose", (0.09, 0.06, 0.09), (0.14, -2.24, 2.22))
    a.pair("teeth", (0.08, 0.05, 0.14), (0.2, -2.2, 1.95))
    a.eyes(0.3, -1.97, 2.42, size=0.18)
    a.pair("crystal", (0.14, 0.14, 0.55), (0.3, -1.3, 2.88), rotation=(math.radians(20), math.radians(15), 0))  # ice horns
    a.pair("wing", (0.9, 0.7, 0.08), (0.75, -0.25, 1.85), anim="wing", rotation=(0, math.radians(-30), math.radians(12)))
    a.pair("wing", (0.65, 0.5, 0.08), (0.62, 0.3, 1.6), anim="wing", rotation=(0, math.radians(-30), math.radians(-8)))
    a.block("body", (0.3, 0.9, 0.3), (0, 1.25, 1.15), anim="tail", rotation=(math.radians(-15), 0, 0))
    a.block("crystal", (0.45, 0.35, 0.12), (0, 1.72, 1.32), anim="tail", rotation=(math.radians(-15), 0, 0))  # ice spade tip


def mouse(a):
    # A mouse: a small grey bundle with ears like coins, a twitching nose and a tail like pink string
    a.legs(0.2, 0.26, -0.3, 0.35, 0.3)
    a.block("body", (0.95, 1.2, 0.7), (0, 0.1, 0.6), studs=True)
    a.block("belly", (0.65, 0.1, 0.45), (0, -0.55, 0.52))
    a.block("glow", (0.16, 0.16, 0.06), (0, 0.25, 0.97))  # one stray pixel on its back
    a.block("body", (0.68, 0.55, 0.52), (0, -0.68, 0.85), studs=True)  # head
    a.block("belly", (0.4, 0.28, 0.24), (0, -1.0, 0.72))  # muzzle
    a.block("nose", (0.15, 0.08, 0.1), (0, -1.16, 0.78))
    a.eyes(0.18, -0.97, 0.94, size=0.13)
    a.pair("body", (0.3, 0.12, 0.3), (0.3, -0.6, 1.14))  # round ears
    a.pair("ear_inner", (0.18, 0.05, 0.18), (0.3, -0.67, 1.13))
    a.block("tail", (0.09, 0.85, 0.09), (0, 0.85, 0.45), anim="tail", rotation=(math.radians(45), 0, 0))  # the string tail


def bot(a):
    # A bot: a friendly little robot, a screen for a face, one antenna, and arms that end in claws
    a.pair("legs", (0.4, 0.5, 0.3), (0.3, 0, 0.15), anim="leg")  # tread feet
    a.block("body", (1.15, 1.0, 1.05), (0, 0, 0.85), studs=True)
    a.block("screen", (0.85, 0.08, 0.6), (0, -0.52, 0.95))  # chest screen
    a.block("glow", (0.2, 0.05, 0.2), (-0.2, -0.57, 0.95))  # a light on it
    a.pair("metal", (0.2, 0.2, 0.7), (0.68, 0, 0.85))  # arms
    a.pair("metal", (0.26, 0.26, 0.2), (0.68, 0, 0.42))  # claw hands
    a.block("body", (0.95, 0.85, 0.8), (0, 0, 1.8), studs=True)  # head
    a.block("screen", (0.7, 0.06, 0.45), (0, -0.44, 1.82))  # face screen
    a.pair("glow", (0.14, 0.04, 0.18), (0.18, -0.48, 1.86))  # screen eyes
    a.block("metal", (0.08, 0.08, 0.4), (0, 0, 2.4))  # antenna
    a.block("glow", (0.16, 0.16, 0.16), (0, 0, 2.66))
    a.pair("metal", (0.3, 0.14, 0.3), (0.5, 0, 2.05))  # ear dials


def drone(a):
    # A drone: it never lands — four rotors over a camera body, one great glowing eye always watching
    a.pair("metal", (0.5, 0.14, 0.1), (0.35, -0.35, 0.55))  # landing skids
    a.pair("metal", (0.14, 0.5, 0.1), (0.35, 0.0, 0.55))
    a.block("body", (1.05, 1.05, 0.55), (0, 0, 0.95), studs=True)
    a.block("screen", (0.6, 0.08, 0.4), (0, -0.54, 0.95))
    a.block("glow", (0.3, 0.06, 0.3), (0, -0.57, 0.95))  # the great eye
    a.block("shine", (0.1, 0.03, 0.1), (-0.07, -0.6, 1.02))
    a.block("metal", (1.7, 0.14, 0.08), (0, 0, 1.3))  # rotor arms
    a.block("metal", (0.14, 1.7, 0.08), (0, 0, 1.3))
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.block("metal", (0.3, 0.3, 0.14), (0.62 * sx, 0.62 * sy, 1.36))  # a motor
            a.block("rotor", (0.85, 0.16, 0.04), (0.62 * sx, 0.62 * sy, 1.5), anim="wing")  # its rotors
            a.block("rotor", (0.16, 0.85, 0.04), (0.62 * sx, 0.62 * sy, 1.5), anim="wing")


def sprite(a):
    # A sprite: a little being made of light and pixels, wings of squares, always slightly not-there
    a.pair("glow", (0.14, 0.14, 0.3), (0.2, 0, 0.35), anim="leg")  # dangly light legs
    a.block("body", (0.7, 0.65, 0.75), (0, 0, 0.85), studs=True)
    a.block("glow", (0.3, 0.08, 0.3), (0, -0.34, 0.85))  # its heart-light
    a.pair("wing", (0.4, 0.3, 0.06), (0.5, 0.15, 1.25), anim="wing", rotation=(0, math.radians(-25), math.radians(12)))
    a.pair("wing", (0.28, 0.22, 0.06), (0.42, 0.28, 1.02), anim="wing", rotation=(0, math.radians(-25), math.radians(-10)))
    a.block("body", (0.72, 0.65, 0.68), (0, 0, 1.55), studs=True)  # head
    a.eyes(0.18, -0.34, 1.62, size=0.16)
    a.pair("body", (0.12, 0.1, 0.3), (0.24, 0, 2.0), rotation=(0, math.radians(10), 0))  # pixel ears
    a.block("glow", (0.14, 0.14, 0.14), (0.55, -0.3, 1.9))  # stray pixels round it
    a.block("glow", (0.1, 0.1, 0.1), (-0.6, 0.35, 1.15))


def glitch(a):
    # A glitch: a creature that isn't rendered quite right — slices offset, one eye wrong, pieces adrift
    a.pair("legs", (0.36, 0.44, 0.28), (0.3, 0.05, 0.14), anim="leg")
    a.block("body", (1.1, 0.95, 0.5), (0, 0, 0.62), studs=True)
    a.block("body", (1.1, 0.95, 0.45), (0.14, 0, 1.05), studs=True)  # top half, slipped sideways
    a.block("stripe", (1.12, 0.97, 0.1), (0.05, 0, 0.86))  # the tear between the halves
    a.block("screen", (0.8, 0.07, 0.55), (0.05, -0.5, 0.82))  # its face
    a.block("glow", (0.2, 0.05, 0.24), (-0.18, -0.54, 0.88))  # one big eye
    a.block("glow", (0.1, 0.05, 0.12), (0.24, -0.54, 0.8))  # one small, and lower
    a.block("metal", (0.18, 0.18, 0.55), (-0.66, 0.1, 0.85))  # arms, not level with each other
    a.block("metal", (0.18, 0.18, 0.55), (0.66, 0.1, 0.68))
    a.block("metal", (0.07, 0.07, 0.35), (-0.3, -0.1, 1.55), rotation=(math.radians(-15), 0, 0))  # bent antenna
    a.block("glow", (0.13, 0.13, 0.13), (-0.36, -0.16, 1.76))
    a.block("body", (0.2, 0.2, 0.2), (0.75, -0.4, 1.5))  # adrift cubes
    a.block("stripe", (0.14, 0.14, 0.14), (-0.72, 0.3, 1.2))


def mecha(a):
    # A mecha: a small walking fortress — shoulder guards, a visor of light, and a core burning in its chest
    a.pair("legs", (0.5, 0.65, 0.35), (0.38, 0, 0.18), anim="leg")  # tread feet
    a.block("body", (1.35, 1.1, 1.15), (0, 0, 1.0), studs=True)
    a.block("glow", (0.34, 0.1, 0.34), (0, -0.57, 1.05))  # chest core
    a.pair("metal", (0.55, 0.6, 0.35), (0.85, 0, 1.62))  # shoulder guards
    a.pair("metal", (0.28, 0.28, 0.75), (0.85, 0, 1.05))  # arms
    a.pair("metal", (0.32, 0.32, 0.25), (0.85, 0, 0.6))  # fists
    a.block("body", (1.0, 0.9, 0.8), (0, 0, 2.0), studs=True)  # head
    a.block("screen", (0.85, 0.07, 0.3), (0, -0.47, 2.05))  # visor
    a.pair("glow", (0.16, 0.04, 0.16), (0.2, -0.51, 2.05))  # visor eyes
    a.pair("horn", (0.12, 0.12, 0.45), (0.35, 0, 2.55), rotation=(math.radians(15), math.radians(12), 0))  # horn antennae
    a.block("metal", (0.5, 0.3, 0.5), (0, 0.62, 1.15))  # backpack


def quantum(a):
    # A quantum: a glowing core that is in several places at once, cubes orbiting it like slow moons
    a.block("glow", (0.2, 0.2, 0.35), (0, 0, 0.42), anim="leg")  # its one foot on the ground, maybe
    a.block("body", (0.95, 0.95, 0.95), (0, 0, 1.15), studs=True)  # the core cube
    a.block("glow", (0.5, 0.5, 0.5), (0, 0, 1.15))  # the burning heart of it
    a.block("screen", (0.6, 0.06, 0.4), (0, -0.49, 1.2))  # its face
    a.pair("glow", (0.13, 0.04, 0.16), (0.16, -0.53, 1.24))  # eyes
    for x, y, z, r in ((0.85, -0.3, 1.6, 0.22), (-0.9, 0.2, 1.35, 0.18), (0.5, 0.75, 1.0, 0.15), (-0.55, -0.7, 0.95, 0.13), (0.1, -0.95, 1.5, 0.12)):
        a.block("body", (r, r, r), (x, y, z))  # orbiting cubes
    a.block("ring", (0.95, 0.09, 0.1), (0, -0.43, 1.98))  # the ring over it
    a.block("ring", (0.95, 0.09, 0.1), (0, 0.43, 1.98))
    a.pair("ring", (0.09, 0.78, 0.1), (0.43, 0, 1.98))


def mainframe(a):
    # The Mainframe: a walking server tower, racks of lights down its front, an aerial farm on its head
    a.pair("legs", (0.55, 0.7, 0.3), (0.42, 0, 0.15), anim="leg")  # cabinet feet
    a.block("body", (1.5, 1.05, 1.9), (0, 0, 1.25), studs=True)  # the tower
    for z in (0.75, 1.15, 1.55):
        a.block("stripe", (1.3, 0.06, 0.08), (0, -0.54, z))  # rack seams
    a.pair("glow", (0.12, 0.04, 0.12), (0.5, -0.56, 0.95))  # status lights
    a.block("glow", (0.12, 0.04, 0.12), (-0.5, -0.56, 1.35))
    a.block("glow", (0.12, 0.04, 0.12), (0.28, -0.56, 1.75))
    a.block("screen", (0.95, 0.07, 0.55), (0, -0.54, 1.95))  # its face, high on the tower
    a.pair("glow", (0.15, 0.04, 0.18), (0.2, -0.58, 1.98))  # eyes in the screen
    a.block("metal", (0.07, 0.07, 0.55), (-0.5, 0, 2.45))  # aerials
    a.block("metal", (0.07, 0.07, 0.75), (0.1, 0.1, 2.55))
    a.block("metal", (0.07, 0.07, 0.45), (0.55, -0.1, 2.4))
    a.block("glow", (0.12, 0.12, 0.12), (-0.5, 0, 2.76))
    a.block("glow", (0.12, 0.12, 0.12), (0.1, 0.1, 2.95))
    a.block("glow", (0.12, 0.12, 0.12), (0.55, -0.1, 2.66))
    a.pair("metal", (0.22, 0.22, 0.9), (0.86, 0, 1.1))  # side vents
    a.block("cable", (0.14, 0.7, 0.14), (0.3, 0.85, 0.7), anim="tail", rotation=(math.radians(40), 0, 0))  # a loose cable


def unicorn(a):
    # A unicorn: a white horse with a spiral horn of gold and a mane like poured rainbow
    a.legs(0.32, 0.38, -0.7, 0.72, 0.95)
    a.block("body", (1.1, 2.2, 0.95), (0, 0.05, 1.42), studs=True)
    a.block("body", (0.7, 0.55, 0.95), (0, -1.0, 2.15))  # neck
    a.block("body", (0.78, 1.15, 0.68), (0, -1.5, 2.8), studs=True)  # head
    a.block("belly", (0.3, 0.04, 0.5), (0, -2.1, 2.75))  # blaze
    a.block("nose", (0.6, 0.3, 0.3), (0, -1.98, 2.58))
    a.block("horn", (0.2, 0.2, 0.35), (0, -1.62, 3.28), rotation=(math.radians(-18), 0, 0))  # the horn, in rings
    a.block("horn", (0.15, 0.15, 0.3), (0, -1.72, 3.55), rotation=(math.radians(-18), 0, 0))
    a.block("horn", (0.1, 0.1, 0.25), (0, -1.8, 3.78), rotation=(math.radians(-18), 0, 0))
    a.block("mane", (0.2, 0.7, 0.45), (0, -0.78, 2.62))  # mane, pink then blue down the neck
    a.block("mane2", (0.2, 0.6, 0.4), (0, -0.7, 2.24))
    a.block("mane", (0.2, 0.55, 0.35), (0, -0.6, 1.9))
    for s in (-1, 1):
        a.block("body", (0.17, 0.15, 0.34), (0.27 * s, -1.22, 3.28))  # ears
    a.eyes(0.41, -1.88, 2.95, size=0.17)
    a.block("mane2", (0.26, 0.26, 0.9), (0, 1.28, 1.5), anim="tail", rotation=(math.radians(-18), 0, 0))  # flowing tail
    a.block("mane", (0.22, 0.22, 0.5), (0, 1.42, 2.05), anim="tail", rotation=(math.radians(-18), 0, 0))
    for y in (-0.7, 0.72):
        a.pair("hoof", (0.34, 0.34, 0.14), (0.38, y, 0.07))


def pegasus(a):
    # A pegasus: a pale horse whose wings could carry it over the weather, feather over feather
    a.legs(0.32, 0.38, -0.7, 0.72, 0.95)
    a.block("body", (1.1, 2.2, 0.95), (0, 0.05, 1.42), studs=True)
    a.block("body", (0.7, 0.55, 0.95), (0, -1.0, 2.15))  # neck
    a.block("body", (0.78, 1.15, 0.68), (0, -1.5, 2.8), studs=True)  # head
    a.block("nose", (0.6, 0.3, 0.3), (0, -1.98, 2.58))
    a.pair("wing", (0.75, 0.6, 0.09), (0.68, -0.3, 2.2), anim="wing", rotation=(0, math.radians(-35), math.radians(15)))  # wings, in layers
    a.pair("wing", (0.6, 0.5, 0.09), (0.6, 0.25, 2.0), anim="wing", rotation=(0, math.radians(-35), math.radians(-5)))
    a.pair("wing", (0.45, 0.4, 0.09), (0.52, 0.7, 1.78), anim="wing", rotation=(0, math.radians(-35), math.radians(-20)))
    a.block("mane", (0.2, 0.8, 0.5), (0, -0.8, 2.5))
    a.block("mane", (0.2, 0.6, 0.4), (0, -0.65, 2.1))
    for s in (-1, 1):
        a.block("body", (0.17, 0.15, 0.34), (0.27 * s, -1.22, 3.28))  # ears
    a.eyes(0.41, -1.88, 2.95, size=0.17)
    a.block("mane", (0.24, 0.24, 0.85), (0, 1.28, 1.45), anim="tail", rotation=(math.radians(-18), 0, 0))
    for y in (-0.7, 0.72):
        a.pair("hoof", (0.34, 0.34, 0.14), (0.38, y, 0.07))


def griffin(a):
    # A griffin: an eagle's white head and great wings on a lion's tawny body, and not a feather of it tame
    a.legs(0.36, 0.4, -0.6, 0.65, 0.7)
    a.block("body", (1.15, 2.0, 1.0), (0, 0.08, 1.12), studs=True)
    a.block("belly", (0.75, 0.12, 0.6), (0, -0.9, 1.05))  # feathered chest
    a.block("belly", (0.85, 0.8, 0.78), (0, -1.05, 1.95), studs=True)  # eagle head
    a.block("beak", (0.34, 0.4, 0.26), (0, -1.6, 1.88))  # hooked beak
    a.block("beak", (0.28, 0.2, 0.2), (0, -1.66, 1.68), rotation=(math.radians(30), 0, 0))
    a.eyes(0.26, -1.47, 2.08, size=0.18)
    a.pair("belly", (0.22, 0.16, 0.4), (0.36, -1.0, 2.42), rotation=(0, math.radians(12), 0))  # ear tufts
    a.pair("wing", (0.85, 0.65, 0.09), (0.7, -0.2, 1.9), anim="wing", rotation=(0, math.radians(-30), math.radians(12)))
    a.pair("wing", (0.65, 0.5, 0.09), (0.62, 0.35, 1.68), anim="wing", rotation=(0, math.radians(-30), math.radians(-8)))
    a.block("body", (0.22, 0.22, 0.8), (0, 1.15, 1.4), anim="tail", rotation=(math.radians(-22), 0, 0))  # lion tail
    a.block("mane", (0.3, 0.3, 0.3), (0, 1.34, 1.95), anim="tail")  # its tuft


def kitsune(a):
    # A kitsune: a white fox of many tails — three already, each tipped with fire-red, and more coming
    a.legs(0.32, 0.36, -0.55, 0.6, 0.6)
    a.block("body", (1.05, 1.8, 0.9), (0, 0.05, 1.02), studs=True)
    a.block("belly", (0.65, 0.14, 0.62), (0, -0.86, 0.95))  # chest
    a.block("body", (1.12, 0.92, 0.92), (0, -0.95, 1.72), studs=True)  # head
    a.block("belly", (0.52, 0.42, 0.34), (0, -1.48, 1.52))  # muzzle
    a.block("nose", (0.2, 0.1, 0.14), (0, -1.7, 1.62))
    a.eyes(0.28, -1.42, 1.88, size=0.2)
    a.pair("mark", (0.16, 0.05, 0.16), (0.3, -1.42, 2.12))  # red marks over its eyes
    for s in (-1, 1):
        a.block("body", (0.32, 0.22, 0.48), (0.38 * s, -0.9, 2.36), rotation=(0, math.radians(14 * s), 0))
        a.block("mark", (0.2, 0.14, 0.18), (0.38 * s, -0.9, 2.64), rotation=(0, math.radians(14 * s), 0))  # red ear tips
    for dx, rz in ((0, 0), (-0.42, 18), (0.42, -18)):
        a.block("body", (0.34, 0.34, 0.95), (dx, 1.05, 1.5), anim="tail", rotation=(math.radians(-25), 0, math.radians(rz)))
        a.block("mark", (0.36, 0.36, 0.32), (dx * 1.15, 1.28, 2.05), anim="tail", rotation=(math.radians(-25), 0, math.radians(rz)))  # red tail tips


def chimera(a):
    # A chimera: a lion in front, a goat's head rearing from its back, and a snake for a tail
    a.legs(0.4, 0.44, -0.6, 0.65, 0.7)
    a.block("body", (1.2, 2.0, 1.05), (0, 0.1, 1.15), studs=True)
    a.block("belly", (0.8, 1.4, 0.12), (0, 0.05, 0.68))
    a.block("mane", (1.5, 0.8, 1.45), (0, -0.85, 1.85))  # lion mane
    a.block("body", (0.92, 0.72, 0.88), (0, -1.05, 1.85), studs=True)  # lion face
    a.block("belly", (0.52, 0.38, 0.34), (0, -1.48, 1.62))  # muzzle
    a.block("nose", (0.22, 0.11, 0.13), (0, -1.7, 1.72))
    a.pair("teeth", (0.08, 0.05, 0.14), (0.18, -1.64, 1.45))  # lion fangs
    a.eyes(0.25, -1.42, 2.0, size=0.19)
    a.block("goat", (0.4, 0.4, 0.7), (0, -0.15, 2.3), rotation=(math.radians(15), 0, 0))  # goat neck from the back
    a.block("goat", (0.55, 0.6, 0.5), (0, -0.28, 2.85), studs=True)  # goat head
    a.block("goat", (0.36, 0.3, 0.26), (0, -0.62, 2.72))  # goat muzzle
    a.block("nose", (0.16, 0.09, 0.1), (0, -0.8, 2.78))
    a.pair("horn", (0.11, 0.11, 0.42), (0.2, -0.22, 3.2), rotation=(math.radians(30), math.radians(10), 0))  # goat horns
    a.pair("eye", (0.11, 0.05, 0.12), (0.16, -0.56, 2.92))  # goat eyes
    a.block("goat", (0.2, 0.12, 0.3), (0, -0.45, 2.45))  # goat beard
    a.block("snake", (0.24, 0.8, 0.24), (0, 1.25, 1.45), anim="tail", rotation=(math.radians(-20), 0, 0))  # snake tail
    a.block("snake", (0.34, 0.3, 0.28), (0, 1.55, 1.95), anim="tail", rotation=(math.radians(-20), 0, 0))  # snake head
    a.pair("eye", (0.08, 0.04, 0.09), (0.09, 1.42, 2.06), anim="tail")
    a.block("tongue", (0.05, 0.22, 0.03), (0, 1.68, 1.78), anim="tail", rotation=(math.radians(-35), 0, 0))


def kraken(a):
    # A kraken: an octopus the size of a ship's nightmare — eight tentacles, and eyes that have seen the deep
    a.block("body", (1.5, 1.5, 1.25), (0, 0, 1.05), studs=True)
    a.block("body", (1.15, 1.15, 0.5), (0, 0, 1.85))
    a.block("belly", (1.0, 0.12, 0.7), (0, -0.72, 0.95))
    a.eyes(0.33, -0.77, 1.18, size=0.23)
    a.pair("body", (0.4, 0.08, 0.14), (0.33, -0.76, 1.48), rotation=(0, 0, math.radians(-18)))  # its heavy brow
    a.block("spot", (0.2, 0.06, 0.12), (0, -0.76, 0.78))  # mouth
    a.pair("spot", (0.22, 0.22, 0.09), (0.42, -0.62, 1.55))
    a.block("spot", (0.24, 0.24, 0.09), (-0.24, 0.24, 2.12))
    for x, y in ((-0.55, -0.45), (-0.18, -0.62), (0.18, -0.62), (0.55, -0.45), (-0.68, 0.2), (0.68, 0.2), (-0.4, 0.6), (0.4, 0.6)):
        a.block("legs", (0.34, 0.48, 0.4), (x, y, 0.2), anim="leg")
        if y < 0:
            a.block("legs", (0.3, 0.34, 0.22), (x, y - 0.24, 0.11), anim="leg")  # curled tips in front
            a.block("belly", (0.16, 0.16, 0.08), (x, y - 0.3, 0.24), anim="leg")  # a sucker


def leviathan(a):
    # A leviathan: a sea serpent long as a river, horned and finned, riding its own dark wave
    a.block("fin", (1.8, 3.4, 0.22), (0, 0.15, 0.11))  # its wave
    a.block("body", (1.25, 2.9, 1.1), (0, 0.2, 0.85), studs=True)
    a.block("belly", (0.9, 2.2, 0.15), (0, 0.15, 0.32))
    for y in (-0.7, 0.0, 0.7):
        a.block("fin", (0.16, 0.22, 0.5), (0, y, 1.55), rotation=(math.radians(-12), 0, 0))  # dorsal spines
    a.block("body", (0.9, 0.85, 0.75), (0, -1.6, 1.0), studs=True)  # head
    a.block("body", (0.66, 0.5, 0.45), (0, -2.15, 0.82))  # jaw snout
    a.block("teeth", (0.5, 0.07, 0.16), (0, -2.38, 0.92))
    a.pair("eye", (0.14, 0.06, 0.16), (0.47, -1.85, 1.12))
    a.pair("shine", (0.05, 0.03, 0.05), (0.48, -1.88, 1.17))
    a.pair("horn", (0.13, 0.13, 0.5), (0.3, -1.5, 1.55), rotation=(math.radians(25), math.radians(15), 0))  # horns
    a.pair("fin", (0.6, 0.4, 0.1), (0.75, -0.9, 0.55), anim="wing", rotation=(0, math.radians(25), math.radians(-15)))  # pectoral fins
    a.block("body", (0.5, 0.7, 0.45), (0, 1.75, 0.9))
    a.block("fin", (1.3, 0.45, 0.12), (0, 2.2, 0.98), anim="tail")  # the great fluke


def elderdragon(a):
    # An elder dragon: the oldest fire of all, purple as dusk, crowned with horns, its belly plated in gold
    a.legs(0.45, 0.5, -0.65, 0.7, 0.75)
    a.block("body", (1.4, 2.3, 1.2), (0, 0.1, 1.25), studs=True)
    a.block("gold", (0.9, 1.7, 0.13), (0, 0.05, 0.68))  # gold belly plates
    for y in (-0.6, 0.05, 0.7):
        a.block("spike", (0.2, 0.24, 0.38), (0, y, 1.95))  # back spikes
    a.block("body", (0.75, 0.6, 0.95), (0, -1.05, 1.9))  # neck
    a.block("body", (0.98, 1.1, 0.8), (0, -1.55, 2.5), studs=True)  # head
    a.block("belly", (0.68, 0.5, 0.4), (0, -2.18, 2.3))  # snout
    a.pair("nose", (0.1, 0.06, 0.1), (0.16, -2.44, 2.4))
    a.pair("teeth", (0.09, 0.05, 0.16), (0.22, -2.4, 2.12))
    a.block("beard", (0.3, 0.14, 0.45), (0, -2.05, 1.95))  # a wise white beard
    a.eyes(0.34, -2.16, 2.62, size=0.2)
    a.pair("horn", (0.16, 0.16, 0.65), (0.34, -1.4, 3.05), rotation=(math.radians(22), math.radians(18), 0))  # great horns
    a.pair("horn", (0.12, 0.12, 0.45), (0.14, -1.35, 3.1), rotation=(math.radians(28), math.radians(-8), 0))  # crown horns
    a.pair("wing", (1.05, 0.8, 0.09), (0.85, -0.3, 2.05), anim="wing", rotation=(0, math.radians(-32), math.radians(12)))
    a.pair("wing", (0.75, 0.55, 0.09), (0.7, 0.35, 1.78), anim="wing", rotation=(0, math.radians(-32), math.radians(-8)))
    a.block("body", (0.34, 1.0, 0.34), (0, 1.35, 1.3), anim="tail", rotation=(math.radians(-15), 0, 0))
    a.block("gold", (0.5, 0.4, 0.13), (0, 1.85, 1.5), anim="tail", rotation=(math.radians(-15), 0, 0))  # gold spade tip


ANIMALS = {
    "dog": dog, "cat": cat, "bunny": bunny, "bear": bear, "chicken": chicken, "pig": pig, "sheep": sheep, "horse": horse,
    "bee": bee, "ladybug": ladybug, "butterfly": butterfly, "snail": snail, "frog": frog, "duckling": duckling, "fox": fox, "deer": deer,
    "squirrel": squirrel, "hedgehog": hedgehog, "owl": owl, "raccoon": raccoon, "wolf": wolf, "moose": moose, "lynx": lynx, "stag": stag,
    "crab": crab, "starfish": starfish, "turtle": turtle, "seagull": seagull, "octopus": octopus, "dolphin": dolphin, "shark": shark, "whale": whale,
    "bat": bat, "mole": mole, "spider": spider, "newt": newt, "scorpion": scorpion, "panther": panther, "golem": golem, "dragon": dragon,
    "camel": camel, "meerkat": meerkat, "fennec": fennec, "vulture": vulture, "cobra": cobra, "hyena": hyena, "lion": lion, "anubis": anubis,
    "lemming": lemming, "penguin": penguin, "seal": seal, "hare": hare, "yak": yak, "walrus": walrus, "narwhal": narwhal, "yeti": yeti,
    "gecko": gecko, "iguana": iguana, "beetle": beetle, "salamander": salamander, "phoenix": phoenix, "cerberus": cerberus, "basilisk": basilisk, "hydra": hydra,
    "puffin": puffin, "otter": otter, "snowleopard": snowleopard, "polarbear": polarbear, "sabertooth": sabertooth, "mammoth": mammoth, "frostwolf": frostwolf, "frostdragon": frostdragon,
    "mouse": mouse, "bot": bot, "drone": drone, "sprite": sprite, "glitch": glitch, "mecha": mecha, "quantum": quantum, "mainframe": mainframe,
    "unicorn": unicorn, "pegasus": pegasus, "griffin": griffin, "kitsune": kitsune, "chimera": chimera, "kraken": kraken, "leviathan": leviathan, "elderdragon": elderdragon,
}


def build(cubelings, spec, mat):
    animal = Animal(cubelings, spec, mat)
    ANIMALS[spec["animal"]](animal)
    # The game finds the body (its middle and size) by the "body" role: the first body block is the torso
    return animal.parts
