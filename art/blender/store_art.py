"""Store page art for Cubelings: the game icon and the thumbnails, rendered from the same 3D creatures
as the game (cubelings.py), then finished in Pillow (background, glow, text).

Run (Blender's Python, no window needed):
    python art/blender/store_art.py            every image
    python art/blender/store_art.py icon       one image by name (see SHOTS)
    LOW=1 python art/blender/store_art.py ...  quick low-quality preview

Outputs go to art/store/: icon_*.png (512x512) and thumb_*.png (1920x1080).
Fonts: art/fonts (Luckiest Guy and Fredoka, SIL Open Font License).
"""

import math
import os
import random
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cubelings as cb  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "store")
FONTS = os.path.join(ROOT, "fonts")
LOW = os.environ.get("LOW") == "1"

# Part roles that keep their own look on every variant (same list as the game's PetModel FACE)
FACE = {"eye", "shine", "mouth", "teeth", "tongue", "brow", "brows", "shades", "white", "screen", "blush", "nose"}


# ---------------------------------------------------------------------------------------------------------------
# Scene


def new_scene(width, height, samples=96):
    cb.reset()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16 if LOW else samples
    scene.cycles.use_denoising = True
    scale = 0.5 if LOW else 1.0
    scene.render.resolution_x = int(width * scale)
    scene.render.resolution_y = int(height * scale)
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.75, 0.82, 1.0, 1)
    bg.inputs["Strength"].default_value = 0.55

    # Key light, soft fill, and a strong rim light from behind for the bright "toy" look
    lights = [
        ("SUN", (4, -6, 8), (50, 10, 25), 3.0, None),
        ("AREA", (-5, -6, 4), (60, 0, -40), 400, 8),
        ("AREA", (0, 6, 5), (-60, 0, 180), 600, 6),
    ]
    for kind, loc, rot, energy, size in lights:
        bpy.ops.object.light_add(type=kind, location=loc)
        light = bpy.context.active_object
        light.data.energy = energy
        if size:
            light.data.size = size
        light.rotation_euler = tuple(math.radians(a) for a in rot)
    return scene


def camera(location, target, lens=50):
    bpy.ops.object.camera_add(location=location)
    cam = bpy.context.active_object
    cam.data.lens = lens
    cam.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


# ---------------------------------------------------------------------------------------------------------------
# Creatures and props


def variant_material(variant, base):
    """A material for a variant look (same idea as the game's Golden / Crystal / Lava / Neon / Pixel)."""
    mat = bpy.data.materials.new(f"{variant}_{base.name}")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    color = base.get("palette_color", (0.8, 0.8, 0.8))
    if variant == "Golden":
        bsdf.inputs["Base Color"].default_value = (1.0, 0.78, 0.3, 1)
        bsdf.inputs["Metallic"].default_value = 1.0
        bsdf.inputs["Roughness"].default_value = 0.18
    elif variant == "Crystal":
        tint = [0.35 + 0.65 * c for c in (0.55, 0.9, 1.0)]
        bsdf.inputs["Base Color"].default_value = (*tint, 1)
        bsdf.inputs["Transmission Weight"].default_value = 0.75
        bsdf.inputs["Emission Color"].default_value = (0.4, 0.8, 1.0, 1)
        bsdf.inputs["Emission Strength"].default_value = 0.25
        bsdf.inputs["Roughness"].default_value = 0.04
        bsdf.inputs["IOR"].default_value = 1.45
        bsdf.inputs["Coat Weight"].default_value = 1.0
    elif variant == "Lava":
        # Dark basalt with a hot orange glow, so it reads as Lava next to Normal
        bsdf.inputs["Base Color"].default_value = (0.22, 0.04, 0.02, 1)
        bsdf.inputs["Roughness"].default_value = 0.7
        bsdf.inputs["Emission Color"].default_value = (1.0, 0.22, 0.0, 1)
        bsdf.inputs["Emission Strength"].default_value = 0.45
    elif variant == "Neon":
        bsdf.inputs["Base Color"].default_value = (0.1, 1.0, 0.55, 1)
        bsdf.inputs["Emission Color"].default_value = (0.1, 1.0, 0.55, 1)
        bsdf.inputs["Emission Strength"].default_value = 0.9
    elif variant == "Pixel":
        bsdf.inputs["Base Color"].default_value = (0.42, 0.12, 0.85, 1)
        bsdf.inputs["Emission Color"].default_value = (0.55, 0.15, 1.0, 1)
        bsdf.inputs["Emission Strength"].default_value = 0.7
    return mat


