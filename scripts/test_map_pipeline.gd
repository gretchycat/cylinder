extends SceneTree
const Config = preload("res://scripts/map_config.gd")
const Generator = preload("res://scripts/map_generator.gd")
const Terrain = preload("res://scripts/terrain_manager.gd")
const Assets = preload("res://scripts/map_asset_loader.gd")
const References = preload("res://scripts/reference_objects.gd")
const SurfaceObject = preload("res://scripts/surface_light_object.gd")
const ObjectFactory = preload("res://scripts/map_object_factory.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)

func write_bad_elevation(path: String, kind: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	match kind:
		"magic":
			file.store_buffer("NOPE".to_ascii_buffer())
			file.store_32(2)
			file.store_32(2)
		"dimensions":
			file.store_buffer("CYLH".to_ascii_buffer())
			file.store_32(1)
			file.store_32(2)
		"truncated":
			file.store_buffer("CYLH".to_ascii_buffer())
			file.store_32(2)
			file.store_32(2)
			for i in 3:
				file.store_float(0.5)
		"sample":
			file.store_buffer("CYLH".to_ascii_buffer())
			file.store_32(2)
			file.store_32(2)
			file.store_float(NAN)
			for i in 3:
				file.store_float(0.5)
	file.close()

func _watchdog(timeout_sec: float = 60.0) -> void:
	await create_timer(timeout_sec).timeout
	printerr("\n[WATCHDOG TIMEOUT] test_map_pipeline exceeded %.1f seconds! Terminating..." % timeout_sec)
	quit(1)

func _initialize():
	_watchdog(60.0)
	_run.call_deferred()

func check_surface_normals() -> void:
	var world: CylinderGenerator = CylinderGenerator.new()
	var terrain: TerrainManager = Terrain.new()
	world.terrain_manager = terrain
	world.radius = 4000.0
	world.cylinder_length = 400.0
	world.radial_segments = 256
	world.length_segments = 4
	terrain.elevation_grid_u = 256
	terrain.elevation_grid_v = 5
	terrain.elevation_data.resize(256 * 5)
	terrain.elevation_data.fill(30.0)
	terrain.elevation_data[1] = 31.0
	terrain.elevation_data[256] = 32.0
	for main_split: bool in [true, false]:
		# Opposite corners select the main or anti-diagonal respectively.
		terrain.elevation_data[257] = 30.0 if main_split else 34.0
		for uv: Vector2 in [Vector2(0.7, 0.2), Vector2(0.3, 0.8)]:
			var theta: float = uv.x * TAU / 256.0
			var point: Dictionary = world.get_surface_mesh_point_and_normal(theta, -200.0 + uv.y * 100.0)
			var radial_up: Vector3 = Vector3(-cos(theta), -sin(theta), 0.0)
			var normal: Vector3 = point.normal
			var slope_deg: float = rad_to_deg(acos(clampf(normal.dot(radial_up), -1.0, 1.0)))
			check(normal.is_normalized() and slope_deg < 5.0,
				"Gentle terrain faces inward and passes clutter slope filtering (main=%s, uv=%s, slope=%.2f)" % [main_split, uv, slope_deg])
	world.free()

func check_clutter_descriptors() -> void:
	var world: CylinderGenerator = CylinderGenerator.new()
	var terrain: TerrainManager = Terrain.new()
	world.terrain_manager = terrain
	world.radius = 4000.0
	world.cylinder_length = 400.0
	world.water_level = 20.0
	world.radial_segments = 256
	world.length_segments = 4
	terrain.elevation_grid_u = 256
	terrain.elevation_grid_v = 5
	terrain.elevation_data.resize(256 * 5)
	terrain.elevation_data.fill(30.0)
	terrain.terrain_grid_u = 256
	terrain.terrain_grid_v = 5
	terrain.terrain_data.resize(256 * 5)
	var clutter: ClutterManager = ClutterManager.new()
	clutter.cylinder_world = world
	clutter.chunk_size = 40.0
	var rule: Dictionary = {"model": "pebbles", "density_per_m2": 0.01,
		"scale_range": [1.0, 1.0], "palette": [[0.2, 0.4, 0.6, 1.0]]}
	var biome: Dictionary = {"raster_id": 31, "name": "River Road", "max_slope_deg": 45.0,
		"submerged": false, "clutter": [rule]}
	clutter.map_config = {"ground_clutter": {"seed": 123}, "biomes": {"custom": biome}}
	var part: Dictionary = {"mesh": BoxMesh.new(), "material": null, "transform": Transform3D.IDENTITY}
	clutter.parts = {"pebbles": [part], "grass_tuft": [part]}
	for raster_id: int in [0, 20, 30, 31, 32]:
		biome.raster_id = raster_id
		terrain.terrain_data.fill(raster_id)
		clutter._build_biome_registry()
		var data: Dictionary = clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length)
		check(data.total == 16, "Clutter uses descriptor density regardless of model/biome name or raster ID %d" % raster_id)
		if not data.batch_table.is_empty():
			check(data.batch_table[0].colors[0].is_equal_approx(Color(0.2, 0.4, 0.6)), "Clutter uses descriptor palette without name-based recoloring")
	biome.clutter = []
	check(clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length).total == 0,
		"Empty clutter descriptor never receives fallback grass")
	biome.clutter = [rule]
	rule.density_per_m2 = 0.0
	check(clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length).total == 0,
		"Zero descriptor density never receives fallback grass")
	rule.density_per_m2 = 0.01
	terrain.terrain_data.fill(20)
	check(clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length).total == 0,
		"Unregistered biome never inherits neighboring clutter rules")
	terrain.terrain_data.fill(32)
	terrain.elevation_data.fill(10.0)
	check(clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length).total == 0,
		"Dry-land biome clutter is rejected underwater")
	biome.submerged = true
	check(clutter._compute_chunk_data(314, 4, 629, world.radius, world.cylinder_length).total == 16,
		"Submerged descriptor can explicitly place underwater clutter")
	clutter.needed_chunks_cache = {Vector2i(1, 1): true, Vector2i(2, 2): true}
	clutter.active_chunks = {Vector2i(9, 9): null}
	clutter.pending_chunk_results = {Vector2i(1, 1): {}}
	check(clutter._has_missing_needed_chunks(), "Stale chunks cannot hide missing nearby clutter")
	clutter.active_chunks.clear()
	clutter.pending_chunk_results[Vector2i(2, 2)] = {}
	check(not clutter._has_missing_needed_chunks(), "Completed results cover their own required chunks")
	clutter.pending_chunk_results.clear()
	clutter.needed_chunks_cache.clear()
	var theta: float = (314.5 * clutter.chunk_size) / world.radius - PI
	var camera: Vector3 = Vector3(3990.0 * cos(theta), 3990.0 * sin(theta), 0.0)
	var near_priority: Dictionary = clutter._evaluate_chunk_priority(314, 4, 629, world.radius, world.cylinder_length, camera, Vector3.BACK)
	var far_priority: Dictionary = clutter._evaluate_chunk_priority(314, 8, 629, world.radius, world.cylinder_length, camera, Vector3.BACK)
	check(near_priority.score < far_priority.score, "Nearby clutter behind player loads before distant clutter ahead")
	clutter.free()
	world.free()

