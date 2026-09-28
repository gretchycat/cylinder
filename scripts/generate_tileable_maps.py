#!/usr/bin/env python3
"""
generate_tileable_maps.py
-------------------------
Advanced procedural map, object, bridge, and ground clutter generator for the O'Neill Cylinder Simulation Engine.

Generates:
1. `elevation_map.png` (8-bit grayscale heightmap, 0..max_elevation meters)
2. `terrain_map.png` (2D RPG color-coded biome classification map)
3. `object_map.json` (Structured metadata for bonfires, campfires, streetlamps, beacons, and bridges)
4. `object_map.png` (Visual 2D preview overlay of placed settlements, bridges, and surface lights)
5. `biomes_manifest.json` (Biome & sub-biome ground clutter specifications, densities, and instancing hooks)

Topography & Hydrology:
- Central Sea circumnavigating the cylinder perimeter in the center at max depth (~18m depth, elevation 2m)
- Inland Lake at half sea depth (~9m depth, elevation 11m)
- Major connecting River linking Lake and Central Sea with guaranteed 100% continuous channel flow
- Tributaries all over (branching continuous highland stream network flowing into Sea and Lake)
- Bridges automatically detected and placed at all road & path river crossings with realistic orientation
- Super high elevation mountain massifs (96m - 98m elevation)
- 10 Villages + 1 City Center with paved road & dirt path network
- Rich ground clutter definitions (Flower fields, Rocky alpine crags, Reeds, Farmland, Plazas)
"""

import os
import sys
import math
import json
import random
import argparse
from PIL import Image, ImageDraw

# 2D RPG Palette (Pure terrain types for multi-splat shader)
PALETTE = {
    0: (35, 105, 195, 255),    # Water (blue ocean / lake / river)
    1: (225, 190, 125, 255),   # Sand (beach / shoreline / dunes)
    2: (115, 78, 48, 255),     # Dirt (loam / dirt paths / foothill earth)
    3: (60, 140, 42, 255),     # Grass (lush meadow green)
    4: (165, 120, 50, 255),    # Farmland (ochre furrowed crop plots)
    5: (95, 100, 108, 255),    # Rocks (slate mountain rock peaks)
    6: (175, 180, 188, 255),   # Concrete (urban plazas / spaceport hub)
    7: (42, 44, 48, 255),      # Road (paved transit asphalt)
}

BIOMES_MANIFEST = {
    "0_water_central_sea": {
        "name": "Central Circumferential Sea",
        "description": "Deep oceanic belt circumnavigating the cylinder axis with bathymetric drop-offs",
        "clutter_types": ["abyssal_basalt_slabs", "kelp_forests", "deep_trench_pebbles", "hydrothermal_vents", "sunken_crystals"],
        "clutter_density": 0.06,
        "scale_range": [0.8, 3.0]
    },
    "0_water_inland_lake": {
        "name": "Inland Freshwater Lake",
        "description": "Sheltered inland lake basin fed by highland river tributaries",
        "clutter_types": ["lakebed_quartz_pebbles", "cattails", "water_lilies", "river_reeds", "driftwood_logs"],
        "clutter_density": 0.14,
        "scale_range": [0.4, 1.8]
    },
    "1_sand_beach": {
        "name": "Shoreline & Alluvial Sands",
        "description": "Coastal beaches, delta sandbars, and silica ripple dunes",
        "clutter_types": ["coastal_shells", "driftwood_twigs", "quartz_pebbles", "dune_grass_shoots", "sandstone_shards"],
        "clutter_density": 0.12,
        "scale_range": [0.3, 1.2]
    },
    "2_dirt_paths": {
        "name": "Dirt Paths & Loam Earth",
        "description": "Inter-village trodden footpaths, forest humus, and foothill loam",
        "clutter_types": ["earth_clods", "humus_leaves", "pebbles", "sprouting_roots", "small_twigs", "wild_mushrooms"],
        "clutter_density": 0.20,
        "scale_range": [0.4, 1.4]
    },
    "3_grass_flower_field": {
        "name": "Flower Fields & Wildflower Meadow",
        "description": "Vibrant floral bloom pastures, pastoral clover turf, and fragrant herbs",
        "clutter_types": ["poppy_blooms", "lavender_tufts", "bluebell_clusters", "lupine_stalks", "golden_buttercups", "dandelion_tufts", "fluttering_petals"],
        "clutter_density": 0.45,
        "scale_range": [0.4, 1.6]
    },
    "4_farmland_plots": {
        "name": "Cultivated Farmland & Terraces",
        "description": "Tilled agricultural crop furrows, grain beds, and seedling terraces",
        "clutter_types": ["furrow_stakes", "golden_wheat_rows", "crop_seedlings", "hay_wisps", "irrigation_markers", "stone_boundary_walls"],
        "clutter_density": 0.30,
        "scale_range": [0.5, 1.8]
    },
    "5_rocks_rocky_area": {
        "name": "Rocky Alpine Crags & Massifs",
        "description": "Super-high elevation mountain massifs, craggy slate pinnacles, and scree talus",
        "clutter_types": ["scree_boulders", "basalt_columns", "craggy_stone_pinnacles", "mineral_crystal_veins", "talus_rubble", "slate_shards", "alpine_lichen_patches"],
        "clutter_density": 0.32,
        "scale_range": [0.6, 3.8]
    },
    "6_concrete_city_plaza": {
        "name": "City Center Concrete Plaza",
        "description": "Engineered urban square, structural foundation pads, and modular concourse",
        "clutter_types": ["modular_expansion_sealant", "anchor_brackets", "street_drains", "utility_conduits", "curb_reflectors", "pedestrian_bollards"],
        "clutter_density": 0.08,
        "scale_range": [0.4, 1.2]
    },
    "7_road_highway": {
        "name": "Paved Regional Highway & Bridges",
        "description": "Compacted asphalt roadbed connecting city center, bridges, and waystations",
        "clutter_types": ["aggregate_flecks", "roadbed_reflectors", "asphalt_gravel", "roadside_mile_markers", "drainage_culverts"],
        "clutter_density": 0.04,
        "scale_range": [0.3, 0.9]
    }
}

def distance_toroidal(u1, v1, u2, v2, tile_u=True, tile_v=False):
    du = abs(u1 - u2)
    if tile_u and du > 0.5:
        du = 1.0 - du
    dv = abs(v1 - v2)
    if tile_v and dv > 0.5:
        dv = 1.0 - dv
    return math.sqrt(du * du + dv * dv)

