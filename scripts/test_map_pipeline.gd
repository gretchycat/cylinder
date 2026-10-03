extends SceneTree
const Config = preload("res://scripts/map_config.gd")
const Generator = preload("res://scripts/map_generator.gd")
const Terrain = preload("res://scripts/terrain_manager.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)

func _initialize():
	_run.call_deferred()

func _run():
	var doc = Config.load_map_config("default")
	check(not doc.is_empty(), "Bundled map validates: " + Config.last_error)
	if doc.is_empty():
		quit(1)
		return
	var tm = Terrain.new()
	tm.configure(doc)
	check(tm.load_layers(Config.get_elevation_map_path(doc), Config.get_terrain_map_path(doc)), "Current map layers load")
	doc.generation.elevation_width = 48
	doc.generation.elevation_height = 25
	doc.generation.terrain_width = 23
	doc.generation.terrain_height = 13
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