func _run():
	check_surface_normals()
	check_clutter_descriptors()
	var doc = Config.load_map_config("default")
	check(not doc.is_empty(), "Bundled map validates: " + Config.last_error)
	if doc.is_empty():
		quit(1)
		return
	var tm = Terrain.new()
	tm.configure(doc)
	check(tm.load_layers(Config.get_elevation_map_path(doc), Config.get_terrain_map_path(doc)), "Current map layers load")
	check(Terrain.read_elevation(Config.get_elevation_map_path(doc)) != null, "Static elevation image reader accepts CYLH")
	var old_elevation: PackedFloat32Array = tm.elevation_data.duplicate()
	var old_terrain: PackedByteArray = tm.terrain_data.duplicate()
	var malformed_dir := "user://maps/elevation_reader_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(malformed_dir)
	var malformed_paths := {
		"missing": malformed_dir.path_join("missing.cylh"),
		"magic": malformed_dir.path_join("magic.cylh"),
		"dimensions": malformed_dir.path_join("dimensions.cylh"),
		"truncated": malformed_dir.path_join("truncated.cylh"),
		"sample": malformed_dir.path_join("sample.cylh")
	}
	for kind in ["magic", "dimensions", "truncated", "sample"]:
		write_bad_elevation(malformed_paths[kind], kind)
	for kind in malformed_paths:
		check(Terrain.read_elevation(malformed_paths[kind]) == null and not Terrain.last_read_error.is_empty(), "Static elevation reader rejects " + kind + " data with a diagnostic")
	check(not tm.load_layers(malformed_paths.truncated, Config.get_terrain_map_path(doc)) and tm.elevation_data == old_elevation and tm.terrain_data == old_terrain, "Invalid layer load preserves previously loaded terrain and elevation")
	check(not tm.load_elevation(malformed_paths.sample) and tm.last_error.contains("normalized"), "Layer reader preserves the invalid-sample diagnostic")
	check(Assets.texture_dimensions_allowed(Vector2i(8192,2048)), "Ground texture limit accepts 16,777,216 pixels within side bounds")
	check(not Assets.texture_dimensions_allowed(Vector2i(4096,4097)) and not Assets.texture_dimensions_allowed(Vector2i(8193,1)), "Ground texture limit rejects excessive pixels or side length")
	var moved_record := {"id":"move-check", "asset":"campfire", "theta":0.2, "z":-3000.0, "transform":[1,0,0,0,1,0,0,0,1,1200,400,250]}
	var references = References.new()
	var moved_surface := references._record_surface_position(moved_record)
	check(is_equal_approx(moved_surface.x, atan2(400.0, 1200.0)) and is_equal_approx(moved_surface.y, 250.0), "Explicit placement transform takes precedence over stale surface coordinates")
	var moved_object = SurfaceObject.new()
	moved_object.transform = Transform3D(Basis.IDENTITY, Vector3(1200,400,250))
	references._capture_live_placement(moved_record, moved_object)
	check(not moved_record.has("theta") and not moved_record.has("z") and moved_record.transform[9] == 1200.0, "Saving an edited placement stores a local transform and removes redundant surface coordinates")
	moved_object.free()
	references.free()
	var texture_pixel_overflow := doc.duplicate(true)
	texture_pixel_overflow.schema_version = 4.5
	check(not Config.validate(texture_pixel_overflow).is_empty(), "Fractional schema version is rejected")
	var fractional_biome_id := doc.duplicate(true)
	fractional_biome_id.biomes.grassland.raster_id = 1.5
	check(not Config.validate(fractional_biome_id).is_empty(), "Fractional biome raster ID is rejected")
	var fractional_rendering := doc.duplicate(true)
	fractional_rendering.rendering.radial_segments = 32.5
	check(not Config.validate(fractional_rendering).is_empty(), "Fractional mesh segment count is rejected")
	check(Config.validate(doc).is_empty(), "Integral JSON floats in bundled schema remain valid")
	var invalid_blend_flag = doc.duplicate(true)
	invalid_blend_flag.biomes.values()[0].blended = 1
	check(not Config.validate(invalid_blend_flag).is_empty(), "Biome blend flag must be boolean")
	check(doc.rendering.biome_blend_width_m > 0, "Map descriptor provides terrain biome blend width")
	var bundled_placements: Variant = JSON.parse_string(FileAccess.get_file_as_string(Config.get_object_map_path(doc)))
	var bridge_override: Dictionary = {}
	for record in bundled_placements.objects:
		if record.get("name") == "River_Bridge_1":
			bridge_override = record
			break
	print("DEBUG bridge_override: ", bridge_override)
	check(bridge_override.is_empty() or (is_equal_approx(float(bridge_override.get("light_range_m", 0)), 38.0) and not bridge_override.has("light_range")), "Bundled bridge uses canonical instance light range")
	if not bridge_override.is_empty():
		var bridge_instance = ObjectFactory.create(doc, bridge_override)
		check(is_equal_approx(bridge_instance.light_range, 38.0), "Canonical per-instance light range is applied by the object factory")
		bridge_instance.free()
	doc.generation.elevation_width = 48
	doc.generation.elevation_height = 25
	doc.generation.terrain_width = 23
	doc.generation.terrain_height = 13
	doc.generation.erase("sample_pitch_m")
	doc.generation.erosion_iterations = 2
	doc.generation.object_limit = 100
	var a = await Generator.generate(doc)
	check(not a.has("error"), "Generation succeeds")
	if a.has("error"):
		print(a.error)
		quit(1)
		return
	var b = await Generator.generate(doc)
	check(a.elevation_image.get_data() == b.elevation_image.get_data() and a.terrain_image.get_data() == b.terrain_image.get_data(), "Seed reproduces layers")
	check(a.objects_data == b.objects_data, "Seed reproduces object placements and IDs")
	var max_area_error = 0.0
	for coverage in a.report.values():
		max_area_error = maxf(max_area_error, absf(coverage.achieved - coverage.requested))
	check(max_area_error < 0.08, "Requested mix remains represented at coarse resolution (max error %.3f)" % max_area_error)
	check(a.elevation_image.get_format() == Image.FORMAT_RF, "Elevation generated as float32")
	var directory = "user://maps/pipeline_test_%d" % Time.get_ticks_usec()
	check(Generator.save_generated_map_package(a, directory), "Generated package saves")
	Config.activate(directory)
	var reloaded = Config.load_map_config(directory)
	var layer = Terrain.new()
	layer.configure(reloaded)
	check(layer.load_layers(Config.get_elevation_map_path(reloaded), Config.get_terrain_map_path(reloaded)), "Generated package reloads")
	check(layer.elevation_grid_u == 48 and layer.elevation_grid_v == 25 and layer.terrain_grid_u == 23 and layer.terrain_grid_v == 13, "Independent non-square resolutions round-trip")
	check(layer.create_terrain_type_id_image().get_width() == 23, "GPU biome texture uses biome resolution")
	check(layer.create_elevation_image().get_data() == a.elevation_image.get_data(), "Float32 elevation round-trip is exact")
	for v in [0.0, 0.31, 1.0]:
		check(is_equal_approx(layer.get_elevation(0, (v-0.5)*doc.geometry.cylinder_length_m, doc.geometry.cylinder_length_m), layer.get_elevation(TAU, (v-0.5)*doc.geometry.cylinder_length_m, doc.geometry.cylinder_length_m)), "Circumference seam wraps at v=" + str(v))
	check(Config.palette_color([[1,0,0,0.2],[0,0,1,0.8]], 0.5).is_equal_approx(Color(0.5,0,0.5,0.5)), "Palette interpolates RGBA continuously")
	var invalid = doc.duplicate(true)
	invalid.geometry.cylinder_radius_m = 1
	check(not Config.validate(invalid).is_empty(), "Invalid geometry rejected")
	invalid = doc.duplicate(true)
	invalid.biomes.values()[1].raster_id = invalid.biomes.values()[0].raster_id
	check(not Config.validate(invalid).is_empty(), "Duplicate biome IDs rejected")
	# Proportion control must reshape terrain, not only recolor it.
	for biome in doc.biomes.values():
		biome.weight = 0
	doc.biomes.grassland.weight = 1
	var low = await Generator.generate(doc)
	doc.biomes.grassland.weight = 0
	doc.biomes.mountain.weight = 1
	var high = await Generator.generate(doc)
	check(not low.has("error") and not high.has("error"), "Single-biome selections generate")
	if not high.has("error") and not low.has("error"):
		var low_mean = 0.0
		var high_mean = 0.0
		for value in low.elevation_image.get_data().to_float32_array():
			low_mean += value
		for value in high.elevation_image.get_data().to_float32_array():
			high_mean += value
		check(high_mean > low_mean, "Mountain selection raises terrain versus grassland")
		check(high.report.mountain.achieved == 1, "Disabled biomes receive no area")
	var panel = preload("res://scripts/map_editor_panel.gd").new()
	root.add_child(panel)
	check(panel.document.biomes.size() == reloaded.biomes.size(), "Biome editor builds from map definitions")
	panel.free()
	print("MAP PIPELINE FAILURES: ", failures)
	quit(1 if failures else 0)
