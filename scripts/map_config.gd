class_name MapConfig
extends RefCounted

## Utility class for loading, validating, and managing modular O'Neill Cylinder map packages.
## Each map package lives in assets/maps/<mapname>/ and contains map_config.json,
## elevation_map.png, terrain_map.png, object_map.json, and biomes_manifest.json.
##
## It also specifies ground clutter models/densities, surface object catalogs & placements,
## and extensible hooks for entities, scripted events, and colony relationships/factions.

const DEFAULT_MAP_DIRECTORY: String = "res://assets/maps/default"
const MAP_ROOT_DIR: String = "res://assets/maps"

## Resolve map identifier/path into the canonical directory path
static func resolve_map_dir(map_name_or_path: String) -> String:
	var path = map_name_or_path.strip_edges()
	if path.is_empty():
		return DEFAULT_MAP_DIRECTORY

	if path.ends_with("/map_config.json") or path.ends_with("/cylinder_config.json"):
		return path.get_base_dir()

	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path.trim_suffix("/")

	# Relative map name like "default" or "mars_colony"
	return MAP_ROOT_DIR.path_join(path)

## Load and parse map_config.json for a given map package
static func load_map_config(map_name_or_path: String = "default") -> Dictionary:
	var map_dir = resolve_map_dir(map_name_or_path)
	var config_file = map_dir.path_join("map_config.json")

	if not FileAccess.file_exists(config_file):
		# Also check alternate name cylinder_config.json
		var alt_config = map_dir.path_join("cylinder_config.json")
		if FileAccess.file_exists(alt_config):
			config_file = alt_config

	var config: Dictionary = {}
	if FileAccess.file_exists(config_file):
		var f = FileAccess.open(config_file, FileAccess.READ)
		if f:
			var json = JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				config = json.data
			f.close()

	# Build normalized dictionary with defaults for any missing keys
	var map_id = map_dir.get_file()
	if map_id.is_empty():
		map_id = "default"

	var norm_config: Dictionary = {
		"map_name": config.get("map_name", map_id),
		"display_name": config.get("display_name", map_id.capitalize()),
		"version": config.get("version", "1.0.0"),
		"description": config.get("description", "O'Neill Cylinder Map Package"),
		"author": config.get("author", "Unknown"),
		"map_directory": map_dir,
		"geometry": {
			"cylinder_radius_m": 4000.0,
			"cylinder_length_m": 18000.0,
			"endcap_radius_m": 4000.0,
			"elevation_variance_m": 100.0,
			"water_sea_level_m": 20.0
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
		"climate_and_atmosphere": {
			"spin_direction": 1,
			"rotation_period_sec": 127.0,
			"base_gravity_m_s2": 9.5,
			"air_density": 1.225,
			"temperature_min_c": -10.0,
			"temperature_max_c": 38.0,
			"cloud_altitude_m": 1250.0,
			"cloud_thickness_m": 250.0,
			"cloud_coverage": 0.55
		},
		"terrain_textures": {},
		"ground_clutter": {
			"view_radius_m": 220.0,
			"chunk_size_m": 40.0,
			"density_multiplier": 1.0,
			"grassland_density_multiplier": 1.0,
			"farmland_density_multiplier": 1.0,
			"models": {},
			"biomes": {}
		},
		"objects": {
			"model_catalog": {},
			"settlements": [],
			"spawn_points": [],
			"placed_objects_count": 0,
			"placed_objects_source": "object_map.json"
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
			"elevation_map": map_dir.path_join("elevation_map.png"),
			"terrain_map": map_dir.path_join("terrain_map.png"),
			"object_map": map_dir.path_join("object_map.json"),
			"object_map_image": map_dir.path_join("object_map.png"),
			"biomes_manifest": map_dir.path_join("biomes_manifest.json")
		}
	}
	if config.get("terrain_textures", {}) is Dictionary:
		norm_config["terrain_textures"] = config.get("terrain_textures", {})

	# Merge geometry from file if present
	if config.has("geometry") and config["geometry"] is Dictionary:
		var g = config["geometry"] as Dictionary
		norm_config["geometry"]["cylinder_radius_m"] = float(g.get("cylinder_radius_m", g.get("radius_m", 4000.0)))
		norm_config["geometry"]["cylinder_length_m"] = float(g.get("cylinder_length_m", g.get("length_m", 18000.0)))
		norm_config["geometry"]["endcap_radius_m"] = float(g.get("endcap_radius_m", norm_config["geometry"]["cylinder_radius_m"]))
		norm_config["geometry"]["elevation_variance_m"] = float(g.get("elevation_variance_m", g.get("max_elevation_m", 100.0)))
		norm_config["geometry"]["water_sea_level_m"] = float(g.get("water_sea_level_m", g.get("water_level_m", 20.0)))

	# Merge celestial parameters if present
	if config.has("celestial") and config["celestial"] is Dictionary:
		var c = config["celestial"] as Dictionary
		for k in c:
			norm_config["celestial"][k] = c[k]

	# Merge climate parameters if present
	if config.has("climate_and_atmosphere") and config["climate_and_atmosphere"] is Dictionary:
		var ca = config["climate_and_atmosphere"] as Dictionary
		for k in ca:
			norm_config["climate_and_atmosphere"][k] = ca[k]

	# Merge ground clutter if present
	if config.has("ground_clutter") and config["ground_clutter"] is Dictionary:
		var gc = config["ground_clutter"] as Dictionary
		norm_config["ground_clutter"]["view_radius_m"] = float(gc.get("view_radius_m", 220.0))
		norm_config["ground_clutter"]["chunk_size_m"] = float(gc.get("chunk_size_m", 40.0))
		norm_config["ground_clutter"]["density_multiplier"] = float(gc.get("density_multiplier", 1.0))
		norm_config["ground_clutter"]["grassland_density_multiplier"] = float(gc.get("grassland_density_multiplier", 1.0))
		norm_config["ground_clutter"]["farmland_density_multiplier"] = float(gc.get("farmland_density_multiplier", 1.0))
		if gc.has("models") and gc["models"] is Dictionary:
			norm_config["ground_clutter"]["models"] = gc["models"]
		if gc.has("biomes") and gc["biomes"] is Dictionary:
			norm_config["ground_clutter"]["biomes"] = gc["biomes"]

	# Merge objects if present
	if config.has("objects") and config["objects"] is Dictionary:
		var obj = config["objects"] as Dictionary
		for k in obj:
			norm_config["objects"][k] = obj[k]

	# Merge entities if present
	if config.has("entities") and config["entities"] is Dictionary:
		var ent = config["entities"] as Dictionary
		for k in ent:
			norm_config["entities"][k] = ent[k]

	# Merge events if present
	if config.has("events") and config["events"] is Dictionary:
		var ev = config["events"] as Dictionary
		for k in ev:
			norm_config["events"][k] = ev[k]

	# Merge relationships if present
	if config.has("relationships") and config["relationships"] is Dictionary:
		var rel = config["relationships"] as Dictionary
		for k in rel:
			norm_config["relationships"][k] = rel[k]

	# Merge specific filenames if provided
	if config.has("files") and config["files"] is Dictionary:
		var fl = config["files"] as Dictionary
		for key in fl:
			var fname = str(fl[key])
			if fname.begins_with("res://") or fname.begins_with("user://") or fname.begins_with("/"):
				norm_config["files"][key] = fname
			else:
				norm_config["files"][key] = map_dir.path_join(fname)

	return norm_config

## Accessors for map properties
static func get_elevation_map_path(config: Dictionary) -> String:
	return str(config.get("files", {}).get("elevation_map", DEFAULT_MAP_DIRECTORY.path_join("elevation_map.png")))

static func get_terrain_map_path(config: Dictionary) -> String:
	return str(config.get("files", {}).get("terrain_map", DEFAULT_MAP_DIRECTORY.path_join("terrain_map.png")))

static func get_object_map_path(config: Dictionary) -> String:
	return str(config.get("files", {}).get("object_map", DEFAULT_MAP_DIRECTORY.path_join("object_map.json")))

static func get_biomes_manifest_path(config: Dictionary) -> String:
	return str(config.get("files", {}).get("biomes_manifest", DEFAULT_MAP_DIRECTORY.path_join("biomes_manifest.json")))

## Resolve a package-relative asset path while preserving explicit resource paths.
static func resolve_map_asset_path(config: Dictionary, asset_path: String) -> String:
	var path = asset_path.strip_edges()
	if path.is_empty() or path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path
	return str(config.get("map_directory", DEFAULT_MAP_DIRECTORY)).path_join(path)

static func get_object_model_path(config: Dictionary, object_type: int, tree_variant: int = -1) -> String:
	var objects: Dictionary = config.get("objects", {}) as Dictionary
	var catalog: Dictionary = objects.get("model_catalog", {}) as Dictionary
	var entry: Dictionary = {}
	if object_type == 6 and tree_variant >= 0:
		var variants: Dictionary = catalog.get("tree_variants", {}) as Dictionary
		entry = variants.get(str(tree_variant), {}) as Dictionary
	if entry.is_empty():
		entry = catalog.get(str(object_type), {}) as Dictionary
	return resolve_map_asset_path(config, str(entry.get("scene_path", "")))

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

## List all available map package directories under assets/maps/
static func list_available_maps() -> Array[String]:
	var results: Array[String] = []
	var dir = DirAccess.open(MAP_ROOT_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir() and not file_name.begins_with("."):
				results.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	if results.is_empty():
		results.append("default")
	return results
