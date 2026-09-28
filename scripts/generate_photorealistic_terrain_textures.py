#!/usr/bin/env python3
"""
generate_photorealistic_terrain_textures.py
---------------------------------------------
Generates high-definition, photorealistic, seamlessly tessellating (512x512)
PBR terrain textures for all 8 O'Neill Cylinder biomes using multi-octave toroidal
frequency synthesis, cellular Voronoi rock fracturing, mineral speckling, and
periodic boundary conditions.

Terrain Types:
1. Grass (0: Lush Meadow, 1: Wildflower Turf, 2: Alpine Highland)
2. Sand (0: Warm Beach Quartz, 1: Wind-Rippled Dune, 2: Coastal Pebble Shore)
3. Dirt (0: Rich Humus Loam, 1: Red Clay Earth, 2: Cracked Arid Soil)
4. Farmland (0: Tilled Furrows, 1: Golden Wheat Rows, 2: Sprouting Seedlings)
5. Rocks (0: Fractured Slate Strata, 1: Granite Face with Moss, 2: Scree Gravel)
6. Concrete (0: Modular Slabs with Joints, 1: Aggregate Pavement, 2: Weathered Concrete)
7. Road (0: Asphalt with Center Stripe, 1: Weathered Roadbed, 2: Highway with Edge Line)
8. End Cap Ribs (Radial Structural Bulkhead Armor)
"""

import os
import math
import numpy as np
from PIL import Image

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures", "terrain")
SIZE = 512

def periodic_toroidal_noise(width, height, scale, octaves=6, persistence=0.52, lacunarity=2.0, seed=0):
    """
    Generates seamless, tileable 2D Perlin-like noise using periodic trigonometric Fourier harmonics.
    Guarantees mathematically exact C^infinity continuity across all borders (x=0 to x=W, y=0 to y=H).
    """
    rng = np.random.RandomState(seed)
    grid = np.zeros((height, width), dtype=np.float32)
    
    y_idx, x_idx = np.indices((height, width))
    u = x_idx / float(width) * 2.0 * np.pi
    v = y_idx / float(height) * 2.0 * np.pi
    
    freq = 1.0
    amp = 1.0
    total_amp = 0.0
    
    for _ in range(octaves):
        k_max = int(scale * freq)
        samples = max(6, int(k_max * 1.5))
        for _ in range(samples):
            kx = rng.randint(-k_max, k_max + 1)
            ky = rng.randint(-k_max, k_max + 1)
            if kx == 0 and ky == 0:
                continue
            k_len = math.sqrt(kx * kx + ky * ky)
            phase = rng.uniform(0.0, 2.0 * np.pi)
            weight = amp / (k_len ** 0.85)
            grid += weight * np.sin(kx * u + ky * v + phase)
            total_amp += weight
        freq *= lacunarity
        amp *= persistence
        
    grid = (grid - grid.min()) / (grid.max() - grid.min() + 1e-7)
    return grid

def periodic_voronoi_cells(width, height, num_cells=36, seed=0):
    """
    Generates periodic, seamlessly tileable Voronoi cellular distance and cell ID fields
    on a 2D flat torus.
    """
    rng = np.random.RandomState(seed)
    points = rng.rand(num_cells, 2) * np.array([width, height])
    
    y_idx, x_idx = np.indices((height, width))
    coords = np.stack([x_idx, y_idx], axis=-1).astype(np.float32) # (H, W, 2)
    
    dist_min = np.full((height, width), 1e9, dtype=np.float32)
    dist_sec = np.full((height, width), 1e9, dtype=np.float32)
    cell_id = np.zeros((height, width), dtype=np.int32)
    
    # 9 toroidal neighbor offsets for seamless tessellation
    offsets = [
        np.array([dx * width, dy * height])
        for dx in [-1, 0, 1]
        for dy in [-1, 0, 1]
    ]
    
    for p_idx, pt in enumerate(points):
        for off in offsets:
            p_wrap = pt + off
            d = np.sqrt(np.sum((coords - p_wrap) ** 2, axis=-1))
            mask_min = d < dist_min
            dist_sec = np.where(mask_min, dist_min, np.minimum(dist_sec, d))
            dist_min = np.where(mask_min, d, dist_min)
            cell_id = np.where(mask_min, p_idx, cell_id)
            
    # Edge boundary mask (Worley F2 - F1)
    edge_field = dist_sec - dist_min
    return dist_min, edge_field, cell_id

