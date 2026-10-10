"""A short GIF of the creatures' moves, the same ones the game plays (game/client/Controllers/PetFollow.luau):
legs walking in diagonal pairs, wings flapping, tail wagging, the open "D" mouth, hopping and hovering.

    python art/blender/anim_preview.py        -> art/renders/moves.gif
"""

import math
import os
import sys

import bpy  # noqa: F401  (loads mathutils)
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_art as sa  # noqa: E402

LEG_PHASE = {"legFL": 0.0, "legBR": 0.0, "legFR": math.pi, "legBL": math.pi}
FRAMES = 24


def pieces(root):
    """Each moving part with its anim name and the point it turns around (in the creature's space)."""
    import cubelings as cb

    out = []
    for part in root.children:
        anim = cb.anim_name(part) if part.get("anim") else ""
        corners = [Vector(c) for c in part.bound_box]
        lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
        hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
        center = (lo + hi) / 2
        pivot = center
        if anim.startswith("leg"):
            pivot = Vector((center.x, center.y, hi.z))
        elif anim.startswith("wing"):
            pivot = Vector((lo.x if center.x > 0 else hi.x, center.y, center.z))
        elif anim == "tail":
            pivot = Vector((center.x, lo.y if center.y > 0 else hi.y, center.z))
        out.append((part, anim, pivot, part.matrix_basis.copy()))
    return out


def pose(items, t, walking, mouth_open):
    for part, anim, pivot, base in items:
        rot = Matrix.Identity(4)
        if anim in LEG_PHASE and walking:
            rot = Matrix.Rotation(math.sin(t * 2 * math.pi * 2 + LEG_PHASE[anim]) * math.radians(28), 4, "X")
        elif anim.startswith("wing"):
            side = 1 if anim == "wingL" else -1
            rot = Matrix.Rotation(side * (math.sin(t * 2 * math.pi * 3) * math.radians(32) + math.radians(8)), 4, "Y")
        elif anim == "tail":
            rot = Matrix.Rotation(math.sin(t * 2 * math.pi * 2) * math.radians(22), 4, "Z")
        part.matrix_basis = Matrix.Translation(pivot) @ rot @ Matrix.Translation(-pivot) @ base
        if anim == "mouthO":
            part.hide_render = not mouth_open
        elif anim == "mouthC":
            part.hide_render = mouth_open


def main():
    from PIL import Image

    sa.new_scene(960, 540, samples=24)
    creatures = [
        ("Kitty", (-3.2, 0, 0), False),
        ("Bat", (0.0, 0, 1.0), True),
        ("Inferno Drake", (3.4, 0, 1.2), True),
    ]
    rigs = []
    for name, loc, flying in creatures:
        root = sa.creature(name, loc, 1.0, yaw=-12, _mouths="both")
        rigs.append((root, Vector(loc), flying, pieces(root)))
    sa.camera((0, -13, 3.0), (0, 0, 1.6), lens=38)
    frames = []
    for f in range(FRAMES):
        t = f / FRAMES
        for i, (root, loc, flying, items) in enumerate(rigs):
            hop = 0.0 if flying else abs(math.sin(t * 2 * math.pi * 2)) * 0.35
            bob = math.sin(t * 2 * math.pi + i) * 0.25 if flying else 0.0
            root.location = loc + Vector((0, 0, hop + bob))
            mouth_open = (f // 6) % 2 == 1
            pose(items, t, walking=True, mouth_open=mouth_open)
        path = sa.render(sa.tmp(f"move_{f:02d}.png"))
        img = sa.gradient((960, 540), (150, 220, 255), (110, 200, 140))
        img = sa.paste_render(img, path, stroke=4)
        frames.append(img.convert("P", palette=Image.ADAPTIVE, colors=200))
    out = os.path.join(sa.ROOT, "renders", "moves.gif")
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=70, loop=0, optimize=True)
    print("[moves]", out)


if __name__ == "__main__":
    main()
