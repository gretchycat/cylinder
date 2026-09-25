class_name TerrainManager
extends RefCounted

enum TerrainType {
	WATER = 0,
	SAND = 1,
	DIRT = 2,
	GRASS = 3,
	CONCRETE = 4,
	ROAD = 5,
	SAND_TO_GRASS = 6,
	DIRT_TO_GRASS = 7,
	ROAD_EDGE = 8
}

var grid_u: int = 128   # Grid divisions around circumference (angle theta)
var grid_v: int = 64    # Grid divisions along cylinder length (Z axis)

var elevation_variance: float = 10.0   # Default 10 meters height variance
var water_level: float = 4.0           # Water surface is 4.0 meters from elevation 0

# Flat 1D storage for 2D RPG grids (size = grid_u * grid_v)
var elevation_data: PackedFloat32Array = PackedFloat32Array()
var terrain_data: PackedByteArray = PackedByteArray()

func _init(u_divisions: int = 128, v_divisions: int = 64, variance: float = 10.0, water_h: float = 4.0) -> void:
	grid_u = max(u_divisions, 16)
	grid_v = max(v_divisions, 8)
	elevation_variance = variance
	water_level = water_h
	generate_default_rpg_map()

## Generates a classic 2D RPG-style world map layout on the cylinder inner surface
func generate_default_rpg_map() -> void:
	var total_cells = grid_u * grid_v
	elevation_data.resize(total_cells)
	terrain_data.resize(total_cells)

	# Seeded deterministic pseudo-noise for RPG landscape features
	for j in range(grid_v):
		var v_frac = float(j) / float(grid_v) # 0 to 1 along length Z
		var z_norm = (v_frac - 0.5) * 2.0      # -1 to +1

		for i in range(grid_u):
			var u_frac = float(i) / float(grid_u) # 0 to 1 around circumference
			var angle = u_frac * TAU

			# 1. Base Rolling Topography (multi-octave harmonic landscape)
			var h1 = sin(angle * 2.0) * cos(z_norm * PI * 1.5) * 0.35
			var h2 = sin(angle * 5.0 + 1.2) * sin(z_norm * PI * 3.0 + 0.4) * 0.20
			var h3 = cos(angle * 9.0 + z_norm * 4.0) * 0.12
			var raw_height = (h1 + h2 + h3 + 0.5) # Roughly 0.0 to 1.0

			# 2. Add an organic river/lake channel (sinuous water body running along cylinder)
			# River meanders around angle ~ PI (deg 180) and has a lake basin at center
			var river_center_angle = PI + sin(z_norm * PI * 2.0) * 0.55
			var angle_dist_river = absf(wrapf(angle - river_center_angle, -PI, PI))
			var lake_factor = exp(-((angle - PI) ** 2 + (z_norm * 2.5) ** 2) / 0.35)

			var river_depth_factor = clampf(1.0 - (angle_dist_river / 0.35), 0.0, 1.0)
			if lake_factor > 0.15:
				river_depth_factor = max(river_depth_factor, clampf(lake_factor * 1.4, 0.0, 1.0))

			# Depress elevation into water basin (elevation < 4.0m)
			var elevation = raw_height * elevation_variance
			if river_depth_factor > 0.0:
				var target_seabed = lerpf(3.8, 0.8, river_depth_factor)
				elevation = lerpf(elevation, target_seabed, river_depth_factor)

			# Guarantee elevation remains in [0.0, elevation_variance]
			elevation = clampf(elevation, 0.0, elevation_variance)

			# 3. Determine Terrain Type based on elevation and designated RPG features
			var t_type = TerrainType.GRASS

			# Axial main road at angle = 0 (z-axis transport corridor)
			# Circumferential ring roads at z_norm ≈ -0.5 and +0.5
			var angle_dist_road = absf(wrapf(angle - 0.0, -PI, PI))
			var is_axial_road = angle_dist_road < 0.05
			var is_ring_road = absf(z_norm - 0.5) < 0.035 or absf(z_norm + 0.5) < 0.035
			var is_road = (is_axial_road or is_ring_road) and elevation >= water_level - 0.2

			# Colony concrete hub / launch port at (angle ≈ 0.4, z_norm ≈ 0.0)
			var is_concrete_hub = absf(wrapf(angle - 0.45, -PI, PI)) < 0.12 and absf(z_norm) < 0.10

			if is_concrete_hub:
				t_type = TerrainType.CONCRETE
				elevation = clampf(elevation, water_level + 1.5, water_level + 2.5)
			elif is_road:
				t_type = TerrainType.ROAD
				elevation = max(elevation, water_level + 0.8) # Elevated roadbed
			elif elevation < water_level:
				t_type = TerrainType.WATER
			elif elevation < water_level + 1.2:
				t_type = TerrainType.SAND
			elif elevation < water_level + 1.8:
				t_type = TerrainType.SAND_TO_GRASS
			elif elevation > elevation_variance * 0.82:
				t_type = TerrainType.DIRT
			elif elevation > elevation_variance * 0.72:
				t_type = TerrainType.DIRT_TO_GRASS
			else:
				t_type = TerrainType.GRASS

			var idx = j * grid_u + i
			elevation_data[idx] = elevation
			terrain_data[idx] = t_type

