class_name MapConfig
extends RefCounted

## Schema 4 map document. See docs/map-descriptor.md.
const DEFAULT_MAP_DIRECTORY = "res://assets/maps/default"
const MAP_ROOT_DIR = "res://assets/maps"
static var active_map_file: String = "user://active_map.txt"
static var last_error: String = ""
static var user_maps_directory: String = "user://maps"
static var active_map_validated_directory: String = ""
static var active_map_preloaded_terrain: RefCounted = null
static var active_map_assets_validated_directory: String = ""

static func resolve_map_dir(value: String) -> String:
	if value.ends_with("/map_config.json"):
		return value.get_base_dir()
	if value.begins_with("res://") or value.begins_with("user://") or value.begins_with("/"):
		return value.trim_suffix("/")
	return MAP_ROOT_DIR.path_join(value)

static func new_map_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func new_user_directory(prefix: String = "map") -> String:
	return user_maps_directory.path_join(prefix + "_" + new_map_id())

static func create_from_template() -> String:
	var directory = new_user_directory()
	if copy_directory(DEFAULT_MAP_DIRECTORY, directory) != OK:
		return ""
	var doc = load_map_config(directory)
	if doc.is_empty():
		return ""
	doc.world_id = new_map_id()
	doc["name"] = "My habitat"
	doc["template_revision"] = FileAccess.get_sha256(DEFAULT_MAP_DIRECTORY.path_join("map_config.json"))
	if save_document(doc, directory) != OK or publish_map(directory) != OK:
		return ""
	return directory

static func active_map() -> String:
	if FileAccess.file_exists(active_map_file):
		var path = FileAccess.get_file_as_string(active_map_file).strip_edges()
		if path.begins_with("user://") and FileAccess.file_exists(path.path_join("map_config.json")):
			if path == active_map_validated_directory:
				return path
			var doc = load_map_config(path)
			if not doc.is_empty():
				var asset_error = validate_assets(doc)
				if asset_error.is_empty():
					var terrain = preload("res://scripts/terrain_manager.gd").new()
					terrain.configure(doc)
					if terrain.load_layers(get_elevation_map_path(doc), get_terrain_map_path(doc)):
						active_map_validated_directory = path
						active_map_assets_validated_directory = path
						active_map_preloaded_terrain = terrain
						publish_map(path)
						return path
					last_error = terrain.last_error
				else:
					last_error = asset_error
			push_warning("Saved map could not be loaded; keeping it and opening the current template: " + last_error)
	var directory = create_from_template()
	if not directory.is_empty() and activate(directory) == OK:
		active_map_validated_directory = directory
		return directory
	push_error("Unable to create writable map: " + last_error)
	return ""

static func take_active_map_terrain(directory: String) -> RefCounted:
	if directory != active_map_validated_directory or active_map_preloaded_terrain == null:
		return null
	var terrain = active_map_preloaded_terrain
	active_map_preloaded_terrain = null
	return terrain

static func load_map_config(value: String = "default") -> Dictionary:
	last_error = ""
	var directory = resolve_map_dir(value)
	var path = directory.path_join("map_config.json")
	if not FileAccess.file_exists(path):
		last_error = "Missing map definition: " + path
		return {}
	var json = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		last_error = "Invalid map JSON: " + path
		return {}
	var doc: Dictionary = json.data
	last_error = validate(doc)
	if not last_error.is_empty():
		return {}
	doc["map_directory"] = directory
	return doc

static func color(value: Array) -> Color:
	return Color(value[0], value[1], value[2], value[3])

static func rgba(value: Color) -> Array:
	return [value.r, value.g, value.b, value.a]

static func palette_color(stops: Array, t: float) -> Color:
	var f = clampf(t, 0.0, 1.0) * (stops.size() - 1)
	var i = int(f)
	return color(stops[i]).lerp(color(stops[mini(i + 1, stops.size() - 1)]), f - i)

