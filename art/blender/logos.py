"""The town shops' logos (art: the user's emblem sheet): a thick round badge per shop with one raised symbol,
in a few flat colors, made to sit on the buildings' plaques.

Units are studs. Each badge faces the front (-Y), its middle at x = z = 0, radius 1.

    python art/blender/logos.py            renders OUT/Logos.png
    python art/blender/logos.py roblox     writes art/models/Logos.glb (parts named Logo<Shop>__<role>)
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402, I001 (bmesh only exists once bpy is loaded)
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

import seatkit  # noqa: E402
from seatkit import ball, cylinder, finish, torus, tube  # noqa: E402

ROOT = os.path.join(HERE, "..")
OUT = os.environ.get("OUT", ROOT)


def srgb(r, g, b):
    return tuple((c / 255) ** 2.2 for c in (r, g, b))


DEPTH = 0.34  # the badge's thickness
FRONT = -DEPTH / 2  # its face


def at(u, v, dy=0.0):
    """A point on the badge's face: u right, v up, dy out of the face (toward the front)."""
    return (u, FRONT - dy, v)


def facing(obj):
    """Turns a part made along Z to face the front, and bakes it."""
    obj.rotation_euler = (math.pi / 2, 0, 0)
    return seatkit.bake(obj)


def badge(name, radius, role, bevel=0.1):
    """The badge's body: a thick disc with rounded edges."""
    return finish(facing(cylinder(name, radius, DEPTH, (0, 0, 0), vertices=64, bevel=bevel)), role)


def pad(name, r, u, v, sx, sz, role, height=0.13, dy=0.0):
    """A soft raised blob on the face."""
    return finish(ball(name, r, at(u, v, dy), (sx, height / r, sz)), role)


def arc(radius, a0, a1, steps=20):
    return [(math.cos(a0 + (a1 - a0) * i / steps) * radius, math.sin(a0 + (a1 - a0) * i / steps) * radius) for i in range(steps + 1)]


def flat_tube(name, pts, r, role, dy=0.12, squash=0.55):
    obj = tube(name, [(u, 0, v) for u, v in pts], r)
    obj.scale = (1, squash, 1)
    seatkit.bake(obj)
    obj.location = (0, FRONT - dy * 0.6, 0)
    return finish(seatkit.bake(obj), role)