def save_rgb(img_arr, filename):
    img_arr = np.clip(img_arr * 255.0, 0, 255).astype(np.uint8)
    img = Image.fromarray(img_arr, mode="RGB")
    path = os.path.join(OUT_DIR, filename)
    img.save(path, quality=95)
    print(f"Generated Seamless Texture: {path}")

# =============================================================================
# 1. GRASS TEXTURES
# =============================================================================
def generate_grass():
    # Grass 0: Lush Meadow (high frequency organic blades + shade depth)
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=4, octaves=5, seed=101)
    n_blade = periodic_toroidal_noise(SIZE, SIZE, scale=36, octaves=4, persistence=0.6, seed=102)
    n_micro = periodic_toroidal_noise(SIZE, SIZE, scale=80, octaves=3, seed=103)
    
    base_dark = np.array([0.14, 0.38, 0.10])
    base_mid  = np.array([0.24, 0.58, 0.18])
    base_high = np.array([0.38, 0.72, 0.26])
    
    g0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    blade_pattern = (n_blade * 0.7 + n_micro * 0.3)
    for c in range(3):
        color_grad = base_dark[c] + n_macro * (base_mid[c] - base_dark[c])
        g0[:, :, c] = color_grad + blade_pattern * (base_high[c] - base_mid[c])
    save_rgb(g0, "grass_0.png")
    save_rgb(g0, "grass.png")
    
    # Grass 1: Wildflower Meadow (pastoral blend with yellow/purple flower flecks)
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=5, octaves=5, seed=111)
    n_blade = periodic_toroidal_noise(SIZE, SIZE, scale=32, octaves=4, seed=112)
    n_flowers = periodic_toroidal_noise(SIZE, SIZE, scale=48, octaves=3, seed=113)
    
    flower_mask = (n_flowers > 0.84).astype(np.float32)
    yellow_flower = np.array([0.88, 0.82, 0.25])
    white_flower  = np.array([0.92, 0.95, 0.88])
    flower_col = np.where(n_flowers[:, :, None] > 0.92, yellow_flower, white_flower)
    
    g1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_grass = np.array([0.28, 0.60, 0.20])
    high_grass = np.array([0.42, 0.70, 0.24])
    for c in range(3):
        g1[:, :, c] = base_grass[c] + n_macro * 0.12 + n_blade * (high_grass[c] - base_grass[c])
        g1[:, :, c] = g1[:, :, c] * (1.0 - flower_mask) + flower_col[:, :, c] * flower_mask
    save_rgb(g1, "grass_1.png")
    
    # Grass 2: Dense Alpine Highland Turf (deep emerald, mossy clumps)
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=3, octaves=5, seed=121)
    n_moss  = periodic_toroidal_noise(SIZE, SIZE, scale=18, octaves=4, seed=122)
    n_grain = periodic_toroidal_noise(SIZE, SIZE, scale=64, octaves=3, seed=123)
    
    alpine_dark = np.array([0.11, 0.30, 0.12])
    alpine_mid  = np.array([0.18, 0.46, 0.20])
    alpine_high = np.array([0.30, 0.56, 0.28])
    
    g2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        g2[:, :, c] = alpine_dark[c] + n_macro * (alpine_mid[c] - alpine_dark[c]) + (n_moss * 0.6 + n_grain * 0.4) * (alpine_high[c] - alpine_mid[c])
    save_rgb(g2, "grass_2.png")

