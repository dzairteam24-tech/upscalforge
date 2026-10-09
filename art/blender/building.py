"""The town building (art: art/sources/building_cottage.glb, the Meshy cottage it follows): a cute cottage with
cream walls on a stone tile base, a puffy roof with rolled eaves, a round gold-framed plaque on the front of
the roof (blank: each shop's logo goes on it), an arched wooden door and round windows on every side. Flat
colors per part (one Roblox part per role), so the game recolors the roof per shop.

Units are studs. It stands on z = 0, middle at x = y = 0, front toward -Y.

    python art/blender/building.py            renders OUT/Building.png (3/4, side, back, top)
    python art/blender/building.py roblox     writes art/models/Building.glb (Building__<role>)

Needs Python with bpy (Blender 4.2+) and pillow.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

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
    "plaque": (0.98, 0.95, 0.9),
}

W, D = 11.0, 8.4  # the walls' footprint
WALL_H = 6.4
BASE_H = 1.0
ROOF_Z = BASE_H + WALL_H  # where the roof sits


def build():
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
    parts.append(finish(box("RoofTop", (W - 0.4, D - 0.8, 2.6), (0, 0.3, ROOF_Z + 3.2), bevel=1.25, segments=6), "roof"))
    for side in (-1, 1):
        roll = [(-(W + 2.6) / 2 + 0.6, side * ((D + 2.6) / 2 - 0.55), ROOF_Z + 0.35), ((W + 2.6) / 2 - 0.6, side * ((D + 2.6) / 2 - 0.55), ROOF_Z + 0.35)]
        parts.append(finish(tube("Eave", roll, 0.62), "roof"))
        roll = [(side * ((W + 2.6) / 2 - 0.55), -(D + 2.6) / 2 + 0.6, ROOF_Z + 0.35), (side * ((W + 2.6) / 2 - 0.55), (D + 2.6) / 2 - 0.6, ROOF_Z + 0.35)]
        parts.append(finish(tube("Eave", roll, 0.62), "roof"))
    gable = box("Gable", (6.2, 2.8, 6.6), (0, -(D + 2.6) / 2 + 1.5, ROOF_Z + 3.3), bevel=1.35, segments=6)
    parts.append(finish(gable, "roof"))

    # The plaque on the gable: a blank disc in a thick gold ring, facing the front
    front_y = -(D + 2.6) / 2 + 0.15
    plaque_z = ROOF_Z + 3.7
    disc = cylinder("Plaque", 2.05, 0.3, (0, front_y - 0.05, plaque_z), vertices=48, bevel=0.08)
    disc.rotation_euler = (math.pi / 2, 0, 0)
    parts.append(finish(seatkit.bake(disc), "plaque"))
    ring = torus("Rim", 2.15, 0.28, (0, front_y - 0.12, plaque_z))
    ring.rotation_euler = (math.pi / 2, 0, 0)
    parts.append(finish(seatkit.bake(ring), "gold"))

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
    for x in (-3.4, 3.4):
        parts += window(Matrix.Translation((x, -D / 2 - 0.05, win_z)))
    for side in (-1, 1):
        for y in (-1.6, 1.6):
            parts += window(Matrix.Translation((side * (W / 2 + 0.05), y, win_z)) @ Matrix.Rotation(-side * math.pi / 2, 4, "Z"))
    for x in (-2.6, 2.6):
        parts += window(Matrix.Translation((x, D / 2 + 0.05, win_z)) @ Matrix.Rotation(math.pi, 4, "Z"))
    return parts


def render(parts):
    from PIL import Image

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 40
    scene.render.resolution_x = 600
    scene.render.resolution_y = 600
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
    camera.data.ortho_scale = 22
    camera.data.clip_end = 500
    scene.camera = camera
    target = Vector((0, 0, 5.5))
    images = []
    for d in (Vector((0.5, -1, 0.5)), Vector((-1, -0.3, 0.3)), Vector((-0.5, 1, 0.5)), Vector((0, -0.01, 1))):
        camera.location = target + d.normalized() * 100
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(OUT, "_b.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        images.append(Image.open(path).copy())
        os.remove(path)
    sheet = Image.new("RGB", (600 * len(images), 600))
    for i, im in enumerate(images):
        sheet.paste(im, (i * 600, 0))
    out = os.path.join(OUT, "Building.png")
    sheet.save(out)
    print("wrote", out, "faces", sum(len(p.data.polygons) for p in parts))


def export(parts):
    by_role = {}
    for obj in parts:
        by_role.setdefault(obj["role"], []).append(obj)
    joined = []
    for role, objs in by_role.items():
        obj = seatkit.join(objs) if len(objs) > 1 else objs[0]
        obj.name = f"Building__{role}"
        obj.data.name = obj.name
        joined.append(obj)
        print(role, len(obj.data.polygons))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined:
        obj.select_set(True)
    out = os.path.join(ROOT, "models", "Building.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True)
    print("wrote", out)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    seatkit.current["seat"] = "Building"
    seatkit.current["colors"] = COLORS
    parts = build()
    if "roblox" in sys.argv[1:]:
        export(parts)
    else:
        render(parts)


main()
