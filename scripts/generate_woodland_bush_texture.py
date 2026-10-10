"""Rebuild the bush's original, procedural 512px leaf/bark atlas (Pillow only)."""
from pathlib import Path
import math
import random
from PIL import Image, ImageDraw

rng = random.Random(61409)
size = 512
image = Image.new('RGB', (size, size))
pixels = image.load()
for y in range(size):
    v = y / (size - 1)
    for x in range(size):
        if x < 384:
            u = x / 383
            # Neutral reflectance: the biome palette supplies the leaf pigment.
            grain = rng.gauss(0, 2.5)
            mottling = 7 * math.sin(u * 32 + math.sin(v * 24)) * math.sin(v * 37)
            ribs = 3 * math.sin((v - abs(u - .5) * .4) * 180)
            value = int(170 + mottling + ribs + grain - 35 * abs(u - .5))
            pixels[x, y] = (value, value, value)
        else:
            u = (x - 384) / 127
            furrow = math.sin(u * 85 + math.sin(v * 25) * .6)
            value = 0.72 + 0.18 * furrow + rng.uniform(-.07, .07)
            pixels[x, y] = tuple(int(c * value) for c in (119, 98, 74))
veins = Image.new('RGB', image.size)
veins.paste(image)
draw = ImageDraw.Draw(veins)
# Fine secondary venation. UVs follow the leaf's actual folded surface.
for i in range(1, 15):
    y = int(i / 16 * size)
    for sign in (-1, 1):
        draw.line([(192, y), (192 + sign * 70, y - 19), (192 + sign * 177, y - 60)], fill=(188, 188, 188), width=1)
draw.line([(192, 0), (192, 511)], fill=(202, 202, 202), width=2)
image = Image.blend(image, veins, .7)
output = Path(__file__).resolve().parents[1] / 'assets/maps/default/models/ground_clutter/woodland_bush_atlas.png'
image.save(output)
print(output)
