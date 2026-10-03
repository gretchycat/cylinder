extends Control

const Editor = preload("res://scripts/world_editor.gd")
const Preview = preload("res://scripts/object_preview.gd")

signal palette_visibility_changed(open: bool)
var editor: Editor
var active_box: PanelContainer
var actions: HBoxContainer
var status_label: Label
var current_name: Label
var current_preview: Preview
var palette: PanelContainer
var palette_grid: GridContainer
var palette_scroll: ScrollContainer
var palette_open := false
var previews: Array[Preview] = []
var selection_buttons: Array[Button] = []
var place_button: Button
var remove_button: Button
var select_button: Button
var save_button: Button
var regen_button: Button

# Map Regeneration UI Elements
var map_editor: VBoxContainer
var object_tint_picker: ColorPickerButton
var light_tint_picker: ColorPickerButton
var regen_dialog: PanelContainer
var confirm_dialog: PanelContainer
var progress_dialog: PanelContainer
var gen_progress_bar: ProgressBar
var reload_progress_bar: ProgressBar
var progress_status_label: Label
var regen_open := false
var biome_sliders: Dictionary = {}
var hydrology_sliders: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor = Editor.new()
	add_child(editor)
	_build_active_object()
	_build_actions()
	_build_palette()
	_build_regen_dialog()
	_build_confirm_dialog()
	_build_progress_dialog()
	resized.connect(_layout)
	_layout()
	set_edit_mode(false)

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(96, 44)
	button.pressed.connect(callback)
	return button

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.09, 0.96)
	style.border_color = Color(0.3, 0.55, 0.7, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _build_active_object() -> void:
	active_box = PanelContainer.new()
	active_box.name = "ActiveObject"
	active_box.add_theme_stylebox_override("panel", _panel_style())
	add_child(active_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	active_box.add_child(row)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(72, 72)
	frame.add_theme_stylebox_override("panel", _panel_style())
	row.add_child(frame)
	current_preview = Preview.new()
	frame.add_child(current_preview)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	current_name = Label.new()
	current_name.add_theme_font_size_override("font_size", 13)
	column.add_child(current_name)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	select_button = _button("SELECT", func(): set_palette_open(true))
	select_button.custom_minimum_size.x = 80
	buttons.add_child(select_button)
	save_button = _button("SAVE", func():
		set_regen_dialog_open(true)
		map_editor.map_name.grab_focus())
	save_button.custom_minimum_size.x = 80
	buttons.add_child(save_button)

func _build_actions() -> void:
	actions = HBoxContainer.new()
	actions.name = "EditActions"
	actions.add_theme_constant_override("separation", 8)
	add_child(actions)
	place_button = _button("PLACE", func():
		editor.place()
		status_label.text = editor.status)
	remove_button = _button("REMOVE", func():
		editor.remove()
		status_label.text = editor.status)
	regen_button = _button("REGEN MAP", func():
		set_regen_dialog_open(true))

	for button in [place_button, remove_button, regen_button]:
		button.custom_minimum_size = Vector2(96, 56)
		actions.add_child(button)

	status_label = Label.new()
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(status_label)

func _build_palette() -> void:
	palette = PanelContainer.new()
	palette.name = "ObjectPalette"
	palette.add_theme_stylebox_override("panel", _panel_style())
	add_child(palette)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	palette.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "SELECT OBJECT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("IMPORT", func():
		map_editor.expanded["Object palette & imports"] = true
		map_editor.rebuild()
		set_regen_dialog_open(true)))
	header.add_child(_button("CLOSE", func(): set_palette_open(false)))
	var tint_row = HBoxContainer.new()
	column.add_child(tint_row)
	for tint_title in ["Object RGBA", "Light RGBA"]:
		var picker = ColorPickerButton.new()
		picker.text = tint_title
		picker.edit_alpha = true
		picker.color = Color.WHITE
		picker.custom_minimum_size = Vector2(100, 44)
		tint_row.add_child(picker)
		if tint_title == "Object RGBA":
			object_tint_picker = picker
		else:
			light_tint_picker = picker
	tint_row.add_child(_button("TINT AIMED OBJECT", func():
		editor.tint_target(object_tint_picker.color, light_tint_picker.color)
		status_label.text = editor.status))
	palette_scroll = ScrollContainer.new()
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(palette_scroll)
	palette_grid = GridContainer.new()
	palette_grid.add_theme_constant_override("h_separation", 10)
	palette_grid.add_theme_constant_override("v_separation", 10)
	palette_scroll.add_child(palette_grid)

