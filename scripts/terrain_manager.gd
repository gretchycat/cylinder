class_name TerrainManager
extends RefCounted

const MapAssetLoaderClass = preload("res://scripts/map_asset_loader.gd")

enum TerrainType {
	WATER = 0,
	SAND = 1,
	DIRT = 2,
	GRASS = 3,
	FARMLAND = 4,
	ROCKS = 5,
	CONCRETE = 6,
	ROAD = 7
}

const PALETTE: Dictionary = {
	TerrainType.WATER: Color(0.137, 0.412, 0.765, 1.0),      # #2369C3 Deep Blue
	TerrainType.SAND: Color(0.882, 0.745, 0.490, 1.0),       # #E1BE7D Beach Gold
	TerrainType.DIRT: Color(0.451, 0.306, 0.188, 1.0),       # #734E30 Earth Brown
	TerrainType.GRASS: Color(0.235, 0.549, 0.165, 1.0),      # #3C8C2A Meadow Green
	TerrainType.FARMLAND: Color(0.647, 0.471, 0.196, 1.0),   # #A57832 Ochre Furrowed Soil
	TerrainType.ROCKS: Color(0.373, 0.392, 0.424, 1.0),      # #5F646C Slate Mountain Rock
	TerrainType.CONCRETE: Color(0.686, 0.706, 0.737, 1.0),   # #AFB4BC Light Grey
	TerrainType.ROAD: Color(0.165, 0.173, 0.188, 1.0),       # #2A2C30 Asphalt
}

## Connection and edge fading properties per terrain type
const TERRAIN_RULES: Dictionary = {
	TerrainType.WATER:    {"name": "Water",    "is_artificial": false, "fade_width": 0.35, "roughness": 0.20, "metallic": 0.05},
	TerrainType.SAND:     {"name": "Sand",     "is_artificial": false, "fade_width": 0.40, "roughness": 0.90, "metallic": 0.02},
	TerrainType.DIRT:     {"name": "Dirt",     "is_artificial": false, "fade_width": 0.42, "roughness": 0.88, "metallic": 0.02},
	TerrainType.GRASS:    {"name": "Grass",    "is_artificial": false, "fade_width": 0.45, "roughness": 0.82, "metallic": 0.02},
	TerrainType.FARMLAND: {"name": "Farmland", "is_artificial": true,  "fade_width": 0.04, "roughness": 0.85, "metallic": 0.02},
	TerrainType.ROCKS:    {"name": "Rocks",    "is_artificial": false, "fade_width": 0.38, "roughness": 0.92, "metallic": 0.05},
	TerrainType.CONCRETE: {"name": "Concrete", "is_artificial": true,  "fade_width": 0.01, "roughness": 0.45, "metallic": 0.15},
	TerrainType.ROAD:     {"name": "Road",     "is_artificial": true,  "fade_width": 0.01, "roughness": 0.38, "metallic": 0.12},
}

var grid_u: int = 512   # Grid divisions around circumference (angle theta)
var grid_v: int = 256   # Grid divisions along cylinder length (Z axis)

var elevation_variance: float = 100.0   # Valid elevations range from 0.0 to 100.0 m
var water_level: float = 20.0           # Water surface is 20.0 meters from elevation 0

# Flat 1D storage for 2D RPG grids (size = grid_u * grid_v)
var elevation_data: PackedFloat32Array = PackedFloat32Array()
var terrain_data: PackedByteArray = PackedByteArray()

func _init(u_divisions: int = 512, v_divisions: int = 256, variance: float = 100.0, water_h: float = 20.0) -> void:
	grid_u = max(u_divisions, 16)
	grid_v = max(v_divisions, 8)
	elevation_variance = variance
	water_level = water_h

	var loaded = load_maps_from_png("res://assets/maps/default/elevation_map.png", "res://assets/maps/default/terrain_map.png")
	if not loaded:
		loaded = load_maps_from_png("res://assets/maps/elevation_map.png", "res://assets/maps/terrain_map.png")
	if not loaded:
		generate_default_rpg_map()

## Backwards-compatible alias for loading elevation and terrain image files.
func load_maps_from_png(elev_path: String, terrain_path: String) -> bool:
	var ok_elev = load_elevation_from_image(elev_path)
	var ok_terr = load_terrain_from_image(terrain_path)
	return ok_elev and ok_terr

func load_maps_from_images(elev_path: String, terrain_path: String) -> bool:
	return load_maps_from_png(elev_path, terrain_path)

## Backwards-compatible alias; image format is detected by Godot.
func load_elevation_from_png(path: String) -> bool:
	return load_elevation_from_image(path)

