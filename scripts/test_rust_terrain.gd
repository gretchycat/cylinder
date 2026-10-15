extends SceneTree

const Config = preload("res://scripts/map_config.gd")
const Terrain = preload("res://scripts/terrain_manager.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ClassDB.class_exists("RustTerrainData"):
		print("RUST TERRAIN SKIP: no GDExtension library matches this Godot platform")
		quit(0)
		return
	var doc: Dictionary = Config.load_map_config("default")
	if doc.is_empty():
		printerr("Rust terrain test could not load the default map: ", Config.last_error)
		quit(1)
		return
	var terrain: TerrainManager = Terrain.new()
	terrain.configure(doc)
	if not terrain.load_layers(Config.get_elevation_map_path(doc), Config.get_terrain_map_path(doc)):
		printerr("Rust terrain backend could not load map layers: ", terrain.last_error)
		quit(1)
		return
	if terrain.elevation_grid_u < 2 or terrain.elevation_grid_v < 2:
		printerr("Rust terrain backend returned invalid elevation dimensions")
		quit(1)
		return
	if terrain.terrain_grid_u < 2 or terrain.terrain_grid_v < 2:
		printerr("Rust terrain backend returned invalid biome dimensions")
		quit(1)
		return
	var sample: float = terrain.get_elevation(0.25 * TAU, 0.0, float(doc.geometry.cylinder_length_m))
	var biome_id: int = terrain.get_biome_id(0.25 * TAU, 0.0, float(doc.geometry.cylinder_length_m))
	if not is_finite(sample) or sample < 0.0 or sample > float(doc.geometry.elevation_variance_m):
		printerr("Rust elevation query returned an out-of-range sample: ", sample)
		quit(1)
		return
	if not terrain.biome_by_id.has(biome_id):
		printerr("Rust biome query returned an unknown ID: ", biome_id)
		quit(1)
		return
	print("RUST TERRAIN PASS: loaded CYLH/biome layers and sampled Rust-owned data")
	quit(0)
