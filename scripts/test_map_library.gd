extends SceneTree
const Config = preload("res://scripts/map_config.gd")
const Library = preload("res://scripts/map_library.gd")
var failures = 0
func check(ok: bool, message: String):
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
func _watchdog(timeout_sec: float = 60.0) -> void:
	await create_timer(timeout_sec).timeout
	printerr("\n[WATCHDOG TIMEOUT] test_map_library exceeded %.1f seconds! Terminating..." % timeout_sec)
	quit(1)

func _initialize():
	_watchdog(60.0)
	_run.call_deferred()
func _run():
	var root_path = "user://library_test_" + Config.new_map_id()
	Config.user_maps_directory = root_path.path_join("maps")
	Config.active_map_file = root_path.path_join("active_map.txt")
	var template_hash = FileAccess.get_sha256(Config.DEFAULT_MAP_DIRECTORY.path_join("map_config.json"))
	var first = Config.active_map()
	check(first.begins_with(Config.user_maps_directory), "First launch creates a writable template copy")
	var doc = Config.load_map_config(first)
	check(doc.template_revision == template_hash and not doc.name.is_empty(), "Template provenance and map name are recorded")
	var template = Config.load_map_config()
	check(doc.world_id != template.world_id, "User copy has independent identity")
	doc.name = "My islands"
	doc.environment.sky_color = [0.1, 0.2, 0.3, 1.0]
	doc.template_revision = "previous-app-template"
	check(Config.save_document(doc, first) == OK, "Named map edits save")
	check(Config.active_map() == first and Config.load_map_config(first).environment.sky_color == doc.environment.sky_color, "Startup retains edited user map despite a newer bundled template")
	var second = Config.create_from_template()
	var second_doc = Config.load_map_config(second)
	check(second != first and second_doc.world_id != doc.world_id, "New from template creates a separate map")
	check(second_doc.environment.sky_color == template.environment.sky_color, "New map uses current template values")
	check(Config.active_map() == first, "Creating a map does not change active selection")
	var revision = Config.new_user_directory("edited")
	check(Config.copy_directory(first, revision) == OK, "Save stages a separate revision")
	check(not revision in Config.list_available_maps(), "Incomplete saves stay out of the load picker")
	check(Config.publish_map(revision) == OK, "Completed save is published")
	check(Config.list_available_maps().size() == 2 and revision in Config.list_available_maps(), "Load picker groups revisions by map identity")
	var archive = root_path.path_join("islands.cylmap")
	check(Library.export_map(first, archive) == OK, "Named map exports to archive")
	var imported = Library.import_map(archive)
	check(not imported.is_empty(), "Archive imports as a validated map: " + Config.last_error)
	if not imported.is_empty():
		var loaded = Config.load_map_config(imported)
		check(loaded.name == doc.name and loaded.world_id != doc.world_id, "Import retains name and assigns separate identity")
		check(loaded.environment.sky_color == doc.environment.sky_color, "Export/import preserves map definitions")
		for file in doc.files.values():
			check(FileAccess.get_sha256(first.path_join(file)) == FileAccess.get_sha256(imported.path_join(file)), "Archive preserves layer bytes: " + file)
	check(Config.active_map() == first, "Import does not silently replace active map")
	var evil = root_path.path_join("invalid.cylmap")
	var zip = ZIPPacker.new()
	zip.open(evil)
	zip.start_file("map_config.json")
	zip.write_file(FileAccess.get_file_as_bytes(first.path_join("map_config.json")))
	zip.close_file()
	zip.start_file("../escape.txt")
	zip.write_file("invalid".to_utf8_buffer())
	zip.close_file()
	zip.close()
	check(Library.import_map(evil).is_empty() and Config.last_error.contains("path"), "Import rejects archive traversal")
	check(not FileAccess.file_exists(root_path.path_join("escape.txt")), "Import cannot write outside its map directory")
	check(FileAccess.get_sha256(Config.DEFAULT_MAP_DIRECTORY.path_join("map_config.json")) == template_hash, "All editing and library operations leave bundled template unchanged")
	print("MAP LIBRARY FAILURES: ", failures)
	quit(1 if failures else 0)
