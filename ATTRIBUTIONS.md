# Asset Attributions & Licenses

This document tracks all external and procedurally generated assets, textures, maps, 3D models, shaders, and audio assets used in the O'Neill Cylinder Simulation Engine.

---

## 1. Weather & Atmospheric Textures

### Rain Droplet Texture (`assets/textures/weather/rain_drop.png`)
* **Description:** 1:3 aspect ratio tapered dark blue streak with soft Gaussian falloff.
* **Source:** Custom procedural texture generator for O'Neill Cylinder Simulation.
* **License:** Creative Commons CC0 1.0 Universal (Public Domain Dedication).
* **Usage:** Volumetric 3D rain particle systems (`GPUParticles3D` / `CPUParticles3D`).

### Snow Flake Texture (`assets/textures/weather/snow_flake.png`)
* **Description:** 1:1 aspect ratio crisp 6-fold radial crystalline snowflake with anti-aliased dendritic branching.
* **Source:** Custom procedural texture generator for O'Neill Cylinder Simulation.
* **License:** Creative Commons CC0 1.0 Universal (Public Domain Dedication).
* **Usage:** Volumetric 3D snowfall particle systems (`GPUParticles3D` / `CPUParticles3D`).

---

## 2. Terrain & Surface Textures

Located in `assets/textures/terrain/`:

* **Seamless Procedural Terrain Texture Suite (22 textures)**:
  * **`grass.png`, `grass_0.png`, `grass_1.png`, `grass_2.png`**: High-frequency organic alpine and meadow grass with micro-fiber blade layering.
  * **`dirt.png`, `dirt_0.png`, `dirt_1.png`, `dirt_2.png`**: Multi-scale granular loamy soil and humus clumps.
  * **`rocks.png`, `rocks_0.png`, `rocks_1.png`, `rocks_2.png`**: Fractured bedrock cliff faces with stratum veining and Voronoi cell ridges.
  * **`sand.png`, `sand_0.png`, `sand_1.png`, `sand_2.png`**: Shoreline, alluvial, and desert silica dunes.
  * **`concrete.png`, `concrete_0.png`, `concrete_1.png`, `concrete_2.png`**: Heavy industrial bulkhead panels, aggregate concrete, and expansion joints.
  * **`farmland.png`, `farmland_0.png`, `farmland_1.png`, `farmland_2.png`**: Furrowed agricultural soil and cultivated crop beds.
  * **`road.png`, `road_0.png`, `road_1.png`, `road_2.png`**: Clean, high-traction bituminous transit asphalt, aggregate gravel roadbeds, and compacted highway surfaces without artificial stripe lines.
  * **`end_cap_ribs.png`**: Radial structural rib pattern for cylinder end-cap retaining bulkheads.
  * **Synthesis Method:** Generated via `scripts/generate_photorealistic_terrain_textures.py` using periodic 4D toroidal noise sampling, Voronoi cell distance wrapping, and multi-octave Fourier synthesis guaranteeing mathematically zero seam discontinuities across periodic boundaries.
  * **License:** Creative Commons CC0 1.0 Universal (Public Domain Dedication).