static func validate(doc: Dictionary) -> String:
	if not integer_number(doc.get("schema_version")) or int(doc.schema_version) != 4:
		return "Map requires schema_version 4"
	if not doc.get("world_id") is String or doc.world_id.is_empty():
		return "Map requires a permanent world_id"
	for section in ["geometry", "rendering", "environment", "generation", "biomes", "objects", "ground_clutter", "files", "simulation", "shader_parameters", "lighting_palette", "weather_palette"]:
		if not doc.get(section) is Dictionary:
			return "Missing map section: " + section
	for group in ["light_bar", "weather_system", "player", "particle_emitter"]:
		if not doc.simulation.get(group) is Dictionary:
			return "Missing simulation." + group
	for key in ["spine", "daylight", "dawn", "morning", "noon", "dusk", "night", "sunset_amber", "sunset_gold", "sunset_crimson", "sunset_twilight", "moon_night", "moon_day"]:
		if not valid_color(doc.lighting_palette.get(key)):
			return "Missing lighting_palette." + key
	for key in ["rain_sheet", "snow_sheet", "dust", "snow_dust", "rain_particles", "snow_particles"]:
		if not valid_color(doc.weather_palette.get(key)):
			return "Missing weather_palette." + key
	var g: Dictionary = doc.geometry
	for key in ["cylinder_radius_m", "cylinder_length_m", "elevation_variance_m", "water_sea_level_m"]:
		if not g.has(key) or not finite_number(g[key]):
			return "Missing/invalid geometry." + key
	if g.cylinder_radius_m <= g.elevation_variance_m or g.elevation_variance_m <= 0 or g.cylinder_length_m <= 0:
		return "Radius must exceed positive elevation range; length must be positive"
	if g.water_sea_level_m < 0 or g.water_sea_level_m > g.elevation_variance_m:
		return "Sea level must be inside the elevation range"
	var gen: Dictionary = doc.generation
	var dims = get_grid_dimensions(doc)
	if not gen.has("sample_pitch_m") and not gen.has("elevation_width"):
		gen["sample_pitch_m"] = 4.0
		dims = get_grid_dimensions(doc)
	if gen.has("sample_pitch_m"):
		if not finite_number(gen.sample_pitch_m) or gen.sample_pitch_m <= 0.01 or gen.sample_pitch_m > 1000.0:
			return "sample_pitch_m must be between 0.01 and 1000.0 meters"
		gen["elevation_width"] = dims.elevation_width
		gen["elevation_height"] = dims.elevation_height
		gen["terrain_width"] = dims.terrain_width
		gen["terrain_height"] = dims.terrain_height

	for key in ["seed", "elevation_width", "elevation_height", "terrain_width", "terrain_height", "noise_wavelength_m", "detail_wavelength_m", "climate_wavelength_m", "base_height_m", "relief_m", "ridge_height_m", "erosion_iterations", "talus_slope_deg", "sea_center_v", "sea_width_m", "sea_depth_m", "coast_wavelength_m", "coast_variation_m", "lake_count", "lake_radius_m", "lake_depth_m", "river_count", "river_width_m", "river_depth_m", "spawn_clearance_m", "object_limit", "noise_octaves", "noise_gain", "detail_strength", "biome_region_wavelength_m", "biome_region_strength", "balance_iterations"]:
		if not gen.has(key) or not finite_number(gen[key]):
			return "Missing/invalid generation." + key
	for key in ["elevation_width", "elevation_height", "terrain_width", "terrain_height"]:
		if not integer_number(gen[key]) or gen[key] < 2 or gen[key] > 32768:
			return key + " must be an integer in 2..32768"
	for key in ["seed", "erosion_iterations", "object_limit", "noise_octaves", "balance_iterations"]:
		if not integer_number(gen[key]):
			return key + " must be an integer"
	if gen.elevation_width * gen.elevation_height > 536870912 or gen.terrain_width * gen.terrain_height > 536870912:
		return "Each layer is limited to 536,870,912 samples"
	for key in ["noise_wavelength_m", "detail_wavelength_m", "climate_wavelength_m", "coast_wavelength_m", "lake_radius_m", "river_width_m", "biome_region_wavelength_m"]:
		if gen[key] <= 0:
			return key + " must be positive"
	if gen.erosion_iterations < 0 or gen.erosion_iterations > 64 or gen.object_limit < 0 or gen.object_limit > 50000:
		return "Erosion iterations must be 0..64 and object limit 0..50000"
	var env: Dictionary = doc.environment
	for key in ["sky_color", "ambient_color", "air_color"]:
		if not valid_color(env.get(key)):
			return "Invalid environment." + key
	for key in ["ambient_energy", "air_density", "air_distance_min", "air_distance_max"]:
		if not finite_number(env.get(key)):
			return "Missing environment." + key
	if not env.get("water") is Dictionary:
		return "Missing environment.water"
	for key in ["shallow_color", "deep_color", "reflection_color", "foam_color", "caustic_color", "overcast_color"]:
		if not valid_color(env.water.get(key)):
			return "Invalid water." + key
	if not env.water.get("extinction_rgb") is Array or env.water.extinction_rgb.size() != 3:
		return "Water extinction_rgb requires three absorption coefficients"
	for coefficient in env.water.extinction_rgb:
		if not finite_number(coefficient) or coefficient < 0:
			return "Invalid water absorption coefficient"
	for palette in [doc.lighting_palette, doc.weather_palette]:
		for value in palette.values():
			if not valid_color(value):
				return "Lighting/weather palette entries must be RGBA"
	for key in ["wave_speed", "roughness", "specular"]:
		if not finite_number(env.water.get(key)):
			return "Missing water." + key
	for key in ["radial_segments", "length_segments", "end_cap_rings", "end_cap_dish_depth_m", "biome_texture_resolution", "biome_blend_width_m"]:
		if not finite_number(doc.rendering.get(key)) or doc.rendering[key] <= 0:
			return "Invalid rendering." + key
	for key in ["radial_segments", "length_segments", "end_cap_rings", "biome_texture_resolution"]:
		if not integer_number(doc.rendering[key]):
			return "rendering.%s must be an integer" % key
	if gen.balance_iterations < 1 or gen.balance_iterations > 64 or gen.biome_region_strength <= 0:
		return "Balance iterations must be 1..64; biome region strength must be positive"
	if gen.noise_octaves < 1 or gen.noise_octaves > 10 or gen.noise_gain < 0 or gen.noise_gain > 1 or gen.detail_strength < 0 or gen.detail_strength > 1:
		return "Noise octaves must be 1..10; gain and detail strength 0..1"
	var enabled_biome_count = 0
	for biome in doc.biomes.values():
		if biome is Dictionary and finite_number(biome.get("weight")) and biome.weight > 0:
			enabled_biome_count += 1
	if gen.terrain_width * gen.terrain_height * doc.biomes.size() > 2147483648:
		return "Biome resolution × biome count exceeds generation memory budget (2,147,483,648)"
	if doc.biomes.is_empty() or doc.biomes.size() > 256:
		return "Define 1..256 biomes"
	if not doc.objects.get("model_catalog") is Dictionary or not doc.ground_clutter.get("models") is Dictionary:
		return "Missing object or clutter catalog"
	var ids: Dictionary = {}
	var weight = 0.0
	for key in doc.biomes:
		var b = doc.biomes[key]
		if not b is Dictionary:
			return "Invalid biome " + key
		for field in ["raster_id", "name", "weight", "elevation_range_m", "max_slope_deg", "moisture", "temperature", "submerged", "blended", "texture", "texture_size_m", "roughness", "tint", "clutter", "objects"]:
			if not b.has(field):
				return "Missing biome %s.%s" % [key, field]
		if not integer_number(b.raster_id) or b.raster_id < 0 or b.raster_id > 255 or ids.has(int(b.raster_id)):
			return "Biome raster IDs must be unique in 0..255"
		ids[int(b.raster_id)] = true
		for numeric in ["weight", "texture_size_m", "roughness", "max_slope_deg", "moisture", "temperature"]:
			if not finite_number(b[numeric]):
				return "Invalid biome number: %s.%s" % [key, numeric]
		if not valid_color(b.tint) or b.texture_size_m <= 0 or b.weight < 0:
			return "Invalid tint, texture size or weight: " + key
		if not valid_range(b.elevation_range_m, 0, g.elevation_variance_m):
			return "Invalid elevation range: " + key
		if b.max_slope_deg < 0 or b.max_slope_deg > 90 or b.roughness < 0 or b.roughness > 1 or b.moisture < 0 or b.moisture > 1 or b.temperature < 0 or b.temperature > 1:
			return "Biome slope/roughness/climate preference out of range: " + key
		if not b.submerged is bool or not b.blended is bool or not b.clutter is Array or not b.objects is Array or not b.name is String or not b.texture is String:
			return "Invalid biome fields: " + key
		if not valid_range(b.elevation_range_m, 0, g.elevation_variance_m):
			return "Biome elevation range exceeds geometry: " + key
		if b.weight > 0 and ((b.submerged and b.elevation_range_m[0] >= g.water_sea_level_m) or (not b.submerged and b.elevation_range_m[1] <= g.water_sea_level_m)):
			return "Biome elevation range conflicts with sea level: " + key
		weight += b.weight
		for rule in b.clutter:
			if not rule is Dictionary or not valid_range(rule.get("scale_range"), 0.001, 100) or not finite_number(rule.get("density_per_m2")) or rule.density_per_m2 < 0 or rule.density_per_m2 > 1:
				return "Invalid clutter scale/density: " + key
			if not doc.ground_clutter.models.has(rule.get("model")) or not rule.get("palette") is Array or rule.palette.is_empty():
				return "Invalid clutter rule: " + key
			for stop in rule.palette:
				if not valid_color(stop):
					return "Invalid clutter palette: " + key
		for rule in b.objects:
			if not rule is Dictionary or not valid_range(rule.get("scale_range"), 0.001, 100) or not finite_number(rule.get("density_per_sq_km")) or rule.density_per_sq_km < 0 or rule.density_per_sq_km > 10000:
				return "Invalid object scale/density: " + key
			if not doc.objects.model_catalog.has(rule.get("asset")):
				return "Unknown object asset in " + key
	if weight <= 0:
		return "Select at least one biome with positive weight"
	for key in ["elevation_map", "terrain_map", "object_map"]:
		if not doc.files.get(key) is String or not relative_path(doc.files[key]):
			return "files.%s must be a package-relative path" % key
	var r: Dictionary = doc.rendering
	if not valid_color(r.get("end_cap_tint")) or not r.get("end_cap_texture") is String or not r.get("include_end_caps") is bool:
		return "Missing end-cap rendering definition"
	if r.radial_segments < 16 or r.radial_segments > 256 or r.length_segments < 4 or r.length_segments > 360 or r.end_cap_rings < 8 or r.end_cap_rings > 64 or r.biome_texture_resolution < 16 or r.biome_texture_resolution > 512:
		return "Mesh segments: radial 16..256, axial 4..360, cap rings 8..64; biome texture resolution 16..512"
	for key in ["view_radius_m", "fade_distance_m", "chunk_size_m", "density_multiplier", "seed"]:
		if not finite_number(doc.ground_clutter.get(key)) or doc.ground_clutter[key] < 0:
			return "Invalid ground_clutter." + key
	if doc.ground_clutter.chunk_size_m < 5 or doc.ground_clutter.chunk_size_m > 100 or doc.ground_clutter.view_radius_m > 1000:
		return "Clutter chunk size must be 5..100m; view radius at most 1000m"
	for id in doc.objects.model_catalog:
		var entry = doc.objects.model_catalog[id]
		if not entry is Dictionary:
			return "Invalid object definition " + id
		for key in ["name", "scene_path", "behavior_type", "variant", "tint", "light_color", "light_energy", "light_range_m", "flicker"]:
			if not entry.has(key):
				return "Missing object %s.%s" % [id, key]
		if not integer_number(entry.behavior_type) or entry.behavior_type < 0 or entry.behavior_type > 8:
			return "Unknown object behavior: " + id
		if not integer_number(entry.variant):
			return "Object variant must be an integer: " + id
		if not valid_color(entry.tint) or not valid_color(entry.light_color):
			return "Invalid object RGBA: " + id
		if not finite_number(entry.light_energy) or entry.light_energy < 0 or not finite_number(entry.light_range_m) or entry.light_range_m < 0:
			return "Invalid light energy/range: " + id
	for key in ["lake_count", "river_count"]:
		if gen[key] < 0 or gen[key] > 32 or gen[key] != int(gen[key]):
			return key + " must be an integer in 0..32"
	if gen.talus_slope_deg < 0 or gen.talus_slope_deg >= 90 or gen.sea_center_v < 0 or gen.sea_center_v > 1:
		return "Invalid talus slope or sea centre"
	return ""