def arrow_head(name, u, v, angle, size, role, depth=0.22):
    """A rounded triangle on the face, its back edge at (u, v), pointing along `angle`."""
    d = Vector((math.cos(angle), math.sin(angle)))
    n = Vector((-d.y, d.x))
    corners = [d * size * 1.05, n * size * 0.85, -n * size * 0.85]
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((u + c.x, FRONT, v + c.y)) for c in corners])
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    bmesh.ops.translate(bm, verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)], vec=(0, -depth, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = 0.06
    mod.segments = 4
    seatkit.apply_modifiers(obj)
    return finish(obj, role)


def cut_above(obj, z):
    """Cuts a part flat at height z, keeping what's below and closing the top."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_outer=True)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    bmesh.ops.edgeloop_fill(bm, edges=edges)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def shop():
    """A gold coin with a raised rim, a deeper gold face and a pale yellow paw print."""
    parts = [badge("Coin", 1.0, "rim")]
    parts.append(finish(_at_face(torus("Rim", 0.86, 0.09, (0, 0, 0)), 0.02), "rim"))
    parts.append(finish(_at_face(cylinder("Face", 0.8, 0.04, (0, 0, 0), vertices=64, bevel=0.01), 0.0), "face"))
    parts.append(pad("Pad", 0.34, 0.0, -0.22, 1.15, 0.85, "paw"))
    for u, v, r in ((-0.48, 0.12, 0.15), (-0.2, 0.38, 0.16), (0.14, 0.38, 0.16), (0.44, 0.12, 0.15)):
        parts.append(pad("Toe", r, u, v, 0.95, 1.18, "paw"))
    return parts


def trade():
    """A cream badge with two chunky arrows chasing round: green above, red below."""
    parts = [badge("Badge", 1.0, "badge")]
    r = 0.5
    for name, start, end, role in (("Top", 205, 85, "green"), ("Bottom", 25, -95, "red")):
        parts.append(flat_tube("Arrow" + name, arc(r, math.radians(start), math.radians(end)), 0.19, role))
        e = math.radians(end)
        parts.append(arrow_head("Head" + name, math.cos(e) * r, math.sin(e) * r, e - math.pi / 2, 0.33, role))
    return parts


def potion():
    """A blue badge with a round glass flask of purple potion and a cork."""
    parts = [badge("Badge", 1.0, "badge")]
    flask = ball("Flask", 0.46, at(0, -0.14, 0.08), (1, 0.4, 1))
    parts.append(finish(flask, "glass"))
    neck = cylinder("Neck", 0.17, 0.32, at(0, 0.36, 0.1), vertices=32, bevel=0.04)
    neck.scale = (1, 0.75, 1)
    parts.append(finish(seatkit.bake(neck), "glass"))
    lip = torus("Lip", 0.2, 0.06, at(0, 0.5, 0.1))
    lip.scale = (1, 0.85, 1)
    parts.append(finish(seatkit.bake(lip), "glass"))
    cork = cylinder("Cork", 0.15, 0.22, at(0, 0.62, 0.1), vertices=32, bevel=0.05)
    parts.append(finish(cork, "cork"))
    liquid = ball("Liquid", 0.39, at(0, -0.16, 0.16), (1, 0.4, 1))
    seatkit.bake(liquid)
    parts.append(finish(cut_above(liquid, -0.02), "potion"))
    for u, v, r in ((-0.14, -0.24, 0.07), (0.1, -0.36, 0.05)):
        parts.append(pad("Bubble", r, u, v, 1, 1, "bubble", height=0.05, dy=0.3))
    return parts


def prism(name, pts, depth, role, dy=0.0, bevel=0.05):
    """A flat shape on the face (points as (u, v)), raised `depth` out of it, with rounded edges."""
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((u, FRONT - dy, v)) for u, v in pts])
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    bmesh.ops.translate(bm, verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)], vec=(0, -depth, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 4
        mod.limit_method = "ANGLE"
        seatkit.apply_modifiers(obj)
    return finish(obj, role)


def split_faces(obj, keep, name):
    """Moves the faces `keep(center)` picks into a new part."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    picked = [f for f in bm.faces if keep(f.calc_center_median())]
    sbm = bmesh.new()
    vmap = {}
    for f in picked:
        vs = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = sbm.verts.new(v.co)
            vs.append(vmap[v])
        sbm.faces.new(vs)
    mesh = bpy.data.meshes.new(name)
    sbm.to_mesh(mesh)
    sbm.free()
    bmesh.ops.delete(bm, geom=picked, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    part = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(part)
    return part


def spin():
    """A gold badge with a cream ring and a six-colour prize wheel, a gold hub and a gold pointer on top."""
    parts = [badge("Badge", 1.0, "gold")]
    parts.append(finish(_at_face(torus("Rim", 0.9, 0.08, (0, 0, 0)), 0.02), "gold"))
    parts.append(finish(_at_face(cylinder("Face", 0.84, 0.04, (0, 0, 0), vertices=64, bevel=0.01), 0.0), "cream"))
    r, gap = 0.72, math.radians(3)
    for k, role in enumerate(("orange", "yellow", "green", "blue", "purple", "red")):
        a1 = math.radians(90 - 60 * k) - gap / 2
        a0 = a1 - math.radians(60) + gap
        mid = (a0 + a1) / 2
        g = (math.cos(mid) * 0.03, math.sin(mid) * 0.03)
        pts = [g] + [(g[0] + math.cos(a0 + (a1 - a0) * i / 10) * r, g[1] + math.sin(a0 + (a1 - a0) * i / 10) * r) for i in range(11)]
        parts.append(prism("Slice", pts, 0.14, role, bevel=0.04))
    parts.append(pad("Hub", 0.17, 0, 0, 1, 1, "gold", height=0.13, dy=0.14))
    parts.append(pad("PointerTop", 0.17, 0, 0.82, 1, 1, "gold", height=0.13, dy=0.14))
    parts.append(prism("Pointer", [(-0.16, 0.8), (0.16, 0.8), (0, 0.52)], 0.24, "gold", dy=0.02, bevel=0.06))
    return parts


def trips():
    """A blue badge with a red and cream striped hot air balloon, ropes and a brown basket."""
    parts = [badge("Badge", 1.0, "badge")]
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=1, location=(0, 0, 0))
    env = bpy.context.active_object
    env.name = "Balloon"
    for v in env.data.vertices:  # narrower toward the bottom
        if v.co.z < 0:
            k = 1 - 0.55 * (-v.co.z) ** 1.6
            v.co.x *= k
            v.co.y *= k

    def cream(c):  # 30 degree stripes round the balloon, red in the middle of the front
        phi = math.degrees(math.atan2(c.x, -c.y))
        return int(math.floor((phi + 15) / 30)) % 2 == 1

    stripes = split_faces(env, cream, "Stripes")
    for obj in (env, stripes):
        obj.scale = (0.56, 0.3, 0.6)
        obj.location = at(0, 0.22, 0.2)
        seatkit.bake(obj)
    parts.append(finish(env, "red"))
    parts.append(finish(stripes, "cream"))
    parts.append(pad("Neck", 0.12, 0, -0.38, 1.4, 0.5, "rope", height=0.1, dy=0.16))
    for side in (-1, 1):
        parts.append(flat_tube("Rope", [(side * 0.14, -0.38), (side * 0.17, -0.6)], 0.035, "rope", dy=0.2, squash=1.0))
    parts.append(prism("Basket", [(-0.22, -0.6), (0.22, -0.6), (0.17, -0.86), (-0.17, -0.86)], 0.24, "basket", bevel=0.06))
    parts.append(flat_tube("BasketRim", [(-0.25, -0.61), (0.25, -0.61)], 0.055, "basket", dy=0.4, squash=1.0))
    return parts


def arcade():
    """A blue badge with a cream face and a joystick: dark base, dark stick, big red ball, a blue and a yellow button."""
    parts = [badge("Badge", 1.0, "badge")]
    parts.append(finish(_at_face(cylinder("Face", 0.84, 0.04, (0, 0, 0), vertices=64, bevel=0.01), 0.0), "cream"))
    parts.append(prism("Base", [(-0.62, -0.6), (0.62, -0.6), (0.58, -0.1), (-0.58, -0.1)], 0.26, "dark", bevel=0.13))
    parts.append(flat_tube("Stick", [(0.05, -0.15), (0.05, 0.3)], 0.08, "dark", dy=0.3, squash=1.0))
    parts.append(pad("Collar", 0.16, 0.05, -0.14, 1, 0.6, "dark", height=0.1, dy=0.26))
    parts.append(pad("Knob", 0.3, 0.05, 0.42, 1, 1, "red", height=0.28, dy=0.2))
    for u, role in ((-0.33, "blue"), (0.38, "yellow")):
        parts.append(pad("ButtonRing", 0.16, u, -0.38, 1, 1, "dark", height=0.06, dy=0.27))
        parts.append(pad("Button", 0.12, u, -0.38, 1, 1, role, height=0.08, dy=0.3))
    return parts


def _at_face(obj, dy):
    obj.rotation_euler = (math.pi / 2, 0, 0)
    seatkit.bake(obj)
    obj.location = (0, FRONT - dy, 0)
    return seatkit.bake(obj)


LOGOS = [
    ("Shop", shop, {"rim": srgb(253, 198, 30), "face": srgb(250, 176, 20), "paw": srgb(255, 214, 90)}),
    ("Trade", trade, {"badge": srgb(245, 236, 220), "green": srgb(100, 215, 150), "red": srgb(245, 90, 85)}),
    ("Potion", potion, {"badge": srgb(50, 160, 240), "glass": srgb(228, 230, 248), "potion": srgb(160, 60, 225), "bubble": srgb(205, 130, 245), "cork": srgb(175, 115, 65)}),
    ("Spin", spin, {"gold": srgb(253, 196, 30), "cream": srgb(246, 236, 218), "red": srgb(240, 70, 70), "orange": srgb(250, 125, 45), "yellow": srgb(255, 205, 60), "green": srgb(80, 200, 70), "blue": srgb(50, 130, 240), "purple": srgb(170, 80, 230)}),
    ("Trips", trips, {"badge": srgb(60, 165, 235), "red": srgb(240, 70, 70), "cream": srgb(246, 236, 218), "rope": srgb(205, 140, 70), "basket": srgb(190, 120, 60)}),
    ("Arcade", arcade, {"badge": srgb(50, 150, 235), "cream": srgb(246, 236, 218), "dark": srgb(60, 64, 74), "red": srgb(240, 70, 70), "blue": srgb(50, 150, 240), "yellow": srgb(255, 205, 60)}),
]


def render(groups):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 40
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 1060
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    bpy.ops.object.light_add(type="SUN")
    sun = bpy.context.active_object
    sun.rotation_euler = (math.radians(55), 0, math.radians(-25))
    sun.data.energy = 2.6
    bpy.ops.object.camera_add()
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 7.6
    scene.camera = camera
    for i, parts in enumerate(groups):
        for obj in parts:
            obj.location.x += (i % 3 - 1) * 2.5
            obj.location.z -= (i // 3 - 0.5) * 2.6
    camera.location = Vector((0.3, -1, 0.08)).normalized() * 50
    camera.rotation_euler = (-camera.location).to_track_quat("-Z", "Y").to_euler()
    out = os.path.join(OUT, "Logos.png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("wrote", out)


def export(groups):
    joined = []
    for (name, _, _), parts in zip(LOGOS, groups):
        by_role = {}
        for obj in parts:
            by_role.setdefault(obj["role"], []).append(obj)
        for role, objs in by_role.items():
            obj = seatkit.join(objs) if len(objs) > 1 else objs[0]
            obj.name = obj.data.name = f"Logo{name}__{role}"
            joined.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined:
        obj.select_set(True)
    out = os.path.join(ROOT, "models", "Logos.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True)
    print("wrote", out)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    groups = []
    for name, build, colors in LOGOS:
        seatkit.current["seat"] = "Logo" + name
        seatkit.current["colors"] = colors
        groups.append(build())
    if "roblox" in sys.argv[1:]:
        export(groups)
    else:
        render(groups)


if __name__ == "__main__":
    main()
