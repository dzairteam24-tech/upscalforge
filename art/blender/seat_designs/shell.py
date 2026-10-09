"""Beach: the Shell Seat. An open scallop seashell, peach with radiating ribs: its bottom half lies flat as the
seat bowl with a soft pearl-pink cushion in it, its top half stands open behind as a fan-shaped backrest, a big
glossy pearl sits at the back in the hinge, and a Cubeling face smiles on the front lip."""

import math

import bmesh
import bpy
from mathutils import Matrix

from seatkit import FACE_COLORS, apply_modifiers, bake, ball, face, finish, front_marker, placed

NAME = "Shell"
TITLE = "Shell Seat"
ZONE = 4
ORDER = 1
TOP = 1.05  # the cushion's top in the middle, where the rider sits
COLORS = {
    **FACE_COLORS,
    "shell": (1.0, 0.5, 0.36),
    "inner": (1.0, 0.8, 0.72),
    "cushion": (1.0, 0.62, 0.72),
    "pearl": (0.95, 0.93, 0.92),
}

RIBS = 10  # ribs across the fan (from one side of the hinge to the other)
RIB = 0.05  # how far the ribs stand out
THICK = 0.1  # the shell wall


def valve(name, rx, ry, depth, power=2.0, rings=18, around=160):
    """One half of the shell: an oval bowl opening up (+Z), its lowest point at the origin, rim `depth` above,
    `rx` by `ry` wide. Ribs radiate from the hinge at its back (+Y): the wall is corrugated along its normal,
    so both sides show them and the rim comes out scalloped. Returns (outside, inside) as two objects."""
    hinge_y = ry

    def point(i, j, inner):
        rho = i / rings
        th = 2 * math.pi * j / around
        x, y = math.cos(th) * rho * rx, math.sin(th) * rho * ry
        z = depth * rho**power
        # the bowl's outward normal (down and out), from the slope of z = depth * rho^power
        k = depth * power * rho ** (power - 2) if rho > 0 else 0
        n = (k * x / rx**2, k * y / ry**2, -1.0)
        ln = math.sqrt(n[0] ** 2 + n[1] ** 2 + 1)
        n = (n[0] / ln, n[1] / ln, n[2] / ln)
        # ribs: a ridge every so many degrees round the hinge, fading in away from it
        phi = math.atan2(x, hinge_y - y)
        dist = math.hypot(x, hinge_y - y)
        ridge = (0.5 + 0.5 * math.cos(2 * RIBS * phi)) ** 1.5
        a = RIB * ridge * min(dist / 0.8, 1.0)
        off = a - (THICK if inner else 0.0)
        return (x + n[0] * off, y + n[1] * off, z + n[2] * off)

    objs = []
    for inner in (False, True):
        bm = bmesh.new()
        pole = bm.verts.new(point(0, 0, inner))
        grid = [[bm.verts.new(point(i, j, inner)) for j in range(around)] for i in range(1, rings + 1)]
        for j in range(around):
            jn = (j + 1) % around
            f = (pole, grid[0][jn], grid[0][j])
            bm.faces.new(f if not inner else f[::-1])
            for i in range(rings - 1):
                f = (grid[i][j], grid[i][jn], grid[i + 1][jn], grid[i + 1][j])
                bm.faces.new(f if not inner else f[::-1])
        if not inner:
            outer_rim = [v.co.copy() for v in grid[-1]]
        else:
            # close the wall: a strip from the inner rim out to the outer rim (part of the lighter inside)
            rim = [bm.verts.new(co) for co in outer_rim]
            for j in range(around):
                jn = (j + 1) % around
                bm.faces.new((grid[-1][j], grid[-1][jn], rim[jn], rim[j]))
        bm.normal_update()
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name + ("In" if inner else "Out"), mesh)
        bpy.context.collection.objects.link(obj)
        objs.append(obj)
    return objs


def build():
    parts = []
    # The bottom half: a shallow ribbed bowl lying flat, its back rim the hinge
    brx, bry, bdepth, base = 1.78, 1.5, 0.82, 0.07
    lower = valve("ShellLower", brx, bry, bdepth)
    for obj in lower:
        placed(obj, Matrix.Translation((0, 0, base)))
    parts.append(finish(lower[0], "shell"))
    parts.append(finish(lower[1], "inner"))

    # The top half, opened up behind: a smaller ribbed fan swung back about the hinge so its hollow faces the
    # rider and its ribs fan out from the bottom
    hinge = (0, bry - 0.05, base + bdepth - 0.06)
    trx, try_, tdepth = 1.55, 0.86, 0.42
    upper = valve("ShellUpper", trx, try_, tdepth, power=2.2)
    m = (
        Matrix.Translation(hinge)
        @ Matrix.Rotation(math.radians(-104), 4, "X")
        @ Matrix.Diagonal((1, 1, -1, 1))  # closed it would face down over the bowl
        @ Matrix.Translation((0, -try_, 0))
    )
    for obj in upper:
        placed(obj, m)
        # a scale with a negative axis turns the faces inside out: flip them back
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.to_mesh(obj.data)
        bm.free()
    parts.append(finish(upper[0], "shell"))
    parts.append(finish(upper[1], "inner"))

    # The hinge: two little rounded ears either side, and a roll joining the halves
    for sx in (-1, 1):
        ear = ball("Ear", 1, (sx * 0.42, hinge[1] + 0.02, hinge[2] + 0.02), (0.36, 0.2, 0.2))
        parts.append(finish(ear, "shell"))
    roll = ball("Hinge", 1, (0, hinge[1] + 0.03, hinge[2] + 0.02), (0.3, 0.17, 0.17))
    parts.append(finish(roll, "shell"))

    # The soft cushion in the bowl, puffing a little over the rim, flat-topped and dipped where the rider sits
    cushion = ball("Cushion", 1, (0, -0.05, 0.62), (1.36, 1.18, 0.5))
    bake(cushion)
    sub = cushion.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    apply_modifiers(cushion)
    for v in cushion.data.vertices:
        if v.co.z > TOP:
            v.co.z = TOP + (v.co.z - TOP) * 0.3
        rr = math.hypot(v.co.x / 0.85, (v.co.y + 0.05) / 0.8)
        if v.co.z > TOP - 0.2 and rr < 1:
            v.co.z -= 0.07 * (1 - rr * rr)
    parts.append(finish(cushion, "cushion"))

    # The big glossy pearl nestled at the back, against the open top half
    parts.append(finish(ball("Pearl", 0.3, (0, 1.2, TOP + 0.1)), "pearl"))

    # The face on the front lip, tilted half way to the bowl's slope so it reads from the front
    rho = 0.83
    fy, fz = -rho * bry, base + bdepth * rho**2
    slope = math.atan(2 * bdepth * rho / bry)
    frame = Matrix.Translation((0, fy - 0.07, fz - 0.03)) @ Matrix.Rotation(slope * 0.55, 4, "X")
    parts += face(frame, 1.15)

    parts.append(front_marker(2 * bry))
    return parts