static func finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func integer_number(value: Variant) -> bool:
	return finite_number(value) and float(value) == floorf(float(value))

static func valid_color(value: Variant) -> bool:
	if not value is Array or value.size() != 4:
		return false
	for n in value:
		if not finite_number(n) or n < 0 or n > 1:
			return false
	return true

static func write_json(path: String, data: Dictionary) -> Error:
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(path + ".tmp", path)

static func save_document(doc: Dictionary, directory: String) -> Error:
	last_error = validate(doc)
	if not last_error.is_empty():
		return ERR_INVALID_DATA
	var authored = doc.duplicate(true)
	authored.erase("map_directory")
	authored["saved_at_unix"] = Time.get_unix_time_from_system()
	return write_json(directory.path_join("map_config.json"), authored)

static func publish_map(directory: String) -> Error:
	var marker = FileAccess.open(directory.path_join(".map_ready"), FileAccess.WRITE)
	if not marker:
		return copy_failure("publish map", directory, FileAccess.get_open_error())
	marker.store_string("ready")
	marker.close()
	return OK

static func activate(directory: String) -> Error:
	var error = publish_map(directory)
	if error != OK:
		return error
	var file = FileAccess.open(active_map_file + ".tmp", FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(directory)
	file.close()
	var result = DirAccess.rename_absolute(active_map_file + ".tmp", active_map_file)
	if result == OK:
		active_map_validated_directory = directory
		active_map_preloaded_terrain = null
		active_map_assets_validated_directory = ""
	return result

## FileAccess reads both exported resource packs and ordinary filesystem files.
static func copy_map_file(source: String, target: String) -> Error:
	var input = FileAccess.open(source, FileAccess.READ)
	if not input:
		return copy_failure("read", source, FileAccess.get_open_error())
	var error = DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if error != OK:
		return copy_failure("create directory", target.get_base_dir(), error)
	var output = FileAccess.open(target, FileAccess.WRITE)
	if not output:
		return copy_failure("write", target, FileAccess.get_open_error())
	var remaining = input.get_length()
	while remaining > 0:
		var size = mini(remaining, 1024 * 1024)
		var chunk = input.get_buffer(size)
		if chunk.size() != size:
			return copy_failure("read", source, ERR_FILE_CANT_READ)
		output.store_buffer(chunk)
		if output.get_error() != OK:
			return copy_failure("write", target, output.get_error())
		remaining -= size
	output.flush()
	error = output.get_error()
	output.close()
	if error != OK:
		return copy_failure("write", target, error)
	return OK

## Exported textures may only exist through Godot's import remap, not as PNG bytes.
static func copy_terrain_image(source: String, target: String) -> Error:
	var image: Image = MapAssetLoader.load_image(source)
	if image == null and source.begins_with("res://") and ResourceLoader.exists(source):
		var texture = ResourceLoader.load(source)
		if texture is Texture2D:
			image = texture.get_image()
			if image and not image.is_empty() and image.get_format() != Image.FORMAT_L8:
				var l8_img = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_L8)
				for y in image.get_height():
					for x in image.get_width():
						var col = image.get_pixel(x, y)
						l8_img.set_pixel(x, y, Color(col.r, col.r, col.r, 1.0))
				image = l8_img
	if image == null or image.is_empty():
		return copy_failure("load biome image", source, ERR_FILE_CANT_READ)
	var error = DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if error != OK:
		return copy_failure("create directory", target.get_base_dir(), error)
	error = image.save_png(target)
	if error != OK:
		return copy_failure("save biome image", target, error)
	return OK

