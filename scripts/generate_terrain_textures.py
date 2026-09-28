#!/usr/bin/env python3
"""
generate_terrain_textures.py
-----------------------------
Generates rich, procedural, seamless tileable textures (512x512) for all O'Neill Cylinder terrain types
with multiple distinctive variations per type:
- Grass: lush meadow, clover/wildflower meadow, dense alpine turf
- Sand: fine shoreline beach, wind-rippled dune, coarse pebble sand
- Dirt: dark rich loam, reddish clay loam, pebbled cracked earth
- Farmland: dark tilled plowed furrows, golden wheat rows, sprouting crop rows
- Rocks: fractured slate strata, weathered granite boulder face, scree gravel
- Concrete: industrial foundation slabs, modular pavement blocks, weathered reinforced concrete
- Road: dark asphalt with markings, weathered highway asphalt, aggregate paved street
"""

import os
import math
import numpy as np
from PIL import Image

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures", "terrain")
SIZE = 512

def periodic_noise_2d(width, height, scale, octaves=4, persistence=0.5, seed=0):
    """Generates seamless 2D toroidal Perlin-like noise using periodic sine/cosine harmonics."""
    rng = np.random.RandomState(seed)
    grid = np.zeros((height, width), dtype=np.float32)
    
    y_coords, x_coords = np.indices((height, width))
    u = x_coords / width * 2.0 * np.pi
    v = y_coords / height * 2.0 * np.pi
    
    freq = 1.0
    amp = 1.0
    total_amp = 0.0
    
    for _ in range(octaves):
        k_count = int(scale * freq)
        for _ in range(max(4, k_count)):
            kx = rng.randint(-k_count, k_count + 1)
            ky = rng.randint(-k_count, k_count + 1)
            if kx == 0 and ky == 0:
                continue
            phase = rng.uniform(0, 2 * np.pi)
            weight = amp / math.sqrt(kx * kx + ky * ky)
            grid += weight * np.sin(kx * u + ky * v + phase)
            total_amp += weight
        freq *= 2.0
        amp *= persistence
        
    grid = (grid - grid.min()) / (grid.max() - grid.min() + 1e-6)
    return grid

def save_rgb(img_arr, filename):
    img_arr = np.clip(img_arr * 255.0, 0, 255).astype(np.uint8)
    img = Image.fromarray(img_arr, mode="RGB")
    path = os.path.join(OUT_DIR, filename)
    img.save(path)
    print(f"Generated: {path}")

def generate_grass_textures():
    # Grass 0: Lush meadow grass
    n1 = periodic_noise_2d(SIZE, SIZE, scale=6, octaves=5, seed=101)
    n2 = periodic_noise_2d(SIZE, SIZE, scale=24, octaves=4, seed=102)
    base_col = np.array([0.22, 0.52, 0.16])
    high_col = np.array([0.35, 0.68, 0.22])
    dark_col = np.array([0.14, 0.36, 0.10])
    
    g0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        g0[:, :, c] = base_col[c] + (n1 - 0.5) * (high_col[c] - dark_col[c]) + (n2 - 0.5) * 0.08
    save_rgb(g0, "grass_0.png")
    save_rgb(g0, "grass.png") # Base compatibility
    
    # Grass 1: Wild meadow with subtle yellow-green flower flecks
    n1 = periodic_noise_2d(SIZE, SIZE, scale=8, octaves=5, seed=111)
    n2 = periodic_noise_2d(SIZE, SIZE, scale=32, octaves=3, seed=112)
    base_col = np.array([0.26, 0.56, 0.18])
    yellow_col = np.array([0.55, 0.62, 0.20])
    flower_mask = (n2 > 0.82).astype(np.float32)
    
    g1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        g1[:, :, c] = base_col[c] * (0.8 + 0.4 * n1)
        g1[:, :, c] = g1[:, :, c] * (1.0 - flower_mask) + yellow_col[c] * flower_mask
    save_rgb(g1, "grass_1.png")
    
    # Grass 2: Dense deep alpine turf
    n1 = periodic_noise_2d(SIZE, SIZE, scale=5, octaves=5, seed=121)
    n2 = periodic_noise_2d(SIZE, SIZE, scale=20, octaves=4, seed=122)
    base_col = np.array([0.16, 0.42, 0.15])
    dark_col = np.array([0.10, 0.28, 0.08])
    high_col = np.array([0.24, 0.52, 0.20])
    
    g2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        g2[:, :, c] = base_col[c] + (n1 - 0.5) * (high_col[c] - dark_col[c]) + (n2 - 0.5) * 0.05
    save_rgb(g2, "grass_2.png")