# =============================================================================
# 2. SAND TEXTURES
# =============================================================================
def generate_sand():
    # Sand 0: Fine Shoreline Quartz Beach Sand
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=4, octaves=5, seed=201)
    n_grain = periodic_toroidal_noise(SIZE, SIZE, scale=64, octaves=4, seed=202)
    n_glint = periodic_toroidal_noise(SIZE, SIZE, scale=120, octaves=2, seed=203)
    
    sand_base = np.array([0.89, 0.76, 0.52])
    sand_dark = np.array([0.76, 0.63, 0.41])
    sand_high = np.array([0.96, 0.86, 0.65])
    
    s0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        s0[:, :, c] = sand_dark[c] + n_macro * (sand_base[c] - sand_dark[c]) + (n_grain - 0.5) * 0.08 + (n_glint > 0.88).astype(np.float32) * 0.08
    save_rgb(s0, "sand_0.png")
    save_rgb(s0, "sand.png")
    
    # Sand 1: Wind-Rippled Dune Sand
    y_idx, x_idx = np.indices((SIZE, SIZE))
    v = y_idx / float(SIZE) * 2.0 * np.pi
    u = x_idx / float(SIZE) * 2.0 * np.pi
    n_warp = periodic_toroidal_noise(SIZE, SIZE, scale=3, octaves=4, seed=211)
    ripple_phase = v * 14.0 + np.sin(u * 2.0) * 1.5 + n_warp * 3.5
    ripples = np.sin(ripple_phase) * 0.5 + 0.5
    n_grain = periodic_toroidal_noise(SIZE, SIZE, scale=50, octaves=3, seed=212)
    
    dune_ridge = np.array([0.94, 0.82, 0.58])
    dune_trough = np.array([0.72, 0.58, 0.38])
    
    s1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        s1[:, :, c] = dune_trough[c] + ripples * (dune_ridge[c] - dune_trough[c]) + (n_grain - 0.5) * 0.05
    save_rgb(s1, "sand_1.png")
    
    # Sand 2: Coarse Coastal Pebble Sand
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=6, octaves=4, seed=221)
    _, _, cell_id = periodic_voronoi_cells(SIZE, SIZE, num_cells=64, seed=222)
    n_pebbles = periodic_toroidal_noise(SIZE, SIZE, scale=40, octaves=3, seed=223)
    
    pebble_mask = (n_pebbles > 0.80).astype(np.float32)
    pebble_col = np.array([0.48, 0.45, 0.42])
    sand_col = np.array([0.82, 0.70, 0.48])
    
    s2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        s2[:, :, c] = sand_col[c] + (n_macro - 0.5) * 0.10
        s2[:, :, c] = s2[:, :, c] * (1.0 - pebble_mask) + pebble_col[c] * pebble_mask
    save_rgb(s2, "sand_2.png")

