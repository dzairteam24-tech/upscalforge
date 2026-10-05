"""Builds the phone-friendly 3D preview page for a creature: python art/viewer/build.py Kitty out.html

The page embeds the .glb, the palette roles and the concept image, and shows the variants live
(Golden, Crystal, Lava, Neon, Pixel) with three.js."""

import base64
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
name = sys.argv[1] if len(sys.argv) > 1 else "Kitty"
out = sys.argv[2] if len(sys.argv) > 2 else f"{name}-3d.html"


def b64(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()


with open(os.path.join(ROOT, "viewer", "template.html")) as f:
    page = f.read()
with open(os.path.join(ROOT, "models", f"{name}_palette.json")) as f:
    palette = json.load(f)
page = (
    page.replace("__GLB__", b64(os.path.join(ROOT, "models", f"{name}.glb")))
    .replace("__CONCEPT__", b64(os.path.join(ROOT, "concepts", f"{name}_small.jpg")))
    .replace("__PALETTE__", json.dumps(palette))
    .replace("__TRIS__", sys.argv[3] if len(sys.argv) > 3 else "")
)
with open(out, "w") as f:
    f.write(page)
print("wrote", out)
