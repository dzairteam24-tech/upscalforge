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


ANIMALS = {"dog": dog, "cat": cat, "bunny": bunny, "bear": bear, "chicken": chicken, "pig": pig, "sheep": sheep, "horse": horse}


def build(cubelings, spec, mat):
    animal = Animal(cubelings, spec, mat)
    ANIMALS[spec["animal"]](animal)
    # The game finds the body (its middle and size) by the "body" role: the first body block is the torso
    return animal.parts