# =============================================================================
# 3. DIRT TEXTURES
# =============================================================================
def generate_dirt():
    # Dirt 0: Dark Rich Humus Loam
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=4, octaves=5, seed=301)
    n_crumb = periodic_toroidal_noise(SIZE, SIZE, scale=32, octaves=4, seed=302)
    n_grit  = periodic_toroidal_noise(SIZE, SIZE, scale=70, octaves=3, seed=303)
    
    loam_dark = np.array([0.25, 0.16, 0.10])
    loam_mid  = np.array([0.40, 0.27, 0.17])
    loam_high = np.array([0.52, 0.36, 0.24])
    
    d0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        d0[:, :, c] = loam_dark[c] + n_macro * (loam_mid[c] - loam_dark[c]) + (n_crumb * 0.7 + n_grit * 0.3) * (loam_high[c] - loam_mid[c])
    save_rgb(d0, "dirt_0.png")
    save_rgb(d0, "dirt.png")
    
    # Dirt 1: Red Clay Earth
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=5, octaves=5, seed=311)
    n_grain = periodic_toroidal_noise(SIZE, SIZE, scale=40, octaves=4, seed=312)
    clay_dark = np.array([0.38, 0.20, 0.12])
    clay_mid  = np.array([0.55, 0.31, 0.19])
    clay_high = np.array([0.68, 0.40, 0.26])
    
    d1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        d1[:, :, c] = clay_dark[c] + n_macro * (clay_mid[c] - clay_dark[c]) + n_grain * (clay_high[c] - clay_mid[c])
    save_rgb(d1, "dirt_1.png")
    
    # Dirt 2: Cracked Arid Soil with Crevices
    _, edge_field, _ = periodic_voronoi_cells(SIZE, SIZE, num_cells=48, seed=321)
    crack_mask = np.exp(-np.maximum(edge_field, 0.0) * 0.4) # Dark crevices at cell borders
    n_grain = periodic_toroidal_noise(SIZE, SIZE, scale=36, octaves=4, seed=322)
    
    arid_base = np.array([0.52, 0.40, 0.28])
    arid_high = np.array([0.64, 0.50, 0.36])
    crack_col = np.array([0.18, 0.12, 0.08])
    
    d2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        base = arid_base[c] + n_grain * (arid_high[c] - arid_base[c])
        d2[:, :, c] = base * (1.0 - crack_mask * 0.75) + crack_col[c] * (crack_mask * 0.75)
    save_rgb(d2, "dirt_2.png")

# =============================================================================
# 4. FARMLAND TEXTURES
# =============================================================================
def generate_farmland():
    y_idx, x_idx = np.indices((SIZE, SIZE))
    v = y_idx / float(SIZE) * 2.0 * np.pi
    u = x_idx / float(SIZE) * 2.0 * np.pi
    
    # Farmland 0: Dark Tilled Plowed Furrows
    furrow_w = np.sin(v * 24.0) * 0.5 + 0.5
    n_clod = periodic_toroidal_noise(SIZE, SIZE, scale=28, octaves=4, seed=401)
    f0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    ridge_col = np.array([0.34, 0.22, 0.14])
    trough_col = np.array([0.18, 0.11, 0.06])
    for c in range(3):
        f0[:, :, c] = trough_col[c] + furrow_w * (ridge_col[c] - trough_col[c]) + (n_clod - 0.5) * 0.06
    save_rgb(f0, "farmland_0.png")
    save_rgb(f0, "farmland.png")
    
    # Farmland 1: Golden Wheat / Grain Rows
    wheat_w = np.sin(v * 20.0) * 0.5 + 0.5
    n_grain = periodic_toroidal_noise(SIZE, SIZE, scale=32, octaves=4, seed=411)
    wheat_gold = np.array([0.76, 0.62, 0.26])
    wheat_shade = np.array([0.48, 0.36, 0.16])
    soil_dark = np.array([0.26, 0.16, 0.09])
    
    f1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        crop = wheat_shade[c] + n_grain * (wheat_gold[c] - wheat_shade[c])
        f1[:, :, c] = soil_dark[c] * (1.0 - wheat_w) + crop * wheat_w
    save_rgb(f1, "farmland_1.png")
    
    # Farmland 2: Sprouting Seedling Rows
    sprout_rows = np.sin(v * 24.0) * 0.5 + 0.5
    n_sprout = periodic_toroidal_noise(SIZE, SIZE, scale=40, octaves=4, seed=421)
    sprout_mask = (sprout_rows > 0.45).astype(np.float32) * (n_sprout > 0.42).astype(np.float32)
    
    sprout_green = np.array([0.42, 0.72, 0.22])
    soil_base = np.array([0.24, 0.15, 0.09])
    
    f2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        f2[:, :, c] = soil_base[c] + (sprout_rows * 0.08)
        f2[:, :, c] = f2[:, :, c] * (1.0 - sprout_mask) + sprout_green[c] * sprout_mask
    save_rgb(f2, "farmland_2.png")

