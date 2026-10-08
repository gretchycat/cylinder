# AGENTS.md — Architecture & Design Standards

This document serves as the authoritative guide for AI agents and human developers contributing to the **O'Neill Cylinder Simulation Engine**.

---

## 1. Project Overview

The project is an **O'Neill Cylinder simulation engine** built in **Godot 4.7** targeting the **Mobile** renderer for cross-platform compatibility (Desktop & Android). The engine simulates living conditions inside a spinning cylindrical space habitat (typically 8 km diameter $\times$ 18 km length).

Key features:
- **Centrifugal Gravity Vector**: Gravity points radially outward toward the cylinder surface.
- **Axial Light Bar**: Central light source along the cylinder spin axis simulating day/night cycles.
- **Procedural & Handcrafted Terrain**: Cylindrical heightmap rasterization, hydraulic/thermal erosion, rivers, lakes, biomes, and object scattering.
- **Distance-Based Placement Streaming**: Dynamic instantiation of 3D props and local surface lights based on proximity to camera/player to keep memory and draw calls within mobile budgets.
- **GPU Instanced Ground Clutter**: Multimesh grass tufts, pebbles, flowers, and ground cover managed in spatial chunks.

---

## 2. Geometry & Coordinate System

Spatial positioning within the cylinder uses a cylindrical coordinate system mapped to 3D Cartesian space:

$$\begin{aligned}
x &= (R + e) \cdot \cos(\theta) \\
y &= (R + e) \cdot \sin(\theta) \\
z &= z
\end{aligned}$$

Where:
- $\theta \in [0, 2\pi)$ is the circumference angle in radians (seam wraps at $0 \equiv 2\pi$).
- $z \in [-L/2, L/2]$ is the longitudinal distance along the cylinder axis in meters.
- $R$ is the base cylinder radius (default: $4000.0\text{ m}$).
- $e$ is elevation offset relative to base radius.

---

## 3. Core Engine Architecture

```
                 +-----------------------+
                 |   Map Package / JSON  |
                 | (map_config / biomes) |
                 +-----------+-----------+
                             |
                             v
                 +-----------------------+
                 |  scripts/map_config   |
                 | (Load / Validate /    |
                 |  Grid Calculation)    |
                 +-----------+-----------+
                             |
         +-------------------+-------------------+
         |                                       |
         v                                       v
+------------------+                    +------------------+
|  map_generator   |                    | reference_objects|
| (Heightmaps &    |                    |  (Placement      |
|  Object Scatter) |                    |   Streaming)     |
+--------+---------+                    +--------+---------+
         |                                       |
         +-------------------+-------------------+
                             |
                             v
                 +-----------------------+
                 |  cylinder_generator   |
                 | (Mesh & Collision &   |
                 |   Shader Materials)   |
                 +-----------------------+
```

### Key Modules & Responsibilities