static func copy_failure(operation: String, path: String, error: Error) -> Error:
	last_error = "Cannot %s %s: %s" % [operation, path, error_string(error)]
	return error

static func copy_tree(source: String, target: String) -> Error:
	var error = DirAccess.make_dir_recursive_absolute(target)
	if error != OK:
		return copy_failure("create directory", target, error)
	var dir = DirAccess.open(source)
	if not dir:
		return copy_failure("open directory", source, ERR_CANT_OPEN)
	for name in dir.get_files():
		if name.ends_with(".import"):
			continue
		error = copy_map_file(source.path_join(name), target.path_join(name))
		if error != OK:
			return error
	for name in dir.get_directories():
		error = copy_tree(source.path_join(name), target.path_join(name))
		if error != OK:
			return error
	return OK

static func list_available_maps() -> Array[String]:
	var newest = {}
	var dir = DirAccess.open(user_maps_directory)
	if dir:
		for name in dir.get_directories():
			var path = user_maps_directory.path_join(name)
			if not FileAccess.file_exists(path.path_join(".map_ready")) or not FileAccess.file_exists(path.path_join("map_config.json")):
				continue
			var doc = load_map_config(path)
			if doc.is_empty():
				continue
			var id: String = doc.world_id
			if not newest.has(id) or doc.get("saved_at_unix", 0) > newest[id].get("saved_at_unix", 0):
				newest[id] = doc
	var result: Array[String] = []
	for doc in newest.values():
		result.append(doc.map_directory)
	result.sort()
	return result

