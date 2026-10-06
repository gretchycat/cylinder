extends SceneTree
const Config = preload("res://scripts/map_config.gd")
const Assets = preload("res://scripts/map_asset_loader.gd")
const Storage = preload("res://scripts/world_edit_storage.gd")
var failures = 0
class Layer extends Node3D:
	var active_map_config: Dictionary
func check(ok: bool, message: String):
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
func _watchdog(timeout_sec: float = 60.0) -> void:
	await create_timer(timeout_sec).timeout
	printerr("\n[WATCHDOG TIMEOUT] test_map_imports exceeded %.1f seconds! Terminating..." % timeout_sec)
	quit(1)

func _initialize():
	_watchdog(60.0)
	_run.call_deferred()
func _test_packed_map(imported_terrain: bool = false):
	var doc = Config.load_map_config()
	var suffix = str(Time.get_ticks_usec())
	var packed_source = "res://save_regression_" + suffix
	var destination = "user://maps/save_regression_" + suffix
	var pack_path = "user://save_regression_" + suffix + ".pck"
	var pack = PCKPacker.new()
	check(pack.pck_start(pack_path) == OK, "Create packaged-map save fixture")
	check(pack.add_file(packed_source.path_join("map_config.json"), Config.DEFAULT_MAP_DIRECTORY.path_join("map_config.json")) == OK, "Pack map descriptor")
	for file in doc.files.values():
		if imported_terrain and file == doc.files.terrain_map:
			check(pack.add_file(packed_source.path_join(file + ".import"), Config.DEFAULT_MAP_DIRECTORY.path_join(file + ".import")) == OK, "Pack imported biome remap without original PNG")
			continue
		check(pack.add_file(packed_source.path_join(file), Config.DEFAULT_MAP_DIRECTORY.path_join(file)) == OK, "Pack map layer: " + file)
	var asset = "assets/nested/grass.png"
	var original_asset = "res://assets/textures/terrain/grass_0.png"
	check(pack.add_file(packed_source.path_join(asset), original_asset) == OK, "Pack nested map asset")
	check(pack.flush() == OK and ProjectSettings.load_resource_pack(pack_path), "Mount packaged map without filesystem source files")
	if imported_terrain:
		check(not FileAccess.file_exists(packed_source.path_join(doc.files.terrain_map)) and ResourceLoader.exists(packed_source.path_join(doc.files.terrain_map)), "Export fixture has only imported biome texture")
	check(Config.copy_directory(packed_source, destination) == OK, "Save bundled map from resource pack: " + Config.last_error)
	for file in doc.files.values():
		if imported_terrain and file == doc.files.terrain_map:
			var original = Assets.load_image(Config.DEFAULT_MAP_DIRECTORY.path_join(file))
			var saved = Assets.load_image(destination.path_join(file))
			if saved:
				saved.convert(original.get_format())
			check(saved != null and saved.get_size() == original.get_size() and saved.get_data() == original.get_data(), "Exported biome IDs survive PNG reconstruction exactly")
			continue
		if file == doc.files.terrain_map:
			var original = Assets.load_image(Config.DEFAULT_MAP_DIRECTORY.path_join(file))
			var saved = Assets.load_image(destination.path_join(file))
			if saved:
				saved.convert(original.get_format())
			check(saved != null and saved.get_data() == original.get_data(), "Saved biome IDs preserved")
		else:
			check(FileAccess.get_sha256(destination.path_join(file)) == FileAccess.get_sha256(Config.DEFAULT_MAP_DIRECTORY.path_join(file)), "Saved layer bytes preserved: " + file)
	check(FileAccess.get_sha256(destination.path_join(asset)) == FileAccess.get_sha256(original_asset), "Nested bundled assets survive save")
	check(not Config.load_map_config(destination).is_empty(), "Saved packaged descriptor reloads")
	var missing = packed_source.path_join("missing.cylh")
	check(Config.copy_map_file(missing, destination.path_join("missing.cylh")) != OK and Config.last_error.contains(missing), "Copy failure identifies unreadable source")

func _test_generation_without_source_layers():
	var doc = Config.load_map_config()
	var source = "user://maps/generation_source_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(source)
	check(Config.save_document(doc, source) == OK, "Create definition-only generation source")
	doc.map_directory = source
	var elevation = Image.create(8, 4, false, Image.FORMAT_RF)
	elevation.fill(Color(0.25, 0, 0))
	var terrain = Image.create(4, 2, false, Image.FORMAT_L8)
	terrain.fill(Color(1.0 / 255.0, 1.0 / 255.0, 1.0 / 255.0))
	var result = {"document": doc, "elevation_image": elevation, "terrain_image": terrain, "objects_data": {"objects": []}, "report": {}, "warnings": []}
	var destination = source + "_generated"
	check(preload("res://scripts/map_generator.gd").save_generated_map_package(result, destination), "Generated map saves without reading obsolete source layers: " + Config.last_error)
	var layers = preload("res://scripts/terrain_manager.gd").new()
	layers.configure(doc)
	check(layers.load_layers(destination.path_join(doc.files.elevation_map), destination.path_join(doc.files.terrain_map)), "Generated layers reload from writable storage")

