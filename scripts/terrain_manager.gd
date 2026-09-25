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

const PALETTE: Dictionary = {
	TerrainType.WATER: Color(0.137, 0.412, 0.765, 1.0),      # #2369C3 Deep Blue
	TerrainType.SAND: Color(0.882, 0.745, 0.490, 1.0),       # #E1BE7D Beach Gold
	TerrainType.DIRT: Color(0.451, 0.306, 0.188, 1.0),       # #734E30 Earth Brown
	TerrainType.GRASS: Color(0.235, 0.549, 0.165, 1.0),      # #3C8C2A Meadow Green
	TerrainType.CONCRETE: Color(0.608, 0.627, 0.659, 1.0),   # #9BA0A8 Light Grey
	TerrainType.ROAD: Color(0.165, 0.173, 0.188, 1.0),       # #2A2C30 Asphalt
	TerrainType.SAND_TO_GRASS: Color(0.569, 0.647, 0.333, 1.0), # #91A555 Transition
	TerrainType.DIRT_TO_GRASS: Color(0.353, 0.431, 0.176, 1.0), # #5A6E2D Transition
	TerrainType.ROAD_EDGE: Color(0.314, 0.333, 0.361, 1.0),     # #50555C Shoulder
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

	# Attempt to load from default PNG maps if present, otherwise generate procedurally
	var loaded = load_maps_from_png("res://assets/maps/elevation_map.png", "res://assets/maps/terrain_map.png")
	if not loaded:
		generate_default_rpg_map()

## Load both elevation and terrain tile maps from PNG image files
func load_maps_from_png(elev_path: String, terrain_path: String) -> bool:
	var ok_elev = load_elevation_from_png(elev_path)
	var ok_terr = load_terrain_from_png(terrain_path)
	return ok_elev and ok_terr

## Load elevation map from PNG image (8-bit grayscale or RGB luminance: 0..255 maps to 0..elevation_variance meters)
func load_elevation_from_png(path: String) -> bool:
	var img = _load_image_from_file_or_buffer(path)
	if not img:
		return false

	grid_u = img.get_width()
	grid_v = img.get_height()
	var total_cells = grid_u * grid_v
	elevation_data.resize(total_cells)

	for y in range(grid_v):
		for x in range(grid_u):
			var col = img.get_pixel(x, y)
			# Normalize luminance/red channel 0.0..1.0 into 0.0..elevation_variance m
			var val_norm = col.r
			var elev = clampf(val_norm * elevation_variance, 0.0, elevation_variance)
			elevation_data[y * grid_u + x] = elev

	return true

## Load terrain map from 2D RPG color-coded PNG image
func load_terrain_from_png(path: String) -> bool:
	var img = _load_image_from_file_or_buffer(path)
	if not img:
		return false

	grid_u = img.get_width()
	grid_v = img.get_height()
	var total_cells = grid_u * grid_v
	terrain_data.resize(total_cells)

	for y in range(grid_v):
		for x in range(grid_u):
			var col = img.get_pixel(x, y)
			var t_type = _color_to_terrain_type(col)
			terrain_data[y * grid_u + x] = t_type

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

## Convert an RGB pixel color to the closest TerrainType
func _color_to_terrain_type(col: Color) -> int:
	# 1. Direct palette color matching (Euclidean RGB distance)
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
	var img = Image.new()
	# Check FileAccess directly
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var bytes = file.get_buffer(file.get_length())
			var err = img.load_png_from_buffer(bytes)
			if err == OK:
				return img

	var global_path = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(global_path):
		var file = FileAccess.open(global_path, FileAccess.READ)
		if file:
			var bytes = file.get_buffer(file.get_length())
			var err = img.load_png_from_buffer(bytes)
			if err == OK:
				return img

	# Fallback to ResourceLoader
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is Texture2D:
			return res.get_image()

	return null

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

			# 2. Water river channel & lake (elevation depressed below 20 m)
			var river_center_angle = 0.5 * PI + sin(z_norm * PI * 2.0) * 0.55
			var angle_dist_river = absf(wrapf(angle - river_center_angle, -PI, PI))
			var lake_dist_sq = ((angle - 0.5 * PI) ** 2 + (z_norm * 2.5) ** 2) / 0.35
			var lake_factor = exp(-lake_dist_sq)

			var river_factor = clampf(1.0 - (angle_dist_river / 0.32), 0.0, 1.0)
			if lake_factor > 0.15:
				river_factor = max(river_factor, clampf(lake_factor * 1.4, 0.0, 1.0))

			var elevation = raw_height * elevation_variance
			if river_factor > 0.0:
				var target_seabed = lerpf(19.0, 5.0, river_factor) # 5m to 19m depth under 20m water
				elevation = lerpf(elevation, target_seabed, river_factor)

			# End Cap Awareness: near cylinder ends (|z_norm| -> 1.0)
			var dist_to_cap_norm = 1.0 - absf(z_norm)
			var is_bulkhead_apron = dist_to_cap_norm < 0.015
			var is_perimeter_ring_road = absf(dist_to_cap_norm - 0.035) < 0.008

			# Coastal seawall containment at end cap interface
			if dist_to_cap_norm < 0.055:
				var seawall_blend = maxf(0.0, 1.0 - dist_to_cap_norm / 0.055)
				elevation = elevation * (1.0 - seawall_blend) + maxf(elevation, 28.0) * seawall_blend

			elevation = clampf(elevation, 0.0, elevation_variance)

			# 3. Determine Terrain Type
			var angle_dist_road = absf(wrapf(angle - 0.0, -PI, PI))
			var is_axial_road = angle_dist_road < 0.035
			var is_ring_road = absf(z_norm - 0.5) < 0.025 or absf(z_norm + 0.5) < 0.025
			var is_road = (is_axial_road or is_ring_road or is_perimeter_ring_road) and elevation >= (water_level - 1.0)

			var is_concrete_hub = absf(wrapf(angle - 0.45, -PI, PI)) < 0.08 and absf(z_norm) < 0.08

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
			elif elevation < water_level:
				t_type = TerrainType.WATER
			elif elevation < water_level + 6.0:
				t_type = TerrainType.SAND
			elif elevation < water_level + 10.0:
				t_type = TerrainType.SAND_TO_GRASS
			elif elevation > 78.0:
				t_type = TerrainType.DIRT
			elif elevation > 70.0:
				t_type = TerrainType.DIRT_TO_GRASS
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