## Accessors for map properties
static func get_elevation_map_path(config: Dictionary) -> String:
	return resolve_map_asset_path(config, config.files.elevation_map)

static func get_terrain_map_path(config: Dictionary) -> String:
	return resolve_map_asset_path(config, config.files.terrain_map)

static func get_object_map_path(config: Dictionary) -> String:
	return resolve_map_asset_path(config, config.files.object_map)

## Resolve a package-relative asset path while preserving explicit resource paths.
static func resolve_map_asset_path(config: Dictionary, asset_path: String) -> String:
	var path = asset_path.strip_edges()
	if path.is_empty() or path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path
	return str(config.get("map_directory", DEFAULT_MAP_DIRECTORY)).path_join(path)

static func get_object_model_path(config: Dictionary, object_type: int, tree_variant: int = -1) -> String:
	for entry in config.objects.model_catalog.values():
		if int(entry.behavior_type) == object_type and int(entry.variant) == tree_variant:
			return resolve_map_asset_path(config, entry.scene_path)
	return ""

static func get_clutter_model_path(config: Dictionary, model_id: String) -> String:
	var clutter: Dictionary = config.get("ground_clutter", {}) as Dictionary
	var models: Dictionary = clutter.get("models", {}) as Dictionary
	var model: Dictionary = models.get(model_id, {}) as Dictionary
	return resolve_map_asset_path(config, str(model.get("scene_path", "")))

