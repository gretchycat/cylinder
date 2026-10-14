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

func find_button_text(root_node: Node, target_text: String) -> Button:
	if root_node is Button and (root_node as Button).text == target_text:
		return root_node as Button
	for child in root_node.get_children():
		var found := find_button_text(child, target_text)
		if found:
			return found
	return null

func find_button_name_prefix(root_node: Node, prefix: String) -> Button:
	if root_node is Button and root_node.name.begins_with(prefix):
		return root_node as Button
	for child in root_node.get_children():
		var found := find_button_name_prefix(child, prefix)
		if found:
			return found
	return null

func find_first_hslider(root_node: Node) -> HSlider:
	for child in root_node.get_children(true):
		if child is HSlider:
			return child as HSlider
		var found := find_first_hslider(child)
		if found:
			return found
	return null

func count_button_text(root_node: Node, target_text: String) -> int:
	var count := 1 if root_node is Button and (root_node as Button).text == target_text else 0
	for child in root_node.get_children():
		count += count_button_text(child, target_text)
	return count

func has_label_text(root_node: Node, target_text: String) -> bool:
	if root_node is Label and (root_node as Label).text == target_text:
		return true
	for child in root_node.get_children():
		if has_label_text(child, target_text):
			return true
	return false

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
	var explicit_transform_record := {
		"id": "explicit-transform-authority-check",
		"asset": "campfire",
		"transform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 1234, 2345, 678],
		"ground_offset_m": -25.0
	}
	var explicit_transform_object := ObjectFactory.create(map_doc, explicit_transform_record, world)
	check(explicit_transform_object.transform.origin.is_equal_approx(Vector3(1234, 2345, 678)), "Explicit saved object transform remains authoritative with a live world")
	explicit_transform_object.free()
	var env = scene.get_node("WorldEnvironment").environment
	check(env.background_color.is_equal_approx(MapConfig.color(world.active_map_config.environment.sky_color)), "Map sky color applied")
	check(world.water_material.get_shader_parameter("deep_color").is_equal_approx(MapConfig.color(world.active_map_config.environment.water.deep_color)), "Map water color applied")
	var controls = scene.find_child("TouchControls", true, false)
	controls.editor_ui.set_edit_mode(true)
	var ui = controls.editor_ui
	ui.set_regen_dialog_open(true)
	check(ui.map_editor.find_child("RegenerateMapButton", true, false) == null, "Map configuration has no redundant standalone Regenerate Map button")
	ui.map_editor._show_category_page("terrain")
	check(find_button_text(ui.map_editor, "Open Regeneration Workbench…") != null, "Terrain settings retain the regeneration workbench entry")
	ui.map_editor._close_category_page()
	ui._on_generate_biome_pressed()
	await process_frame
	await process_frame
	check(ui.regen_workbench.visible, "Regenerate Map opens the regeneration workbench")
	check(ui.regen_workbench.size.y <= 420.0, "Regeneration workbench has a bounded initial height")
	check(ui.gen_progress_bar is ProgressBar and ui.reload_progress_bar is ProgressBar and ui.progress_log is RichTextLabel and has_label_text(ui.progress_dialog, "LIVE GENERATION LOG"), "Progress view includes progress bars and an always-visible live log")
	ui._show_progress_dialog()
	await process_frame
	var progress_rect: Rect2 = ui.progress_dialog.get_global_rect()
	check(ui.progress_dialog.visible and ui.progress_dialog.z_index == RenderingServer.CANVAS_ITEM_Z_MAX and progress_rect.size.x > 100.0 and ui.progress_log.visible, "Progress panel is frontmost, sized, and visibly contains the live log")
	ui.progress_dialog.visible = false
	check(ui.regen_elevations_check.button_pressed and ui.regen_terrain_check.button_pressed and ui.regen_smooth_check.button_pressed and ui.regen_clear_objects_check.button_pressed and ui.regen_add_objects_check.button_pressed and ui.regen_normalize_check.button_pressed, "Workbench defaults to Select All")
	check(ui.regen_smooth_check is CheckBox and ui.regen_clear_objects_check is CheckBox and ui.regen_add_objects_check is CheckBox and ui.regen_normalize_check is CheckBox, "Workbench exposes smoothing, object clearing, placement, and height normalization")
	check(ui.regen_clear_objects_check.get_index() < ui.regen_add_objects_check.get_index(), "Clear existing objects appears before generating or adding objects")
	var run_sequence_button := ui.regen_workbench.find_child("RunSelectedRegeneration", true, false) as Button
	var workbench_rect: Rect2 = ui.regen_workbench.get_global_rect()
	check(run_sequence_button != null and run_sequence_button.custom_minimum_size.y >= 48 and run_sequence_button.get_global_rect().end.y <= workbench_rect.end.y + 1.0, "Run sequence button stays visible at the bottom of the workbench")
	find_button_text(ui.regen_workbench, "Select None").pressed.emit()
	check(not ui.regen_elevations_check.button_pressed and not ui.regen_terrain_check.button_pressed and not ui.regen_smooth_check.button_pressed and not ui.regen_clear_objects_check.button_pressed and not ui.regen_add_objects_check.button_pressed and not ui.regen_normalize_check.button_pressed, "Select None clears every regeneration operation")
	find_button_text(ui.regen_workbench, "Select All").pressed.emit()
	check(ui.regen_elevations_check.button_pressed and ui.regen_terrain_check.button_pressed and ui.regen_smooth_check.button_pressed and ui.regen_clear_objects_check.button_pressed and ui.regen_add_objects_check.button_pressed and ui.regen_normalize_check.button_pressed, "Select All enables every regeneration operation")
	ui.regen_workbench.visible = false
	var smoothing_samples := PackedFloat32Array()
	smoothing_samples.resize(12)
	smoothing_samples[0] = 1.0
	var smoothing_image := Image.create_from_data(4, 3, false, Image.FORMAT_RF, smoothing_samples.to_byte_array())
	ui._smooth_elevation_image(smoothing_image)
	check(is_equal_approx(smoothing_image.get_pixel(0, 0).r, smoothing_image.get_pixel(3, 0).r), "Smoothing pass wraps across the cylinder circumference seam")
	var normalize_doc: Dictionary = world.active_map_config.duplicate(true)
	normalize_doc.geometry.elevation_variance_m = 100.0
	normalize_doc.geometry.water_sea_level_m = 0.0
	normalize_doc.biomes = {"test": {"raster_id": 5, "elevation_range_m": [20.0, 80.0], "submerged": false}}
	var normalize_height := Image.create(2, 2, false, Image.FORMAT_RF)
	normalize_height.fill(Color(0.5, 0, 0, 1))
	var normalize_terrain := Image.create(2, 2, false, Image.FORMAT_L8)
	normalize_terrain.fill(Color(5.0 / 255.0, 0, 0, 1))
	ui._normalize_elevations_to_terrain(normalize_height, normalize_terrain, normalize_doc)
	check(is_equal_approx(normalize_height.get_pixel(0, 0).r, 0.5), "Height normalization maps samples into their categorical biome elevation ranges")
	await process_frame
	check(ui.map_editor.document.biomes.size() == world.active_map_config.biomes.size(), "Map editor opens with actual biomes")
	check(ui.map_button.text == "MAP", "Map editor button uses the neutral MAP label")
	var danger_button := ui.map_editor.body.get_node_or_null("RegenerateMapButton") as Button
	check(danger_button != null and danger_button.get_index() == ui.map_editor.body.get_child_count() - 1, "Destructive regenerate action is last on map overview")
	var danger_style := danger_button.get_theme_stylebox("normal") as StyleBoxFlat if danger_button else null
	check(danger_style != null and danger_style.bg_color.r > danger_style.bg_color.g, "Regenerate action is visibly red")
	var biome_category := ui.map_editor.body.find_child("MapCategory_biomes", true, false) as Button
	if biome_category:
		biome_category.pressed.emit()
	await process_frame
	var biome_page: Node = ui.map_editor.biome_editor_screen.get_child(0) if ui.map_editor.biome_editor_screen.get_child_count() > 0 else null
	var biome_detail: Node = biome_page.find_child("SelectedBiomeEditor", true, false) if biome_page else null
	check(ui.map_editor.biome_editor_screen.visible and ui.map_editor.biome_picker != null and biome_detail != null, "Biomes category keeps the selected biome editor inline below its list")
	check(biome_detail != null and biome_detail.find_child("SelectedGroundTexturePreview", true, false) is TextureRect, "Inline biome editor previews its selected ground texture")
	check(count_button_text(biome_page, "Save") == 1, "Biome editor has one Save button at the bottom")
	var test_biome: Dictionary = ui.map_editor.document.biomes[ui.map_editor.selected_biome_id]
	var original_clutter_rules: Array = test_biome.clutter.duplicate(true)
	var original_object_rules: Array = test_biome.objects.duplicate(true)
	var fixture_clutter_id: String = ui.map_editor.document.ground_clutter.models.keys()[0]
	var fixture_object_id: String = ui.map_editor.document.objects.model_catalog.keys()[0]
	test_biome.clutter = [{"model": fixture_clutter_id, "density_per_m2": 0.01, "scale_range": [0.8, 1.2], "palette": [[0.9, 0.2, 0.15, 1.0]]}]
	test_biome.objects = [{"asset": fixture_object_id, "density_per_sq_km": 1.0, "scale_range": [0.8, 1.2]}]
	ui.map_editor._build_biome(ui.map_editor.selected_biome_id, ui.map_editor.biome_detail_container)
	var clutter_row_button := find_button_name_prefix(ui.map_editor.biome_detail_container, "BiomeAssetRule_")
	var clutter_row_preview: Node = clutter_row_button.find_child("BiomeAssetRulePreview", true, false) if clutter_row_button else null
	var clutter_delete_button: Button = clutter_row_button.get_parent().get_child(1) as Button if clutter_row_button else null
	var red_delete: StyleBoxFlat = clutter_delete_button.get_theme_stylebox("normal") as StyleBoxFlat if clutter_delete_button else null
	check(clutter_row_preview != null and clutter_delete_button != null and red_delete != null and red_delete.bg_color.r > red_delete.bg_color.g, "Clutter rule row has a preview and red delete button")
	if clutter_row_button:
		clutter_row_button.pressed.emit()
		await process_frame
	check(has_label_text(ui.map_editor.biome_detail_container, "CLUTTER DETAILS · " + fixture_clutter_id), "Tapping clutter preview/name opens its detail editor")
	var palette_swatches: Node = ui.map_editor.biome_detail_container.find_child("ClutterColorSwatches", true, false)
	var palette_color := palette_swatches.get_node_or_null("ClutterPaletteColor_0") as ColorPickerButton if palette_swatches else null
	var palette_add := ui.map_editor.biome_detail_container.find_child("AddClutterPaletteColor", true, false) as Button
	var palette_menu := palette_color.get_node_or_null("PaletteColorContextMenu") as PopupMenu if palette_color else null
	check(has_label_text(ui.map_editor.biome_detail_container, "Palette") and palette_color != null and palette_add != null and palette_menu != null and palette_menu.get_item_text(0) == "Delete color", "Clutter colors show one Palette section, tappable swatches, add, and context-delete")
	if palette_color:
		ColorPickerUI._configure_created_picker(palette_color)
		var picker_slider := find_first_hslider(palette_color.get_picker())
		check(picker_slider != null and picker_slider.custom_minimum_size.y >= 24.0, "Color-picker internal slider rows receive scaled touch height")
	clutter_delete_button = find_button_name_prefix(ui.map_editor.biome_detail_container, "DeleteBiomeAssetRule")
	if clutter_delete_button:
		clutter_delete_button.pressed.emit()
		await process_frame
	check(test_biome.clutter.is_empty(), "Clutter red X deletes only its selected rule")
	var object_row_button := find_button_name_prefix(ui.map_editor.biome_detail_container, "BiomeAssetRule_")
	if object_row_button:
		object_row_button.pressed.emit()
		await process_frame
	check(has_label_text(ui.map_editor.biome_detail_container, "MAP OBJECT DETAILS · " + fixture_object_id), "Tapping map-object preview/name opens its detail editor")
	var object_delete_button := find_button_name_prefix(ui.map_editor.biome_detail_container, "DeleteBiomeAssetRule")
	if object_delete_button:
		object_delete_button.pressed.emit()
		await process_frame
	check(test_biome.objects.is_empty(), "Map-object red X deletes only its selected rule")
	test_biome.clutter = original_clutter_rules
	test_biome.objects = original_object_rules
	ui.map_editor.selected_rule_type = ""
	ui.map_editor.selected_rule_index = -1
	ui.map_editor._build_biome(ui.map_editor.selected_biome_id, ui.map_editor.biome_detail_container)
	biome_detail = ui.map_editor.biome_detail_container
	var selector_ui: Variant = ui
	var selector_checked := false
	if biome_detail:
		var clutter_button := find_button_text(biome_detail, "Select clutter model…")
		if clutter_button:
			clutter_button.pressed.emit()
			await process_frame
			var none_card: VBoxContainer = selector_ui.palette_grid.get_child(0) as VBoxContainer if selector_ui.palette_grid.get_child_count() > 0 else null
			var none_button: Button = none_card.get_child(0) as Button if none_card else null
			var clutter_before_none: int = ui.map_editor.document.biomes[ui.map_editor.selected_biome_id].clutter.size()
			var empty_option_works := none_button != null and none_button.text == "NONE"
			if empty_option_works:
				none_button.pressed.emit()
				await process_frame
				empty_option_works = ui.map_editor.document.biomes[ui.map_editor.selected_biome_id].clutter.size() == clutter_before_none
			check(empty_option_works, "Empty clutter choice leaves the biome rule list unchanged")
			clutter_button = find_button_text(ui.map_editor.biome_detail_container, "Select clutter model…")
			if clutter_button:
				clutter_button.pressed.emit()
				await process_frame
			var preview_count := 0
			for preview in selector_ui.palette_grid.get_children():
				if preview is VBoxContainer and preview.find_child("AssetMiniPreview", true, false):
					preview_count += 1
			selector_checked = selector_ui.palette.visible and selector_ui.palette_title_label.text == "SELECT CLUTTER MODEL" and preview_count > 0
			selector_ui._cancel_map_asset_selection()
			await process_frame
	check(selector_checked, "Clutter selection uses the shared mini-preview asset palette")
	var object_rule_button := find_button_text(ui.map_editor.biome_detail_container, "Select object for rule…")
	var object_empty_works := false
	if object_rule_button:
		var object_rule_count: int = ui.map_editor.document.biomes[ui.map_editor.selected_biome_id].objects.size()
		object_rule_button.pressed.emit()
		await process_frame
		var object_none_card: VBoxContainer = ui.palette_grid.get_child(0) as VBoxContainer if ui.palette_grid.get_child_count() > 0 else null
		var object_none_button: Button = object_none_card.get_child(0) as Button if object_none_card else null
		if object_none_button and object_none_button.text == "NONE":
			object_none_button.pressed.emit()
			await process_frame
			object_empty_works = ui.map_editor.document.biomes[ui.map_editor.selected_biome_id].objects.size() == object_rule_count
	check(object_empty_works, "Empty generated-object choice leaves the biome rule list unchanged")
	var climate_category := ui.map_editor.body.find_child("MapCategory_climate", true, false) as Button
	if climate_category:
		climate_category.pressed.emit()
	await process_frame
	var climate_page: Node = ui.map_editor.biome_editor_screen.get_child(0) if ui.map_editor.biome_editor_screen.get_child_count() > 0 else null
	check(ui.map_editor.biome_editor_screen.visible and climate_page != null and climate_page.get_child(1).text == "Climate" and find_button_text(climate_page, "‹ Back") != null and find_button_text(climate_page, "CLOSE") == null, "Climate category has a title, one back action, and no duplicate close control")
	check(count_button_text(climate_page, "Save") == 1, "Climate page uses the same single Save action")
	ui.map_editor._show_category_page("report")
	await process_frame
	var report_page: Node = ui.map_editor.biome_editor_screen.get_child(0) if ui.map_editor.biome_editor_screen.get_child_count() > 0 else null
	check(report_page != null and find_button_text(report_page, "Open Regeneration Workbench") == null, "Generation report has no separate workbench/log launcher")
	ui.map_editor._show_category_page("assets")
	await process_frame
	var assets_page: Node = ui.map_editor.biome_editor_screen.get_child(0) if ui.map_editor.biome_editor_screen.get_child_count() > 0 else null
	var terrain_interface_button := find_button_text(assets_page, "Open Terrain Interface") if assets_page else null
	var objects_interface_button := find_button_text(assets_page, "Open Objects Interface") if assets_page else null
	check(terrain_interface_button != null and objects_interface_button != null and find_button_text(assets_page, "Import object (.glb)") == null, "Assets & Objects page only links to the existing terrain and objects interfaces")
	if terrain_interface_button:
		terrain_interface_button.pressed.emit()
		await process_frame
	check(ui.palette_open and ui.editor.sub_mode == WorldEditor.SubMode.PAINTER and not ui.regen_open, "Terrain interface launcher opens terrain editing")
	ui.set_palette_open(false)
	ui.set_regen_dialog_open(true)
	ui.map_editor._show_category_page("assets")
	await process_frame
	assets_page = ui.map_editor.biome_editor_screen.get_child(0) if ui.map_editor.biome_editor_screen.get_child_count() > 0 else null
	objects_interface_button = find_button_text(assets_page, "Open Objects Interface") if assets_page else null
	if objects_interface_button:
		objects_interface_button.pressed.emit()
		await process_frame
	check(ui.palette_open and ui.editor.sub_mode == WorldEditor.SubMode.OBJECT and not ui.regen_open, "Objects interface launcher opens object editing")
	ui.set_palette_open(false)
	ui.set_regen_dialog_open(true)
	ui.map_editor._close_category_page()
	for size_value in [Vector2i(320,640), Vector2i(480,900), Vector2i(1280,720)]:
		root.size = size_value
		await process_frame
		await process_frame
		var screen_rect = ui.regen_dialog.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, ui.regen_dialog.size)
		var viewport_rect = root.get_visible_rect()
		check(screen_rect.position.x >= 0 and screen_rect.end.x <= viewport_rect.end.x, "Map editor fits viewport width " + str(size_value.x))
	ui.set_palette_open(true)
	await process_frame
	for viewport_width in [320.0, 480.0]:
		root.size.x = int(viewport_width)
		await process_frame
		var palette_rect: Rect2 = ui.palette.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, ui.palette.size)
		var visible_rect := root.get_visible_rect()
		check(palette_rect.position.x >= 0 and palette_rect.end.x <= visible_rect.end.x, "Object/texture selector fits viewport width " + str(int(viewport_width)))
	ui.set_clutter_dialog_open(true)
	await process_frame
	var clutter_rect: Rect2 = ui.clutter_dialog.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, ui.clutter_dialog.size)
	check(clutter_rect.position.x >= 0 and clutter_rect.end.x <= root.get_visible_rect().end.x, "Clutter window fits viewport width")
	ui.set_clutter_dialog_open(false)
	ui.set_palette_open(false)
	ui.set_regen_dialog_open(true)

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
	var terrain_manager_before_definition_save = world.terrain_manager
	ui.map_editor.document.environment.water.deep_color = [0.1,0.2,0.4,0.6]
	await ui._save_map_definition()
	check(world.water_material.get_shader_parameter("deep_color").is_equal_approx(Color(0.1,0.2,0.4,0.6)), "Definition save applies edited water color")
	check(is_same(world.terrain_manager, terrain_manager_before_definition_save), "Environment-only save keeps the loaded terrain layer instance")
	check(not ui.progress_dialog.visible, "Definition-save progress dialog closes after reload")
	var saved_map_directory: String = world.active_map_config.map_directory
	await ui._save_map_definition()
	check(ui.map_editor.message.text == "No changes to save" and world.active_map_config.map_directory == saved_map_directory, "Unchanged map save skips package copy and world reload")
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