func _build_regen_dialog() -> void:
	regen_dialog = PanelContainer.new()
	regen_dialog.add_theme_stylebox_override("panel", _panel_style())
	add_child(regen_dialog)
	var column = VBoxContainer.new()
	regen_dialog.add_child(column)
	column.add_child(_button("CLOSE MAP EDITOR", func(): set_regen_dialog_open(false)))
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	map_editor = preload("res://scripts/map_editor_panel.gd").new()
	scroll.add_child(map_editor)
	map_editor.generate_requested.connect(_on_generate_biome_pressed)
	map_editor.save_requested.connect(_save_map_definition)
	map_editor.save_as_requested.connect(func(): await _save_map_definition(true))
	map_editor.load_requested.connect(_activate_map)
	map_editor.new_requested.connect(_new_map)
	map_editor.import_map_requested.connect(_import_map)
	map_editor.export_map_requested.connect(_export_map)
	regen_dialog.visible = false

func _build_confirm_dialog() -> void:
	confirm_dialog = PanelContainer.new()
	confirm_dialog.name = "ConfirmRegenDialog"
	confirm_dialog.add_theme_stylebox_override("panel", _panel_style())
	add_child(confirm_dialog)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	confirm_dialog.add_child(column)

	var title := Label.new()
	title.text = "CONFIRM MAP REGENERATION"
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var warn := Label.new()
	warn.text = "Are you sure? Regenerating will CLEAR all current terrain, elevation, and placed objects, and rebuild the world using the configured biome sliders."
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.add_theme_font_size_override("font_size", 12)
	column.add_child(warn)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)

	var cancel_btn := _button("CANCEL", func(): confirm_dialog.visible = false)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cancel_btn)

	var yes_btn := Button.new()
	yes_btn.text = "YES, CLEAR & REGENERATE"
	yes_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes_btn.custom_minimum_size = Vector2(0, 44)
	var red_style := StyleBoxFlat.new()
	red_style.bg_color = Color(0.85, 0.15, 0.15, 0.95)
	red_style.set_corner_radius_all(6)
	yes_btn.add_theme_stylebox_override("normal", red_style)
	yes_btn.add_theme_color_override("font_color", Color.WHITE)
	yes_btn.pressed.connect(_execute_map_regeneration)
	row.add_child(yes_btn)

	confirm_dialog.visible = false