## Load elevation image (grayscale: 0..255 maps to 0..elevation_variance meters).
func load_elevation_from_image(path: String) -> bool:
	var img = _load_image_from_file_or_buffer(path)
	if not img:
		return false

	img.convert(Image.FORMAT_L8)
	grid_u = img.get_width()
	grid_v = img.get_height()
	var total_cells = grid_u * grid_v
	elevation_data.resize(total_cells)
	var raw_bytes = img.get_data()
	var factor = elevation_variance / 255.0

	for i in range(total_cells):
		elevation_data[i] = float(raw_bytes[i]) * factor

	return true

## Backwards-compatible alias; image format is detected by Godot.
func load_terrain_from_png(path: String) -> bool:
	return load_terrain_from_image(path)

## Load terrain map from a 2D RPG color-coded image.
func load_terrain_from_image(path: String) -> bool:
	var img = _load_image_from_file_or_buffer(path)
	if not img:
		return false

	img.convert(Image.FORMAT_RGBA8)
	grid_u = img.get_width()
	grid_v = img.get_height()
	var total_cells = grid_u * grid_v
	terrain_data.resize(total_cells)
	var raw_bytes = img.get_data()

	var pal_entries: Array = []
	for t_id in PALETTE:
		var c: Color = PALETTE[t_id]
		pal_entries.append({
			"type": t_id,
			"r": int(round(c.r * 255.0)),
			"g": int(round(c.g * 255.0)),
			"b": int(round(c.b * 255.0))
		})

	for i in range(total_cells):
		var p_idx = i * 4
		var r = int(raw_bytes[p_idx])
		var g = int(raw_bytes[p_idx + 1])
		var b = int(raw_bytes[p_idx + 2])

		var best_dist = 999999
		var best_type = TerrainType.GRASS
		for entry in pal_entries:
			var dr = r - entry.r
			var dg = g - entry.g
			var db = b - entry.b
			var dist_sq = dr * dr + dg * dg + db * db
			if dist_sq < best_dist:
				best_dist = dist_sq
				best_type = entry.type

		terrain_data[i] = best_type

	return true

## Save current elevation grid to PNG image file
func save_elevation_to_png(save_path: String) -> bool:
	var img = create_elevation_image()
	if not img:
		return false
	var global_path = ProjectSettings.globalize_path(save_path)
	var err = img.save_png(global_path)
	return err == OK

## Save current terrain tile grid to 2D RPG color-coded PNG image file
func save_terrain_to_png(save_path: String) -> bool:
	var img = create_terrain_image()
	if not img:
		return false
	var global_path = ProjectSettings.globalize_path(save_path)
	var err = img.save_png(global_path)
	return err == OK

## Export elevation data as an 8-bit Image object
func create_elevation_image() -> Image:
	var img = Image.create(grid_u, grid_v, false, Image.FORMAT_L8)
	for y in range(grid_v):
		for x in range(grid_u):
			var elev = elevation_data[y * grid_u + x]
			var norm = clampf(elev / max(elevation_variance, 0.1), 0.0, 1.0)
			img.set_pixel(x, y, Color(norm, norm, norm, 1.0))
	return img

## Export terrain tile data as an RGBA8 Image object
func create_terrain_image() -> Image:
	var img = Image.create(grid_u, grid_v, false, Image.FORMAT_RGBA8)
	for y in range(grid_v):
		for x in range(grid_u):
			var t_type = terrain_data[y * grid_u + x]
			var col = PALETTE.get(t_type, PALETTE[TerrainType.GRASS])
			img.set_pixel(x, y, col)
	return img

## Export terrain type as single-channel byte texture (R8) for direct shader sampling
func create_terrain_type_id_image() -> Image:
	var img = Image.create(grid_u, grid_v, false, Image.FORMAT_R8)
	for y in range(grid_v):
		for x in range(grid_u):
			var t_type = float(terrain_data[y * grid_u + x]) / 255.0
			img.set_pixel(x, y, Color(t_type, 0.0, 0.0, 1.0))
	return img

## Convert an RGB pixel color to the closest TerrainType
func _color_to_terrain_type(col: Color) -> int:
	var best_dist: float = 999999.0
	var best_type: int = TerrainType.GRASS

	for t_id in PALETTE:
		var pal_col: Color = PALETTE[t_id]
		var dr = col.r - pal_col.r
		var dg = col.g - pal_col.g
		var db = col.b - pal_col.b
		var dist_sq = dr * dr + dg * dg + db * db
		if dist_sq < best_dist:
			best_dist = dist_sq
			best_type = t_id

	return best_type

## Robust image loader supporting res://, buffers, and exported packages
func _load_image_from_file_or_buffer(path: String) -> Image:
	var img = MapAssetLoaderClass.load_image(path)
	if img and not img.is_empty():
		return img
	var texture = MapAssetLoaderClass.load_texture(path)
	return texture.get_image() if texture else null