static func get_clutter_config(config: Dictionary) -> Dictionary:
	return config.get("ground_clutter", {}) as Dictionary

static func get_object_catalog(config: Dictionary) -> Dictionary:
	return config.get("objects", {}).get("model_catalog", {}) as Dictionary

static func get_settlements(config: Dictionary) -> Array:
	return config.get("objects", {}).get("settlements", []) as Array

static func get_spawn_points(config: Dictionary) -> Array:
	return config.get("objects", {}).get("spawn_points", []) as Array

static func get_entities_config(config: Dictionary) -> Dictionary:
	return config.get("entities", {}) as Dictionary

static func get_events_config(config: Dictionary) -> Dictionary:
	return config.get("events", {}) as Dictionary

static func get_relationships_config(config: Dictionary) -> Dictionary:
	return config.get("relationships", {}) as Dictionary


static func copy_directory(source: String, target: String, copy_layers: bool = true) -> Error:
	var doc = load_map_config(source)
	if doc.is_empty():
		return ERR_INVALID_DATA
	var error = DirAccess.make_dir_recursive_absolute(target)
	if error != OK:
		return copy_failure("create directory", target, error)
	for file in doc.files.values() if copy_layers else []:
		var path = str(file)
		if path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://") or ".." in path.split("/"):
			return copy_failure("copy invalid map path", path, ERR_INVALID_DATA)
		if path == doc.files.terrain_map:
			error = copy_terrain_image(source.path_join(path), target.path_join(path))
		else:
			error = copy_map_file(source.path_join(path), target.path_join(path))
		if error != OK:
			return error
	if DirAccess.dir_exists_absolute(source.path_join("assets")):
		error = copy_tree(source.path_join("assets"), target.path_join("assets"))
		if error != OK:
			return error
	error = save_document(doc, target)
	if error != OK and last_error.is_empty():
		return copy_failure("save definition", target, error)
	return error

static func valid_range(value: Variant, low: float, high: float) -> bool:
	return value is Array and value.size() == 2 and finite_number(value[0]) and finite_number(value[1]) and value[0] >= low and value[0] <= value[1] and value[1] <= high

static func relative_path(value: String) -> bool:
	return not value.is_empty() and not value.is_absolute_path() and not value.contains(":") and not value.contains("\\") and not ".." in value.split("/")