func _build_progress_dialog() -> void:
	progress_dialog = PanelContainer.new()
	progress_dialog.name = "ProgressDialog"
	progress_dialog.add_theme_stylebox_override("panel", _panel_style())
	add_child(progress_dialog)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	progress_dialog.add_child(column)

	var title := Label.new()
	title.text = "REGENERATING WORLD MAP"
	title.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	# Bar 1 Label & Progress Bar
	var l1 := Label.new()
	l1.text = "1. Terrain & Biomes Generation"
	l1.add_theme_font_size_override("font_size", 11)
	l1.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	column.add_child(l1)

	gen_progress_bar = ProgressBar.new()
	gen_progress_bar.custom_minimum_size = Vector2(360, 20)
	gen_progress_bar.min_value = 0.0
	gen_progress_bar.max_value = 100.0
	gen_progress_bar.value = 0.0
	gen_progress_bar.show_percentage = true

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.12, 0.18)
	bg_style.set_corner_radius_all(4)

	var fill_style1 := StyleBoxFlat.new()
	fill_style1.bg_color = Color(0.2, 0.65, 0.95)
	fill_style1.set_corner_radius_all(4)

	gen_progress_bar.add_theme_stylebox_override("background", bg_style)
	gen_progress_bar.add_theme_stylebox_override("fill", fill_style1)
	column.add_child(gen_progress_bar)

	# Bar 2 Label & Progress Bar
	var l2 := Label.new()
	l2.text = "2. World Reload & 3D Objects Spawning"
	l2.add_theme_font_size_override("font_size", 11)
	l2.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	column.add_child(l2)

	reload_progress_bar = ProgressBar.new()
	reload_progress_bar.custom_minimum_size = Vector2(360, 20)
	reload_progress_bar.min_value = 0.0
	reload_progress_bar.max_value = 100.0
	reload_progress_bar.value = 0.0
	reload_progress_bar.show_percentage = true

	var fill_style2 := StyleBoxFlat.new()
	fill_style2.bg_color = Color(0.25, 0.85, 0.55)
	fill_style2.set_corner_radius_all(4)

	reload_progress_bar.add_theme_stylebox_override("background", bg_style)
	reload_progress_bar.add_theme_stylebox_override("fill", fill_style2)
	column.add_child(reload_progress_bar)

	progress_status_label = Label.new()
	progress_status_label.text = "Initializing map generation..."
	progress_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_status_label.add_theme_font_size_override("font_size", 12)
	progress_status_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	column.add_child(progress_status_label)

	progress_dialog.visible = false

func _on_generate_biome_pressed() -> void:
	confirm_dialog.visible = true

func _execute_map_regeneration() -> void:
	if str(map_editor.document.get("name", "")).strip_edges().is_empty():
		_map_failure("Give the map a name before generating")
		return
	confirm_dialog.visible = false
	progress_dialog.visible = true
	gen_progress_bar.value = 0
	reload_progress_bar.value = 0
	var generator = preload("res://scripts/map_generator.gd")
	var cb = func(value: float, message: String):
		gen_progress_bar.value = value * 100
		progress_status_label.text = message
		await get_tree().process_frame
	var result = await generator.generate(map_editor.document, cb)
	if result.has("error"):
		_map_failure(result.error)
		return
	var directory = MapConfig.new_user_directory("generated")
	await cb.call(0.93, "Saving generated map")
	if not generator.save_generated_map_package(result, directory):
		_map_failure("Unable to save generated map: " + MapConfig.last_error)
		return
	var previous: Dictionary = map_editor.document
	map_editor.document = result.document
	if not map_editor.package_imports(directory) or MapConfig.save_document(map_editor.document, directory) != OK:
		map_editor.document = previous
		_map_failure("Unable to package imported assets")
		return
	await _activate_map(directory)

func _save_map_definition(as_new: bool = false) -> bool:
	if str(map_editor.document.get("name", "")).strip_edges().is_empty():
		_map_failure("Give the map a name before saving")
		return false
	var error = MapConfig.validate(map_editor.document)
	if not error.is_empty():
		_map_failure(error)
		return false
	var world = get_tree().get_first_node_in_group("cylinder_world")
	var refs = get_tree().get_first_node_in_group("reference_objects")
	var directory = MapConfig.new_user_directory("edited")
	if MapConfig.copy_directory(world.active_map_config.map_directory, directory) != OK:
		_map_failure("Unable to prepare map save: " + MapConfig.last_error)
		return false
	var original_document = map_editor.document.duplicate(true)
	if as_new:
		map_editor.document.world_id = MapConfig.new_map_id()
	if not map_editor.package_imports(directory) or MapConfig.save_document(map_editor.document, directory) != OK:
		map_editor.document = original_document
		map_editor.rebuild()
		_map_failure("Unable to save definition and assets")
		return false
	if preload("res://scripts/world_edit_storage.gd").save(refs, directory.path_join(map_editor.document.files.object_map), editor.player) != OK:
		map_editor.document = original_document
		map_editor.rebuild()
		_map_failure("Unable to save placed objects")
		return false
	var activated = await _activate_map(directory)
	if not activated:
		var failure_message = map_editor.message.text
		map_editor.document = original_document
		map_editor.rebuild()
		_map_failure(failure_message)
	return activated