## Set user-defined elevation array (RPG map height array)
func set_elevation_array(arr: Array, w: int = -1, l: int = -1) -> void:
	if w > 0: grid_u = w
	if l > 0: grid_v = l
	var count = grid_u * grid_v
	elevation_data.resize(count)
	for idx in range(min(arr.size(), count)):
		elevation_data[idx] = float(arr[idx])

## Set user-defined terrain tile array (RPG map tile type array)
func set_terrain_array(arr: Array, w: int = -1, l: int = -1) -> void:
	if w > 0: grid_u = w
	if l > 0: grid_v = l
	var count = grid_u * grid_v
	terrain_data.resize(count)
	for idx in range(min(arr.size(), count)):
		terrain_data[idx] = int(arr[idx])

## Query elevation in meters at continuous angle theta [0, TAU] and z [-L/2, L/2] with bilinear interpolation
func get_elevation(theta: float, z: float, cyl_len: float) -> float:
	if elevation_data.is_empty():
		return 0.0

	var u = fposmod(theta, TAU) / TAU # 0.0 to 1.0
	var v = clampf((z + cyl_len * 0.5) / max(cyl_len, 1.0), 0.0, 1.0)

	var fx = u * float(grid_u)
	var fy = v * float(grid_v - 1)

	var i0 = int(floor(fx)) % grid_u
	var i1 = (i0 + 1) % grid_u
	var j0 = clampi(int(floor(fy)), 0, grid_v - 1)
	var j1 = clampi(j0 + 1, 0, grid_v - 1)

	var tx = fx - floor(fx)
	var ty = fy - floor(fy)

	var e00 = elevation_data[j0 * grid_u + i0]
	var e10 = elevation_data[j0 * grid_u + i1]
	var e01 = elevation_data[j1 * grid_u + i0]
	var e11 = elevation_data[j1 * grid_u + i1]

	var top = lerpf(e00, e10, tx)
	var bot = lerpf(e01, e11, tx)
	return lerpf(top, bot, ty)

## Query terrain tile type at continuous angle theta and z
func get_terrain_type(theta: float, z: float, cyl_len: float) -> int:
	if terrain_data.is_empty():
		return TerrainType.GRASS

	var u = fposmod(theta, TAU) / TAU
	var v = clampf((z + cyl_len * 0.5) / max(cyl_len, 1.0), 0.0, 1.0)

	var i = clampi(int(round(u * float(grid_u))) % grid_u, 0, grid_u - 1)
	var j = clampi(int(round(v * float(grid_v - 1))), 0, grid_v - 1)
	return terrain_data[j * grid_u + i]

## Export current elevation map as a flat array for serialization or editor inspect
func export_elevation_array() -> Array[float]:
	var out: Array[float] = []
	for val in elevation_data:
		out.append(val)
	return out

## Export current terrain type map as a flat array
func export_terrain_array() -> Array[int]:
	var out: Array[int] = []
	for val in terrain_data:
		out.append(val)
	return out