## Generates a classic 2D RPG-style world map layout on the cylinder inner surface
func generate_default_rpg_map() -> void:
	var total_cells = grid_u * grid_v
	elevation_data.resize(total_cells)
	terrain_data.resize(total_cells)

	for j in range(grid_v):
		var v_frac = float(j) / float(grid_v)
		var z_norm = (v_frac - 0.5) * 2.0

		for i in range(grid_u):
			var u_frac = float(i) / float(grid_u)
			var angle = u_frac * TAU

			# 1. Base Rolling Topography in 0 to 100 m
			var h1 = sin(angle * 2.0) * cos(z_norm * PI * 1.5) * 0.32
			var h2 = sin(angle * 4.0 + 1.2) * sin(z_norm * PI * 2.5 + 0.5) * 0.18
			var h3 = cos(angle * 8.0 + z_norm * 3.5) * 0.10
			var h4 = sin(angle * 14.0 - z_norm * 6.0) * 0.05
			var raw_height = (h1 + h2 + h3 + h4 + 0.52)

			# 2. Water river channel & lake
			var river_center_angle = 0.5 * PI + sin(z_norm * PI * 2.0) * 0.55
			var angle_dist_river = absf(wrapf(angle - river_center_angle, -PI, PI))
			var lake_dist_sq = ((angle - 0.5 * PI) ** 2 + (z_norm * 2.5) ** 2) / 0.35
			var lake_factor = exp(-lake_dist_sq)

			var river_factor = clampf(1.0 - (angle_dist_river / 0.32), 0.0, 1.0)
			if lake_factor > 0.15:
				river_factor = max(river_factor, clampf(lake_factor * 1.4, 0.0, 1.0))

			var elevation = raw_height * elevation_variance
			if river_factor > 0.0:
				var target_seabed = lerpf(17.5, 3.5, river_factor)
				elevation = lerpf(elevation, target_seabed, river_factor)

			# End Cap Awareness
			var dist_to_cap_norm = 1.0 - absf(z_norm)
			var is_bulkhead_apron = dist_to_cap_norm < 0.015
			var is_perimeter_ring_road = absf(dist_to_cap_norm - 0.035) < 0.008

			if dist_to_cap_norm < 0.055:
				var seawall_blend = maxf(0.0, 1.0 - dist_to_cap_norm / 0.055)
				elevation = elevation * (1.0 - seawall_blend) + maxf(elevation, 28.0) * seawall_blend

			elevation = clampf(elevation, 0.0, elevation_variance)

			# 3. Determine Pure Terrain Type
			var angle_dist_road = absf(wrapf(angle - 0.0, -PI, PI))
			var is_axial_road = angle_dist_road < 0.035
			var is_ring_road = absf(z_norm - 0.5) < 0.025 or absf(z_norm + 0.5) < 0.025
			var is_road = (is_axial_road or is_ring_road or is_perimeter_ring_road) and elevation >= (water_level - 1.0)

			var is_concrete_hub = absf(wrapf(angle - 0.45, -PI, PI)) < 0.08 and absf(z_norm) < 0.08
			var is_farmland = absf(wrapf(angle - 1.2, -PI, PI)) < 0.14 and absf(z_norm - 0.25) < 0.12 and elevation > water_level + 2.0 and elevation < 55.0

			var t_type = TerrainType.GRASS

			if is_bulkhead_apron:
				t_type = TerrainType.CONCRETE
				elevation = max(elevation, water_level + 8.0)
			elif is_concrete_hub:
				t_type = TerrainType.CONCRETE
				elevation = max(elevation, water_level + 8.0)
			elif is_road:
				t_type = TerrainType.ROAD
				elevation = max(elevation, water_level + 4.0)
			elif is_farmland:
				t_type = TerrainType.FARMLAND
			elif elevation < water_level:
				t_type = TerrainType.WATER
			elif elevation < water_level + 6.0:
				t_type = TerrainType.SAND
			elif elevation > 75.0:
				t_type = TerrainType.ROCKS
			elif elevation > 58.0:
				t_type = TerrainType.DIRT
			else:
				t_type = TerrainType.GRASS

			var idx = j * grid_u + i
			elevation_data[idx] = elevation
			terrain_data[idx] = t_type

## Set user-defined elevation array
func set_elevation_array(arr: Array, w: int = -1, l: int = -1) -> void:
	if w > 0: grid_u = w
	if l > 0: grid_v = l
	var count = grid_u * grid_v
	elevation_data.resize(count)
	for idx in range(min(arr.size(), count)):
		elevation_data[idx] = float(arr[idx])

## Set user-defined terrain tile array
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

	var u = fposmod(theta, TAU) / TAU
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

## Export current elevation map as a flat array
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