def creature(name, location=(0, 0, 0), scale=1.0, yaw=0.0, variant=None, tilt=0.0, **overrides):
    """Builds a creature from cubelings.py and places it. Yaw 0 faces the camera at -Y.
    `overrides` change the spec for a pose (e.g. mouth="open", eye_style="sparkle")."""
    cb.materials.clear()  # each creature gets its own materials (cubelings caches them by role name)
    spec = dict(cb.SPECIES[name])
    spec.update(overrides)
    parts = cb.build(spec)
    bpy.ops.object.empty_add(location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = name.replace(" ", "") + "_root"
    for part in parts:
        part.parent = root
        if variant and variant != "Normal":
            new_slots = []
            for slot in part.material_slots:
                base = slot.material
                if base is not None and base.get("key") not in FACE:
                    new_slots.append(variant_material(variant, base))
                else:
                    new_slots.append(base)
            for i, mat in enumerate(new_slots):
                part.material_slots[i].material = mat
    root.location = location
    root.scale = (scale, scale, scale)
    root.rotation_euler = Euler((math.radians(tilt), 0, math.radians(yaw)))
    return root


def egg(location, scale=1.0, color=(1.0, 0.85, 0.35), spots=(1.0, 0.55, 0.2), glow=0.0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, location=location)
    shell = bpy.context.active_object
    shell.scale = (0.8 * scale, 0.8 * scale, 1.0 * scale)
    bpy.ops.object.shade_smooth()
    mat = bpy.data.materials.new("Egg")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.3
    bsdf.inputs["Coat Weight"].default_value = 0.6
    # Spots from a Voronoi pattern
    tex = nodes.new("ShaderNodeTexVoronoi")
    tex.inputs["Scale"].default_value = 4.0
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.18
    ramp.color_ramp.elements[0].color = (*spots, 1)
    ramp.color_ramp.elements[1].position = 0.2
    ramp.color_ramp.elements[1].color = (*color, 1)
    links = mat.node_tree.links
    links.new(tex.outputs["Distance"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    if glow > 0:
        links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = glow
    shell.data.materials.append(mat)
    return shell


def coin(location, scale=0.5, rotation=(80, 0, 20)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=1.0, depth=0.18, location=location)
    obj = bpy.context.active_object
    obj.scale = (scale, scale, scale)
    obj.rotation_euler = tuple(math.radians(a) for a in rotation)
    bpy.ops.object.modifier_add(type="BEVEL")
    obj.modifiers["Bevel"].width = 0.05
    obj.modifiers["Bevel"].segments = 3
    bpy.ops.object.shade_smooth()
    mat = bpy.data.materials.new("Coin")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (1.0, 0.75, 0.2, 1)
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.25
    obj.data.materials.append(mat)
    return obj


def ground(color=(0.45, 0.78, 0.4), size=40, z=0.0):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, z))
    plane = bpy.context.active_object
    mat = bpy.data.materials.new("Ground")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    plane.data.materials.append(mat)
    plane.is_shadow_catcher = True
    return plane


# ---------------------------------------------------------------------------------------------------------------
# 2D finishing (Pillow)


def font(name, size):
    from PIL import ImageFont

    return ImageFont.truetype(os.path.join(FONTS, name), size)


def gradient(size, top, bottom, rays=None, center=(0.5, 0.45)):
    """Vertical gradient, with optional sun rays from a point."""
    from PIL import Image, ImageDraw, ImageFilter

    w, h = size
    img = Image.new("RGB", size)
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        draw.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    if rays:
        color, count, alpha = rays
        layer = Image.new("RGBA", size, (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        cx, cy = center[0] * w, center[1] * h
        r = math.hypot(w, h)
        for i in range(count):
            a0 = (i / count) * 2 * math.pi
            a1 = a0 + math.pi / count
            ld.polygon(
                [(cx, cy), (cx + r * math.cos(a0), cy + r * math.sin(a0)), (cx + r * math.cos(a1), cy + r * math.sin(a1))],
                fill=(*color, alpha),
            )
        # A soft glow in the middle
        glow = Image.new("RGBA", size, (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gr = min(w, h) * 0.45
        gd.ellipse([cx - gr, cy - gr, cx + gr, cy + gr], fill=(255, 255, 255, 110))
        glow = glow.filter(ImageFilter.GaussianBlur(min(w, h) * 0.12))
        img = Image.alpha_composite(img.convert("RGBA"), layer)
        img = Image.alpha_composite(img, glow).convert("RGB")
    return img


def sparkles(img, count, seed, color=(255, 255, 255), area=None, size=(10, 34)):
    """Four-point star sparkles."""
    from PIL import Image, ImageDraw, ImageFilter

    rng = random.Random(seed)
    w, h = img.size
    x0, y0, x1, y1 = area or (0, 0, w, h)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        s = rng.uniform(*size)
        thin = s * 0.22
        d.polygon([(x, y - s), (x + thin, y - thin), (x + s, y), (x + thin, y + thin), (x, y + s), (x - thin, y + thin), (x - s, y), (x - thin, y - thin)], fill=(*color, 235))
    glow = layer.filter(ImageFilter.GaussianBlur(4))
    base = img.convert("RGBA")
    base = Image.alpha_composite(base, glow)
    base = Image.alpha_composite(base, layer)
    return base.convert("RGB")


def outline(layer, width, color=(30, 24, 70)):
    """Thick outline around everything visible in a transparent render (the "sticker" look)."""
    from PIL import Image, ImageFilter

    alpha = layer.split()[3].point(lambda a: 255 if a > 40 else 0)
    size = width * 2 + 1
    grown = alpha.filter(ImageFilter.MaxFilter(size if size % 2 else size + 1))
    edge = Image.new("RGBA", layer.size, (*color, 255))
    edge.putalpha(grown.filter(ImageFilter.GaussianBlur(1)))
    edge.alpha_composite(layer)
    return edge


def paste_render(img, path, scale=1.0, offset=(0, 0), shadow=True, stroke=0):
    """Puts a transparent render on the background, with a soft drop shadow under it."""
    from PIL import Image, ImageFilter

    layer = Image.open(path).convert("RGBA")
    if layer.size != img.size or scale != 1.0:
        size = (int(img.size[0] * scale), int(img.size[1] * scale))
        layer = layer.resize(size, Image.LANCZOS)
    if stroke:
        layer = outline(layer, stroke)
    base = img.convert("RGBA")
    pos = (int((img.size[0] - layer.size[0]) / 2 + offset[0]), int((img.size[1] - layer.size[1]) / 2 + offset[1]))
    if shadow:
        alpha = layer.split()[3]
        dark = Image.new("RGBA", layer.size, (20, 20, 50, 0))
        dark.putalpha(alpha.point(lambda a: int(a * 0.45)))
        dark = dark.filter(ImageFilter.GaussianBlur(max(4, img.size[0] // 120)))
        base.alpha_composite(dark, (pos[0] + img.size[0] // 160, pos[1] + img.size[1] // 80))
    base.alpha_composite(layer, pos)
    return base.convert("RGB")


def text(img, value, center, size, fill=(255, 255, 255), stroke=(40, 30, 90), stroke_width=None, face="LuckiestGuy.ttf", angle=0, shadow=True):
    """Big outlined text, the style every top Roblox thumbnail uses."""
    from PIL import Image, ImageDraw

    f = font(face, size)
    sw = stroke_width if stroke_width is not None else max(3, size // 9)
    probe = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    box = probe.textbbox((0, 0), value, font=f, stroke_width=sw)
    tw, th = box[2] - box[0] + 20, box[3] - box[1] + 20
    layer = Image.new("RGBA", (tw, th + size // 6), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if shadow:
        d.text((10 - box[0], 10 - box[1] + size // 10), value, font=f, fill=(*stroke, 255), stroke_width=sw, stroke_fill=(*stroke, 255))
    d.text((10 - box[0], 10 - box[1]), value, font=f, fill=fill, stroke_width=sw, stroke_fill=(*stroke, 255))
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    base = img.convert("RGBA")
    base.alpha_composite(layer, (int(center[0] - layer.size[0] / 2), int(center[1] - layer.size[1] / 2)))
    return base.convert("RGB")


def badge(img, value, center, size, fill=(255, 70, 70), color=(255, 255, 255), angle=-8):
    """A rounded label (e.g. "NEW!", "x1M")."""
    from PIL import Image, ImageDraw

    f = font("LuckiestGuy.ttf", size)
    probe = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    box = probe.textbbox((0, 0), value, font=f)
    pad = size // 2
    w, h = box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2
    layer = Image.new("RGBA", (w + 12, h + 12), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([6, 6, w + 6, h + 6], radius=h // 2, fill=(*fill, 255), outline=(255, 255, 255, 255), width=max(3, size // 10))
    d.text((6 + pad - box[0], 6 + pad - box[1]), value, font=f, fill=color)
    layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    base = img.convert("RGBA")
    base.alpha_composite(layer, (int(center[0] - layer.size[0] / 2), int(center[1] - layer.size[1] / 2)))
    return base.convert("RGB")


def save(img, name, size):
    from PIL import Image

    os.makedirs(OUT, exist_ok=True)
    if img.size != size:
        img = img.resize(size, Image.LANCZOS)
    path = os.path.join(OUT, name)
    img.save(path, optimize=True)
    print(f"[store] {path}")
    return path


def tmp(name):
    return os.path.join(OUT, "_render", name)


# ---------------------------------------------------------------------------------------------------------------
# Shots. Each one is one clear message (research: one subject, saturated colors, few words, readable small).

ICON = (512, 512)
THUMB = (1920, 1080)
NAVY = (30, 24, 70)


def shot_icon():
    """Main icon: a Golden Kitty's happy face fills the frame. No text (the title sits under the icon)."""
    new_scene(1024, 1024, samples=128)
    creature("Kitty", (0, 0, 0), 1.0, yaw=-14, variant="Golden", mouth="open", eye_style="sparkle")
    camera((0.6, -5.4, 2.5), (0.08, 0, 1.3), lens=50)
    path = render(tmp("icon.png"))
    img = gradient((1024, 1024), (70, 225, 255), (120, 60, 230), rays=((255, 255, 255), 18, 46), center=(0.5, 0.42))
    img = paste_render(img, path, stroke=10)
    img = sparkles(img, 9, 3, area=(60, 60, 964, 700), size=(18, 46))
    return save(img, "icon_golden_kitty.png", ICON)


def shot_icon_brand():
    """Alternative icon: the normal orange Kitty, the game's mascot, on a sky background."""
    new_scene(1024, 1024, samples=128)
    creature("Kitty", (0, 0, 0), 1.0, yaw=-14, mouth="open", eye_style="sparkle")
    camera((0.6, -5.4, 2.5), (0.08, 0, 1.3), lens=50)
    path = render(tmp("icon_brand.png"))
    img = gradient((1024, 1024), (110, 220, 255), (40, 120, 235), rays=((255, 255, 255), 18, 40), center=(0.5, 0.42))
    img = paste_render(img, path, stroke=10)
    img = sparkles(img, 7, 5, area=(60, 60, 964, 700), size=(18, 40))
    return save(img, "icon_kitty.png", ICON)


def shot_icon_hatch():
    """Alternative icon: a glowing egg with a Pixel creature popping out."""
    new_scene(1024, 1024, samples=128)
    # The creature sits up behind the egg's top, the egg glowing in front of it
    creature("Cubby", (0, 0.6, 1.2), 0.9, yaw=-10, variant="Pixel", mouth="open", eye_style="sparkle")
    egg((0, -0.5, 0.75), 1.0, color=(1.0, 0.85, 0.4), spots=(1.0, 0.5, 0.25), glow=0.35)
    camera((0.3, -6.8, 2.6), (0, 0, 1.55), lens=50)
    path = render(tmp("icon_hatch.png"))
    img = gradient((1024, 1024), (40, 30, 120), (150, 60, 220), rays=((255, 230, 120), 18, 55), center=(0.5, 0.45))
    img = paste_render(img, path, stroke=10)
    img = sparkles(img, 12, 7, color=(255, 240, 180), area=(60, 60, 964, 760), size=(16, 40))
    return save(img, "icon_hatch.png", ICON)


def shot_thumb_hatch():
    """Thumbnail 1: hatch cute cube pets."""
    new_scene(*THUMB)
    egg((0, 1.2, 1.0), 1.4, glow=0.25)
    creature("Kitty", (-2.6, -0.4, 0), 1.0, yaw=20, mouth="open", eye_style="sparkle")
    creature("Bunny", (2.6, -0.2, 0), 1.0, yaw=-20, eye_style="sparkle")
    creature("Bee", (1.1, -0.6, 2.4), 0.65, yaw=-15, tilt=-10)
    camera((0, -11.5, 3.0), (0, 0, 1.7), lens=40)
    path = render(tmp("thumb_hatch.png"))
    img = gradient(THUMB, (120, 220, 255), (90, 200, 120), rays=((255, 255, 255), 22, 38), center=(0.5, 0.42))
    img = paste_render(img, path, stroke=8)
    img = sparkles(img, 16, 11, area=(100, 60, 1820, 700))
    img = text(img, "HATCH CUTE PETS!", (960, 120), 120, fill=(255, 230, 80), stroke=NAVY)
    return save(img, "thumb_1_hatch.png", THUMB)


def shot_thumb_variants():
    """Thumbnail 2: the rarity ladder, one creature in every variant."""
    new_scene(*THUMB)
    variants = ["Normal", "Golden", "Crystal", "Lava", "Neon", "Pixel"]
    for i, variant in enumerate(variants):
        x = (i - 2.5) * 2.55
        creature("Kitty", (x, 0, 0.0), 0.8 + i * 0.06, yaw=-8 + i * 3, variant=variant, eye_style="sparkle")
    camera((0, -18.5, 2.8), (0, 0, 1.5), lens=40)
    path = render(tmp("thumb_variants.png"))
    img = gradient(THUMB, (25, 20, 70), (90, 40, 160), rays=((255, 255, 255), 24, 26), center=(0.85, 0.45))
    img = paste_render(img, path, stroke=7)
    img = sparkles(img, 22, 13, color=(255, 240, 200), area=(980, 160, 1880, 820))
    img = text(img, "6 RARE VARIANTS", (960, 125), 120, fill=(255, 255, 255), stroke=NAVY)
    labels = ["NORMAL", "GOLDEN", "CRYSTAL", "LAVA", "NEON", "PIXEL"]
    colors = [(230, 230, 230), (255, 205, 60), (150, 230, 255), (255, 120, 40), (90, 255, 170), (200, 140, 255)]
    for i, label in enumerate(labels):
        img = text(img, label, (960 + (i - 2.5) * 300, 820), 46, fill=colors[i], stroke=NAVY, shadow=False)
    return save(img, "thumb_2_variants.png", THUMB)


def shot_thumb_titan():
    """Thumbnail 3: a building-sized Titan next to normal creatures."""
    new_scene(*THUMB)
    creature("Bear", (1.6, 3.5, 0), 4.2, yaw=-18, mouth="open", eye_style="sparkle")
    creature("Kitty", (-3.6, -2.2, 0), 0.75, yaw=25, mouth="open")
    creature("Bunny", (-1.6, -2.8, 0), 0.7, yaw=10, mouth="open")
    camera((-2.5, -15, 1.1), (0.5, 0, 3.6), lens=32)
    path = render(tmp("thumb_titan.png"))
    img = gradient(THUMB, (255, 180, 70), (230, 70, 90), rays=((255, 240, 200), 22, 40), center=(0.6, 0.4))
    img = paste_render(img, path, stroke=8)
    img = text(img, "TITAN!", (430, 230), 210, fill=(255, 225, 60), stroke=NAVY, angle=6)
    return save(img, "thumb_3_titan.png", THUMB)


def shot_thumb_legendary():
    """Thumbnail 4: a Legendary in a burst of light."""
    new_scene(*THUMB)
    creature("Inferno Drake", (0.4, 0, 0), 1.35, yaw=-22, eye_style="sparkle")
    camera((0, -9.5, 2.6), (0.3, 0, 1.8), lens=40)
    path = render(tmp("thumb_legendary.png"))
    img = gradient(THUMB, (255, 210, 80), (200, 60, 200), rays=((255, 255, 255), 26, 60), center=(0.5, 0.48))
    img = paste_render(img, path, stroke=8)
    img = sparkles(img, 26, 17, color=(255, 250, 210), area=(200, 100, 1720, 860), size=(14, 40))
    img = text(img, "LEGENDARY!", (960, 120), 140, fill=(255, 255, 255), stroke=(120, 30, 110))
    img = badge(img, "1 in 2.5M", (1560, 760), 64, fill=(255, 70, 90))
    return save(img, "thumb_4_legendary.png", THUMB)


def shot_thumb_numbers():
    """Thumbnail 5: huge numbers, a team breaking a coin pile."""
    new_scene(*THUMB)
    creature("Ice Dragon", (-2.5, 0.3, 0), 1.0, yaw=28, variant="Neon", mouth="open")
    creature("Phoenix", (2.5, 0.5, 0), 0.95, yaw=-28, variant="Golden", eye_style="sparkle")
    rng = random.Random(9)
    for i in range(40):
        r = 1.3 * math.sqrt(rng.random())
        a = rng.uniform(0, 2 * math.pi)
        height = max(0.0, 1.0 - r) * 1.1
        coin((math.cos(a) * r, 0.2 + math.sin(a) * r * 0.6, 0.08 + height * rng.uniform(0.3, 1.0)), 0.32, rotation=(rng.uniform(0, 40), rng.uniform(-20, 20), rng.uniform(0, 360)))
    camera((0, -12.5, 3.2), (0, 0, 1.4), lens=40)
    path = render(tmp("thumb_numbers.png"))
    img = gradient(THUMB, (60, 200, 255), (40, 70, 200), rays=((255, 255, 255), 20, 34), center=(0.5, 0.5))
    img = paste_render(img, path, stroke=8)
    for value, pos, size, angle in [("+2.5M", (960, 210), 150, 0), ("+840K", (470, 330), 96, 8), ("+12M", (1480, 300), 110, -8)]:
        img = text(img, value, pos, size, fill=(255, 225, 60), stroke=NAVY, angle=angle)
    return save(img, "thumb_5_numbers.png", THUMB)


def shot_thumb_collection():
    """Thumbnail 6: a crowd of different creatures (50 to collect)."""
    new_scene(*THUMB)
    names = ["Cubby", "Kitty", "Bunny", "Bear", "Bee", "Fox", "Frog", "Penguin", "Crab", "Owl", "Yeti", "Imp", "Ice Fox", "Bot"]
    names = [n for n in names if n in cb.SPECIES]
    rng = random.Random(4)
    for i, name in enumerate(names):
        row = i // 7
        col = i % 7
        x = (col - 3) * 2.3 + (1.15 if row == 1 else 0)
        y = row * 3.0
        creature(name, (x, y, 0), 1.05, yaw=rng.uniform(-25, 25), eye_style="sparkle" if i % 3 == 0 else cb.SPECIES[name].get("eye_style", "oval"))
    camera((0, -16.5, 7.0), (0, 1.5, 1.0), lens=36)
    path = render(tmp("thumb_collection.png"))
    img = gradient(THUMB, (130, 230, 255), (120, 220, 140), rays=((255, 255, 255), 20, 30), center=(0.5, 0.3))
    img = paste_render(img, path, stroke=7)
    img = text(img, "COLLECT 50 CUBE PETS!", (960, 120), 112, fill=(255, 255, 255), stroke=NAVY)
    return save(img, "thumb_6_collection.png", THUMB)


SHOTS = {
    "icon": shot_icon,
    "icon_brand": shot_icon_brand,
    "icon_hatch": shot_icon_hatch,
    "hatch": shot_thumb_hatch,
    "variants": shot_thumb_variants,
    "titan": shot_thumb_titan,
    "legendary": shot_thumb_legendary,
    "numbers": shot_thumb_numbers,
    "collection": shot_thumb_collection,
}


def main():
    names = sys.argv[1:] or list(SHOTS)
    for name in names:
        SHOTS[name]()


if __name__ == "__main__":
    main()