def generate_sand_textures():
    # Sand 0: Fine warm shoreline beach sand
    n1 = periodic_noise_2d(SIZE, SIZE, scale=5, octaves=4, seed=201)
    n2 = periodic_noise_2d(SIZE, SIZE, scale=36, octaves=3, seed=202)
    base_col = np.array([0.88, 0.74, 0.48])
    dark_col = np.array([0.76, 0.62, 0.38])
    
    s0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        s0[:, :, c] = base_col[c] + (n1 - 0.5) * 0.12 + (n2 - 0.5) * 0.06
    save_rgb(s0, "sand_0.png")
    save_rgb(s0, "sand.png")
    
    # Sand 1: Wind-rippled dune sand
    y_coords, x_coords = np.indices((SIZE, SIZE))
    v = y_coords / SIZE * 2.0 * np.pi
    u = x_coords / SIZE * 2.0 * np.pi
    n_warp = periodic_noise_2d(SIZE, SIZE, scale=4, octaves=3, seed=211)
    ripples = np.sin(v * 16.0 + n_warp * 4.0) * 0.5 + 0.5
    n_grain = periodic_noise_2d(SIZE, SIZE, scale=32, octaves=3, seed=212)
    
    s1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_col = np.array([0.86, 0.72, 0.46])
    for c in range(3):
        s1[:, :, c] = base_col[c] + (ripples - 0.5) * 0.14 + (n_grain - 0.5) * 0.05
    save_rgb(s1, "sand_1.png")
    
    # Sand 2: Coarse coastal sand with wet pebble flecks
    n1 = periodic_noise_2d(SIZE, SIZE, scale=6, octaves=4, seed=221)
    n2 = periodic_noise_2d(SIZE, SIZE, scale=40, octaves=4, seed=222)
    base_col = np.array([0.82, 0.68, 0.44])
    pebble_mask = (n2 > 0.85).astype(np.float32)
    pebble_col = np.array([0.45, 0.40, 0.36])
    
    s2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        s2[:, :, c] = base_col[c] + (n1 - 0.5) * 0.10
        s2[:, :, c] = s2[:, :, c] * (1.0 - pebble_mask) + pebble_col[c] * pebble_mask
    save_rgb(s2, "sand_2.png")

def generate_dirt_textures():
    # Dirt 0: Rich dark loamy earth
    n1 = periodic_noise_2d(SIZE, SIZE, scale=6, octaves=5, seed=301)
    n2 = periodic_noise_2d(SIZE, SIZE, scale=28, octaves=4, seed=302)
    base_col = np.array([0.42, 0.28, 0.17])
    
    d0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        d0[:, :, c] = base_col[c] + (n1 - 0.5) * 0.12 + (n2 - 0.5) * 0.08
    save_rgb(d0, "dirt_0.png")
    save_rgb(d0, "dirt.png")
    
    # Dirt 1: Reddish clay loam
    n1 = periodic_noise_2d(SIZE, SIZE, scale=7, octaves=5, seed=311)
    n2 = periodic_noise_2d(SIZE, SIZE, scale=32, octaves=3, seed=312)
    base_col = np.array([0.50, 0.29, 0.18])
    dark_col = np.array([0.35, 0.18, 0.10])
    
    d1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        d1[:, :, c] = base_col[c] + (n1 - 0.5) * 0.14 + (n2 - 0.5) * 0.06
    save_rgb(d1, "dirt_1.png")
    
    # Dirt 2: Dry cracked earth with small stone grit
    n1 = periodic_noise_2d(SIZE, SIZE, scale=5, octaves=5, seed=321)
    n_crack = periodic_noise_2d(SIZE, SIZE, scale=18, octaves=4, seed=322)
    crack_mask = (abs(n_crack - 0.5) < 0.04).astype(np.float32)
    base_col = np.array([0.46, 0.34, 0.22])
    crack_col = np.array([0.22, 0.15, 0.09])
    
    d2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        d2[:, :, c] = base_col[c] + (n1 - 0.5) * 0.10
        d2[:, :, c] = d2[:, :, c] * (1.0 - crack_mask * 0.8) + crack_col[c] * (crack_mask * 0.8)
    save_rgb(d2, "dirt_2.png")

