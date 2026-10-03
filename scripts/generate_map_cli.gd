extends SceneTree
const Config = preload("res://scripts/map_config.gd")
const Generator = preload("res://scripts/map_generator.gd")
func _initialize():
	_run.call_deferred()
func _run():
	var args = OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("Usage: godot --headless --path . -s scripts/generate_map_cli.gd -- MAP_DIRECTORY NEW_OUTPUT_DIRECTORY [SEED]")
		quit(2)
		return
	var doc = Config.load_map_config(args[0])
	if doc.is_empty():
		printerr(Config.last_error)
		quit(1)
		return
	if DirAccess.dir_exists_absolute(args[1]):
		printerr("Output directory already exists; choose a new directory")
		quit(2)
		return
	if args.size() > 2:
		doc.generation.seed = int(args[2])
	var result = await Generator.generate(doc, func(value, message):
		print("%d%% %s" % [value * 100, message])
		await process_frame)
	if result.has("error"):
		printerr(result.error)
		quit(1)
		return
	if not Generator.save_generated_map_package(result, args[1]):
		printerr("Failed to save generated map")
		quit(1)
		return
	print(JSON.stringify(result.report, "\t"))
	quit(0)
