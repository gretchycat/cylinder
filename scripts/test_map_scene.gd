extends SceneTree
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
	MapConfig.active_map_file = "user://test_active_map_%d.txt" % Time.get_ticks_usec()
	create_timer(90).timeout.connect(func(): quit(1))
	root.size = Vector2i(1280,720)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var world = scene.get_node("CylinderWorld")
	check(world.terrain_manager != null and world.terrain_manager.terrain_data.size() > 0, "Scene has loaded biome data")
	var refs = scene.get_node("ReferenceObjects")
	check(refs.get_child_count() > 1, "Scene instantiates map objects")
	var first = get_first_node_in_group("surface_light_objects")
	check(first != null and not first.asset_id.is_empty(), "Object instances retain stable catalog IDs")
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