def generate_farmland_textures():
    y_coords, x_coords = np.indices((SIZE, SIZE))
    v = y_coords / SIZE * 2.0 * np.pi
    u = x_coords / SIZE * 2.0 * np.pi
    
    # Farmland 0: Dark tilled soil with parallel plowed furrows
    furrow_wave = np.sin(v * 24.0) * 0.5 + 0.5
    n_soil = periodic_noise_2d(SIZE, SIZE, scale=20, octaves=4, seed=401)
    f0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_ridge = np.array([0.32, 0.20, 0.12])
    base_trough = np.array([0.18, 0.11, 0.06])
    for c in range(3):
        f0[:, :, c] = base_trough[c] + furrow_wave * (base_ridge[c] - base_trough[c]) + (n_soil - 0.5) * 0.05
    save_rgb(f0, "farmland_0.png")
    save_rgb(f0, "farmland.png")
    
    # Farmland 1: Golden wheat / grain rows
    crop_rows = np.sin(v * 20.0) * 0.5 + 0.5
    n_grain = periodic_noise_2d(SIZE, SIZE, scale=16, octaves=4, seed=411)
    f1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    wheat_col = np.array([0.72, 0.58, 0.24])
    soil_col = np.array([0.28, 0.18, 0.10])
    for c in range(3):
        f1[:, :, c] = soil_col[c] + crop_rows * (wheat_col[c] - soil_col[c]) + (n_grain - 0.5) * 0.08
    save_rgb(f1, "farmland_1.png")
    
    # Farmland 2: Sprouting green crop rows on dark furrowed soil
    crop_rows = np.sin(v * 24.0) * 0.5 + 0.5
    n_leaf = periodic_noise_2d(SIZE, SIZE, scale=24, octaves=4, seed=421)
    sprout_mask = (crop_rows > 0.4).astype(np.float32) * (n_leaf > 0.45).astype(np.float32)
    f2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    soil_col = np.array([0.22, 0.14, 0.08])
    sprout_col = np.array([0.38, 0.65, 0.18])
    for c in range(3):
        f2[:, :, c] = soil_col[c] + (crop_rows * 0.08)
        f2[:, :, c] = f2[:, :, c] * (1.0 - sprout_mask) + sprout_col[c] * sprout_mask
    save_rgb(f2, "farmland_2.png")

def generate_rocks_textures():
    # Rocks 0: Craggy fractured mountain rock face and slate strata
    n1 = periodic_noise_2d(SIZE, SIZE, scale=4, octaves=5, seed=501)
    n2 = periodic_noise_2d(SIZE, SIZE, scale=18, octaves=4, seed=502)
    n_strata = np.sin(n1 * 12.0 + n2 * 4.0) * 0.5 + 0.5
    base_col = np.array([0.38, 0.40, 0.43])
    dark_col = np.array([0.22, 0.23, 0.25])
    high_col = np.array([0.55, 0.58, 0.62])
    
    r0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        r0[:, :, c] = dark_col[c] + n_strata * (high_col[c] - dark_col[c]) + (n2 - 0.5) * 0.08
    save_rgb(r0, "rocks_0.png")
    save_rgb(r0, "rocks.png")
    
    # Rocks 1: Weathered granite boulders with moss accents
    n1 = periodic_noise_2d(SIZE, SIZE, scale=6, octaves=5, seed=511)
    n2 = periodic_noise_2d(SIZE, SIZE, scale=24, octaves=4, seed=512)
    moss_mask = (n1 < 0.28).astype(np.float32) * (n2 > 0.45).astype(np.float32)
    base_col = np.array([0.45, 0.46, 0.48])
    moss_col = np.array([0.28, 0.38, 0.18])
    
    r1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        r1[:, :, c] = base_col[c] + (n1 - 0.5) * 0.12 + (n2 - 0.5) * 0.06
        r1[:, :, c] = r1[:, :, c] * (1.0 - moss_mask) + moss_col[c] * moss_mask
    save_rgb(r1, "rocks_1.png")
    
    # Rocks 2: Scree gravel field with angular stone fragments
    n1 = periodic_noise_2d(SIZE, SIZE, scale=14, octaves=5, seed=521)
    n2 = periodic_noise_2d(SIZE, SIZE, scale=36, octaves=3, seed=522)
    base_col = np.array([0.42, 0.43, 0.45])
    r2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        r2[:, :, c] = base_col[c] + (n1 - 0.5) * 0.18 + (n2 - 0.5) * 0.10
    save_rgb(r2, "rocks_2.png")