func _new_map() -> void:
	var directory = MapConfig.create_from_template()
	if directory.is_empty():
		_map_failure(MapConfig.last_error)
		return
	await _activate_map(directory)

func _import_map(path: String) -> void:
	var directory = preload("res://scripts/map_library.gd").import_map(path)
	if directory.is_empty():
		_map_failure("Import failed: " + MapConfig.last_error)
		return
	await _activate_map(directory)

func _export_map(path: String) -> void:
	if not await _save_map_definition():
		return
	if preload("res://scripts/map_library.gd").export_map(map_editor.document.map_directory, path) != OK:
		_map_failure("Export failed: " + MapConfig.last_error)
		return
	map_editor.message.text = "Exported " + str(map_editor.document.name) + " to " + path

func _activate_map(directory: String) -> bool:
	var world = get_tree().get_first_node_in_group("cylinder_world")
	var previous_directory = world.map_package if world else ""
	if not world or not world.load_map_package(directory):
		_map_failure("Map failed validation: %s; current world preserved" % (world.map_load_error if world else "World is unavailable"))
		return false
	if MapConfig.activate(directory) != OK:
		world.load_map_package(previous_directory)
		_map_failure("Could not persist the active map selection")
		return false
	reload_progress_bar.value = 35
	var clutter = get_tree().get_first_node_in_group("clutter_manager")
	if clutter:
		clutter.reload_clutter()
	var refs = get_tree().get_first_node_in_group("reference_objects")
	if refs:
		await refs.load_object_map_with_progress(MapConfig.get_object_map_path(world.active_map_config))
		preload("res://scripts/world_edit_storage.gd").restore(refs)
	if editor.player:
		editor.player.reset_to_spawn()
	map_editor.document = world.active_map_config.duplicate(true)
	map_editor.rebuild()
	editor.reload_catalog()
	for child in palette_grid.get_children():
		palette_grid.remove_child(child)
		child.queue_free()
	selection_buttons.clear()
	previews.clear()
	_update_current_object()
	reload_progress_bar.value = 100
	progress_dialog.visible = false
	status_label.text = "Map saved and loaded"
	map_editor.message.text = "Saved. Open the generation report to compare biome coverage."
	return true

func _map_failure(message: String) -> void:
	progress_dialog.visible = false
	status_label.text = message
	map_editor.message.text = message