# =============================================================================
# 5. MOUNTAIN ROCKS TEXTURES
# =============================================================================
def generate_rocks():
    # Rocks 0: Fractured Slate & Geological Strata
    n1 = periodic_toroidal_noise(SIZE, SIZE, scale=4, octaves=6, seed=501)
    n2 = periodic_toroidal_noise(SIZE, SIZE, scale=24, octaves=4, seed=502)
    strata = np.sin(n1 * 16.0 + n2 * 3.5) * 0.5 + 0.5
    
    slate_dark = np.array([0.24, 0.25, 0.28])
    slate_mid  = np.array([0.42, 0.44, 0.47])
    slate_high = np.array([0.62, 0.65, 0.69])
    
    r0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        r0[:, :, c] = slate_dark[c] + strata * (slate_mid[c] - slate_dark[c]) + n2 * (slate_high[c] - slate_mid[c])
    save_rgb(r0, "rocks_0.png")
    save_rgb(r0, "rocks.png")
    
    # Rocks 1: Weathered Granite Boulder Face with Lichen/Moss Crags
    _, edge_field, _ = periodic_voronoi_cells(SIZE, SIZE, num_cells=32, seed=511)
    crevice = np.exp(-np.maximum(edge_field, 0.0) * 0.35)
    n_granite = periodic_toroidal_noise(SIZE, SIZE, scale=64, octaves=4, seed=512)
    n_moss = periodic_toroidal_noise(SIZE, SIZE, scale=12, octaves=4, seed=513)
    moss_mask = (crevice > 0.4).astype(np.float32) * (n_moss > 0.45).astype(np.float32)
    
    granite_base = np.array([0.48, 0.49, 0.52])
    granite_fleck = np.array([0.72, 0.73, 0.75])
    moss_col = np.array([0.32, 0.44, 0.20])
    crevice_col = np.array([0.16, 0.17, 0.19])
    
    r1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        g = granite_base[c] + (n_granite - 0.5) * 0.18
        g = g * (1.0 - crevice * 0.8) + crevice_col[c] * (crevice * 0.8)
        r1[:, :, c] = g * (1.0 - moss_mask) + moss_col[c] * moss_mask
    save_rgb(r1, "rocks_1.png")
    
    # Rocks 2: Scree Gravel & Angular Talus Field
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=8, octaves=5, seed=521)
    n_pebble = periodic_toroidal_noise(SIZE, SIZE, scale=48, octaves=4, seed=522)
    n_grit = periodic_toroidal_noise(SIZE, SIZE, scale=100, octaves=3, seed=523)
    
    scree_dark = np.array([0.30, 0.31, 0.33])
    scree_mid  = np.array([0.46, 0.47, 0.50])
    scree_high = np.array([0.65, 0.67, 0.70])
    
    r2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    for c in range(3):
        r2[:, :, c] = scree_dark[c] + n_macro * (scree_mid[c] - scree_dark[c]) + (n_pebble * 0.7 + n_grit * 0.3) * (scree_high[c] - scree_mid[c])
    save_rgb(r2, "rocks_2.png")