def generate_concrete_textures():
    y_coords, x_coords = np.indices((SIZE, SIZE))
    v = y_coords / SIZE * 2.0 * np.pi
    u = x_coords / SIZE * 2.0 * np.pi
    
    # Concrete 0: Industrial foundation slabs with expansion joints
    joint_x = (abs(np.sin(u * 4.0)) < 0.025).astype(np.float32)
    joint_y = (abs(np.sin(v * 4.0)) < 0.025).astype(np.float32)
    joints = np.maximum(joint_x, joint_y)
    n_grain = periodic_noise_2d(SIZE, SIZE, scale=32, octaves=3, seed=601)
    
    c0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_col = np.array([0.65, 0.67, 0.70])
    for c in range(3):
        c0[:, :, c] = (base_col[c] + (n_grain - 0.5) * 0.05) * (1.0 - joints * 0.6)
    save_rgb(c0, "concrete_0.png")
    save_rgb(c0, "concrete.png")
    
    # Concrete 1: Modular pavement blocks
    joint_x = (abs(np.sin(u * 8.0)) < 0.035).astype(np.float32)
    joint_y = (abs(np.sin(v * 8.0)) < 0.035).astype(np.float32)
    joints = np.maximum(joint_x, joint_y)
    n_grain = periodic_noise_2d(SIZE, SIZE, scale=24, octaves=3, seed=611)
    
    c1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_col = np.array([0.58, 0.60, 0.63])
    for c in range(3):
        c1[:, :, c] = (base_col[c] + (n_grain - 0.5) * 0.07) * (1.0 - joints * 0.55)
    save_rgb(c1, "concrete_1.png")
    
    # Concrete 2: Weathered reinforced concrete with subtle stains
    n1 = periodic_noise_2d(SIZE, SIZE, scale=4, octaves=4, seed=621)
    n_grain = periodic_noise_2d(SIZE, SIZE, scale=28, octaves=3, seed=622)
    c2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_col = np.array([0.62, 0.63, 0.65])
    for c in range(3):
        c2[:, :, c] = base_col[c] + (n1 - 0.5) * 0.12 + (n_grain - 0.5) * 0.06
    save_rgb(c2, "concrete_2.png")

def generate_road_textures():
    y_coords, x_coords = np.indices((SIZE, SIZE))
    v = y_coords / SIZE * 2.0 * np.pi
    u = x_coords / SIZE * 2.0 * np.pi
    
    # Road 0: Dark asphalt highway with dashed center line
    center_stripe = (abs(np.sin(u * 1.0)) < 0.03).astype(np.float32) * (np.sin(v * 8.0) > 0.0).astype(np.float32)
    n_asphalt = periodic_noise_2d(SIZE, SIZE, scale=32, octaves=3, seed=701)
    
    r0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_col = np.array([0.16, 0.17, 0.18])
    line_col = np.array([0.90, 0.85, 0.30]) # Highway yellow line
    for c in range(3):
        r0[:, :, c] = base_col[c] + (n_asphalt - 0.5) * 0.04
        r0[:, :, c] = r0[:, :, c] * (1.0 - center_stripe) + line_col[c] * center_stripe
    save_rgb(r0, "road_0.png")
    save_rgb(r0, "road.png")
    
    # Road 1: Weathered asphalt with subtle aggregate
    n_asphalt = periodic_noise_2d(SIZE, SIZE, scale=24, octaves=4, seed=711)
    r1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_col = np.array([0.22, 0.23, 0.24])
    for c in range(3):
        r1[:, :, c] = base_col[c] + (n_asphalt - 0.5) * 0.06
    save_rgb(r1, "road_1.png")
    
    # Road 2: Urban paved road with white edge border
    edge_stripe = ((u < 0.08) | (u > 2.0 * np.pi - 0.08)).astype(np.float32)
    n_asphalt = periodic_noise_2d(SIZE, SIZE, scale=28, octaves=3, seed=721)
    
    r2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_col = np.array([0.18, 0.19, 0.20])
    line_col = np.array([0.88, 0.88, 0.90])
    for c in range(3):
        r2[:, :, c] = base_col[c] + (n_asphalt - 0.5) * 0.04
        r2[:, :, c] = r2[:, :, c] * (1.0 - edge_stripe * 0.7) + line_col[c] * (edge_stripe * 0.7)
    save_rgb(r2, "road_2.png")

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Generating procedural seamless terrain textures...")
    generate_grass_textures()
    generate_sand_textures()
    generate_dirt_textures()
    generate_farmland_textures()
    generate_rocks_textures()
    generate_concrete_textures()
    generate_road_textures()
    print("All terrain textures generated successfully!")

if __name__ == "__main__":
    main()