### External CC0 Texture Resources Reference
The engine's terrain shaders and texture pipeline are designed to be 100% compatible with PBR textures sourced from the following open-access CC0 repositories:
* **ambientCG** ([ambientcg.com](https://ambientcg.com)) - Public domain (CC0) terrain, ground, rock, and architectural surface maps.
* **Poly Haven** ([polyhaven.com](https://polyhaven.com)) - CC0 public domain textures, materials, and HDRIs.
* **ShareTextures** ([sharetextures.com](https://sharetextures.com)) - CC0 public domain architectural and environmental textures.
* When importing external textures from these sources, seamless tiling is verified and documented in this registry.

---

## 3. World Maps, Object Manifests & Modular Map Packages

Located in `assets/maps/<mapname>/` (e.g. `assets/maps/default/`):

* **`map_config.json`**
  * **Description:** Configuration descriptor for the cylinder habitat defining cylinder geometry (radius, length, elevation variance, sea level), celestial cycle (day length, year length, solar latitude, midnight intensity), climate/atmosphere (gravity, rotation period, min/max temperatures, cloud altitude), and asset file mappings.
  * **Source:** Modular O'Neill Cylinder Map Package Standard.
  * **License:** CC0 / Public Domain.
* **`elevation_map.png`**
  * **Description:** 8-bit heightmap defining the topological relief (mountain chains, river canyons, hills, lake basins, and shorelines) of the cylindrical world interior.
  * **Source:** Custom procedural Fourier heightmap synthesis pipeline (`scripts/generate_tileable_maps.py`).
  * **License:** CC0 / Public Domain.
* **`terrain_map.png`**
  * **Description:** 2D RPG biome classification lookup map encoding terrain types (0: Water, 1: Sand, 2: Dirt Paths, 3: Grass, 4: Farmland, 5: Rocks, 6: Concrete City Plazas, 7: Paved Roads).
  * **Source:** Custom procedural biome classification pipeline.
  * **License:** CC0 / Public Domain.
* **`object_map.json` & `object_map.png`**
  * **Description:** Structured entity metadata and visual 2D map preview specifying coordinates, elevations, and lighting properties for city center beacons, street lamps, village bonfires/campfires, and navigation beacons.
  * **Source:** Custom settlement & object distribution generator.
  * **License:** CC0 / Public Domain.
* **`biomes_manifest.json`**
  * **Description:** Extensible biome specification defining ground clutter categories (foliage, rock debris, crop markers, shell fragments), densities, and scale intervals across all 8 biomes.
  * **Source:** Custom biome manifest generator.
  * **License:** CC0 / Public Domain.

---

## 4. Shaders & Visual Effects

Located in `assets/shaders/`:

* **`cylinder_terrain.gdshader`**: Multi-splat triplanar shader projecting seamlessly onto the interior concave cylindrical shell with stochastic rotation and noise blending.
* **`cylinder_water.gdshader`**: Concave cylindrical water body shader with gerstner wave displacements, depth absorption, and specular axial sun reflections.
* **`cylinder_clouds.gdshader` & `cylinder_clouds_far.gdshader`**: Dual-layer troposphere cloud deck shader with 3D toroidal noise embedding and axial wind translation.
* **`cylinder_rain_sheet.gdshader`**: Far-field atmospheric rain/snow curtain depth shader.
* **`campfire_flame.gdshader`**: Animated particle shader for interior settlement campfires and bonfires.
* **`ground_clutter.gdshader`**: GPU instanced foliage, wildflower, crop, shrub, and stone clutter shader with vertex wind sway, distance culling fade, and per-instance color modulation.
* **`cylinder_surface.gdshader`**: Hull bulkhead and structural base shader.

All shaders developed for the O'Neill Cylinder Simulation Engine and released under the **MIT License / CC0**.

---

## 5. 3D Prefabs, Meshes & Objects

Located in `assets/objects/` and `scripts/`:

* **`campfire.tscn`**: Cylindrical interior settlement campfire assembly with animated flame shader and dynamic point lighting.
* **`bonfire.tscn`**: Large village assembly with 16-stone ring, glowing coal bed, 10 timber logs, animated flame cards, ember/smoke particles, and 80m omni light.
* **`lamp_post.tscn`**: Structural perimeter pathway lantern post.
* **`beacon_lantern.tscn`**: High-visibility navigation lantern.
* **`bridge.tscn`**: Walkable stone and steel roadway river bridge with support piers, protective railings, and dual post lantern illumination.
* **`scripts/clutter_manager.gd`**: Procedural mesh generation suite and chunked GPU instancing manager for grass tufts, wildflower blossom heads, mountain stones/scree, agricultural wheat crops, and low-poly shrubs.

### Recommended Free / CC0 3D Model Repositories
The simulation engine's object pipeline and glTF/OBJ importer support assets from the following public domain (CC0) and permissive open-source collections:
* **Kenney Assets** ([kenney.nl](https://kenney.nl)) - CC0 Public Domain 3D kits for Nature, Medieval / Village buildings, Furniture, Roads, and Urban structures.
* **Quaternius** ([quaternius.com](https://quaternius.com)) - CC0 modular low-poly packs for Nature/Trees, Modular Buildings, Medieval Villages, and Props.
* **Poly Pizza** ([poly.pizza](https://poly.pizza)) - CC0 and CC-BY repository of thousands of low-poly 3D models (trees, bridges, houses, vehicles).
* **Poly Haven** ([polyhaven.com](https://polyhaven.com)) - CC0 PBR 3D models and environmental scans.

---

## 6. Audio Architecture

Located in `assets/audio/`:
* `assets/audio/sfx/`
* `assets/audio/music/`
* `assets/audio/sound_effects/`

Directory structures initialized for ambient environmental audio and footstep physical acoustics.

---

## 7. Engine & Fonts

* **Godot Engine**: Copyright (c) 2014-present Juan Linietsky, Ariel Manzur, Godot Engine contributors. Released under the **MIT License**.
* **Engine Icon (`icon.svg`)**: Copyright (c) Godot Engine contributors, released under the **CC-BY 4.0** license.

