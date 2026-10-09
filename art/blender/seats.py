"""The floating seats (art: the floating seats sheet): seats the player sits on cross-legged while travelling,
three per zone. Each design is a module in seat_designs/ (NAME, TITLE, ZONE, TOP, COLORS, optional GLOW and
LIGHT, and build() returning its parts); seatkit.py has the shared pieces.

Units are studs as modeled (the game draws seats seatkit.SEAT_SCALE bigger). A seat's bottom is z = 0, its
middle x = y = 0, front is -Y like the creatures. Each seat has a tiny marker part, <Seat>__front, in front of
its middle: the game finds the seat's front from it (Studio's importer may turn a model around).

    SEAT=Cloud python art/blender/seats.py          renders OUT/Cloud.png (3/4, front, side, back, top)
    SEAT=Cloud RIDE=1 python art/blender/seats.py   renders OUT/CloudRide.png with a standard R15 rider posed by
                                                    the game's own solver (needs LUNE: the lune binary)
    python art/blender/seats.py roblox              writes art/models/Seats.glb (one mesh per seat and color
                                                    role: Cloud__body, Cloud__eye, ...) for Studio's Import
                                                    3D, and roblox/shared/Config/SeatLooks.luau (what the game
                                                    needs to know about each seat)
    python art/blender/seats.py sheet               renders OUT/SeatsSheet.png: every seat, in zone order

Needs Python with bpy (Blender 4.2+) and pillow.
"""

import importlib
import json
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import seatkit  # noqa: E402

ROOT = os.path.join(HERE, "..")
REPO = os.path.join(ROOT, "..")
OUT = os.environ.get("OUT", ROOT)


def designs():
    folder = os.path.join(HERE, "seat_designs")
    found = []
    # ONLY=cloud,blossom: just those designs (module names)
    only = [n for n in os.environ.get("ONLY", "").lower().split(",") if n]
    for file in sorted(os.listdir(folder)):
        if file.endswith(".py") and not file.startswith("_"):
            if only and file[:-3] not in only:
                continue
            found.append(importlib.import_module("seat_designs." + file[:-3]))
    found.sort(key=lambda d: (d.ZONE, getattr(d, "ORDER", 0), d.NAME))
    return found


def build(design):
    seatkit.current["seat"] = design.NAME
    seatkit.current["colors"] = design.COLORS
    seatkit.current["glow"] = getattr(design, "GLOW", ())
    parts = design.build()
    for obj in parts:
        obj["seat"] = design.NAME
    return parts


def world_points(obj):
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


def measure_top(parts):
    """The sitting surface: the highest point of the seat straight down onto its middle."""
    best = None
    for obj in parts:
        if obj["role"] == "front":
            continue
        inv = obj.matrix_world.inverted()
        origin = inv @ Vector((0, 0, 20))
        direction = (inv.to_3x3() @ Vector((0, 0, -1))).normalized()
        hit, location, _, _ = obj.ray_cast(origin, direction)
        if hit:
            z = (obj.matrix_world @ location).z
            best = z if best is None else max(best, z)
    return best or 1.0


# ---------------------------------------------------------------------------------------------------------
# Render


def setup_render(resolution=600):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.72, 0.8, 0.95, 1)
    bpy.ops.object.light_add(type="SUN", location=(4, -6, 8))
    sun = bpy.context.active_object
    sun.data.energy = 2.4
    sun.rotation_euler = (math.radians(45), math.radians(10), math.radians(25))
    bpy.ops.object.light_add(type="AREA", location=(-4, -5, 4))
    fill = bpy.context.active_object
    fill.data.energy = 250
    fill.data.size = 8
    fill.rotation_euler = (math.radians(60), 0, math.radians(-40))
    bpy.ops.object.camera_add()
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 4.8
    scene.camera = camera
    return camera


