extends SceneTree

const Config = preload("res://scripts/map_config.gd")
const Generator = preload("res://scripts/map_generator.gd")

func _initialize():
	_run.call_deferred()

func _run():
	var raw_args: PackedStringArray = OS.get_cmdline_user_args()
	var map_dir := ""
	var output_dir := ""
	var seed_override := -1
	var has_seed_override := false

	var positionals: Array[String] = []
	var skip_objects_flag := false
	var i := 0
	while i < raw_args.size():
		var arg: String = raw_args[i]
		if (arg == "--map" or arg == "-m") and i + 1 < raw_args.size():
			map_dir = raw_args[i + 1]
			i += 2
		elif (arg == "--output-dir" or arg == "-o") and i + 1 < raw_args.size():
			output_dir = raw_args[i + 1]
			i += 2
		elif (arg == "--seed" or arg == "-s") and i + 1 < raw_args.size():
			seed_override = int(raw_args[i + 1])
			has_seed_override = true
			i += 2
		elif arg == "--skip-objects" or arg == "--no-objects" or arg == "-S":
			skip_objects_flag = true
			i += 1
		elif not arg.begins_with("-"):
			positionals.append(arg)
			i += 1
		else:
			i += 1

	if map_dir.is_empty() and positionals.size() > 0:
		map_dir = positionals[0]
	if output_dir.is_empty() and positionals.size() > 1:
		output_dir = positionals[1]
	if not has_seed_override and positionals.size() > 2:
		seed_override = int(positionals[2])
		has_seed_override = true

	if map_dir.is_empty() or output_dir.is_empty():
		printerr("Usage: generate_map.sh MAP_DIRECTORY OUTPUT_DIRECTORY [SEED] [--skip-objects]")
		printerr("   or: generate_map.sh --map MAP_DIRECTORY --output-dir OUTPUT_DIRECTORY [--seed SEED] [--skip-objects]")
		quit(2)
		return

	var doc = Config.load_map_config(map_dir)
	if doc.is_empty():
		printerr(Config.last_error)
		quit(1)
		return

	if DirAccess.dir_exists_absolute(output_dir):
		printerr("Output directory already exists; choose a new directory: %s" % output_dir)
		quit(2)
		return

	if not doc.has("generation"):
		doc["generation"] = {}
	if has_seed_override:
		doc.generation["seed"] = seed_override
	else:
		doc.generation["seed"] = (int(Time.get_ticks_usec()) ^ randi()) & 0x7fffffff
	if skip_objects_flag:
		doc.generation["skip_objects"] = true

	var cb = func(value, message):
		print("%d%% %s" % [int(value * 100), message])

	var result = await Generator.generate(doc, cb)

	if result.has("error"):
		printerr(result.error)
		quit(1)
		return

	if not Generator.save_generated_map_package(result, output_dir, cb):
		printerr("Failed to save generated map package")
		quit(1)
		return

	print(JSON.stringify(result.report, "\t"))
	quit(0)
