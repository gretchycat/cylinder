extends SceneTree

const Config = preload("res://scripts/map_config.gd")
const Storage = preload("res://scripts/world_edit_storage.gd")
const TEST_SAVE := "res://build/test_world_edits.json"
var failures := 0

class ObjectLayer extends Node3D:
	var active_map_config: Dictionary

class MockCylinderWorld extends Node3D:
	var terrain_manager: TerrainManager
	var active_map_config: Dictionary
	var surface_material: Material = null
	var radius: float = 4000.0
	var cylinder_length: float = 18000.0
	func generate_cylinder() -> void:
		pass
	func load_map_package(dir: String) -> void:
		pass

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("[FAIL] ", message)

func _watchdog(timeout_sec: float = 60.0) -> void:
	await create_timer(timeout_sec).timeout
	printerr("\n[WATCHDOG TIMEOUT] test_edit_controls exceeded %.1f seconds! Terminating..." % timeout_sec)
	quit(1)

func _init() -> void:
	_watchdog(60.0)
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var world := MockCylinderWorld.new()
	world.active_map_config = Config.load_map_config("default")
	world.add_to_group("cylinder_world")
	world.terrain_manager = TerrainManager.new()
	world.terrain_manager.configure(Config.load_map_config("default"))
	world.terrain_manager.elevation_data.resize(world.terrain_manager.elevation_grid_u * world.terrain_manager.elevation_grid_v)
	world.terrain_manager.terrain_data.resize(world.terrain_manager.terrain_grid_u * world.terrain_manager.terrain_grid_v)
	root.add_child(world)
	var layer := ObjectLayer.new()
	layer.active_map_config = Config.load_map_config("default")
	layer.add_to_group("reference_objects")
	world.add_child(layer)
	var player: PlayerController = load("res://scenes/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.global_transform = Transform3D.IDENTITY
	player.global_position = Vector3(0, 2, 0)
	var ui_scene: Node = load("res://scenes/ui.tscn").instantiate()
	var controls: MobileTouchControls = ui_scene.get_node("UIRoot/TouchControls")
	controls.get_parent().remove_child(controls)
	ui_scene.free()
	controls.player = player
	root.add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	controls.size = Vector2(1280, 720)
	await process_frame
	await process_frame
	var joy := controls.joystick_base.get_global_rect().get_center()
	var original_run := player.mobile_sprint_active
	controls._handle_touch_start(10, joy)
	controls._handle_touch_end(10)
	check(player.mobile_sprint_active != original_run, "Joystick tap toggles run")
	controls._handle_touch_start(10, joy)
	controls._handle_touch_end(10)
	check(player.mobile_sprint_active == original_run, "Second tap toggles run back")
	check(controls.knob_style.bg_color.r > controls.knob_style.bg_color.b, "Running joystick center is red")
	controls._handle_touch_start(10, joy)
	controls._handle_touch_drag(10, joy + Vector2(40, -30), Vector2(40, -30))
	check(player.input_axis.length() > 0.2, "Joystick drag moves player")
	controls._handle_touch_end(10)
	check(player.mobile_sprint_active == original_run, "Dragging never toggles run")
	check(player.input_axis == Vector2.ZERO, "Release stops joystick movement")
	controls._handle_touch_start(10, joy)
	controls.joystick_press_time -= 400
	controls._handle_touch_end(10)
	check(player.mobile_sprint_active == original_run, "Long hold never toggles run")
	controls._handle_mouse_press(joy)
	controls._handle_mouse_release()
	check(player.mobile_sprint_active != original_run, "Mouse click toggles run once")
	check(controls.knob_style.bg_color.b > controls.knob_style.bg_color.r, "Walking joystick center is blue")
	check(controls.get_node("ActionButtons").get_child_count() == 1, "Jump is the only normal right-side button")
	check(controls.debug_panel.get_global_rect().end.y < controls.jump_btn.get_global_rect().position.y, "Debug box sits above Jump")
	check(controls.fly_up_btn.disabled, "Fly up disabled outside flight")
	controls._on_fly_pressed()
	check(not controls.fly_up_btn.disabled, "Fly up enabled in flight")
	controls._on_fly_pressed()
	var editor_ui = controls.editor_ui
	check(not editor_ui.editor.enabled and not editor_ui.actions.visible, "Edit actions initially hidden")
	controls.edit_btn.button_pressed = true
	check(editor_ui.editor.enabled and editor_ui.actions.visible, "Edit toggle reveals actions")
	check(editor_ui.editor.catalog.size() >= 14, "Palette includes models and tree variants")
	check(editor_ui.current_preview.mesh_count > 0, "Selected object has a miniature model")
	var group_count := get_nodes_in_group("surface_light_objects").size()
	editor_ui.set_palette_open(true)
	await process_frame
	await process_frame
	await screenshot("edit-palette")
	check(player.ui_input_blocked, "Palette blocks player input")
	check(editor_ui.selection_buttons.size() == editor_ui.editor.catalog.size(), "Palette contains every catalog entry")
	for preview in editor_ui.previews:
		check(preview.mesh_count > 0, "Each palette card contains model meshes")
	check(get_nodes_in_group("surface_light_objects").size() == group_count, "Previews do not create gameplay objects")
	controls._handle_touch_start(11, joy)
	check(controls.joystick_touch_id == -1, "Palette blocks joystick touches")
	var windmill_index := -1
	for i in editor_ui.editor.catalog.size():
		if editor_ui.editor.catalog[i].id == "windmill":
			windmill_index = i
	editor_ui._select(windmill_index)
	check(editor_ui.editor.current_object().type == SurfaceLightObject.ObjectType.WINDMILL, "Windmill catalog ID maps to correct runtime type")
	check(not player.ui_input_blocked and not editor_ui.palette_open, "Selection closes palette and restores input")

	await screenshot("edit-controls")
	for layout_size in [Vector2(1280, 720), Vector2(1024, 576), Vector2(480, 900)]:
		controls.size = layout_size
		await process_frame
		await process_frame
		check(not editor_ui.actions.get_global_rect().intersects(controls.joystick_base.get_global_rect()), "Edit actions do not overlap joystick at %s" % layout_size)
		check(not editor_ui.actions.get_global_rect().intersects(controls.debug_panel.get_global_rect()), "Edit actions do not overlap debug box at %s" % layout_size)
		check(editor_ui.size.is_equal_approx(controls.size), "Crosshair canvas follows viewport size")
	controls.size = Vector2(1280, 720)
	await process_frame

	# Exercise actual physics ray placement on a solid surface.
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	player.camera.look_at(Vector3(0, 0, -8), Vector3.UP)
	await physics_frame
	await physics_frame
	editor_ui._select(_catalog_index(editor_ui.editor.catalog, "campfire"))
	var placed: SurfaceLightObject = editor_ui.editor.place()
	check(placed != null, "Place creates the selected object on the camera ray hit")
	if placed:
		check(absf(placed.global_position.y - 0.03) < 0.01, "Placed object rests on hit surface")
		check(placed.global_basis.y.dot(Vector3.UP) > 0.99, "Placed object aligns with surface normal")
		player.camera.look_at(placed.global_position + Vector3.UP * 0.2, Vector3.UP)
		check(editor_ui.editor.target_object(editor_ui.editor.ray_hit()) == placed, "Remove targets a decorative object without physics")
		# A nearer wall must prevent removing an object behind it.
		var wall := StaticBody3D.new()
		var wall_shape := CollisionShape3D.new()
		var wall_box := BoxShape3D.new()
		wall_box.size = Vector3(10, 10, 0.2)
		wall_shape.shape = wall_box
		wall.add_child(wall_shape)
		wall.position = player.camera.global_position.lerp(placed.global_position, 0.5)
		world.add_child(wall)
		await physics_frame
		await physics_frame
		check(editor_ui.editor.target_object(editor_ui.editor.ray_hit()) == null, "Remove respects solid occlusion")
		wall.free()
		await physics_frame
		check(Storage.save(layer, TEST_SAVE) == OK, "Save writes object snapshot")
		check(editor_ui.editor.remove(), "Remove deletes crosshair target")
		await process_frame
		check(layer.get_child_count() == 0, "Removed object leaves the world")
		check(Storage.restore(layer, TEST_SAVE), "Saved snapshot restores successfully")
		check(layer.get_child_count() == 1, "Unsaved removal is discarded on reload")
		var restored: SurfaceLightObject = layer.get_child(0)
		check(restored.object_type == SurfaceLightObject.ObjectType.CAMPFIRE, "Saved object type survives reload")
		check(absf(restored.position.y - 0.03) < 0.01, "Saved transform survives reload")
		restored.queue_free()
		await process_frame
		check(Storage.save(layer, TEST_SAVE) == OK, "Save persists empty object layer")
		check(Storage.restore(layer, TEST_SAVE) and layer.get_child_count() == 0, "Saved removals survive reload")
	# Placement must follow sloped/curved habitat surfaces, not global up.
	floor_body.rotation.z = deg_to_rad(25.0)
	player.camera.look_at(Vector3(0, 0, -8), Vector3.UP)
	await physics_frame
	await physics_frame
	editor_ui._select(_catalog_index(editor_ui.editor.catalog, "tree_5"))
	var tree: SurfaceLightObject = editor_ui.editor.place()
	check(tree != null, "Tree variant places on a sloped surface")
	if tree:
		check(tree.tree_variant == SurfaceLightObject.TreeVariant.DEAD_TREE, "Selected tree variant is used")
		check(tree.global_basis.y.dot(Vector3.UP) > 0.99, "Object stands flat to gravity on sloped surface")
		tree.queue_free()
		await process_frame
	player.camera.look_at(player.camera.global_position + Vector3.UP, Vector3.FORWARD)
	check(editor_ui.editor.place() == null, "Place does nothing when aiming into empty space")
	check(not editor_ui.editor.remove(), "Remove does nothing without a target")
	# Saving also updates the map's default player spawn, both now and at startup.
	player.global_transform = Transform3D(Basis(Vector3.FORWARD, 0.4), Vector3(12, -35, 27))
	player.pitch = 0.3
	player.head.rotation.x = player.pitch
	player.is_flying = true
	var saved_transform := player.global_transform
	check(Storage.save(layer, TEST_SAVE, player) == OK, "Save includes current player location")
	player.global_position = Vector3(100, 100, 100)
	player.velocity = Vector3(5, 6, 7)
	player.reset_to_spawn()
	check(player.global_transform.is_equal_approx(saved_transform), "Reset immediately uses saved position and facing")
	check(player.velocity == Vector3.ZERO, "Saved spawn resets movement velocity")
	layer.set_meta("saved_player_spawn", {})
	check(Storage.restore(layer, TEST_SAVE), "Saved location loads from disk")
	var restarted_player: PlayerController = load("res://scenes/player.tscn").instantiate()
	world.add_child(restarted_player)
	restarted_player.set_physics_process(false)
	check(restarted_player.global_transform.is_equal_approx(saved_transform), "Player ready restores saved position and facing")
	check(is_equal_approx(restarted_player.pitch, 0.3) and is_equal_approx(restarted_player.head.rotation.x, 0.3), "Saved camera pitch is restored")
	check(restarted_player.is_flying, "A spawn saved in flight remains in flight")
	restarted_player.free()
	# A placement document without an explicit player transform uses map spawning.
	var old_save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	old_save.erase("player_spawn")
	var old_file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(old_save))
	old_file.close()
	check(Storage.restore(layer, TEST_SAVE), "Object-only document loads")
	check(layer.get_meta("saved_player_spawn").is_empty(), "Absent player transform uses map spawn")
	# Test 3 Sub-Modes (Object, Painter, Elevation)
	var WorldEditorClass = preload("res://scripts/world_editor.gd")
	editor_ui._set_sub_mode(WorldEditorClass.SubMode.PAINTER)
	check(editor_ui.editor.sub_mode == WorldEditorClass.SubMode.PAINTER, "Submode switches to PAINTER")
	check(editor_ui.active_box.visible, "Active chooser box visible in PAINTER mode")
	check(editor_ui.paint_button != null and editor_ui.paint_button.is_inside_tree(), "Paint button present in PAINTER mode")

	editor_ui._set_sub_mode(WorldEditorClass.SubMode.ELEVATION)
	check(editor_ui.editor.sub_mode == WorldEditorClass.SubMode.ELEVATION, "Submode switches to ELEVATION")
	check(not editor_ui.active_box.visible, "Elevation interface hides top chooser panel per requirements")
	check(editor_ui.raise_button != null and editor_ui.raise_button.is_inside_tree(), "Raise button present in ELEVATION mode")
	check(editor_ui.smooth_button != null and editor_ui.smooth_button.is_inside_tree(), "Smooth button present in ELEVATION mode")

	editor_ui._set_sub_mode(WorldEditorClass.SubMode.OBJECT)
	check(editor_ui.editor.sub_mode == WorldEditorClass.SubMode.OBJECT, "Submode switches back to OBJECT")

	# Test terrain and elevation saving
	if world and "terrain_manager" in world and world.terrain_manager:
		var tm: TerrainManager = world.terrain_manager
		tm.elevation_grid_u = 16
		tm.elevation_grid_v = 16
		tm.terrain_grid_u = 16
		tm.terrain_grid_v = 16
		tm.elevation_data.resize(256)
		tm.terrain_data.resize(256)
		tm.elevation_data[0] = 77.5
		tm.terrain_data[0] = 4
		check(editor_ui.editor.save_edits() == OK, "save_edits saves terrain and elevation layers successfully")
		var reloaded_cfg = layer.active_map_config
		var reloaded_elev = Config.get_elevation_map_path(reloaded_cfg)
		var reloaded_terr = Config.get_terrain_map_path(reloaded_cfg)
		check(FileAccess.file_exists(reloaded_elev), "Elevation map file exists after save")
		check(FileAccess.file_exists(reloaded_terr), "Terrain map file exists after save")
		var read_tm = TerrainManager.new()
		read_tm.configure(reloaded_cfg)
		check(read_tm.load_elevation(reloaded_elev), "Saved elevation layer loads from disk")
		check(is_equal_approx(read_tm.elevation_data[0], 77.5), "Saved elevation sample value survives reload")
		check(read_tm.load_terrain(reloaded_terr), "Saved terrain layer loads from disk")
		check(read_tm.terrain_data[0] == 4, "Saved terrain sample value survives reload")

		# Test distance scaling for painter mode
		editor_ui._set_sub_mode(WorldEditorClass.SubMode.PAINTER)
		editor_ui.editor.selected_biome_id = 9
		editor_ui.editor.brush_radius_m = 300.0
		tm.terrain_grid_u = 128
		tm.terrain_grid_v = 128
		tm.terrain_data.resize(128 * 128)
		tm.terrain_data.fill(0)
		player.camera.global_position = Vector3(0, 500, 0)
		var hit_500 := {"position": Vector3(0, 0, 0)}
		editor_ui.editor.paint_terrain(hit_500)
		var count_500 := 0
		for cell in tm.terrain_data:
			if cell == 9: count_500 += 1

		tm.terrain_data.fill(0)
		player.camera.global_position = Vector3(0, 2000, 0)
		var hit_2000 := {"position": Vector3(0, 0, 0)}
		editor_ui.editor.paint_terrain(hit_2000)
		var count_2000 := 0
		for cell in tm.terrain_data:
			if cell == 9: count_2000 += 1

		check(count_2000 > count_500, "Painter area scales up with distance (2000m paints larger area than 500m)")

		# Test replacing terrain ground texture image
		var test_tex_path := "res://build/test_replace_texture.png"
		var dummy_img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		dummy_img.fill(Color.GREEN)
		dummy_img.save_png(test_tex_path)
		var cat_size_before: int = editor_ui.editor.texture_catalog.size()
		if cat_size_before > 0:
			var old_path: String = str(editor_ui.editor.texture_catalog[0].get("path", ""))
			var replace_ok: bool = editor_ui.editor.replace_ground_texture(0, test_tex_path)
			check(replace_ok, "replace_ground_texture executes successfully")
			check(editor_ui.editor.texture_catalog.size() >= cat_size_before, "Texture catalog size valid after replace")
			var new_path: String = str(editor_ui.editor.texture_catalog[0].get("path", ""))
			check(new_path != old_path and new_path.find("test_replace_texture.png") != -1, "Target biome texture path updated to replaced texture file")
			var rotate_ok: bool = editor_ui.editor.set_biome_rotate(0, false)
			check(rotate_ok, "set_biome_rotate disables rotation")
			check(editor_ui.editor.texture_catalog[0].rotate == false, "Texture catalog reflects disabled rotation flag")
			editor_ui.editor.set_biome_rotate(0, true)
			check(editor_ui.editor.texture_catalog[0].rotate == true, "set_biome_rotate enables rotation back")
			editor_ui.editor.replace_ground_texture(0, old_path)

	layer.set_meta("saved_player_spawn", {})
	player.reset_to_spawn()
	check(not player.global_position.is_equal_approx(saved_transform.origin), "Missing saved location falls back to map spawn")
	controls.edit_btn.button_pressed = false
	check(editor_ui.editor.place() == null, "Cannot place outside edit mode")
	check(not editor_ui.active_box.visible and not editor_ui.actions.visible, "Exiting edit mode hides editor controls")
	controls._handle_touch_start(12, joy)
	controls.hide()
	check(player.input_axis == Vector2.ZERO and controls.joystick_touch_id == -1, "Hiding UI clears active gestures")
	controls.free()
	world.free()
	print("[RESULT] Edit controls test failures: ", failures)
	quit(0 if failures == 0 else 1)


func screenshot(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--screenshots"):
		return
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png("res://build/%s.png" % label) == OK, "Screenshot saved")

func _catalog_index(catalog: Array[Dictionary], id: String) -> int:
	for i in catalog.size():
		if catalog[i].id == id:
			return i
	return -1