def render_views(camera, parts, name, target, views=None):
    from PIL import Image

    for obj in bpy.data.objects:
        if obj.type == "MESH":
            rider = str(obj.get("role", "")).startswith("rider_")
            obj.hide_render = not rider and (obj not in parts or obj["role"] == "front")
    views = views or [("three_quarter", 35, 0.35), ("front", 0, 0.08), ("side", 90, 0.08), ("back", 180, 0.12), ("top", 0, 3.0)]
    images = []
    for view, angle, up in views:
        rad = math.radians(angle)
        direction = Vector((-math.sin(rad), -math.cos(rad), up)).normalized()
        camera.location = target + direction * 12
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(OUT, f"_seat_{view}.png")
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        images.append(Image.open(path).copy())
        os.remove(path)
    sheet = Image.new("RGB", (sum(i.width for i in images), images[0].height))
    x = 0
    for image in images:
        sheet.paste(image, (x, 0))
        x += image.width
    out = os.path.join(OUT, name + ".png")
    sheet.save(out)
    print("wrote", out)
    return out


def pose_rider(top):
    """A standard R15 rider posed on a seat whose surface is `top` (model units) by the game's own solver
    (SeatPose and RideIK, as RideClient does it): blocks in the game's frame for the seat."""
    lune = os.environ.get("LUNE", "lune")
    path = os.path.join(OUT, "_rider.json")
    subprocess.run([lune, "run", os.path.join(HERE, "seat_rider.luau"), path, str(top * seatkit.SEAT_SCALE)], check=True, cwd=REPO)
    return path


def add_rider(path):
    """The rider's blocks (studs, Y up, front -Z, origin on the ground under the seat's middle), shrunk to
    the seat's modeled size."""
    # game (x, y, z) -> Blender (-x, z, y), and the game draws the seat SEAT_SCALE bigger
    shrink = 1 / seatkit.SEAT_SCALE
    turn = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
    seatkit.current["seat"] = "Rider"
    parts = []
    for block in json.load(open(path))["parts"]:
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.active_object
        obj.scale = [v * shrink for v in block["s"]]
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        bevel = obj.modifiers.new("Bevel", "BEVEL")
        bevel.width = 0.05
        bevel.segments = 2
        r = block["r"]  # rows: the block's X, Y and Z axes
        rot = Matrix(((r[0], r[3], r[6]), (r[1], r[4], r[7]), (r[2], r[5], r[8])))
        obj.matrix_world = Matrix.Translation(turn @ Vector(block["p"]) * shrink) @ (turn @ rot @ turn.transposed()).to_4x4()
        role = "rider_" + "_".join(f"{c:.2f}" for c in block["c"])
        seatkit.current["colors"] = {role: tuple(c**2.2 for c in block["c"])}
        seatkit.finish(obj, role)
        parts.append(obj)
    return parts


