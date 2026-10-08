@tool
extends SceneTree

const Config = preload("res://scripts/map_config.gd")
const MapGenerator = preload("res://scripts/map_generator.gd")

func _init() -> void:
	_run.call_deferred()

func _parse_cli_args() -> Dictionary:
	var raw_args = OS.get_cmdline_user_args()
	raw_args.append_array(OS.get_cmdline_args())
	var parsed = {}
	for arg in raw_args:
		var s = str(arg).strip_edges()
		while s.begins_with("-"):
			s = s.substr(1)
		if "=" in s:
			var parts = s.split("=", true, 1)
			parsed[parts[0].to_lower()] = parts[1]
	return parsed

func _run() -> void:
	print("==================================================")
	print("  Regenerating Default Habitat Map Package")
	print("==================================================")
	
	var cli = _parse_cli_args()
	var map_dir = cli.get("out", cli.get("map_dir", "res://assets/maps/default"))
	var doc = Config.load_map_config(map_dir)
	if doc.is_empty():
		printerr("ERROR: Failed to load map configuration at ", map_dir)
		if not Config.last_error.is_empty():
			printerr("Config error details: ", Config.last_error)
		quit(1)
		return

	# CLI Overrides if passed
	if cli.has("pitch") or cli.has("sample_pitch") or cli.has("sample_pitch_m"):
		var p_val = float(cli.get("pitch", cli.get("sample_pitch", cli.get("sample_pitch_m", 8.0))))
		if p_val > 0:
			doc.generation["sample_pitch_m"] = p_val
	if cli.has("seed"):
		doc.generation["seed"] = int(cli.seed)
	else:
		doc.generation["seed"] = (int(Time.get_ticks_usec()) ^ randi()) & 0x7fffffff
	if cli.has("radius") or cli.has("cylinder_radius_m"):
		doc.geometry["cylinder_radius_m"] = float(cli.get("radius", cli.get("cylinder_radius_m", 4000.0)))
	if cli.has("length") or cli.has("cylinder_length_m"):
		doc.geometry["cylinder_length_m"] = float(cli.get("length", cli.get("cylinder_length_m", 18000.0)))

	var dims = Config.get_grid_dimensions(doc)
	doc.generation["elevation_width"] = dims.elevation_width
	doc.generation["elevation_height"] = dims.elevation_height
	doc.generation["terrain_width"] = dims.terrain_width
	doc.generation["terrain_height"] = dims.terrain_height

	var g = doc.geometry
	var p = doc.generation
	print("Map Target:           %s" % doc.get("name", "Default Habitat"))
	print("Cylinder Dimensions:  Radius = %.1fm, Length = %.1fm" % [float(g.cylinder_radius_m), float(g.cylinder_length_m)])
	print("Sample Pitch:         %.2fm per pixel" % float(dims.sample_pitch_m))
	print("Calculated Grid:      %dx%d pixels" % [dims.elevation_width, dims.elevation_height])
	print("Seed:                 %d" % int(p.seed))
	print("--------------------------------------------------")
	
	var start_time = Time.get_ticks_msec()
	var last_progress_time = start_time
	
	var cb = func(fraction: float, message: String):
		var now = Time.get_ticks_msec()
		var step_dt = now - last_progress_time
		last_progress_time = now
		print("[%d%%] (%d ms) %s" % [int(fraction * 100.0), now - start_time, message])

	var result = await MapGenerator.generate(doc, cb)
	var elapsed = Time.get_ticks_msec() - start_time
	
	if result.has("error"):
		printerr("\nERROR during terrain generation: ", result.error)
		quit(1)
		return

	print("\nTerrain generation complete in %.2f seconds." % (elapsed / 1000.0))
	print("Saving generated layers to %s..." % map_dir)
	
	if not MapGenerator.save_generated_map_package(result, map_dir, cb):
		printerr("ERROR: Failed to save generated map package!")
		if not Config.last_error.is_empty():
			printerr("Save error details: ", Config.last_error)
		quit(1)
		return

	print("\nSUCCESS! Default map package regenerated and saved.")
	print("  - Elevation map: %s" % result.document.files.elevation_map)
	print("  - Terrain map:   %s" % result.document.files.terrain_map)
	print("  - Placements:    %s" % result.document.files.object_map)
	print("  - Total Objects: %d" % result.objects_data.objects.size())
	print("==================================================")
	quit(0)
