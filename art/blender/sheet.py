# The riding model sheet: the views of Ride.png (pony.py ride) and the saddle alone (the first view of
# Saddle.png, saddle.py), labeled.   python art/blender/sheet.py Ride.png Saddle.png RideSheet.png
import sys
from PIL import Image, ImageDraw, ImageFont
ride = Image.open(sys.argv[1]); saddle = Image.open(sys.argv[2]); out = sys.argv[3]
w = ride.height
tiles = [ride.crop((i * w, 0, (i + 1) * w, w)) for i in range(ride.width // w)]
sw = saddle.height
alone = saddle.crop((0, 0, sw, sw)).resize((w, w))
names = ["3/4 FRONT", "FRONT", "SIDE", "3/4 REAR", "BACK", "TOP", "BOTTOM", "SADDLE ALONE"]
tiles.append(alone)
pad = 50
sheet = Image.new("RGB", (4 * w, 2 * (w + pad)), (226, 223, 218))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
except OSError:
    font = ImageFont.load_default()
for i, (t, n) in enumerate(zip(tiles, names)):
    x, y = (i % 4) * w, (i // 4) * (w + pad)
    sheet.paste(t, (x, y))
    tw = d.textlength(n, font=font)
    d.text((x + (w - tw) / 2, y + w + 10), n, fill=(90, 70, 60), font=font)
sheet.save(out)
print("wrote", out)
