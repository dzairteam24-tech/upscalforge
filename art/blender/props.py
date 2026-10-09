"""Map props (art: art/renders/props_reference_batch1.webp and the props list in docs/map-art.md): the
decorations PropService places along the edges of each zone. Each prop is a module in prop_designs/ (NAME,
ZONES, COLORS, optional GLOW and WEIGHT, and build() returning its parts), built with seatkit's pieces in
flat colors like the seats and creatures.

Units are studs, at the size the game shows them (PropService only varies it a little). A prop stands on
z = 0 with its middle at x = y = 0. It has no front: the game turns each one at random.

    PROP=Tree python art/blender/props.py      renders OUT/Tree.png (3/4, front, side, top)
    python art/blender/props.py sheet          renders OUT/PropsSheet.png: every prop, by zone
    python art/blender/props.py roblox         writes art/models/Props.glb (one mesh per prop and color role,
                                               named Prop<Name>__<role>) and roblox/shared/Config/PropLooks.luau

Needs Python with bpy (Blender 4.2+) and pillow.
"""

import importlib
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import seatkit  # noqa: E402

ROOT = os.path.join(HERE, "..")
REPO = os.path.join(ROOT, "..")
OUT = os.environ.get("OUT", ROOT)


def designs():
    folder = os.path.join(HERE, "prop_designs")
    found = []
    for file in sorted(os.listdir(folder)):
        if file.endswith(".py") and not file.startswith("_"):
            found.append(importlib.import_module("prop_designs." + file[:-3]))
    found.sort(key=lambda d: (min(d.ZONES), getattr(d, "ORDER", 0), d.NAME))
    return found


def build(design):
    seatkit.current["seat"] = "Prop" + design.NAME
    seatkit.current["colors"] = design.COLORS
    seatkit.current["glow"] = getattr(design, "GLOW", ())
    return design.build()


def bounds(parts):
    pts = [o.matrix_world @ v.co for o in parts for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def setup_render(resolution=500):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 40
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
    bpy.ops.object.light_add(type="SUN")
    fill = bpy.context.active_object
    fill.data.energy = 0.9
    fill.rotation_euler = (math.radians(60), 0, math.radians(-130))
    bpy.ops.object.camera_add()
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    scene.camera = camera
    return camera


def render_views(camera, parts, name, views=None):
    from PIL import Image

    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.hide_render = obj not in parts
    lo, hi = bounds(parts)
    target = (lo + hi) / 2
    camera.data.ortho_scale = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z) * 1.35
    views = views or [("three_quarter", 35, 0.35), ("front", 0, 0.08), ("side", 90, 0.08), ("top", 0, 3.0)]
    images = []
    for view, angle, up in views:
        rad = math.radians(angle)
        direction = Vector((-math.sin(rad), -math.cos(rad), up)).normalized()
        camera.location = target + direction * 200
        camera.data.clip_end = 1000
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(OUT, f"_prop_{view}.png")
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


def sheet(all_designs):
    from PIL import Image, ImageDraw

    camera = setup_render(400)
    built = {d.NAME: build(d) for d in all_designs}
    tiles = []
    for d in all_designs:
        path = render_views(camera, built[d.NAME], "_tile", [("three_quarter", 35, 0.35)])
        tile = Image.open(path).copy()
        os.remove(path)
        lo, hi = bounds(built[d.NAME])
        ImageDraw.Draw(tile).text((10, 10), f"{d.NAME} (zones {', '.join(map(str, d.ZONES))}, {hi.z:.0f} studs)", fill=(30, 30, 60))
        tiles.append(tile)
    cols = 6
    rows = (len(tiles) + cols - 1) // cols
    out = Image.new("RGB", (cols * 400, rows * 400), (220, 228, 245))
    for i, tile in enumerate(tiles):
        out.paste(tile, ((i % cols) * 400, (i // cols) * 400))
    path = os.path.join(OUT, "PropsSheet.png")
    out.save(path)
    print("wrote", path)


def srgb(c):
    return tuple(round(255 * max(0.0, min(1.0, v)) ** (1 / 2.2)) for v in c)


def export_roblox(all_designs):
    joined = []
    looks = []
    for d in all_designs:
        parts = build(d)
        by_role = {}
        for obj in parts:
            by_role.setdefault(obj["role"], []).append(obj)
        boxes = {}
        faces = 0
        for role, objs in by_role.items():
            obj = seatkit.join(objs) if len(objs) > 1 else objs[0]
            obj.name = f"Prop{d.NAME}__{role}"
            obj.data.name = obj.name
            joined.append(obj)
            lo, hi = bounds([obj])
            c, s = (lo + hi) / 2, hi - lo
            boxes[role] = ((c.x, c.z, -c.y), (s.x, s.z, s.y), s.x * s.y * s.z)
            faces += len(obj.data.polygons)
        ref = max(boxes, key=lambda r: boxes[r][2])
        lo, hi = bounds([o for o in joined if o.name.startswith(f"Prop{d.NAME}__")])
        print(f"{d.NAME}: {faces} faces, {hi.x - lo.x:.1f} x {hi.z:.1f} x {hi.y - lo.y:.1f} studs, ref {ref}")
        looks.append((d, ref, boxes[ref], (hi.x - lo.x, hi.z, hi.y - lo.y)))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined:
        obj.select_set(True)
    out = os.path.join(ROOT, "models", "Props.glb")
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True)
    print("wrote", out)

    def v3(t):
        return "Vector3.new(" + ", ".join(f"{x:.3f}" for x in t) + ")"

    def rgb(c):
        r, g, b = srgb(c)
        return f"Color3.fromRGB({r}, {g}, {b})"

    lines = [
        "--!strict",
        "-- The map props' models as exported (written by art/blender/props.py roblox; don't edit by hand): per prop,",
        "-- its reference part's box in the file (studs), its size, the zones it decorates, how often it's picked",
        "-- there, and the color of each part role. PropService places them.",
        "",
        "export type Look = {",
        "\tname: string,",
        "\tmodel: { ref: string, center: Vector3, size: Vector3 },",
        "\tsize: Vector3,",
        "\tzones: { number },",
        "\tweight: number,",
        "\tcolors: { [string]: Color3 },",
        "\tglow: { [string]: boolean },",
        "}",
        "",
        "local looks: { Look } = {",
    ]
    for d, ref, box, size in looks:
        lines.append("\t{")
        lines.append(f'\t\tname = "{d.NAME}",')
        lines.append(f'\t\tmodel = {{ ref = "{ref}", center = {v3(box[0])}, size = {v3(box[1])} }},')
        lines.append(f"\t\tsize = {v3(size)},")
        lines.append(f"\t\tzones = {{ {', '.join(str(z) for z in d.ZONES)} }},")
        lines.append(f"\t\tweight = {getattr(d, 'WEIGHT', 1)},")
        lines.append("\t\tcolors = {")
        for r in sorted(d.COLORS):
            lines.append(f"\t\t\t{r} = {rgb(d.COLORS[r])},")
        lines.append("\t\t},")
        lines.append("\t\tglow = {" + "".join(f" {r} = true," for r in getattr(d, "GLOW", ())) + " },")
        lines.append("\t},")
    lines += ["}", "", "return looks", ""]
    path = os.path.join(REPO, "roblox", "shared", "Config", "PropLooks.luau")
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
    name = os.environ.get("PROP", "Tree")
    design = next(d for d in all_designs if d.NAME == name)
    parts = build(design)
    camera = setup_render()
    render_views(camera, parts, name)


main()