func _populate_palette() -> void:
	if not selection_buttons.is_empty():
		return
	for index in range(editor.catalog.size()):
		var entry := editor.catalog[index]
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(128, 164)
		palette_grid.add_child(card)
		var button := _button("", _select.bind(index))
		button.custom_minimum_size = Vector2(128, 126)
		button.toggle_mode = true
		var normal_style := _panel_style()
		normal_style.bg_color = Color(0.09, 0.13, 0.18)
		button.add_theme_stylebox_override("normal", normal_style)
		var selected_style := normal_style.duplicate() as StyleBoxFlat
		selected_style.border_color = Color(0.35, 0.8, 1.0)
		selected_style.set_border_width_all(3)
		button.add_theme_stylebox_override("pressed", selected_style)
		button.tooltip_text = str(entry.get("name", "Object"))
		card.add_child(button)
		selection_buttons.append(button)
		var preview := Preview.new()
		button.add_child(preview)
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.offset_left = 6
		preview.offset_top = 6
		preview.offset_right = -6
		preview.offset_bottom = -6
		preview.show_model(entry.path)
		previews.append(preview)
		var label := Label.new()
		label.text = str(entry.get("name", "Object"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(label)

func _select(index: int) -> void:
	editor.selected_index = index
	_update_current_object()
	set_palette_open(false)

func _update_current_object() -> void:
	var entry := editor.current_object()
	if entry.is_empty():
		current_name.text = "No objects available"
		place_button.disabled = true
		select_button.disabled = true
		return
	current_name.text = str(entry.get("name", "Object"))
	current_preview.show_model(entry.path)
	for index in range(selection_buttons.size()):
		selection_buttons[index].set_pressed_no_signal(index == editor.selected_index)

func set_edit_mode(active: bool) -> void:
	editor.enabled = active
	set_palette_open(false)
	set_regen_dialog_open(false)
	active_box.visible = active
	actions.visible = active
	status_label.visible = active
	status_label.text = editor.status
	if active:
		_update_current_object()
	queue_redraw()

func set_palette_open(open: bool) -> void:
	palette_open = open and editor.enabled
	palette.visible = palette_open
	if palette_open:
		set_regen_dialog_open(false)
		var aimed = editor.target_object(editor.ray_hit())
		if aimed:
			object_tint_picker.color = aimed.tint
			light_tint_picker.color = aimed.light_color
		_populate_palette()
		for index in range(selection_buttons.size()):
			selection_buttons[index].set_pressed_no_signal(index == editor.selected_index)
		for preview in previews:
			preview.refresh()
	palette_visibility_changed.emit(palette_open or regen_open)
	queue_redraw()

func set_regen_dialog_open(open: bool) -> void:
	regen_open = open and editor.enabled
	regen_dialog.visible = regen_open
	palette_visibility_changed.emit(regen_open or palette_open)
	if regen_open:
		palette.visible = false
		palette_open = false
	queue_redraw()

func contains_ui_point(point: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	if palette_open or regen_open or (confirm_dialog and confirm_dialog.visible) or (progress_dialog and progress_dialog.visible):
		return true
	return editor.enabled and (active_box.get_global_rect().has_point(point) or actions.get_global_rect().has_point(point))

func _layout() -> void:
	if not active_box:
		return
	active_box.position = Vector2((size.x - 296) * 0.5, 64)
	active_box.size = Vector2(296, 88)
	actions.position = Vector2((size.x - 312) * 0.5, size.y - (360 if size.x < 640 else 84))
	status_label.position = Vector2(0, 158)
	status_label.size = Vector2(size.x, 24)
	palette.position = Vector2(20, 60)
	palette.size = Vector2(maxf(size.x - 40, 180), maxf(size.y - 80, 180))
	palette_grid.columns = maxi(1, int((palette.size.x - 44) / 138))

	if regen_dialog:
		regen_dialog.position = Vector2(maxf((size.x - minf(620, size.x - 20)) * 0.5, 10), 50)
		regen_dialog.size = Vector2(minf(620, size.x - 20), maxf(size.y - 100, 200))
	if confirm_dialog:
		confirm_dialog.position = Vector2(maxf((size.x - 360) * 0.5, 10), (size.y - 200) * 0.5)
		confirm_dialog.size = Vector2(minf(360, size.x - 20), 200)
	if progress_dialog:
		var dialog_w = minf(440, size.x - 20)
		var dialog_h = 230.0
		progress_dialog.position = Vector2((size.x - dialog_w) * 0.5, (size.y - dialog_h) * 0.5)
		progress_dialog.size = Vector2(dialog_w, dialog_h)
	queue_redraw()

func _draw() -> void:
	if not editor or not editor.enabled or palette_open or regen_open or (progress_dialog and progress_dialog.visible):
		return
	var center := size * 0.5
	for width in [4.0, 2.0]:
		var color := Color(0, 0, 0, 0.85) if width == 4.0 else Color.WHITE
		draw_line(center - Vector2(9, 0), center + Vector2(9, 0), color, width)
		draw_line(center - Vector2(0, 9), center + Vector2(0, 9), color, width)