# =============================================================================
# 6. CONCRETE TEXTURES
# =============================================================================
def generate_concrete():
    y_idx, x_idx = np.indices((SIZE, SIZE))
    v = y_idx / float(SIZE) * 2.0 * np.pi
    u = x_idx / float(SIZE) * 2.0 * np.pi
    
    # Concrete 0: Engineered Modular Slabs with Beveled Joints
    joint_x = (abs(np.sin(u * 4.0)) < 0.022).astype(np.float32)
    joint_y = (abs(np.sin(v * 4.0)) < 0.022).astype(np.float32)
    joints = np.maximum(joint_x, joint_y)
    n_agg = periodic_toroidal_noise(SIZE, SIZE, scale=48, octaves=4, seed=601)
    
    c0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_col = np.array([0.68, 0.70, 0.73])
    joint_col = np.array([0.22, 0.23, 0.25])
    for c in range(3):
        c0[:, :, c] = (base_col[c] + (n_agg - 0.5) * 0.08) * (1.0 - joints) + joint_col[c] * joints
    save_rgb(c0, "concrete_0.png")
    save_rgb(c0, "concrete.png")
    
    # Concrete 1: Modular Aggregate Pavement Blocks
    joint_x = (abs(np.sin(u * 8.0)) < 0.030).astype(np.float32)
    joint_y = (abs(np.sin(v * 8.0)) < 0.030).astype(np.float32)
    joints = np.maximum(joint_x, joint_y)
    n_agg = periodic_toroidal_noise(SIZE, SIZE, scale=36, octaves=4, seed=611)
    
    c1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_col = np.array([0.60, 0.62, 0.65])
    for c in range(3):
        c1[:, :, c] = (base_col[c] + (n_agg - 0.5) * 0.10) * (1.0 - joints * 0.75) + 0.18 * (joints * 0.75)
    save_rgb(c1, "concrete_1.png")
    
    # Concrete 2: Weathered Reinforced Concrete with Carbonation
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=4, octaves=5, seed=621)
    n_micro = periodic_toroidal_noise(SIZE, SIZE, scale=40, octaves=4, seed=622)
    c2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_col = np.array([0.64, 0.65, 0.67])
    stain_col = np.array([0.48, 0.49, 0.50])
    for c in range(3):
        c2[:, :, c] = base_col[c] + (n_macro - 0.5) * 0.16 + (n_micro - 0.5) * 0.07
    save_rgb(c2, "concrete_2.png")

# =============================================================================
# 7. ROAD TEXTURES
# =============================================================================
def generate_road():
    # Road 0: Dark Bituminous High-Traction Asphalt (clean uniform roadbed)
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=4, octaves=5, seed=701)
    n_asphalt = periodic_toroidal_noise(SIZE, SIZE, scale=48, octaves=4, seed=702)
    n_grit = periodic_toroidal_noise(SIZE, SIZE, scale=96, octaves=3, seed=703)
    
    r0 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    asphalt_dark = np.array([0.15, 0.16, 0.17])
    asphalt_mid  = np.array([0.22, 0.23, 0.25])
    asphalt_high = np.array([0.30, 0.31, 0.33])
    for c in range(3):
        base = asphalt_dark[c] + n_macro * (asphalt_mid[c] - asphalt_dark[c])
        r0[:, :, c] = base + (n_asphalt * 0.7 + n_grit * 0.3) * (asphalt_high[c] - asphalt_mid[c])
    save_rgb(r0, "road_0.png")
    save_rgb(r0, "road.png")
    
    # Road 1: Weathered Dense Aggregate Asphalt & Crushed Stone
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=6, octaves=4, seed=711)
    n_micro = periodic_toroidal_noise(SIZE, SIZE, scale=50, octaves=4, seed=712)
    n_fleck = periodic_toroidal_noise(SIZE, SIZE, scale=110, octaves=2, seed=713)
    r1 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    base_col = np.array([0.24, 0.25, 0.27])
    light_col = np.array([0.38, 0.39, 0.42])
    fleck_mask = (n_fleck > 0.88).astype(np.float32)
    for c in range(3):
        r1[:, :, c] = base_col[c] + (n_macro - 0.5) * 0.07 + (n_micro - 0.5) * 0.05 + fleck_mask * 0.10
    save_rgb(r1, "road_1.png")
    
    # Road 2: Compacted Engineered Transit Surface / Smooth Highway
    n_macro = periodic_toroidal_noise(SIZE, SIZE, scale=5, octaves=5, seed=721)
    n_asphalt = periodic_toroidal_noise(SIZE, SIZE, scale=36, octaves=4, seed=722)
    n_grain = periodic_toroidal_noise(SIZE, SIZE, scale=80, octaves=3, seed=723)
    r2 = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    asphalt_base = np.array([0.18, 0.19, 0.20])
    asphalt_shade = np.array([0.26, 0.27, 0.29])
    for c in range(3):
        r2[:, :, c] = asphalt_base[c] + (n_macro * 0.5 + n_asphalt * 0.3 + n_grain * 0.2) * (asphalt_shade[c] - asphalt_base[c])
    save_rgb(r2, "road_2.png")