def sheet(all_designs):
    """Every seat from the 3/4 view, in zone order, labeled."""
    from PIL import Image, ImageDraw

    camera = setup_render(400)
    built = {d.NAME: build(d) for d in all_designs}
    tiles = []
    for d in all_designs:
        path = render_views(camera, built[d.NAME], "_tile", Vector((0, 0, 0.7)), [("three_quarter", 35, 0.35)])
        tile = Image.open(path).copy()
        os.remove(path)
        ImageDraw.Draw(tile).text((10, 10), f"{d.ZONE}. {d.TITLE}", fill=(30, 30, 60))
        tiles.append(tile)
    cols = 6
    rows = (len(tiles) + cols - 1) // cols
    out = Image.new("RGB", (cols * 400, rows * 400), (220, 228, 245))
    for i, tile in enumerate(tiles):
        out.paste(tile, ((i % cols) * 400, (i // cols) * 400))
    path = os.path.join(OUT, "SeatsSheet.png")
    out.save(path)
    print("wrote", path)


# ---------------------------------------------------------------------------------------------------------
# Export


def srgb(c):
    return tuple(round(255 * max(0.0, min(1.0, v)) ** (1 / 2.2)) for v in c)


def export_roblox(all_designs):
    """One mesh per color role and seat, named <Seat>__<role> (the mesh too: Studio names parts after it),
    and SeatLooks.luau: each seat's reference part box (in the file's axes: x, z up, -y), sitting height,
    bottom and colors."""
    joined = []
    looks = []
    for d in all_designs:
        parts = build(d)
        top = measure_top(parts)
        by_role = {}
        for obj in parts:
            by_role.setdefault(obj["role"], []).append(obj)
        boxes = {}
        bottom = None
        for role, objs in by_role.items():
            obj = seatkit.join(objs) if len(objs) > 1 else objs[0]
            obj.name = f"{d.NAME}__{role}"
            obj.data.name = obj.name
            joined.append(obj)
            pts = world_points(obj)
            lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
            hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
            if role != "front":
                bottom = lo.z if bottom is None else min(bottom, lo.z)
            c, s = (lo + hi) / 2, hi - lo
            boxes[role] = ((c.x, c.z, -c.y), (s.x, s.z, s.y), s.x * s.y * s.z)
        ref = max((r for r in boxes if r != "front"), key=lambda r: boxes[r][2])
        print(f"{d.NAME}: top {top:.3f} bottom {bottom:.3f} ref {ref}, " + ", ".join(f"{r} {len(bpy.data.objects[d.NAME + '__' + r].data.polygons)}" for r in boxes))
        looks.append((d, ref, boxes[ref], top, bottom))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined:
        obj.select_set(True)
    out = os.path.join(ROOT, "models", "Seats.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True)
    print("wrote", out)

    def v3(t):
        return "Vector3.new(" + ", ".join(f"{x:.3f}" for x in t) + ")"

    def rgb(c):
        r, g, b = srgb(c)
        return f"Color3.fromRGB({r}, {g}, {b})"

    lines = [
        "--!strict",
        "-- The floating seats' models as exported (written by art/blender/seats.py roblox; don't edit by hand): per",
        "-- seat, in zone order, its reference part's box in the file (front +Z, studs), where the rider sits and the",
        "-- seat's underside (above its bottom), and the color of each part role. SeatModel draws them; Cosmetics",
        "-- makes a ride of each.",
        "",
        "export type Look = {",
        "\tname: string,",
        "\ttitle: string,",
        "\tzone: number,",
        "\tmodel: { ref: string, center: Vector3, size: Vector3 },",
        "\ttop: number,",
        "\tbottom: number,",
        "\tcolors: { [string]: Color3 },",
        "\tglow: { [string]: boolean },",
        "\tlight: Color3,",
        "}",
        "",
        "local looks: { Look } = {",
    ]
    for d, ref, box, top, bottom in looks:
        colors = {r: c for r, c in d.COLORS.items() if r != "front"}
        light = getattr(d, "LIGHT", (1.0, 0.75, 0.9))
        lines.append("\t{")
        lines.append(f'\t\tname = "{d.NAME}",')
        lines.append(f'\t\ttitle = "{d.TITLE}",')
        lines.append(f"\t\tzone = {d.ZONE},")
        lines.append(f'\t\tmodel = {{ ref = "{ref}", center = {v3(box[0])}, size = {v3(box[1])} }},')
        lines.append(f"\t\ttop = {top:.3f},")
        lines.append(f"\t\tbottom = {max(bottom, 0):.3f},")
        lines.append("\t\tcolors = {")
        for r in sorted(colors):
            lines.append(f"\t\t\t{r} = {rgb(colors[r])},")
        lines.append("\t\t},")
        lines.append("\t\tglow = {" + "".join(f" {r} = true," for r in getattr(d, "GLOW", ())) + " },")
        lines.append(f"\t\tlight = {rgb(light)},")
        lines.append("\t},")
    lines += ["}", "", "return looks", ""]
    path = os.path.join(REPO, "roblox", "shared", "Config", "SeatLooks.luau")
    open(path, "w").write("\n".join(lines))
    print("wrote", path)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    all_designs = designs()
    if "roblox" in sys.argv[1:]:
        export_roblox(all_designs)
        return
    if "sheet" in sys.argv[1:]:
        sheet(all_designs)
        return
    name = os.environ.get("SEAT", "Cloud")
    design = next(d for d in all_designs if d.NAME == name)
    parts = build(design)
    camera = setup_render()
    if os.environ.get("RIDE"):
        top = measure_top(parts)
        add_rider(pose_rider(top))
        camera.data.ortho_scale = float(os.environ.get("ZOOM", 6))
        render_views(camera, parts, name + "Ride", Vector((0, 0, float(os.environ.get("AIM", 2.0)))))
        return
    render_views(camera, parts, name, Vector((0, 0, 0.7)))


main()
