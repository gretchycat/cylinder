#!/usr/bin/env python3
"""Generate a seamless per-biome ground-cover atlas for the terrain shader."""

from pathlib import Path
import math
import random

from PIL import Image, ImageDraw


TILE = 224
GUTTER = 16
CELL = TILE + GUTTER * 2
SCALE = 2
OUTPUT = Path(__file__).resolve().parents[1] / "assets/maps/default/textures/clutter_cover_atlas.png"
GRASS_SOURCE = OUTPUT.parent / "sparse_grass_diff_1k.jpg"


def _wrapped_polygon(draw: ImageDraw.ImageDraw, points: list[tuple[float, float]], color: tuple[int, ...]) -> None:
    size = TILE * SCALE
    for ox in (-size, 0, size):
        for oy in (-size, 0, size):
            draw.polygon([(round(x + ox), round(y + oy)) for x, y in points], fill=color)


def _wrapped_ellipse(draw: ImageDraw.ImageDraw, box: tuple[float, float, float, float], color: tuple[int, ...]) -> None:
    size = TILE * SCALE
    for ox in (-size, 0, size):
        for oy in (-size, 0, size):
            draw.ellipse(tuple(round(value + (ox if index % 2 == 0 else oy)) for index, value in enumerate(box)), fill=color)


def make_tile(kind: str, seed: int) -> Image.Image:
    rng = random.Random(seed)
    size = TILE * SCALE
    if kind == "grass":
        # Poly Haven's tileable, 2m Sparse Grass diffuse is blended over the
        # existing terrain texture as the cached grassland ground-cover layer.
        tile = Image.open(GRASS_SOURCE).convert("RGB").resize((TILE, TILE), Image.Resampling.LANCZOS).convert("RGBA")
        tile.putalpha(170)
        padded = Image.new("RGBA", (CELL, CELL))
        padded.paste(tile, (GUTTER, GUTTER))
        padded.paste(tile.crop((TILE - GUTTER, 0, TILE, TILE)), (0, GUTTER))
        padded.paste(tile.crop((0, 0, GUTTER, TILE)), (GUTTER + TILE, GUTTER))
        padded.paste(tile.crop((0, TILE - GUTTER, TILE, TILE)), (GUTTER, 0))
        padded.paste(tile.crop((0, 0, TILE, GUTTER)), (GUTTER, GUTTER + TILE))
        padded.paste(tile.crop((TILE - GUTTER, TILE - GUTTER, TILE, TILE)), (0, 0))
        padded.paste(tile.crop((0, TILE - GUTTER, GUTTER, TILE)), (GUTTER + TILE, 0))
        padded.paste(tile.crop((TILE - GUTTER, 0, TILE, GUTTER)), (0, GUTTER + TILE))
        padded.paste(tile.crop((0, 0, GUTTER, GUTTER)), (GUTTER + TILE, GUTTER + TILE))
        return padded

    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile, "RGBA")

    if kind == "farmland":
        # Small paired seedlings follow the rows already visible in the soil map.
        for row in range(9):
            y = (row + 0.5) * size / 9.0
            x = rng.uniform(0, size)
            while x < size:
                x += rng.uniform(18.0, 34.0) * SCALE
                cx, cy = x, y + rng.uniform(-3.0, 3.0) * SCALE
                color = rng.choice([(73, 126, 38, 190), (102, 151, 48, 190), (54, 106, 39, 195)])
                for sign in (-1, 1):
                    points = [(cx, cy), (cx + sign * 5 * SCALE, cy - 9 * SCALE),
                              (cx + sign * 2 * SCALE, cy + 2 * SCALE)]
                    _wrapped_polygon(draw, points, color)

    elif kind in ("dirt", "rocks", "sand"):
        palettes = {
            "dirt": [(70, 48, 32, 185), (105, 75, 48, 175), (45, 91, 35, 175)],
            "rocks": [(94, 99, 105, 205), (130, 130, 126, 195), (73, 78, 86, 205)],
            "sand": [(143, 119, 81, 170), (183, 154, 105, 165), (119, 103, 78, 170)],
        }
        count = 150 if kind == "dirt" else (240 if kind == "rocks" else 110)
        for _ in range(count):
            cx, cy = rng.uniform(0, size), rng.uniform(0, size)
            radius = rng.uniform(1.4, 4.5) * SCALE
            _wrapped_ellipse(draw, (cx - radius, cy - radius * 0.65, cx + radius, cy + radius * 0.65), rng.choice(palettes[kind]))
        if kind == "dirt":
            for _ in range(95):
                cx, cy = rng.uniform(0, size), rng.uniform(0, size)
                _wrapped_polygon(draw, [(cx - 2 * SCALE, cy), (cx, cy - 7 * SCALE), (cx + 2 * SCALE, cy)], (66, 119, 43, 185))

    # Downsample for smooth blade edges, then add periodic gutters so filtering
    # and mipmaps cannot sample a neighboring biome's atlas cell.
    tile = tile.resize((TILE, TILE), Image.Resampling.LANCZOS)
    padded = Image.new("RGBA", (CELL, CELL))
    padded.paste(tile, (GUTTER, GUTTER))
    padded.paste(tile.crop((TILE - GUTTER, 0, TILE, TILE)), (0, GUTTER))
    padded.paste(tile.crop((0, 0, GUTTER, TILE)), (GUTTER + TILE, GUTTER))
    padded.paste(tile.crop((0, TILE - GUTTER, TILE, TILE)), (GUTTER, 0))
    padded.paste(tile.crop((0, 0, TILE, GUTTER)), (GUTTER, GUTTER + TILE))
    padded.paste(tile.crop((TILE - GUTTER, TILE - GUTTER, TILE, TILE)), (0, 0))
    padded.paste(tile.crop((0, TILE - GUTTER, GUTTER, TILE)), (GUTTER + TILE, 0))
    padded.paste(tile.crop((TILE - GUTTER, 0, TILE, GUTTER)), (0, GUTTER + TILE))
    padded.paste(tile.crop((0, 0, GUTTER, GUTTER)), (GUTTER + TILE, GUTTER + TILE))
    return padded


def main() -> None:
    atlas = Image.new("RGBA", (CELL * 3, CELL * 2), (0, 0, 0, 0))
    # Atlas cell coordinates are documented in cylinder_terrain.gdshader.
    cells = [("grass", 11), ("farmland", 23), ("dirt", 37), ("rocks", 41), ("sand", 53)]
    for index, (kind, seed) in enumerate(cells):
        atlas.paste(make_tile(kind, seed), ((index % 3) * CELL, (index // 3) * CELL))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUTPUT, optimize=True)


if __name__ == "__main__":
    main()