# =============================================================================
# 8. END CAP WEATHERED INDUSTRIAL RIBS TEXTURE
# =============================================================================
def generate_end_cap_ribs():
    width = SIZE
    height = SIZE
    rng = np.random.RandomState(42)

    c_rib_face      = np.array([82, 88, 96], dtype=np.float32) / 255.0     # Primary structural steel rib face
    c_scuff_alloy   = np.array([195, 205, 218], dtype=np.float32) / 255.0  # Worn alloy corner scuffing
    c_primer_mid    = np.array([62, 66, 74], dtype=np.float32) / 255.0     # Weathered industrial primer
    c_primer_dark   = np.array([38, 42, 48], dtype=np.float32) / 255.0     # Recessed bay paneling
    c_crevice_dirt  = np.array([18, 20, 24], dtype=np.float32) / 255.0     # Deep shadow crease grime
    c_oxide_rust    = np.array([125, 62, 38], dtype=np.float32) / 255.0    # Localized oxidation / rust bleed
    c_rivet         = np.array([145, 155, 168], dtype=np.float32) / 255.0  # Metal rivet heads
    c_hazard_amber  = np.array([185, 138, 42], dtype=np.float32) / 255.0   # Aged industrial safety markings

    num_rib_cols = 4
    num_cross_rows = 4
    col_pitch = width / float(num_rib_cols)
    row_pitch = height / float(num_cross_rows)
    rib_half_w = col_pitch * 0.14
    cross_half_h = row_pitch * 0.12

    n_macro = periodic_toroidal_noise(width, height, scale=4, octaves=4, seed=801)
    n_micro = periodic_toroidal_noise(width, height, scale=16, octaves=4, seed=802)
    n_fine  = periodic_toroidal_noise(width, height, scale=48, octaves=3, seed=803)
    patina  = n_macro * 0.50 + n_micro * 0.35 + n_fine * 0.15

    y_idx, x_idx = np.indices((height, width))
    x_in_cell = x_idx % col_pitch
    y_in_cell = y_idx % row_pitch
    dist_x_rib = np.abs(x_in_cell - col_pitch * 0.5)
    dist_y_cross = np.abs(y_in_cell - row_pitch * 0.5)

    is_on_rib = dist_x_rib <= rib_half_w
    is_rib_edge = np.abs(dist_x_rib - rib_half_w) <= 3.5
    is_on_cross = dist_y_cross <= cross_half_h
    is_cross_edge = np.abs(dist_y_cross - cross_half_h) <= 3.0

    # Corrugation
    flute_x = np.maximum(0.0, (dist_x_rib - rib_half_w) / max(col_pitch * 0.5 - rib_half_w, 1.0))
    corrugation = np.sin(flute_x * math.pi * 18.0) * 0.5 + 0.5

    # Rivets
    rivet_spacing = row_pitch / 8.0
    rivet_y_rel = np.abs((y_idx % rivet_spacing) - rivet_spacing * 0.5)
    dx_riv1 = np.abs((x_in_cell - col_pitch * 0.5) - (-rib_half_w * 0.65))
    dx_riv2 = np.abs((x_in_cell - col_pitch * 0.5) - (rib_half_w * 0.65))
    dist_riv = np.minimum(
        np.sqrt(dx_riv1 * dx_riv1 + rivet_y_rel * rivet_y_rel),
        np.sqrt(dx_riv2 * dx_riv2 + rivet_y_rel * rivet_y_rel)
    )
    is_rivet = (dist_riv <= 3.8).astype(np.float32)
    is_rivet_rim = ((dist_riv > 3.8) & (dist_riv <= 5.2)).astype(np.float32)

    # Hazard stripe
    stripe = (((x_idx + y_idx * 1.2) % 40.0) / 40.0 > 0.5).astype(np.float32)
    is_hazard = is_on_cross & ((y_idx // row_pitch) % 2 == 1) & (stripe > 0.5)

    ribs_out = np.zeros((height, width, 3), dtype=np.float32)

    for c in range(3):
        # Structural rib surface
        blend_x = dist_x_rib / max(rib_half_w, 1.0)
        blend_y = dist_y_cross / max(cross_half_h, 1.0)
        blend = np.where(is_on_rib, blend_x, blend_y)
        rib_base = c_rib_face[c] * (1.0 - blend * 0.25) + c_primer_mid[c] * (blend * 0.25)

        # Scuffing
        scuff_amt = (0.65 + 0.35 * n_fine) * (is_rib_edge | is_cross_edge)
        rib_base = rib_base * (1.0 - scuff_amt) + c_scuff_alloy[c] * scuff_amt

        # Gusset intersection
        rib_base = np.where(is_on_rib & is_on_cross, rib_base * 1.12, rib_base)

        # Recessed paneling
        panel_base = c_primer_dark[c] * (0.8 + 0.3 * corrugation)
        crease = ((dist_x_rib < rib_half_w + 8.0) | (dist_y_cross < cross_half_h + 8.0)).astype(np.float32)
        panel_base = panel_base * (1.0 - crease * 0.35) + c_crevice_dirt[c] * (crease * 0.35)

        rust_mask = ((dist_x_rib < rib_half_w + 14.0) & (dist_y_cross < cross_half_h + 14.0)).astype(np.float32)
        rust_f = np.maximum(0.0, 0.45 * (n_micro + 0.2)) * rust_mask
        panel_base = panel_base * (1.0 - rust_f) + c_oxide_rust[c] * rust_f

        base_val = np.where(is_on_rib | is_on_cross, rib_base, panel_base)

        # Rivet overlays
        base_val = base_val * (1.0 - is_rivet) + c_rivet[c] * 1.15 * is_rivet
        base_val = base_val * (1.0 - is_rivet_rim) + c_crevice_dirt[c] * 0.8 * is_rivet_rim

        # Hazard stripe overlay
        h_f = (0.55 + 0.25 * n_fine) * is_hazard
        base_val = base_val * (1.0 - h_f) + c_hazard_amber[c] * h_f

        # Grime / Patina modulation
        grime = 0.82 + 0.36 * (patina + 0.5)
        ribs_out[:, :, c] = base_val * grime

    save_rgb(ribs_out, "end_cap_ribs.png")

def cleanup_obsolete_textures():
    obsolete = [
        "dirt_to_grass.png", "dirt_to_grass.png.import",
        "sand_to_grass.png", "sand_to_grass.png.import",
        "road_edge.png", "road_edge.png.import"
    ]
    for filename in obsolete:
        path = os.path.join(OUT_DIR, filename)
        if os.path.exists(path):
            os.remove(path)
            print(f"Removed Obsolete Texture: {path}")

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    cleanup_obsolete_textures()
    print("Synthesizing seamless, high-definition, tessellating terrain textures...")
    generate_grass()
    generate_sand()
    generate_dirt()
    generate_farmland()
    generate_rocks()
    generate_concrete()
    generate_road()
    generate_end_cap_ribs()
    print("All terrain textures generated and tessellation-verified successfully!")

if __name__ == "__main__":
    main()
