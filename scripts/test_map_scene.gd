extends SceneTree
const ObjectFactory = preload("res://scripts/map_object_factory.gd")
const EditStorage = preload("res://scripts/world_edit_storage.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)

func flame_card_material(object: Node) -> ShaderMaterial:
	var card := object.find_child("FlameCard0", true, false) as MeshInstance3D
	if not card or not card.mesh:
		return null
	return card.get_active_material(0) as ShaderMaterial
func _watchdog(timeout_sec: float = 90.0) -> void:
	await create_timer(timeout_sec).timeout
	printerr("\n[WATCHDOG TIMEOUT] test_map_scene exceeded %.1f seconds! Terminating..." % timeout_sec)
	quit(1)

func _initialize():
	_watchdog(90.0)
	_run.call_deferred()
func _run():
	MapConfig.active_map_file = "user://test_active_map_%d.txt" % Time.get_ticks_usec()
	root.size = Vector2i(1280,720)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var world = scene.get_node("CylinderWorld")
	check(world.terrain_manager != null and world.terrain_manager.terrain_data.size() > 0, "Scene has loaded biome data")
	var refs = scene.get_node("ReferenceObjects")
	if refs.get_child_count() == 0:
		var test_light_obj := ObjectFactory.create(world.active_map_config, {"id":"scene-light-check", "asset":"campfire", "theta":0.1, "z":5.0}, world)
		refs.add_child(test_light_obj)
		await process_frame
	check(refs.get_child_count() > 0, "Scene instantiates map objects")
	var first = get_first_node_in_group("surface_light_objects")
	check(first != null and not first.asset_id.is_empty(), "Object instances retain stable catalog IDs")
	var map_doc: Dictionary = world.active_map_config
	var terrain_material := world.surface_material as ShaderMaterial
	check(terrain_material != null and is_equal_approx(terrain_material.get_shader_parameter("biome_blend_width_m"), map_doc.rendering.biome_blend_width_m), "Terrain shader receives map-owned biome blend width")
	if terrain_material:
		var parameter_texture := terrain_material.get_shader_parameter("biome_parameters") as Texture2D
		var parameter_image := parameter_texture.get_image() if parameter_texture else null
		var sample_biome: Dictionary = map_doc.biomes.values()[0]
		var blend_enabled := parameter_image != null and parameter_image.get_pixel(int(sample_biome.raster_id), 0).a > 0.5
		check(blend_enabled == sample_biome.blended, "Terrain shader receives each biome's blend flag")
	var flame_parameters: Dictionary = map_doc.shader_parameters["campfire_flame.gdshader"]
	var shader_object := ObjectFactory.create(map_doc, {"id":"shader-map-check", "asset":"campfire", "theta":0.4, "z":12.0}, world)
	refs.add_child(shader_object)
	await process_frame
	var flame_material := flame_card_material(shader_object)
	check(flame_material != null and flame_material.get_shader_parameter("color_flame").is_equal_approx(MapConfig.color(flame_parameters.color_flame)), "Map flame shader parameters apply to duplicated nested object materials")
	var alternate_doc: Dictionary = map_doc.duplicate(true)
	alternate_doc.shader_parameters["campfire_flame.gdshader"].color_flame = [0.2,0.7,0.9,1.0]
	world.active_map_config = alternate_doc
	shader_object.rebuild_object()
	await process_frame
	flame_material = flame_card_material(shader_object)
	check(flame_material != null and flame_material.get_shader_parameter("color_flame").is_equal_approx(Color(0.2,0.7,0.9,1)), "Object rebuild uses newly active map shader values")
	world.active_map_config = map_doc
	shader_object.rebuild_object()
	await process_frame
	shader_object.queue_free()
	var saved_light_record := {"id":"canonical-light-range-check", "asset":"campfire", "theta":0.4, "z":20.0, "light_range_m":38.0}
	var saved_light_object := ObjectFactory.create(map_doc, saved_light_record, world)
	refs.add_child(saved_light_object)
	await process_frame
	var placement_snapshot_path := "user://maps/canonical_light_range_%d.json" % Time.get_ticks_usec()
	check(EditStorage.save(refs, placement_snapshot_path) == OK, "Placement snapshot saves canonical light settings")
	var placement_snapshot: Variant = JSON.parse_string(FileAccess.get_file_as_string(placement_snapshot_path))
	var persisted_light: Dictionary = {}
	if placement_snapshot is Dictionary:
		for record in placement_snapshot.get("objects", []):
			if record.get("id") == "canonical-light-range-check":
				persisted_light = record
				break
	check(persisted_light.get("light_range_m") == 38.0, "Canonical instance light range survives saving")
	var restored_light = ObjectFactory.create(map_doc, persisted_light, world) if not persisted_light.is_empty() else null
	check(restored_light != null and is_equal_approx(restored_light.light_range, 38.0), "Saved canonical light range survives object reconstruction")
	if restored_light:
		restored_light.free()
	var env = scene.get_node("WorldEnvironment").environment
	check(env.background_color.is_equal_approx(MapConfig.color(world.active_map_config.environment.sky_color)), "Map sky color applied")
	check(world.water_material.get_shader_parameter("deep_color").is_equal_approx(MapConfig.color(world.active_map_config.environment.water.deep_color)), "Map water color applied")
	var controls = scene.find_child("TouchControls", true, false)
	controls.editor_ui.set_edit_mode(true)
	var ui = controls.editor_ui
	ui.set_regen_dialog_open(true)
	await process_frame
	check(ui.map_editor.document.biomes.size() == world.active_map_config.biomes.size(), "Map editor opens with actual biomes")
	ui.map_editor.expanded["Geometry, resolution & generation"] = true
	ui.map_editor.rebuild()
	for size_value in [Vector2i(480,900), Vector2i(1280,720)]:
		root.size = size_value
		await process_frame
		await process_frame
		var screen_rect = ui.regen_dialog.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, ui.regen_dialog.size)
		var viewport_rect = root.get_visible_rect()
		check(screen_rect.position.x >= 0 and screen_rect.end.x <= viewport_rect.end.x, "Map editor fits viewport width " + str(size_value.x))

	if "--screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/map-editor-desktop.png")
		root.size = Vector2i(480,900)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/map-editor-mobile.png")
		ui.set_regen_dialog_open(false)
		root.size = Vector2i(1280,720)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/map-world.png")
	# Exercise the actual asynchronous editor generation/save/activation path.
	var pointer_existed = FileAccess.file_exists(MapConfig.active_map_file)
	var old_pointer = FileAccess.get_file_as_string(MapConfig.active_map_file) if pointer_existed else ""
	ui.map_editor.document.generation.erase("sample_pitch_m")
	ui.map_editor.document.generation.elevation_width = 32
	ui.map_editor.document.generation.elevation_height = 17
	ui.map_editor.document.generation.terrain_width = 19
	ui.map_editor.document.generation.terrain_height = 11
	ui.map_editor.document.generation.object_limit = 24
	ui.map_editor.document.geometry.cylinder_radius_m = 1600
	ui.map_editor.document.geometry.cylinder_length_m = 6200
	ui.map_editor.document.rendering.radial_segments = 32
	ui.map_editor.document.rendering.length_segments = 24
	ui.map_editor.document.environment.sky_color = [0.2,0.1,0.3,1]
	await ui._execute_map_regeneration()
	check(world.radius == 1600 and world.cylinder_length == 6200, "Editor generation uses authoritative geometry")
	check(world.terrain_manager.elevation_grid_u == 32 and world.terrain_manager.terrain_grid_u == 19, "Editor regenerates and reloads independent layer resolutions")
	check(world.active_map_config.map_directory.begins_with("user://maps/"), "Editor activates writable generated package")
	check(not ui.progress_dialog.visible, "Generation completion closes progress dialog")
	check(scene.get_node("Player").cylinder_radius == 1600, "Player geometry follows the activated map")
	check(env.background_color.is_equal_approx(Color(0.2,0.1,0.3,1)), "Sky edit survives generation and activation")
	# Exercise save without regeneration as well.
	ui.map_editor.document.environment.water.deep_color = [0.1,0.2,0.4,0.6]
	await ui._save_map_definition()
	check(world.water_material.get_shader_parameter("deep_color").is_equal_approx(Color(0.1,0.2,0.4,0.6)), "Definition save applies edited water color")
	var original_id: String = world.active_map_config.world_id
	ui.map_editor.map_name.text = "Named scene test"
	ui.map_editor.map_name.text_changed.emit("Named scene test")
	check(await ui._save_map_definition(true), "Save As succeeds through editor")
	check(world.active_map_config.name == "Named scene test" and world.active_map_config.world_id != original_id, "Save As retains entered name with separate identity")
	var archive = "user://scene_export_" + MapConfig.new_map_id() + ".cylmap"
	await ui._export_map(archive)
	check(FileAccess.file_exists(archive), "Editor saves and exports active map")
	var exported_id: String = world.active_map_config.world_id
	await ui._import_map(archive)
	check(world.active_map_config.name == "Named scene test" and world.active_map_config.world_id != exported_id, "Editor imports and activates independent named map")
	check(world.radius == 1600 and world.terrain_manager.terrain_grid_u == 19, "Imported map preserves physical geometry and independent resolution")
	if pointer_existed:
		var file = FileAccess.open(MapConfig.active_map_file, FileAccess.WRITE)
		file.store_string(old_pointer)
		file.close()
	else:
		DirAccess.remove_absolute(MapConfig.active_map_file)
	print("MAP SCENE FAILURES: ", failures)
	scene.free()
	quit(1 if failures else 0)