def rasterize_path_segments(grid, x0, y0, x1, y1, val, width_cells=1, width_map=512, height_map=256, tile_u=True):
    # Bresenham-based line rasterization with thickness and toroidal wrap in U
    dx = x1 - x0
    if tile_u:
        if dx > width_map // 2:
            x1 -= width_map
            dx = x1 - x0
        elif dx < -width_map // 2:
            x1 += width_map
            dx = x1 - x0
            
    dy = y1 - y0
    steps = max(abs(dx), abs(dy), 1)
    points = []
    
    for step in range(steps + 1):
        t = float(step) / float(steps)
        cx = int(round(x0 + t * dx))
        cy = int(round(y0 + t * dy))
        
        for oy in range(-width_cells // 2, width_cells // 2 + 1):
            for ox in range(-width_cells // 2, width_cells // 2 + 1):
                px = (cx + ox) % width_map if tile_u else (cx + ox)
                py = cy + oy
                if 0 <= py < height_map and 0 <= px < width_map:
                    grid[py][px] = val
                    points.append((px, py, t, dx, dy))
    return points

def generate_tileable_maps(
    width: int = 512,
    height: int = 256,
    max_elevation: float = 100.0,
    water_level: float = 20.0,
    num_villages: int = 10,
    num_city_centers: int = 1,
    road_development: float = 0.70,
    road_width_px: int = 2,
    preset: str = "dramatic",
    roughness: float = 0.85,
    tile_horizontal: bool = True,
    tile_vertical: bool = True,
    seed: int = 42,
    output_dir: str = "assets/maps/default",
    elevation_filename: str = "elevation_map.png",
    terrain_filename: str = "terrain_map.png",
    object_map_filename: str = "object_map.json"
):
    rng = random.Random(seed)
    os.makedirs(output_dir, exist_ok=True)

    elevation_img = Image.new("L", (width, height))
    terrain_img = Image.new("RGBA", (width, height))
    object_preview_img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw_preview = ImageDraw.Draw(object_preview_img)

    # 1. Fourier Harmonic Phase Tables
    num_harmonics = 48
    phases = []
    for _ in range(num_harmonics):
        phases.append({
            "px": rng.random() * math.tau,
            "py": rng.random() * math.tau,
            "pxy": rng.random() * math.tau,
        })

    elev_grid = [[0.0 for _ in range(width)] for _ in range(height)]
    terr_grid = [[3 for _ in range(width)] for _ in range(height)]
    is_water_mask = [[False for _ in range(width)] for _ in range(height)]

    # 2. Key Landmarks & Geography Configuration
    peak1_u, peak1_v = 0.18, 0.82
    peak2_u, peak2_v = 0.82, 0.18

    lake_u, lake_v = 0.35, 0.22
    lake_rad_u = 0.095
    lake_rad_v = 0.085

    # 3. Continuous River and Stream Networks
    # Main river connecting Inland Lake (v=0.22) to Central Sea (v=0.45)
    def get_main_river_u(v_norm):
        prog = (v_norm - 0.20) / (0.45 - 0.20 + 1e-5)
        prog = max(0.0, min(1.0, prog))
        meander = 0.022 * math.sin(prog * 12.0) + 0.012 * math.sin(prog * 24.0)
        return (lake_u + prog * 0.02 + meander) % 1.0

    # Continuous Tributary Splines
    tributaries = [
        {"v_start": 0.78, "v_end": 0.54, "u_start": 0.15, "u_end": 0.23, "w": 0.016, "freq": 14.0, "amp": 0.012},
        {"v_start": 0.86, "v_end": 0.55, "u_start": 0.68, "u_end": 0.60, "w": 0.017, "freq": 16.0, "amp": 0.014},
        {"v_start": 0.26, "v_end": 0.46, "u_start": 0.88, "u_end": 0.80, "w": 0.016, "freq": 15.0, "amp": 0.012},
        {"v_start": 0.08, "v_end": 0.20, "u_start": 0.55, "u_end": 0.42, "w": 0.015, "freq": 12.0, "amp": 0.010},
        {"v_start": 0.12, "v_end": 0.21, "u_start": 0.12, "u_end": 0.27, "w": 0.015, "freq": 14.0, "amp": 0.011},
        {"v_start": 0.88, "v_end": 0.56, "u_start": 0.48, "u_end": 0.50, "w": 0.016, "freq": 15.0, "amp": 0.012},
    ]

    def get_tributary_u(trib, v_norm):
        v0, v1 = trib["v_start"], trib["v_end"]
        prog = (v_norm - v0) / (v1 - v0 + 1e-5)
        prog = max(0.0, min(1.0, prog))
        meander = trib["amp"] * math.sin(prog * trib["freq"])
        return (trib["u_start"] + prog * (trib["u_end"] - trib["u_start"]) + meander) % 1.0

    # 4. Elevation & Hydrology Pass
    for y in range(height):
        v = float(y) / float(height)
        phi = v * math.tau

        for x in range(width):
            u = float(x) / float(width)
            theta = u * math.tau

            # Macro continents and base terrain
            macro = 0.40 * math.sin(2.0 * theta + phases[0]["px"]) * math.cos(1.0 * phi + phases[0]["py"]) \
                  + 0.28 * math.cos(3.0 * theta - 2.0 * phi + phases[1]["pxy"]) \
                  + 0.16 * math.sin(1.0 * theta + 2.0 * phi + phases[2]["px"])

            s_ridge1 = 1.0 - abs(math.sin(4.0 * theta + 3.0 * phi + phases[3]["px"]))
            s_ridge2 = 1.0 - abs(math.cos(7.0 * theta - 5.0 * phi + phases[4]["py"]))
            s_ridge3 = 1.0 - abs(math.sin(10.0 * theta + 8.0 * phi + phases[5]["pxy"]))
            ridge = (s_ridge1 ** 2.2 + 0.65 * (s_ridge2 ** 2.0) + 0.35 * (s_ridge3 ** 1.8)) * 0.45

            h1 = math.sin(16.0 * theta + 12.0 * phi + phases[6]["px"])
            h2 = math.cos(24.0 * theta - 18.0 * phi + phases[7]["py"])
            h3 = math.sin(36.0 * theta + 28.0 * phi + phases[8]["pxy"])
            hills = (0.24 * h1 + 0.18 * h2 + 0.12 * h3) * roughness

            mesa_raw = math.sin(5.0 * theta + 4.0 * phi + phases[10]["px"]) * 0.5 + 0.5
            mesa = (math.tanh((mesa_raw - 0.55) * 6.0) * 0.5 + 0.5) * 0.30

            raw_elev = (macro * 0.32 + ridge * 0.42 + hills * 0.30 + mesa * 0.18)
            norm_height = (raw_elev + 0.45) * 0.95
            elevation = norm_height * 78.0

            # Alpine Massifs (96m - 98m peaks)
            d_p1_u = abs(u - peak1_u)
            if tile_horizontal and d_p1_u > 0.5:
                d_p1_u = 1.0 - d_p1_u
            d_p1_v = abs(v - peak1_v)
            d_p1 = math.sqrt((d_p1_u * 7.5) ** 2 + (d_p1_v * 7.5) ** 2)
            if d_p1 < 1.0:
                p1_boost = ((1.0 - d_p1) ** 1.6) * 38.0
                elevation = max(elevation, 58.0 + p1_boost)

            d_p2_u = abs(u - peak2_u)
            if tile_horizontal and d_p2_u > 0.5:
                d_p2_u = 1.0 - d_p2_u
            d_p2_v = abs(v - peak2_v)
            d_p2 = math.sqrt((d_p2_u * 8.0) ** 2 + (d_p2_v * 8.0) ** 2)
            if d_p2 < 1.0:
                p2_boost = ((1.0 - d_p2) ** 1.6) * 40.0
                elevation = max(elevation, 58.0 + p2_boost)

            # Central Circumferential Sea: v ~ 0.50, Max Depth ~ 18.0m (seabed elev ~ 2.0m)
            d_sea_center_v = abs(v - 0.50)
            sea_half_width = 0.072 + 0.020 * math.sin(theta * 4.0 + 0.5) + 0.012 * math.sin(theta * 8.0 + 1.2)
            sea_carve_factor = 0.0
            if d_sea_center_v < sea_half_width:
                sea_carve_factor = math.cos((d_sea_center_v / sea_half_width) * (math.pi * 0.5))

            # Inland Freshwater Lake: (lake_u, lake_v), Half Depth ~ 9.0m (seabed elev ~ 11.0m)
            d_lake_u = abs(u - lake_u)
            if tile_horizontal and d_lake_u > 0.5:
                d_lake_u = 1.0 - d_lake_u
            d_lake_v = abs(v - lake_v)
            lake_dist_sq = (d_lake_u / lake_rad_u) ** 2 + (d_lake_v / lake_rad_v) ** 2
            lake_carve_factor = 0.0
            if lake_dist_sq < 1.0:
                lake_carve_factor = math.cos(math.sqrt(lake_dist_sq) * (math.pi * 0.5))

            # Major Continuous Connecting River
            river_carve_factor = 0.0
            if 0.19 <= v <= 0.47:
                riv_u_center = get_main_river_u(v)
                d_riv_u = abs(u - riv_u_center)
                if tile_horizontal and d_riv_u > 0.5:
                    d_riv_u = 1.0 - d_riv_u
                main_riv_w = 0.026
                if d_riv_u < main_riv_w:
                    river_carve_factor = 1.0 - (d_riv_u / main_riv_w)

            # Continuous Tributary Highland Streams
            tributary_carve_factor = 0.0
            for trib in tributaries:
                t_min_v = min(trib["v_start"], trib["v_end"])
                t_max_v = max(trib["v_start"], trib["v_end"])
                if t_min_v - 0.01 <= v <= t_max_v + 0.01:
                    trib_u_center = get_tributary_u(trib, v)
                    d_t_u = abs(u - trib_u_center)
                    if tile_horizontal and d_t_u > 0.5:
                        d_t_u = 1.0 - d_t_u
                    if d_t_u < trib["w"]:
                        tf = 1.0 - (d_t_u / trib["w"])
                        tributary_carve_factor = max(tributary_carve_factor, tf)

            # Bathymetric Bed Carving
            if sea_carve_factor > 0.0:
                prof = sea_carve_factor ** 1.3
                target_sea_elev = 2.0
                elevation = elevation * (1.0 - prof) + target_sea_elev * prof

            if lake_carve_factor > 0.0:
                prof = lake_carve_factor ** 1.3
                target_lake_elev = 11.0
                elevation = elevation * (1.0 - prof) + target_lake_elev * prof

            if river_carve_factor > 0.0:
                prof = river_carve_factor ** 1.4
                target_riv_elev = 13.0
                elevation = elevation * (1.0 - prof) + target_riv_elev * prof

            if tributary_carve_factor > 0.0:
                prof = tributary_carve_factor ** 1.5
                target_trib_elev = 14.5
                elevation = elevation * (1.0 - prof) + target_trib_elev * prof

            # Guaranteed dry player spawn promontory (u=0.75, v=0.50 -> theta = -PI*0.5, z = 0.0)
            d_sp_u = abs(u - 0.75)
            if tile_horizontal and d_sp_u > 0.5:
                d_sp_u = 1.0 - d_sp_u
            d_sp_v = abs(v - 0.50)
            d_sp = math.sqrt((d_sp_u * 6.5) ** 2 + (d_sp_v * 6.5) ** 2)
            if d_sp < 1.0:
                spawn_island = (math.cos(d_sp * math.pi * 0.5) ** 1.4) * 24.0
                elevation = max(elevation, water_level + 8.0 + spawn_island)

            # End cap retention seawall (v=0 and v=1)
            dist_to_cap = min(v, 1.0 - v)
            dist_to_cap_m = dist_to_cap * 18000.0
            if dist_to_cap_m < 400.0:
                seawall_blend = max(0.0, 1.0 - dist_to_cap_m / 400.0)
                target_rim_elev = 26.0
                elevation = elevation * (1.0 - seawall_blend) + max(elevation, target_rim_elev) * seawall_blend

            elevation = max(0.0, min(max_elevation, elevation))
            elev_grid[y][x] = elevation
            is_water_mask[y][x] = (elevation < water_level)

    # 5. Base Biome Classification
    for y in range(height):
        for x in range(width):
            e = elev_grid[y][x]
            if e < water_level:
                terr_grid[y][x] = 0 # Water
            elif e < water_level + 4.5:
                terr_grid[y][x] = 1 # Sand Shoreline
            elif e > 78.0:
                terr_grid[y][x] = 5 # Mountain Bedrock Rocks
            elif e > 58.0:
                terr_grid[y][x] = 2 # Highland Dirt
            else:
                terr_grid[y][x] = 3 # Lush Grass & Flower Fields

    scale_factor = width / 512.0

    # 6. Settlement Placement (1 City Center, 10 Villages)
    city_centers = []
    villages = []
    placed_settlements = []

    candidates = []
    step_y = max(2, int(round(4 * scale_factor)))
    step_x = max(2, int(round(4 * scale_factor)))
    for cy in range(int(16 * scale_factor), height - int(16 * scale_factor), step_y):
        for cx in range(int(16 * scale_factor), width - int(16 * scale_factor), step_x):
            e = elev_grid[cy][cx]
            t = terr_grid[cy][cx]
            if (water_level + 3.0) <= e <= 54.0 and t in [1, 2, 3]:
                water_dist = 999.0
                search_r = int(round(8 * scale_factor))
                for dy in range(-search_r, search_r + 1, int(max(1, round(2 * scale_factor)))):
                    for dx in range(-search_r, search_r + 1, int(max(1, round(2 * scale_factor)))):
                        nx = (cx + dx) % width
                        ny = max(0, min(height - 1, cy + dy))
                        if terr_grid[ny][nx] == 0:
                            d = math.sqrt(dx * dx + dy * dy)
                            water_dist = min(water_dist, d)
                candidates.append({
                    "x": cx, "y": cy, "u": float(cx) / float(width), "v": float(cy) / float(height),
                    "elevation": e, "water_dist": water_dist
                })

    rng.shuffle(candidates)
    candidates.sort(key=lambda c: abs(c["water_dist"] - 5.0 * scale_factor))

    # City Center
    city_radius_px = int(round(7 * scale_factor))
    village_large_radius_px = int(round(4 * scale_factor))
    village_small_radius_px = int(max(2, round(2.5 * scale_factor)))

    for cand in candidates:
        if 0.28 <= cand["v"] <= 0.40 and 0.25 <= cand["u"] <= 0.50:
            cand["id"] = "Grand_City_Center"
            cand["type"] = "city"
            cand["radius"] = city_radius_px
            city_centers.append(cand)
            placed_settlements.append(cand)
            break

    if not city_centers and candidates:
        cc_cand = candidates[0]
        cc_cand["id"] = "Grand_City_Center"
        cc_cand["type"] = "city"
        cc_cand["radius"] = city_radius_px
        city_centers.append(cc_cand)
        placed_settlements.append(cc_cand)

    # 10 Villages
    for cand in candidates:
        if len(villages) >= num_villages:
            break
        separated = True
        for s in placed_settlements:
            d = distance_toroidal(cand["u"], cand["v"], s["u"], s["v"], tile_u=tile_horizontal)
            if d < 0.12:
                separated = False
                break
        if separated:
            v_idx = len(villages) + 1
            cand["id"] = f"Village_{v_idx}"
            cand["type"] = "village"
            cand["size"] = "large" if (v_idx in [1, 4, 7]) else "small"
            cand["radius"] = village_large_radius_px if cand["size"] == "large" else village_small_radius_px
            villages.append(cand)
            placed_settlements.append(cand)

    # 7. Settlement Clearings, Plazas, and Farmland
    for cc in city_centers:
        cx, cy = cc["x"], cc["y"]
        r = cc["radius"]
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r:
                    px = (cx + dx) % width
                    py = max(0, min(height - 1, cy + dy))
                    if elev_grid[py][px] > water_level:
                        terr_grid[py][px] = 6 # Concrete Plaza
                        elev_grid[py][px] = max(elev_grid[py][px], water_level + 8.0)
        farm_r = r + int(round(6 * scale_factor))
        for dy in range(-farm_r, farm_r + 1):
            for dx in range(-farm_r, farm_r + 1):
                d_sq = dx * dx + dy * dy
                if r * r < d_sq <= farm_r * farm_r:
                    px = (cx + dx) % width
                    py = max(0, min(height - 1, cy + dy))
                    if terr_grid[py][px] == 3 and elev_grid[py][px] > water_level + 1.0:
                        terr_grid[py][px] = 4 # Farmland

    for v_obj in villages:
        vx, vy = v_obj["x"], v_obj["y"]
        r = v_obj["radius"]
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r:
                    px = (vx + dx) % width
                    py = max(0, min(height - 1, vy + dy))
                    if terr_grid[py][px] == 3:
                        terr_grid[py][px] = 2 # Village dirt clearing
        if v_obj["size"] == "large":
            farm_off_x = rng.choice([-int(round(3 * scale_factor)), int(round(3 * scale_factor))])
            farm_off_y = rng.choice([-int(round(3 * scale_factor)), int(round(3 * scale_factor))])
            farm_box_r = int(max(2, round(2.5 * scale_factor)))
            for dy in range(-farm_box_r, farm_box_r + 1):
                for dx in range(-farm_box_r, farm_box_r + 1):
                    px = (vx + farm_off_x + dx) % width
                    py = max(0, min(height - 1, vy + farm_off_y + dy))
                    if terr_grid[py][px] in [2, 3]:
                        terr_grid[py][px] = 4 # Farmland

    # 8. Road & Path Networks + Automated River-Crossing Bridge Placement
    bridge_crossings = []
    all_path_points = []
    scaled_road_width = int(max(2, round(road_width_px * scale_factor)))
    scaled_path_width = int(max(1, round(scale_factor * 0.75)))

    # Arterial Paved Highway from City Center
    if city_centers:
        cc = city_centers[0]
        for v_obj in villages:
            d = distance_toroidal(cc["u"], cc["v"], v_obj["u"], v_obj["v"], tile_u=tile_horizontal)
            if d < 0.28:
                pts = rasterize_path_segments(terr_grid, cc["x"], cc["y"], v_obj["x"], v_obj["y"],
                                              val=7, width_cells=scaled_road_width,
                                              width_map=width, height_map=height, tile_u=tile_horizontal)
                all_path_points.extend(pts)

    # Inter-Village Dirt Paths
    for v_obj in villages:
        best_dist = 999.0
        best_target = None
        for other in placed_settlements:
            if other["id"] == v_obj["id"]:
                continue
            d = distance_toroidal(v_obj["u"], v_obj["v"], other["u"], other["v"], tile_u=tile_horizontal)
            if d < best_dist:
                best_dist = d
                best_target = other
        if best_target and best_dist < 0.35:
            pts = rasterize_path_segments(terr_grid, v_obj["x"], v_obj["y"], best_target["x"], best_target["y"],
                                          val=2, width_cells=scaled_path_width,
                                          width_map=width, height_map=height, tile_u=tile_horizontal)
            all_path_points.extend(pts)

    # Detect Bridge Locations where paths cross water channels
    processed_crossings = set()
    bridge_cell_cluster = int(max(3, round(3 * scale_factor)))
    for (px, py, t, dx, dy) in all_path_points:
        if is_water_mask[py][px]:
            cell_key = (px // bridge_cell_cluster, py // bridge_cell_cluster)
            if cell_key not in processed_crossings:
                processed_crossings.add(cell_key)
                u_cr = float(px) / float(width)
                v_cr = float(py) / float(height)
                # Compute bridge alignment angle across river
                du_m = (dx / float(width)) * (2.0 * math.pi * 4000.0)
                dz_m = (dy / float(height)) * 18000.0
                yaw_angle = math.atan2(du_m, dz_m) if (abs(du_m) > 1e-4 or abs(dz_m) > 1e-4) else 0.0

                bridge_crossings.append({
                    "px": px, "py": py, "u": u_cr, "v": v_cr,
                    "yaw_rad": yaw_angle, "road_type": terr_grid[py][px]
                })

                # Maintain continuous road surface across bridge
                terr_grid[py][px] = 7 if terr_grid[py][px] == 7 else 2
                elev_grid[py][px] = max(elev_grid[py][px], water_level + 0.85)

    # 9. Object Map Generation (Bonfires, Campfires, Street Lamps, Beacons, and BRIDGES)
    object_entries = []
    CYLINDER_RADIUS = 4000.0
    CYLINDER_LENGTH = 18000.0

    def add_object(obj_type_enum, u_coord, v_coord, name, color_rgb, light_range, energy, settlement_id, role, yaw_rad=0.0):
        theta = (u_coord * math.tau) - math.pi
        z = (v_coord - 0.5) * CYLINDER_LENGTH
        px = int(round(u_coord * (width - 1))) % width
        py = int(round(v_coord * (height - 1)))
        elev = elev_grid[py][px]

        entry = {
            "name": name,
            "object_type": obj_type_enum, # 0: CAMPFIRE, 1: LAMP_POST, 2: BEACON_LANTERN, 3: BRIDGE, 4: BONFIRE, 5: HOUSE, 6: TREE, 7: WINDMILL
            "object_type_name": ["CAMPFIRE", "LAMP_POST", "BEACON_LANTERN", "BRIDGE", "BONFIRE", "HOUSE", "TREE", "WINDMILL"][obj_type_enum],
            "u": round(u_coord, 5),
            "v": round(v_coord, 5),
            "theta": round(theta, 5),
            "z": round(z, 2),
            "elevation": round(elev, 2),
            "light_color": color_rgb,
            "light_range": round(light_range, 1),
            "light_energy": round(energy, 2),
            "yaw_rad": round(yaw_rad, 4),
            "settlement_id": settlement_id,
            "role": role
        }
        object_entries.append(entry)

        # Draw on preview
        dot_colors = {
            0: (255, 120, 30, 255),   # Campfire (warm orange)
            1: (255, 230, 140, 255),  # Street lamp (warm yellow)
            2: (50, 220, 255, 255),   # Beacon (cyan)
            3: (220, 180, 80, 255),   # Bridge (golden stone)
            4: (255, 60, 10, 255),    # Bonfire (deep blaze orange-red)
            5: (180, 100, 60, 255),   # House (timber brown)
            6: (30, 140, 40, 255),    # Tree (forest green)
            7: (210, 190, 110, 255)   # Windmill (stone/gold)
        }
        dc = dot_colors.get(obj_type_enum, (255, 255, 255, 255))
        rad = 3 if obj_type_enum in (2, 4, 5, 7) else (1 if obj_type_enum == 6 else 2)
        draw_preview.ellipse([px - rad, py - rad, px + rad, py + rad], fill=dc, outline=(0, 0, 0, 255))

    # Helper to check if a location is on dry, non-road land
    def is_valid_land(u_c, v_c):
        px_chk = int(round(u_c * (width - 1))) % width
        py_chk = int(round(v_c * (height - 1)))
        py_chk = max(0, min(height - 1, py_chk))
        t_chk = terr_grid[py_chk][px_chk]
        e_chk = elev_grid[py_chk][px_chk]
        return e_chk >= water_level + 0.5 and t_chk not in (0, 7) # not water and not road

    # Player Spawn Welcoming Campfire & Spawn Cabin (u=0.75, v=0.50 -> theta = -PI*0.5, z = 0.0)
    add_object(
        obj_type_enum=0, # CAMPFIRE
        u_coord=0.75, v_coord=0.50,
        name="Spawn_Welcoming_Campfire",
        color_rgb=[1.0, 0.58, 0.20],
        light_range=45.0, energy=6.0,
        settlement_id="Spawn_Clearance", role="spawn_landmark"
    )
    add_object(
        obj_type_enum=5, # HOUSE
        u_coord=0.748, v_coord=0.504,
        name="Spawn_Ranger_Cabin",
        color_rgb=[1.0, 0.85, 0.55],
        light_range=14.0, energy=2.4,
        settlement_id="Spawn_Clearance", role="spawn_ranger_cabin",
        yaw_rad=0.35
    )

    # City Center: Central Beacon + 4 Street Lamps + 4 Townhouses
    for cc in city_centers:
        add_object(
            obj_type_enum=2, # BEACON_LANTERN
            u_coord=cc["u"], v_coord=cc["v"],
            name=f"{cc['id']}_Central_Beacon",
            color_rgb=[0.20, 0.88, 1.0],
            light_range=58.0, energy=6.5,
            settlement_id=cc["id"], role="city_central_beacon"
        )
        r_u = float(cc["radius"]) / float(width)
        r_v = float(cc["radius"]) / float(height)
        offsets = [(-r_u, 0), (r_u, 0), (0, -r_v), (0, r_v)]
        for k, (ou, ov) in enumerate(offsets):
            add_object(
                obj_type_enum=1, # LAMP_POST
                u_coord=(cc["u"] + ou) % 1.0,
                v_coord=max(0.01, min(0.99, cc["v"] + ov)),
                name=f"{cc['id']}_StreetLamp_{k + 1}",
                color_rgb=[1.0, 0.92, 0.78],
                light_range=38.0, energy=4.5,
                settlement_id=cc["id"], role="street_lamp"
            )
        # City Townhouses
        diag_offsets = [(-r_u * 0.75, -r_v * 0.75), (r_u * 0.75, -r_v * 0.75), (-r_u * 0.75, r_v * 0.75), (r_u * 0.75, r_v * 0.75)]
        for k, (ou, ov) in enumerate(diag_offsets):
            u_h = (cc["u"] + ou) % 1.0
            v_h = max(0.01, min(0.99, cc["v"] + ov))
            if is_valid_land(u_h, v_h):
                add_object(
                    obj_type_enum=5, # HOUSE
                    u_coord=u_h, v_coord=v_h,
                    name=f"{cc['id']}_Townhouse_{k + 1}",
                    color_rgb=[1.0, 0.85, 0.55],
                    light_range=14.0, energy=2.4,
                    settlement_id=cc["id"], role="city_residence",
                    yaw_rad=k * (math.pi * 0.5)
                )

    # 10 Villages: Houses, Bonfires/Campfires, and Rural Windmills
    for v_obj in villages:
        v_u = v_obj["u"]
        v_v = v_obj["v"]

        if v_obj["size"] == "large":
            # Central Bonfire (Type 4)
            add_object(
                obj_type_enum=4, # BONFIRE
                u_coord=v_u, v_coord=v_v,
                name=f"{v_obj['id']}_Central_Bonfire",
                color_rgb=[1.0, 0.48, 0.12],
                light_range=80.0, energy=8.5,
                settlement_id=v_obj["id"], role="village_bonfire"
            )
            # Perimeter Campfires
            add_object(
                obj_type_enum=0, # CAMPFIRE
                u_coord=(v_u + 0.015) % 1.0,
                v_coord=max(0.01, min(0.99, v_v + 0.012)),
                name=f"{v_obj['id']}_Perimeter_Campfire_1",
                color_rgb=[1.0, 0.60, 0.22],
                light_range=38.0, energy=5.0,
                settlement_id=v_obj["id"], role="village_perimeter_fire"
            )
            add_object(
                obj_type_enum=0, # CAMPFIRE
                u_coord=(v_u - 0.014) % 1.0,
                v_coord=max(0.01, min(0.99, v_v - 0.011)),
                name=f"{v_obj['id']}_Perimeter_Campfire_2",
                color_rgb=[1.0, 0.58, 0.20],
                light_range=36.0, energy=4.8,
                settlement_id=v_obj["id"], role="village_perimeter_fire"
            )
            # 4 Village Cabins
            house_offsets = [(-0.010, -0.008), (0.011, -0.007), (-0.009, 0.010), (0.012, 0.009)]
            for h_idx, (ho_u, ho_v) in enumerate(house_offsets):
                u_h = (v_u + ho_u) % 1.0
                v_h = max(0.01, min(0.99, v_v + ho_v))
                if is_valid_land(u_h, v_h):
                    add_object(
                        obj_type_enum=5, # HOUSE
                        u_coord=u_h, v_coord=v_h,
                        name=f"{v_obj['id']}_Cabin_{h_idx + 1}",
                        color_rgb=[1.0, 0.85, 0.55],
                        light_range=14.0, energy=2.4,
                        settlement_id=v_obj["id"], role="village_cabin",
                        yaw_rad=h_idx * 1.57 + 0.3
                    )
            # Farmland Windmill nearby
            u_wm = (v_u + 0.024) % 1.0
            v_wm = max(0.02, min(0.98, v_v + 0.020))
            if is_valid_land(u_wm, v_wm):
                add_object(
                    obj_type_enum=7, # WINDMILL
                    u_coord=u_wm, v_coord=v_wm,
                    name=f"{v_obj['id']}_Windmill",
                    color_rgb=[1.0, 0.88, 0.60],
                    light_range=16.0, energy=2.8,
                    settlement_id=v_obj["id"], role="agricultural_windmill",
                    yaw_rad=0.75
                )
        else:
            # Small villages get 2-3 hearth & communal campfires
            add_object(
                obj_type_enum=0, # CAMPFIRE
                u_coord=v_u, v_coord=v_v,
                name=f"{v_obj['id']}_Hearth_Campfire",
                color_rgb=[1.0, 0.58, 0.20],
                light_range=42.0, energy=5.5,
                settlement_id=v_obj["id"], role="village_hearth"
            )
            add_object(
                obj_type_enum=0, # CAMPFIRE
                u_coord=(v_u + 0.009) % 1.0,
                v_coord=max(0.01, min(0.99, v_v - 0.008)),
                name=f"{v_obj['id']}_Communal_Campfire",
                color_rgb=[1.0, 0.55, 0.18],
                light_range=36.0, energy=4.8,
                settlement_id=v_obj["id"], role="village_communal_fire"
            )
            add_object(
                obj_type_enum=0, # CAMPFIRE
                u_coord=(v_u - 0.008) % 1.0,
                v_coord=max(0.01, min(0.99, v_v + 0.009)),
                name=f"{v_obj['id']}_Outpost_Campfire",
                color_rgb=[1.0, 0.60, 0.22],
                light_range=34.0, energy=4.5,
                settlement_id=v_obj["id"], role="village_outpost_fire"
            )
            # 2 Village Cabins
            s_offsets = [(-0.008, -0.006), (0.009, 0.006)]
            for h_idx, (ho_u, ho_v) in enumerate(s_offsets):
                u_h = (v_u + ho_u) % 1.0
                v_h = max(0.01, min(0.99, v_v + ho_v))
                if is_valid_land(u_h, v_h):
                    add_object(
                        obj_type_enum=5, # HOUSE
                        u_coord=u_h, v_coord=v_h,
                        name=f"{v_obj['id']}_Cabin_{h_idx + 1}",
                        color_rgb=[1.0, 0.85, 0.55],
                        light_range=14.0, energy=2.4,
                        settlement_id=v_obj["id"], role="village_cabin",
                        yaw_rad=h_idx * 1.57 + 0.8
                    )

    # Forest Tree Groves across Woodlands and Foothills
    tree_rng = random.Random(987654)
    tree_count = 0
    max_trees = 90
    for _ in range(350):
        if tree_count >= max_trees:
            break
        u_t = tree_rng.random()
        v_t = tree_rng.uniform(0.05, 0.95)
        px_t = int(round(u_t * (width - 1))) % width
        py_t = int(round(v_t * (height - 1)))
        t_type = terr_grid[py_t][px_t]
        e_type = elev_grid[py_t][px_t]

        # Place trees on grass and dirt hillsides, away from water and roads
        if t_type in (2, 3) and e_type >= water_level + 1.2:
            add_object(
                obj_type_enum=6, # TREE
                u_coord=u_t, v_coord=v_t,
                name=f"Forest_Tree_{tree_count + 1}",
                color_rgb=[0.0, 0.0, 0.0],
                light_range=0.0, energy=0.0,
                settlement_id="Wildland_Forest", role="forest_tree",
                yaw_rad=tree_rng.uniform(0.0, math.tau)
            )
            tree_count += 1

    # River Crossing Bridges
    for b_idx, br in enumerate(bridge_crossings):
        add_object(
            obj_type_enum=3, # BRIDGE
            u_coord=br["u"], v_coord=br["v"],
            name=f"River_Bridge_{b_idx + 1}",
            color_rgb=[1.0, 0.90, 0.72],
            light_range=38.0, energy=4.2,
            settlement_id="Regional_Transport", role="river_crossing_bridge",
            yaw_rad=br["yaw_rad"]
        )

    # Navigation Beacon Lanterns at Cylinder End Caps
    end_cap_v_zones = [0.03, 0.97]
    for z_idx, v_cap in enumerate(end_cap_v_zones):
        for k in range(4):
            u_b = (float(k) / 4.0 + 0.125) % 1.0
            add_object(
                obj_type_enum=2, # BEACON_LANTERN
                u_coord=u_b, v_coord=v_cap,
                name=f"EndCap_NavBeacon_{'South' if z_idx == 0 else 'North'}_{k + 1}",
                color_rgb=[0.20, 0.88, 1.0],
                light_range=45.0, energy=5.5,
                settlement_id=f"EndCap_{'South' if z_idx == 0 else 'North'}", role="navigation_beacon"
            )

    # 10. Spawn Points Generation (Curated village, city, and landmark spawns with nearby fires)
    spawn_points = []

    # Default Primary Spawn: Village 1 Grand Bonfire Plaza
    for v_obj in villages:
        if v_obj["id"] == "Village_1":
            u_sp = v_obj["u"]
            v_sp = v_obj["v"] - (4.0 / CYLINDER_LENGTH)
            theta_sp = (u_sp * math.tau) - math.pi
            z_sp = (v_sp - 0.5) * CYLINDER_LENGTH
            px_sp = int(round(u_sp * (width - 1))) % width
            py_sp = int(round(v_sp * (height - 1)))
            elev_sp = elev_grid[py_sp][px_sp]

            spawn_points.append({
                "id": "village_1_bonfire",
                "name": "Village 1 - Grand Bonfire Plaza (Default Spawn)",
                "settlement_id": "Village_1",
                "u": round(u_sp, 5),
                "v": round(v_sp, 5),
                "theta": round(theta_sp, 5),
                "z": round(z_sp, 2),
                "elevation": round(elev_sp, 2),
                "facing_yaw_rad": 0.0, # Facing North (+Z) directly towards the Bonfire
                "nearby_light": "Village_1_Central_Bonfire",
                "is_default": True
            })
            break

    # City Center Cyan Beacon Plaza
    for cc in city_centers:
        u_sp = cc["u"]
        v_sp = cc["v"] - (5.0 / CYLINDER_LENGTH)
        theta_sp = (u_sp * math.tau) - math.pi
        z_sp = (v_sp - 0.5) * CYLINDER_LENGTH
        px_sp = int(round(u_sp * (width - 1))) % width
        py_sp = int(round(v_sp * (height - 1)))
        elev_sp = elev_grid[py_sp][px_sp]

        spawn_points.append({
            "id": f"{cc['id'].lower()}_square",
            "name": f"{cc['id'].replace('_', ' ')} - Cyan Beacon Plaza",
            "settlement_id": cc["id"],
            "u": round(u_sp, 5),
            "v": round(v_sp, 5),
            "theta": round(theta_sp, 5),
            "z": round(z_sp, 2),
            "elevation": round(elev_sp, 2),
            "facing_yaw_rad": 0.0,
            "nearby_light": f"{cc['id']}_Central_Beacon",
            "is_default": False
        })

    # All other villages (Large & Small)
    for v_obj in villages:
        if v_obj["id"] == "Village_1":
            continue
        u_sp = v_obj["u"]
        v_sp = v_obj["v"] - (3.5 / CYLINDER_LENGTH)
        theta_sp = (u_sp * math.tau) - math.pi
        z_sp = (v_sp - 0.5) * CYLINDER_LENGTH
        px_sp = int(round(u_sp * (width - 1))) % width
        py_sp = int(round(v_sp * (height - 1)))
        elev_sp = elev_grid[py_sp][px_sp]

        light_name = f"{v_obj['id']}_Central_Bonfire" if v_obj["size"] == "large" else f"{v_obj['id']}_Hearth_Campfire"
        spawn_points.append({
            "id": f"{v_obj['id'].lower()}_hearth",
            "name": f"{v_obj['id'].replace('_', ' ')} - {'Bonfire Plaza' if v_obj['size'] == 'large' else 'Hearth Campfire'}",
            "settlement_id": v_obj["id"],
            "u": round(u_sp, 5),
            "v": round(v_sp, 5),
            "theta": round(theta_sp, 5),
            "z": round(z_sp, 2),
            "elevation": round(elev_sp, 2),
            "facing_yaw_rad": 0.0,
            "nearby_light": light_name,
            "is_default": False
        })

    # 11. Output PNG and Metadata
    for y in range(height):
        for x in range(width):
            elevation = elev_grid[y][x]
            t_type = terr_grid[y][x]

            elev_byte = int(round((elevation / max_elevation) * 255.0))
            elev_byte = max(0, min(255, elev_byte))
            elevation_img.putpixel((x, y), elev_byte)
            terrain_img.putpixel((x, y), PALETTE[t_type])

    elev_output_path = os.path.join(output_dir, elevation_filename)
    terr_output_path = os.path.join(output_dir, terrain_filename)
    obj_json_path = os.path.join(output_dir, object_map_filename)
    obj_preview_path = os.path.join(output_dir, "object_map.png")
    biomes_manifest_path = os.path.join(output_dir, "biomes_manifest.json")

    elevation_img.save(elev_output_path)
    terrain_img.save(terr_output_path)

    composite_preview = Image.alpha_composite(terrain_img, object_preview_img)
    composite_preview.save(obj_preview_path)

    obj_data = {
        "generator_version": "2.2.0",
        "cylinder_scale": {"radius_m": CYLINDER_RADIUS, "length_m": CYLINDER_LENGTH},
        "hydrology": {
            "central_sea": {"v_center": 0.50, "width_v": 0.14, "max_depth_m": 18.0, "seabed_elevation_m": 2.0},
            "inland_lake": {"u_center": lake_u, "v_center": lake_v, "depth_m": 9.0, "seabed_elevation_m": 11.0},
            "main_river": {"connects": "Inland Lake to Central Sea", "depth_m": 7.0, "continuity": "guaranteed"},
            "tributaries_count": len(tributaries),
            "bridges_placed": len(bridge_crossings)
        },
        "topography": {
            "max_elevation_massifs": [
                {"name": "South Alpine Massif", "u": peak1_u, "v": peak1_v, "elevation_m": 96.0},
                {"name": "North Alpine Massif", "u": peak2_u, "v": peak2_v, "elevation_m": 98.0}
            ]
        },
        "statistics": {
            "num_city_centers": len(city_centers),
            "num_villages": len(villages),
            "total_placed_objects": len(object_entries),
            "campfires_and_bonfires": sum(1 for o in object_entries if o["object_type"] in (0, 4)),
            "street_lamps": sum(1 for o in object_entries if o["object_type"] == 1),
            "beacon_lanterns": sum(1 for o in object_entries if o["object_type"] == 2),
            "bridges": sum(1 for o in object_entries if o["object_type"] == 3),
            "houses": sum(1 for o in object_entries if o["object_type"] == 5),
            "trees": sum(1 for o in object_entries if o["object_type"] == 6),
            "windmills": sum(1 for o in object_entries if o["object_type"] == 7)
        },
        "settlements": placed_settlements,
        "spawn_points": spawn_points,
        "bridges": bridge_crossings,
        "objects": object_entries
    }
    with open(obj_json_path, "w") as f:
        json.dump(obj_data, f, indent=2)

    with open(biomes_manifest_path, "w") as f:
        json.dump(BIOMES_MANIFEST, f, indent=2)

    map_name = os.path.basename(os.path.normpath(output_dir))
    map_config_data = {
        "map_name": map_name,
        "display_name": f"O'Neill Cylinder ({preset.capitalize()})",
        "version": "1.0.0",
        "description": f"Procedurally generated O'Neill Cylinder ({preset} topography preset) with settlements, hydrology, ground clutter, and biomes.",
        "author": "Colony Habitat Systems",
        "geometry": {
            "cylinder_radius_m": CYLINDER_RADIUS,
            "cylinder_length_m": CYLINDER_LENGTH,
            "endcap_radius_m": CYLINDER_RADIUS,
            "elevation_variance_m": max_elevation,
            "water_sea_level_m": water_level
        },
        "celestial": {
            "day_length_hours": 24.0,
            "year_length_days": 365,
            "earth_latitude_deg": 35.0,
            "axial_tilt_deg": 23.44,
            "solar_lighting_mode": "SOLAR_CYCLE",
            "base_solar_intensity": 3.5,
            "midnight_intensity": 0.12
        },
        "light_profiles": {
            "active_preset": "SOLAR_CYCLE",
            "presets_available": ["UNIFORM", "SOLAR_CYCLE", "GRADIENT", "WARM_SUNSET", "NEON_AURORA", "DAY_NIGHT_WAVE"],
            "diurnal_cycle": {
                "day_length_hours": 24.0,
                "year_length_days": 365,
                "earth_latitude_deg": 35.0,
                "axial_tilt_deg": 23.44,
                "solar_intensity_peak": 3.5,
                "solar_intensity_midnight": 0.12,
                "spectrum_colors": {
                    "noon_daylight": [1.0, 0.98, 0.95, 1.0],
                    "dawn_gold": [1.0, 0.52, 0.18, 1.0],
                    "dusk_violet": [0.65, 0.35, 0.75, 1.0],
                    "nautical_twilight": [0.40, 0.35, 0.68, 1.0],
                    "midnight_starlight": [0.16, 0.20, 0.32, 1.0]
                }
            },
            "atmosphere_and_fog": {
                "rayleigh_air_color": [0.52, 0.72, 0.88, 1.0],
                "air_density": 1.25,
                "air_distance_min_m": 200.0,
                "air_distance_max_m": 18000.0,
                "fog_depth_curve": 1.1,
                "night_fog_color": [0.08, 0.10, 0.17, 1.0]
            }
        },
        "climate_and_atmosphere": {
            "spin_direction": 1,
            "rotation_period_sec": 127.0,
            "base_gravity_m_s2": 9.5,
            "air_density": 1.225,
            "base_air_pressure_kpa": 101.3,
            "temperature_min_c": -10.0,
            "temperature_max_c": 38.0,
            "seasonal_temperature_delta_c": 15.0,
            "snow_temperature_threshold_c": 4.0,
            "cloud_altitude_m": 1250.0,
            "cloud_thickness_m": 250.0,
            "cloud_coverage": 0.55,
            "cloud_density": 1.0,
            "cloud_softness": 0.25,
            "dust_density": 0.20,
            "wind_speed_base_m_s": 8.0,
            "climate_zones": [
                {"name": "Tundra North", "v_range": [0.0, 0.15], "temp_range_c": [-10.0, 5.0], "humidity": 0.25, "precipitation": "snow"},
                {"name": "Temperate North", "v_range": [0.15, 0.40], "temp_range_c": [10.0, 22.0], "humidity": 0.55, "precipitation": "rain"},
                {"name": "Tropical Central Sea", "v_range": [0.40, 0.60], "temp_range_c": [24.0, 34.0], "humidity": 0.85, "precipitation": "heavy_rain"},
                {"name": "Temperate South", "v_range": [0.60, 0.85], "temp_range_c": [12.0, 24.0], "humidity": 0.60, "precipitation": "rain"},
                {"name": "Alpine South", "v_range": [0.85, 1.0], "temp_range_c": [-8.0, 8.0], "humidity": 0.35, "precipitation": "snow"}
            ]
        },
        "hydrology_and_terrain": {
            "water_sea_level_m": water_level,
            "water_depth_fade_m": 15.0,
            "water_shallow_color": [0.08, 0.45, 0.65, 1.0],
            "water_deep_color": [0.02, 0.18, 0.35, 1.0],
            "water_wave_speed": 0.8,
            "water_wave_strength": 0.15,
            "terrain_uv_scale": 32.0,
            "elevation_variance_m": max_elevation
        },
        "ground_clutter": {
            "view_radius_m": 220.0,
            "chunk_size_m": 40.0,
            "density_multiplier": 1.0,
            "models": {
                "grass_tuft": {
                    "type": "procedural_mesh",
                    "category": "foliage",
                    "mesh_generator": "generate_grass_mesh",
                    "scene_path": "",
                    "base_color": [0.24, 0.52, 0.16, 1.0],
                    "tip_color": [0.48, 0.78, 0.25, 1.0],
                    "wind_speed": 2.2,
                    "wind_strength": 0.24,
                    "fade_distance_m": 45.0
                },
                "wildflowers": {
                    "type": "procedural_mesh",
                    "category": "foliage",
                    "mesh_generator": "generate_flower_mesh",
                    "scene_path": "",
                    "base_color": [0.22, 0.50, 0.18, 1.0],
                    "tip_color": [0.95, 0.30, 0.20, 1.0],
                    "wind_speed": 2.6,
                    "wind_strength": 0.18,
                    "fade_distance_m": 45.0
                },
                "pebbles": {
                    "type": "procedural_mesh",
                    "category": "rock_debris",
                    "mesh_generator": "generate_stone_mesh",
                    "scene_path": "",
                    "base_color": [0.42, 0.44, 0.46, 1.0],
                    "tip_color": [0.55, 0.56, 0.58, 1.0],
                    "roughness": 0.94,
                    "fade_distance_m": 45.0
                },
                "crops": {
                    "type": "procedural_mesh",
                    "category": "crops",
                    "mesh_generator": "generate_crop_mesh",
                    "scene_path": "",
                    "base_color": [0.65, 0.52, 0.22, 1.0],
                    "tip_color": [0.88, 0.74, 0.32, 1.0],
                    "wind_speed": 1.8,
                    "wind_strength": 0.20,
                    "fade_distance_m": 45.0
                },
                "shrubs": {
                    "type": "procedural_mesh",
                    "category": "foliage",
                    "mesh_generator": "generate_shrub_mesh",
                    "scene_path": "",
                    "base_color": [0.18, 0.42, 0.14, 1.0],
                    "tip_color": [0.35, 0.65, 0.22, 1.0],
                    "wind_speed": 1.5,
                    "wind_strength": 0.12,
                    "fade_distance_m": 45.0
                }
            },
            "biomes": BIOMES_MANIFEST
        },
        "objects": {
            "model_catalog": {
                "0": {"name": "Campfire", "scene_path": "res://assets/objects/campfire.tscn", "has_light": True, "light_energy": 5.5, "light_range_m": 55.0, "light_color": [1.0, 0.58, 0.22], "flicker": True},
                "1": {"name": "Lamp Post", "scene_path": "res://assets/objects/lamp_post.tscn", "has_light": True, "light_energy": 4.0, "light_range_m": 45.0, "light_color": [1.0, 0.92, 0.70], "flicker": True},
                "2": {"name": "Beacon Lantern", "scene_path": "res://assets/objects/beacon_lantern.tscn", "has_light": True, "light_energy": 12.0, "light_range_m": 120.0, "light_color": [0.45, 0.75, 1.0], "flicker": True},
                "3": {"name": "Arched Bridge", "scene_path": "res://assets/objects/bridge.tscn", "has_light": True, "light_energy": 4.5, "light_range_m": 50.0, "light_color": [1.0, 0.82, 0.45], "flicker": True},
                "4": {"name": "Bonfire", "scene_path": "res://assets/objects/bonfire.tscn", "has_light": True, "light_energy": 8.5, "light_range_m": 85.0, "light_color": [1.0, 0.50, 0.15], "flicker": True},
                "5": {"name": "Colony House", "scene_path": "res://assets/objects/house.tscn", "has_light": False},
                "6": {"name": "Foliage Tree", "scene_path": "res://assets/objects/tree.tscn", "has_light": False},
                "7": {"name": "Windmill", "scene_path": "res://assets/objects/windmill.tscn", "has_light": False}
            },
            "statistics": obj_data["statistics"],
            "settlements": placed_settlements,
            "spawn_points": spawn_points,
            "placed_objects_count": len(object_entries),
            "placed_objects_source": object_map_filename
        },
        "entities": {
            "model_catalog": {},
            "groups": [],
            "spawns": []
        },
        "events": {
            "scheduled": [],
            "environmental_triggers": []
        },
        "relationships": {
            "factions": [],
            "routes": []
        },
        "files": {
            "elevation_map": elevation_filename,
            "terrain_map": terrain_filename,
            "object_map": object_map_filename,
            "object_map_image": "object_map.png",
            "biomes_manifest": "biomes_manifest.json"
        }
    }
    map_config_path = os.path.join(output_dir, "map_config.json")
    with open(map_config_path, "w") as f:
        json.dump(map_config_data, f, indent=2)

    print("=============================================================")
    print(" O'NEILL CYLINDER MAP & OBJECT SUITE GENERATION REPORT")
    print("=============================================================")
    print(f" Preset Selected         : {preset.upper()}")
    print(f" Dimensions              : {width} x {height} px")
    print(f" Hydrology Features      : Central Sea (Depth: 18.0m) + Inland Lake (Depth: 9.0m)")
    print(f" River Channels          : 100% Continuous Main River + {len(tributaries)} Tributaries")
    print(f" River Crossing Bridges  : {len(bridge_crossings)} Bridges Placed & Aligned")
    print(f" Alpine Massifs          : 2 Super High Elevation Massifs (96m - 98m peaks)")
    print(f" Settlements             : {len(city_centers)} City Center, {len(villages)} Villages")
    print(f" Surface Light Objects   : {len(object_entries)} total (Bonfires/Campfires: {obj_data['statistics']['campfires_and_bonfires']}, Lamps: {obj_data['statistics']['street_lamps']}, Beacons: {obj_data['statistics']['beacon_lanterns']}, Bridges: {obj_data['statistics']['bridges']})")
    print(f" Map Config JSON Path    : {map_config_path}")
    print(f" Elevation Map Path      : {elev_output_path}")
    print(f" Terrain Map Path        : {terr_output_path}")
    print(f" Object Map JSON Path    : {obj_json_path}")
    print(f" Object Map Preview Path : {obj_preview_path}")
    print(f" Biomes Manifest Path    : {biomes_manifest_path}")
    print("=============================================================\n")

    return elev_output_path, terr_output_path, obj_json_path

def main():
    parser = argparse.ArgumentParser(
        description="Generate vertically & horizontally tileable elevation, terrain, object placement map with bridges, and biomes manifest."
    )
    parser.add_argument("--preset", type=str, default="dramatic",
                        choices=["dramatic", "alpine", "canyon", "rolling", "archipelago"],
                        help="Topography preset (default: dramatic)")
    parser.add_argument("--num-villages", type=int, default=10, help="Number of rural villages to spawn (default: 10)")
    parser.add_argument("--num-city-centers", type=int, default=1, help="Number of major city center hubs (default: 1)")
    parser.add_argument("--road-development", type=float, default=0.70, help="Road network development factor [0.0..1.0] (default: 0.70)")
    parser.add_argument("--road-width", type=int, default=2, help="Paved road width in cells (default: 2)")
    parser.add_argument("--roughness", type=float, default=0.85, help="Rolling hills roughness multiplier (default: 0.85)")
    parser.add_argument("--width", type=int, default=2048, help="Map image width in pixels (default: 2048)")
    parser.add_argument("--height", type=int, default=1024, help="Map image height in pixels (default: 1024)")
    parser.add_argument("--max-elevation", type=float, default=100.0, help="Maximum elevation in meters (default: 100.0)")
    parser.add_argument("--water-level", type=float, default=20.0, help="Water surface elevation in meters (default: 20.0)")
    parser.add_argument("--seed", type=int, default=42, help="RNG seed for procedural generation")
    parser.add_argument("--out-dir", type=str, default="assets/maps/default", help="Target output directory")
    parser.add_argument("--elev-name", type=str, default="elevation_map.png", help="Elevation PNG filename")
    parser.add_argument("--terr-name", type=str, default="terrain_map.png", help="Terrain PNG filename")
    parser.add_argument("--obj-name", type=str, default="object_map.json", help="Object map JSON filename")

    args = parser.parse_args()

    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(project_dir, args.out_dir) if not os.path.isabs(args.out_dir) else args.out_dir

    generate_tileable_maps(
        width=args.width,
        height=args.height,
        max_elevation=args.max_elevation,
        water_level=args.water_level,
        num_villages=args.num_villages,
        num_city_centers=args.num_city_centers,
        road_development=args.road_development,
        road_width_px=args.road_width,
        preset=args.preset,
        roughness=args.roughness,
        tile_horizontal=True,
        tile_vertical=True,
        seed=args.seed,
        output_dir=out_dir,
        elevation_filename=args.elev_name,
        terrain_filename=args.terr_name,
        object_map_filename=args.obj_name
    )

if __name__ == "__main__":
    main()