static func validate_assets(doc: Dictionary) -> String:
	var paths: Array = [doc.rendering.end_cap_texture]
	for b in doc.biomes.values():
		paths.append(b.texture)
	for catalog in [doc.objects.model_catalog, doc.ground_clutter.models]:
		for entry in catalog.values():
			if not entry.get("scene_path") is String:
				return "Missing catalog scene_path"
			paths.append(entry.scene_path)
	for path in paths:
		if not str(path).begins_with("res://") and not relative_path(path):
			return "Asset must be package-relative or a bundled resource: " + str(path)
		var full = resolve_map_asset_path(doc, path)
		if not FileAccess.file_exists(full) and not ResourceLoader.exists(full):
			return "Missing asset: " + str(path)
	for b in doc.biomes.values():
		var image = preload("res://scripts/map_asset_loader.gd").load_image(resolve_map_asset_path(doc, b.texture))
		if image == null:
			return "Invalid biome texture (each side <= 8192 px; <= 16,777,216 pixels): " + str(b.texture)
	var placements_path = get_object_map_path(doc)
	var placements: Variant = JSON.parse_string(FileAccess.get_file_as_string(placements_path))
	if not placements is Dictionary or not placements.get("objects") is Array:
		return "Invalid object placement document: " + placements_path
	var placement_ids: Dictionary = {}
	for record in placements.objects:
		if not record is Dictionary or not doc.objects.model_catalog.has(record.get("asset")):
			return "Placement refers to an undefined asset"
		if not record.get("id") is String or record.id.is_empty() or placement_ids.has(record.id):
			return "Placement IDs must be unique non-empty strings"
		placement_ids[record.id] = true
		if record.has("light_range"):
			return "Placement uses obsolete light_range; use light_range_m: " + record.id
		if record.has("transform"):
			if not record.transform is Array or record.transform.size() != 12:
				return "Placement transform must contain 12 numbers"
			for n in record.transform:
				if not finite_number(n):
					return "Invalid placement transform"
		elif not finite_number(record.get("theta")) or not finite_number(record.get("z")):
			return "Placement requires finite theta/z coordinates or a transform"
		for key in ["tint", "light_color"]:
			if record.has(key) and not valid_color(record[key]):
				return "Invalid placement " + key
		for key in ["scale", "light_energy", "light_range_m", "yaw_rad"]:
			if record.has(key) and not finite_number(record[key]):
				return "Invalid placement " + key
		if record.has("scale") and record.scale <= 0:
			return "Placement scale must be positive"
	var spawn_points: Variant = placements.get("spawn_points", [])
	if not spawn_points is Array:
		return "Spawn points must be an array"
	for spawn in spawn_points:
		if not spawn is Dictionary or not finite_number(spawn.get("theta")) or not finite_number(spawn.get("z")):
			return "Each spawn point requires finite theta/z coordinates"
	return ""

static func get_grid_dimensions(doc: Dictionary) -> Dictionary:
	var g: Dictionary = doc.get("geometry", {})
	var gen: Dictionary = doc.get("generation", {})
	var r_m = float(g.get("cylinder_radius_m", 4000.0))
	var l_m = float(g.get("cylinder_length_m", 18000.0))
	
	if gen.has("elevation_width") and gen.has("elevation_height"):
		var ew = int(gen.elevation_width)
		var eh = int(gen.elevation_height)
		var tw = int(gen.get("terrain_width", ew))
		var th = int(gen.get("terrain_height", eh))
		var calc_pitch = (2.0 * PI * r_m) / float(ew) if ew > 0 else 4.0
		if gen.has("sample_pitch_m"):
			var user_pitch = float(gen.sample_pitch_m)
			if user_pitch > 0 and absf(user_pitch - calc_pitch) > 0.05:
				ew = max(16, int(round((2.0 * PI * r_m) / user_pitch)))
				eh = max(16, int(round(l_m / user_pitch)))
				return {
					"elevation_width": ew,
					"elevation_height": eh,
					"terrain_width": ew,
					"terrain_height": eh,
					"sample_pitch_m": user_pitch
				}
		return {
			"elevation_width": ew,
			"elevation_height": eh,
			"terrain_width": tw,
			"terrain_height": th,
			"sample_pitch_m": calc_pitch
		}

	var pitch = float(gen.get("sample_pitch_m", 4.0))
	if pitch <= 0.0:
		pitch = 4.0
	var ew = max(16, int(round((2.0 * PI * r_m) / pitch)))
	var eh = max(16, int(round(l_m / pitch)))
	return {
		"elevation_width": ew,
		"elevation_height": eh,
		"terrain_width": ew,
		"terrain_height": eh,
		"sample_pitch_m": pitch
	}