func _run():
	_test_packed_map()
	_test_packed_map(true)
	_test_generation_without_source_layers()
	var panel = preload("res://scripts/map_editor_panel.gd").new()
	root.add_child(panel)
	panel.file_dialog.set_meta("kind", "model")
	var model_path = [""]
	panel.import_callback = func(path): model_path[0] = path
	panel._import_file(ProjectSettings.globalize_path("res://assets/maps/default/models/source/trees/oak.glb"))
	check(not model_path[0].is_empty(), "Self-contained GLB imports through editor")
	if model_path[0].is_empty():
		print(panel.message.text)
		quit(1)
		return
	var instance = Assets.instantiate_model(model_path[0])
	check(instance != null and not instance.find_children("*", "MeshInstance3D", true, false).is_empty(), "Imported GLB instantiates renderable meshes")
	if instance:
		instance.free()
	panel.document.objects.model_catalog["imported_tree"] = {"name":"Imported tree", "scene_path":model_path[0], "behavior_type":6, "variant":0, "light_color":[0.1,0.3,0.9,0.4], "light_energy":2, "light_range_m":20, "flicker":false, "tint":[0.4,0.7,0.8,0.5]}
	panel.file_dialog.set_meta("kind", "texture")
	var texture_path = [""]
	panel.import_callback = func(path): texture_path[0] = path
	panel._import_file(ProjectSettings.globalize_path("res://assets/textures/terrain/grass_0.png"))
	check(not texture_path[0].is_empty(), "Texture imports through editor")
	panel.document.biomes.grassland.texture = texture_path[0]
	var directory = "user://maps/import_test_%d" % Time.get_ticks_usec()
	check(Config.copy_directory(panel.document.map_directory, directory) == OK, "Map package copy succeeds")
	check(panel.package_imports(directory), "Imports are copied into map assets")
	check(Config.save_document(panel.document, directory) == OK, "Imported definitions save")
	var doc = Config.load_map_config(directory)
	check(doc.biomes.grassland.texture.begins_with("assets/") and doc.objects.model_catalog.imported_tree.scene_path.begins_with("assets/"), "Imported references become package-relative")
	check(Config.validate_assets(doc).is_empty(), "Packaged asset references resolve")
	var relocated = directory + "_relocated"
	check(Config.copy_directory(directory, relocated) == OK, "Map relocates with imported assets")
	doc = Config.load_map_config(relocated)
	Assets.model_cache.clear()
	instance = Assets.instantiate_model(Config.resolve_map_asset_path(doc, doc.objects.model_catalog.imported_tree.scene_path))
	check(instance != null, "Imported model reloads from relocated package without import cache")
	if instance:
		instance.free()
	check(Assets.load_image(Config.resolve_map_asset_path(doc, doc.biomes.grassland.texture)) != null, "Imported texture reloads from relocated package")
	var archive = relocated + ".cylmap"
	var library = preload("res://scripts/map_library.gd")
	check(library.export_map(relocated, archive) == OK, "Export includes imported assets")
	var imported_directory = library.import_map(archive)
	check(not imported_directory.is_empty(), "Archive with custom assets validates and imports: " + Config.last_error)
	if not imported_directory.is_empty():
		var imported_doc = Config.load_map_config(imported_directory)
		Assets.model_cache.clear()
		var imported_model = Assets.instantiate_model(Config.resolve_map_asset_path(imported_doc, imported_doc.objects.model_catalog.imported_tree.scene_path))
		check(imported_model != null, "Custom GLB reloads from imported archive")
		if imported_model:
			imported_model.free()
		check(Assets.load_image(Config.resolve_map_asset_path(imported_doc, imported_doc.biomes.grassland.texture)) != null, "Custom biome texture reloads from imported archive")
	var layer = Layer.new()
	layer.active_map_config = doc
	root.add_child(layer)
	var record = {"id":"tinted_instance", "asset":"imported_tree", "theta":0.0, "z":0.0}
	var obj = preload("res://scripts/map_object_factory.gd").create(doc, record)
	layer.add_child(obj)
	check(obj.omni_light != null and is_equal_approx(obj.omni_light.light_energy, 0.8), "Light alpha multiplies emitted energy")
	var bare_mesh = MeshInstance3D.new()
	bare_mesh.mesh = BoxMesh.new()
	obj.add_child(bare_mesh)
	obj.apply_appearance(bare_mesh)
	check(bare_mesh.get_active_material(0).albedo_color.is_equal_approx(obj.tint), "Models without a source material still accept RGBA tint")
	bare_mesh.free()
	var path = relocated.path_join(doc.files.object_map)
	check(Storage.save(layer, path) == OK, "Tinted object saves as authored placement")
	obj.free()
	check(Storage.restore(layer, path), "Authored placement restores")
	obj = layer.get_child(0)
	check(obj.tint.is_equal_approx(Color(0.4,0.7,0.8,0.5)) and obj.light_color.is_equal_approx(Color(0.1,0.3,0.9,0.4)), "Appearance and lighting RGBA survive save/reload")
	check(obj.asset_id == "imported_tree" and obj.instance_id == "tinted_instance", "Instance and asset IDs survive save/reload")
	layer.free()
	panel.free()
	print("MAP IMPORT FAILURES: ", failures)
	quit(1 if failures else 0)