| Script | Purpose |
| :--- | :--- |
| [`scripts/map_config.gd`](file:///data/data/com.termux/files/home/Projects/cylinder/scripts/map_config.gd) | Handles map descriptor loading, schema validation, color parsing, and default grid calculations. |
| [`scripts/map_generator.gd`](file:///data/data/com.termux/files/home/Projects/cylinder/scripts/map_generator.gd) | Procedurally generates elevation/terrain heightmaps, river/lake erosion, and scatters biome objects. |
| [`scripts/cylinder_generator.gd`](file:///data/data/com.termux/files/home/Projects/cylinder/scripts/cylinder_generator.gd) | Generates the 3D cylindrical surface mesh, collision hulls, end-cap walls, and axial light bar. |
| [`scripts/reference_objects.gd`](file:///data/data/com.termux/files/home/Projects/cylinder/scripts/reference_objects.gd) | Manages distance-based object streaming, instantiating models and lights within active visibility ranges. |
| [`scripts/clutter_manager.gd`](file:///data/data/com.termux/files/home/Projects/cylinder/scripts/clutter_manager.gd) | MultiMesh ground clutter renderer with chunked streaming and adaptive quality density scaling. |
| [`scripts/climate_system.gd`](file:///data/data/com.termux/files/home/Projects/cylinder/scripts/climate_system.gd) | Simulates temperature, humidity, dust, and diurnal weather patterns. |
| [`scripts/hud.gd`](file:///data/data/com.termux/files/home/Projects/cylinder/scripts/hud.gd) | Main player UI, performance metrics, map inspector, and environmental control sliders. |
| [`scripts/player_controller.gd`](file:///data/data/com.termux/files/home/Projects/cylinder/scripts/player_controller.gd) | 3D player controller adapted for cylindrical orientation and outward radial gravity. |

---

## 4. Design Standards & Default Configuration

### Map Generation Pitch Standard
- **Default Pitch (`sample_pitch_m`)**: **`8.0` meters per pixel**.
- When `sample_pitch_m` is unconstrained in a map descriptor or generation request, the default sampling resolution is $8.0\text{ m/px}$.

### Map Seed Standard
- **Random Map Seed Default**: Unless explicitly specified in a CLI argument (`--seed` / `-s`) or descriptor document, map generation automatically generates a random seed (`(int(Time.get_ticks_usec()) ^ randi()) & 0x7fffffff`).

### Tree Density Standard
- **Tree Density Budget**: **75% of baseline density**.
- Tree object densities across biome manifests (`biomes_manifest.json`), map configs (`map_config.json`), and pre-generated placement maps (`placements.json`) are maintained at 75% of legacy baseline density to prevent mobile vertex overload and ensure high frame rates on Android devices.

### Placement Streaming Standards
- **Streaming Radius (`PLACEMENT_STREAM_RADIUS_M`)**: `850.0` meters.
- **Retention Radius (`PLACEMENT_RETENTION_RADIUS_M`)**: `1250.0` meters.
- **Maximum Live Placements (`MAX_LIVE_PLACEMENTS`)**: `256` active node instances.
- **Mobile Local Light Budget (`MOBILE_LOCAL_LIGHT_BUDGET`)**: `6` active OmniLights near camera.

### Object Placement Metadata Standards
- **Ground Offset (`ground_offset_m`)**: Sinks objects (negative values along normal/up axis, e.g. `-0.4m` for dead tree `tree_5`) so curved trunk bases sit properly underground.
- **Normal Alignment (`align_to_normal`)**: Objects like campfires align flat to terrain surface normals (`align_to_normal: true`), while upright structures (trees, buildings) align vertically with centrifugal gravity (`align_to_normal: false`).
- **Random Rotations & Fallen Variants**: Placements store 3D rotation angles (`yaw_rad`, `pitch_rad`, `roll_rad`). Objects with `allow_on_side: true` (e.g. dead trees) are occasionally scattered lying on their side as fallen logs during procedural map generation (`on_side_chance: 0.25`).

### Modular Biomes & Descriptor Architecture Standards
- **Individual Biome JSON Files (`assets/biomes/<biome_id>.json`)**: Every biome is specified in its own standalone JSON document containing identity, climate preferences, terrain material specs, clutter density, object scattering budgets, and POI creation rules.
- **Primary vs Filler Biome Roles**: Map descriptors define target coverage percentages ± variance (`target_percentage: 20.0`, `variance_percent: 4.0`) and roles: `"primary"` biomes establish main contiguous regions, while `"filler"` biomes blend transitional boundaries.
- **Meta & Artificial Geometric Biomes**: Meta biomes handle environmental conditions (hydrology, lakes, rivers, waterbeds), while artificial biomes render geometric shapes (`"circle"`, `"rectangle"`, `"square"`, `"polygon"`) for settlements, farmlands, and outposts.
- **Path Artificial Biomes**: Paved roads and trails connect points of interest (POIs) with defined road width and geometry.
- **Points of Interest Registry (`pois.json`)**: Automatically generated during map creation, exporting 3D coordinates ($x,y,z$), cylindrical coordinates ($\theta, z$), elevation, POI type, and landmark names.

---

## 5. Coding Standards & Best Practices

1. **GDScript Conventions**:
   - Use static typing everywhere (`var radius: float = 4000.0`, `func calc(...) -> Dictionary:`).
   - Annotate exported variables with `@export` and `@export_category`.
   - Preserve `@tool` compatibility for scripts running in editor tool mode.

2. **Schema & Validation**:
   - Validate map JSON fields strictly in `MapConfigClass.validate_map_config()`.
   - Never assume missing fields; use safe accessor fallbacks (`doc.get("generation", {})`).

3. **Error Handling & Logs**:
   - Print clear diagnostics with `printerr()` and store error details in `Config.last_error`.
   - Never suppress errors silently or mask broken state with dummy values.

---

## 6. Verification & Test Suite

Before committing any changes, run the headless test suite to verify pipeline integrity:

```bash
# Run headless verification test suite
bash build.sh test
```

Or run test scripts individually via Godot:
```bash
godot --headless -s res://scripts/test_map_pipeline.gd
```

All tests must report **`MAP PIPELINE FAILURES: 0`**.
