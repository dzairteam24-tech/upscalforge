"""The town building (art: art/sources/building_cottage.glb, the Meshy cottage it follows): a cute cottage with
cream walls on a stone tile base, a puffy roof with rolled eaves, a round gold-framed plaque on the front of
the roof (blank: each shop's logo goes on it), an arched wooden door and round windows on every side. Flat
colors per part (one Roblox part per role), so the game recolors the roof per shop.

Units are studs. It stands on z = 0, middle at x = y = 0, front toward -Y.

    python art/blender/building.py            renders OUT/Buildings.png (the six shops' buildings)
    python art/blender/building.py roblox     writes art/models/Buildings.glb (Building<Shop>__<role>)

Needs Python with bpy (Blender 4.2+) and pillow.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import logos  # noqa: E402
import seatkit  # noqa: E402
from seatkit import ball, box, cylinder, finish, placed, torus, tube  # noqa: E402

ROOT = os.path.join(HERE, "..")
OUT = os.environ.get("OUT", ROOT)

COLORS = {
    "wall": (0.96, 0.86, 0.68),
    "roof": (0.2, 0.7, 0.42),
    "gold": (1.0, 0.6, 0.08),
    "stone": (0.82, 0.7, 0.55),
    "door": (0.42, 0.2, 0.08),
    "glass": (0.45, 0.72, 1.0),
    "frame": (0.97, 0.9, 0.78),
}

W, D = 11.0, 8.4  # the walls' footprint (each variant sets its own)
WALL_H = 6.4
BASE_H = 1.0
ROOF_Z = BASE_H + WALL_H  # where the roof sits

# One building per town shop, each a little different: its roof color, size, roof top, windows, chimney
VARIANTS = [
    {"name": "Shop", "roof": (0.2, 0.7, 0.42), "w": 11.0, "d": 8.4, "h": 6.4, "top": "pillow", "windows": "round", "chimney": False},
    {"name": "Trade", "roof": (0.18, 0.45, 0.95), "w": 12.0, "d": 8.4, "h": 6.0, "top": "bumps", "windows": "round", "chimney": False},
    {"name": "Potion", "roof": (0.45, 0.25, 0.85), "w": 10.0, "d": 8.4, "h": 7.0, "top": "dome", "windows": "round", "chimney": True},
    {"name": "Spin", "roof": (1.0, 0.42, 0.22), "w": 11.0, "d": 9.0, "h": 6.0, "top": "dome", "windows": "square", "chimney": False},
    {"name": "Trips", "roof": (0.15, 0.62, 0.8), "w": 10.5, "d": 8.4, "h": 6.8, "top": "pillow", "windows": "square", "chimney": True},
    {"name": "Arcade", "roof": (0.9, 0.25, 0.55), "w": 11.5, "d": 8.8, "h": 6.4, "top": "bumps", "windows": "square", "chimney": False},
]


LOGO_BUILDS = {name: make for name, make, _ in logos.LOGOS}
LOGO_COLORS = {name: {"logo_" + r: c for r, c in colors.items()} for name, _, colors in logos.LOGOS}


def build(v):
    global W, D, WALL_H, ROOF_Z
    W, D, WALL_H = v["w"], v["d"], v["h"]
    ROOF_Z = BASE_H + WALL_H
    parts = []
    # Stone tile base: a slab, and a ring of rounded tiles round its edge
    parts.append(finish(box("Base", (W + 2.4, D + 2.4, BASE_H * 0.7), (0, 0, BASE_H * 0.35), bevel=0.25), "stone"))
    for along, length, count in ((0, W + 2.4, 6), (1, D + 2.4, 5)):
        for side in (-1, 1):
            for i in range(count):
                t = -length / 2 + length * (i + 0.5) / count
                at = (t, side * (D + 2.4) / 2, BASE_H * 0.55) if along == 0 else (side * (W + 2.4) / 2, t, BASE_H * 0.55)
                size = (length / count - 0.15, 1.1, BASE_H) if along == 0 else (1.1, length / count - 0.15, BASE_H)
                parts.append(finish(box("Tile", size, at, bevel=0.3), "stone"))
    # Walls, and a gold band where they meet the base
    parts.append(finish(box("Walls", (W, D, WALL_H + 0.4), (0, 0, BASE_H + WALL_H / 2), bevel=0.6, segments=4), "wall"))
    parts.append(finish(box("Band", (W + 0.35, D + 0.35, 0.45), (0, 0, BASE_H + 0.3), bevel=0.15), "gold"))

    # The roof: a puffy overhanging slab, rolled eaves all round, and a rounded gable in front for the plaque
    parts.append(finish(box("Roof", (W + 2.6, D + 2.6, 3.2), (0, 0, ROOF_Z + 1.6), bevel=1.5, segments=6), "roof"))
    if v["top"] == "pillow":
        parts.append(finish(box("RoofTop", (W - 0.4, D - 0.8, 2.6), (0, 0.3, ROOF_Z + 3.2), bevel=1.25, segments=6), "roof"))
    elif v["top"] == "dome":
        parts.append(finish(ball("RoofTop", 1, (0, 0.4, ROOF_Z + 3.0), ((W - 0.8) / 2, (D - 1.0) / 2, 2.6)), "roof"))
    else:
        for x in (-W / 3.2, 0, W / 3.2):
            parts.append(finish(ball("RoofBump", 1, (x, 0.4, ROOF_Z + 3.0), (W / 5.2, (D - 1.2) / 2, 2.1 if x else 2.5)), "roof"))
    if v["chimney"]:
        parts.append(finish(box("Chimney", (1.6, 1.6, 4.2), (W / 2 - 2.2, D / 2 - 2.0, ROOF_Z + 4.0), bevel=0.4), "stone"))
        parts.append(finish(box("ChimneyCap", (2.0, 2.0, 0.6), (W / 2 - 2.2, D / 2 - 2.0, ROOF_Z + 6.2), bevel=0.25), "gold"))
    for side in (-1, 1):
        roll = [(-(W + 2.6) / 2 + 0.6, side * ((D + 2.6) / 2 - 0.55), ROOF_Z + 0.35), ((W + 2.6) / 2 - 0.6, side * ((D + 2.6) / 2 - 0.55), ROOF_Z + 0.35)]
        parts.append(finish(tube("Eave", roll, 0.62), "roof"))
        roll = [(side * ((W + 2.6) / 2 - 0.55), -(D + 2.6) / 2 + 0.6, ROOF_Z + 0.35), (side * ((W + 2.6) / 2 - 0.55), (D + 2.6) / 2 - 0.6, ROOF_Z + 0.35)]
        parts.append(finish(tube("Eave", roll, 0.62), "roof"))
    gable = box("Gable", (6.2, 2.8, 6.6), (0, -(D + 2.6) / 2 + 1.5, ROOF_Z + 3.3), bevel=1.35, segments=6)
    parts.append(finish(gable, "roof"))

    # The plaque on the gable: the shop's logo (logos.py) in a thick gold ring, facing the front
    front_y = -(D + 2.6) / 2 + 0.15
    plaque_z = ROOF_Z + 3.7
    ring = torus("Rim", 2.15, 0.28, (0, front_y - 0.12, plaque_z))
    ring.rotation_euler = (math.pi / 2, 0, 0)
    parts.append(finish(seatkit.bake(ring), "gold"))
    scale = 1.8
    for obj in LOGO_BUILDS[v["name"]]():
        seatkit.bake(obj)  # (some pieces keep their place as the object's location)
        obj.scale = (scale, scale, scale)
        obj.location = (0, front_y - 0.2 - logos.FRONT * scale, plaque_z)
        parts.append(finish(seatkit.bake(obj), "logo_" + obj["role"]))

    # Door: an arched wooden door in a gold arch, a gold knob
    door_y = -D / 2 - 0.2
    door_w, door_h = 2.6, 3.6
    door = box("Door", (door_w, 0.45, door_h - door_w / 2), (0, door_y, BASE_H + (door_h - door_w / 2) / 2), bevel=0.05)
    parts.append(finish(door, "door"))
    top = ball("DoorTop", 1, (0, door_y, BASE_H + door_h - door_w / 2), (door_w / 2, 0.22, door_w / 2))
    parts.append(finish(top, "door"))
    arch = [(-door_w / 2 - 0.18, door_y - 0.12, BASE_H + 0.05)]
    arch += [(math.cos(a) * (door_w / 2 + 0.18), door_y - 0.12, BASE_H + door_h - door_w / 2 + math.sin(a) * (door_w / 2 + 0.18)) for a in [math.pi - math.pi * i / 16 for i in range(17)]]
    arch += [(door_w / 2 + 0.18, door_y - 0.12, BASE_H + 0.05)]
    parts.append(finish(tube("Arch", arch, 0.2), "gold"))
    parts.append(finish(ball("Knob", 0.17, (0.75, door_y - 0.25, BASE_H + 1.6)), "gold"))

    # Round windows: a gold ring, blue glass and a cream cross, on the front (beside the door), sides and back
    def window(frame):
        if v["windows"] == "square":
            out = [finish(placed(box("Glass", (1.5, 0.2, 1.7), (0, 0, 0), bevel=0.3), frame), "glass")]
            out.append(finish(placed(box("WinRim", (1.95, 0.16, 2.15), (0, 0.05, 0), bevel=0.4), frame), "gold"))
            for size in ((1.6, 0.12, 0.14), (0.14, 0.12, 1.8)):
                out.append(finish(placed(box("Bar", size, (0, -0.12, 0), bevel=0.03), frame), "frame"))
            return out
        glass = cylinder("Glass", 0.85, 0.2, (0, 0, 0), vertices=32, bevel=0.03)
        glass.rotation_euler = (math.pi / 2, 0, 0)
        seatkit.bake(glass)
        out = [finish(placed(glass, frame), "glass")]
        rim = torus("WinRim", 0.95, 0.18, (0, -0.08, 0))
        rim.rotation_euler = (math.pi / 2, 0, 0)
        seatkit.bake(rim)
        out.append(finish(placed(rim, frame), "gold"))
        for size in ((1.7, 0.12, 0.14), (0.14, 0.12, 1.7)):
            out.append(finish(placed(box("Bar", size, (0, -0.1, 0), bevel=0.03), frame), "frame"))
        return out

    win_z = BASE_H + 3.4
    for x in (-W * 0.31, W * 0.31):
        parts += window(Matrix.Translation((x, -D / 2 - 0.05, win_z)))
    for side in (-1, 1):
        for y in (-1.6, 1.6):
            parts += window(Matrix.Translation((side * (W / 2 + 0.05), y, win_z)) @ Matrix.Rotation(side * math.pi / 2, 4, "Z"))
    for x in (-2.6, 2.6):
        parts += window(Matrix.Translation((x, D / 2 + 0.05, win_z)) @ Matrix.Rotation(math.pi, 4, "Z"))
    return parts


def render(groups):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 40
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 1100
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.72, 0.8, 0.95, 1)
    bpy.ops.object.light_add(type="SUN")
    sun = bpy.context.active_object
    sun.rotation_euler = (0.7, 0.2, 0.6)
    sun.data.energy = 2.4
    bpy.ops.object.light_add(type="SUN")
    fill = bpy.context.active_object
    fill.rotation_euler = (math.radians(60), 0, math.radians(-130))
    fill.data.energy = 0.8
    bpy.ops.object.camera_add()
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 64
    camera.data.clip_end = 600
    scene.camera = camera
    for i, parts in enumerate(groups):
        offset = Vector(((i % 3 - 1) * 20, (i // 3) * 22, 0))
        for obj in parts:
            obj.location += offset
    target = Vector((0, 11, 5))
    camera.location = target + Vector((0.45, -1, 0.6)).normalized() * 200
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    out = os.path.join(OUT, "Buildings.png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("wrote", out)


def export(groups):
    joined = []
    for v, parts in zip(VARIANTS, groups):
        by_role = {}
        for obj in parts:
            by_role.setdefault(obj["role"], []).append(obj)
        faces = 0
        for role, objs in by_role.items():
            obj = seatkit.join(objs) if len(objs) > 1 else objs[0]
            obj.name = f"Building{v['name']}__{role}"
            obj.data.name = obj.name
            joined.append(obj)
            faces += len(obj.data.polygons)
        print(v["name"], faces, "faces")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined:
        obj.select_set(True)
    out = os.path.join(ROOT, "models", "Buildings.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True)
    print("wrote", out)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    groups = []
    for v in VARIANTS:
        seatkit.current["seat"] = "Building" + v["name"]
        seatkit.current["colors"] = {**COLORS, "roof": v["roof"], **LOGO_COLORS[v["name"]]}
        groups.append(build(v))
    if "roblox" in sys.argv[1:]:
        export(groups)
    else:
        render(groups)


main()
