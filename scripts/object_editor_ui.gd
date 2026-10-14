extends Control

const Editor = preload("res://scripts/world_editor.gd")
const Preview = preload("res://scripts/object_preview.gd")
const ColorPickerUI = preload("res://scripts/color_picker_ui.gd")

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
var paint_button: Button
var raise_button: Button
var lower_button: Button
var smooth_button: Button
var brush_minus_btn: Button
var brush_plus_btn: Button
var save_button: Button
var map_button: Button
var replace_active_button: Button
var rotate_checkbox: CheckBox
var target_replace_texture_index: int = -1
var map_asset_selection_kind := ""
var map_asset_selection_callback: Callable
var map_asset_selection_previous_submode: int = Editor.SubMode.OBJECT
var map_asset_selection_previous_object_index := 0
var map_asset_selection_previous_texture_index := 0

# Submode Bar
var submode_bar: HBoxContainer
var obj_mode_btn: Button
var paint_mode_btn: Button
var elev_mode_btn: Button

# Palette & Import/Clutter elements
var texture_swatch: TextureRect
var palette_title_label: Label
var import_palette_btn: Button
var edit_clutter_btn: Button
var import_file_dialog: FileDialog
var current_import_mode: String = "object"
var collision_import_dialog: ConfirmationDialog
var pending_object_import_path: String = ""
var collision_import_checks: Dictionary = {}
var clutter_dialog: PanelContainer
var clutter_density_slider: HSlider
var clutter_density_label: Label

# Map Regeneration UI Elements
var map_editor: VBoxContainer
var object_tint_picker: ColorPickerButton
var light_tint_picker: ColorPickerButton
var regen_dialog: PanelContainer
var regen_workbench: PanelContainer
var progress_dialog: PanelContainer
var progress_title_label: Label
var progress_stage1_label: Label
var progress_stage2_label: Label
var gen_progress_bar: ProgressBar
var reload_progress_bar: ProgressBar
var progress_status_label: Label
var progress_log: RichTextLabel
var regen_elevations_check: CheckBox
var regen_terrain_check: CheckBox
var regen_smooth_check: CheckBox
var regen_clear_objects_check: CheckBox
var regen_add_objects_check: CheckBox
var regen_normalize_check: CheckBox
var regen_warning_label: Label
var regen_open := false
var biome_sliders: Dictionary = {}
var hydrology_sliders: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor = Editor.new()
	add_child(editor)
	_build_submode_bar()
	_build_active_object()
	_build_actions()
	_build_palette()
	_build_clutter_dialog()
	_build_collision_import_dialog()
	_build_regen_dialog()
	_build_regen_workbench()
	_build_progress_dialog()
	resized.connect(_layout)
	_layout()
	set_edit_mode(false)

func _process(_delta: float) -> void:
	if editor and editor.enabled:
		queue_redraw()


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

func _build_submode_bar() -> void:
	submode_bar = HBoxContainer.new()
	submode_bar.name = "SubmodeBar"
	submode_bar.add_theme_constant_override("separation", 6)
	add_child(submode_bar)

	obj_mode_btn = _button("OBJECTS", func(): _set_sub_mode(Editor.SubMode.OBJECT))
	paint_mode_btn = _button("PAINTER", func(): _set_sub_mode(Editor.SubMode.PAINTER))
	elev_mode_btn = _button("ELEVATION", func(): _set_sub_mode(Editor.SubMode.ELEVATION))

	map_button = _button("MAP", func(): set_regen_dialog_open(true))

	for btn in [obj_mode_btn, paint_mode_btn, elev_mode_btn, map_button]:
		btn.custom_minimum_size = Vector2(90, 36)
		submode_bar.add_child(btn)

func _set_sub_mode(mode: Editor.SubMode) -> void:
	if not editor:
		return
	editor.sub_mode = mode
	set_palette_open(false)
	_update_submode_buttons()
	_update_action_buttons()
	_update_active_box_content()
	queue_redraw()

func open_terrain_interface() -> void:
	_open_editor_interface(Editor.SubMode.PAINTER)

func open_objects_interface() -> void:
	_open_editor_interface(Editor.SubMode.OBJECT)

func _open_editor_interface(mode: Editor.SubMode) -> void:
	if not editor or not editor.enabled:
		return
	set_regen_dialog_open(false)
	_set_sub_mode(mode)
	set_palette_open(true)

func _update_submode_buttons() -> void:
	if not obj_mode_btn or not editor:
		return
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = Color(0.2, 0.6, 0.9, 0.95)
	active_style.set_corner_radius_all(6)
	var inactive_style := _panel_style()

	obj_mode_btn.add_theme_stylebox_override("normal", active_style if editor.sub_mode == Editor.SubMode.OBJECT else inactive_style)
	paint_mode_btn.add_theme_stylebox_override("normal", active_style if editor.sub_mode == Editor.SubMode.PAINTER else inactive_style)
	elev_mode_btn.add_theme_stylebox_override("normal", active_style if editor.sub_mode == Editor.SubMode.ELEVATION else inactive_style)
	map_button.add_theme_stylebox_override("normal", inactive_style)

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
	current_preview.gui_input.connect(_on_active_preview_gui_input)
	frame.add_child(current_preview)
	# ObjectPreview defaults to input-pass-through in _ready() so palette
	# previews remain visual-only. The active preview is the selector trigger.
	current_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	current_name = Label.new()
	current_name.add_theme_font_size_override("font_size", 13)
	column.add_child(current_name)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	replace_active_button = _button("REPLACE", func():
		if editor and editor.selected_texture_index >= 0:
			_open_replace_image_dialog(editor.selected_texture_index)
	)
	replace_active_button.custom_minimum_size.x = 80
	buttons.add_child(replace_active_button)

	rotate_checkbox = CheckBox.new()
	rotate_checkbox.text = "ROTATE"
	rotate_checkbox.tooltip_text = "Enable pseudo-random rotation and flipping to eliminate pattern repetition and moiré"
	rotate_checkbox.toggled.connect(func(toggled_on: bool):
		if editor and editor.selected_texture_index >= 0:
			editor.set_biome_rotate(editor.selected_texture_index, toggled_on)
			status_label.text = editor.status
	)
	buttons.add_child(rotate_checkbox)

	save_button = _button("SAVE", func():


		editor.save_edits()
		status_label.text = editor.status)
	save_button.custom_minimum_size.x = 80
	buttons.add_child(save_button)


func _on_active_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		set_palette_open(true)
		get_viewport().set_input_as_handled()

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

	paint_button = _button("PAINT", func():
		editor.paint_terrain()
		status_label.text = editor.status)

	raise_button = _button("RAISE", func():
		editor.modify_elevation(editor.ray_hit(), editor.elevation_step_m)
		status_label.text = editor.status)

	lower_button = _button("LOWER", func():
		editor.modify_elevation(editor.ray_hit(), -editor.elevation_step_m)
		status_label.text = editor.status)

	smooth_button = _button("SMOOTH", func():
		editor.smooth_elevation(editor.ray_hit())
		status_label.text = editor.status)

	brush_minus_btn = _button("SIZE -", func():
		editor.brush_radius_m = maxf(editor.brush_radius_m - 5.0, 5.0)
		var mult := 1.0 + clampf((editor.brush_radius_m - 5.0) / 70.0, 0.0, 1.0) * 8.0
		status_label.text = "Brush size: %.1fx (%d m)" % [mult, int(editor.brush_radius_m)]
		queue_redraw())

	brush_plus_btn = _button("SIZE +", func():
		editor.brush_radius_m = minf(editor.brush_radius_m + 5.0, 75.0)
		var mult := 1.0 + clampf((editor.brush_radius_m - 5.0) / 70.0, 0.0, 1.0) * 8.0
		status_label.text = "Brush size: %.1fx (%d m)" % [mult, int(editor.brush_radius_m)]
		queue_redraw())

	_update_action_buttons()

	status_label = Label.new()
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(status_label)

func _update_action_buttons() -> void:
	if not actions or not editor:
		return
	for c in actions.get_children():
		actions.remove_child(c)

	match editor.sub_mode:
		Editor.SubMode.OBJECT:
			for b in [place_button, remove_button]:
				b.custom_minimum_size = Vector2(100, 56)
				actions.add_child(b)
		Editor.SubMode.PAINTER:
			for b in [paint_button, brush_minus_btn, brush_plus_btn]:
				b.custom_minimum_size = Vector2(90, 56)
				actions.add_child(b)
		Editor.SubMode.ELEVATION:
			for b in [raise_button, lower_button, smooth_button, brush_minus_btn, brush_plus_btn]:
				b.custom_minimum_size = Vector2(70, 56)
				actions.add_child(b)


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
	palette_title_label = Label.new()
	palette_title_label.text = "SELECT OBJECT"
	palette_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(palette_title_label)
	header.add_child(_button("CLOSE", _cancel_map_asset_selection))
	var palette_actions := VBoxContainer.new()
	palette_actions.add_theme_constant_override("separation", 6)
	column.add_child(palette_actions)
	import_palette_btn = _button("ADD OBJECT", func(): _open_import_dialog())
	import_palette_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_actions.add_child(import_palette_btn)
	edit_clutter_btn = _button("CLUTTER", func():
		set_clutter_dialog_open(true))
	edit_clutter_btn.visible = false
	edit_clutter_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_actions.add_child(edit_clutter_btn)
	var tint_column := VBoxContainer.new()
	tint_column.add_theme_constant_override("separation", 6)
	column.add_child(tint_column)
	var tint_row := HBoxContainer.new()
	tint_row.add_theme_constant_override("separation", 6)
	tint_column.add_child(tint_row)
	for tint_title in ["Object RGBA", "Light RGBA"]:
		var picker = ColorPickerButton.new()
		picker.text = tint_title
		picker.edit_alpha = true
		picker.color = Color.WHITE
		picker.custom_minimum_size = Vector2(0, 44)
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ColorPickerUI.configure(picker)
		tint_row.add_child(picker)
		if tint_title == "Object RGBA":
			object_tint_picker = picker
		else:
			light_tint_picker = picker
	var tint_target_button := _button("TINT AIMED OBJECT", func():
		editor.tint_target(object_tint_picker.color, light_tint_picker.color)
		status_label.text = editor.status)
	tint_target_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tint_column.add_child(tint_target_button)
	palette_scroll = ScrollContainer.new()
	palette_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(palette_scroll)
	palette_grid = GridContainer.new()
	palette_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_grid.add_theme_constant_override("h_separation", 10)
	palette_grid.add_theme_constant_override("v_separation", 10)
	palette_scroll.add_child(palette_grid)

func _update_palette_columns() -> void:
	if not palette_grid or not palette:
		return
	var avail_w: float = palette_scroll.size.x if palette_scroll and palette_scroll.size.x > 100.0 else (palette.size.x - 44.0)
	if avail_w < 100.0:
		avail_w = maxf(size.x - 60.0, 180.0)
	palette_grid.columns = maxi(1, int(avail_w / 138.0))

func _open_import_dialog() -> void:
	if not import_file_dialog:
		import_file_dialog = FileDialog.new()
		import_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		import_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		import_file_dialog.use_native_dialog = true
		import_file_dialog.file_selected.connect(_on_import_file_selected)
		add_child(import_file_dialog)

	if editor.sub_mode == Editor.SubMode.OBJECT:
		current_import_mode = "object"
		import_file_dialog.filters = PackedStringArray(["*.glb, *.gltf, *.obj, *.tscn ; 3D Model files"])
		import_file_dialog.title = "Import 3D Object Model"
	else:
		current_import_mode = "texture"
		import_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image texture files"])
		import_file_dialog.title = "Import Ground Texture Image"
	var default_dir := OS.get_environment("HOME").path_join("storage/shared/Projects")
	if not DirAccess.dir_exists_absolute(default_dir):
		default_dir = OS.get_environment("HOME").path_join("storage/shared")
	if DirAccess.dir_exists_absolute(default_dir):
		import_file_dialog.current_dir = default_dir

	var dialog_w := int(maxf(minf(700, size.x - 16), 1))
	var dialog_h := int(maxf(minf(500, size.y - 16), 1))
	import_file_dialog.popup_centered(Vector2i(dialog_w, dialog_h))

func _open_replace_image_dialog(index: int) -> void:
	target_replace_texture_index = index
	if not import_file_dialog:
		import_file_dialog = FileDialog.new()
		import_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		import_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		import_file_dialog.use_native_dialog = true
		import_file_dialog.file_selected.connect(_on_import_file_selected)
		add_child(import_file_dialog)

	current_import_mode = "replace_texture"
	var biome_name: String = ""
	if editor and index >= 0 and index < editor.texture_catalog.size():
		biome_name = str(editor.texture_catalog[index].get("name", "Terrain"))
	import_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image texture files"])
	import_file_dialog.title = "Replace Image for " + biome_name if not biome_name.is_empty() else "Replace Ground Texture Image"
	var default_dir := OS.get_environment("HOME").path_join("storage/shared/Projects")
	if not DirAccess.dir_exists_absolute(default_dir):
		default_dir = OS.get_environment("HOME").path_join("storage/shared")
	if DirAccess.dir_exists_absolute(default_dir):
		import_file_dialog.current_dir = default_dir

	var dialog_w := int(minf(700, size.x - 20))
	var dialog_h := int(minf(500, size.y - 20))
	import_file_dialog.popup_centered(Vector2i(dialog_w, dialog_h))

func _on_import_file_selected(path: String) -> void:
	var rotate_setting: bool = rotate_checkbox.button_pressed if rotate_checkbox else true
	if current_import_mode == "object":
		pending_object_import_path = path
		collision_import_dialog.popup_centered()
		return
	elif current_import_mode == "replace_texture":
		if target_replace_texture_index >= 0:
			editor.replace_ground_texture(target_replace_texture_index, path, rotate_setting)
			target_replace_texture_index = -1
	else:
		editor.import_ground_texture(path, rotate_setting)
	status_label.text = editor.status

	_populate_palette()
	_update_active_box_content()

func _build_collision_import_dialog() -> void:
	collision_import_dialog = ConfirmationDialog.new()
	collision_import_dialog.title = "OBJECT COLLISION HULLS"
	collision_import_dialog.ok_button_text = "IMPORT MODEL"
	collision_import_dialog.cancel_button_text = "NO COLLISION"
	collision_import_dialog.min_size = Vector2(280, 240)
	add_child(collision_import_dialog)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	collision_import_dialog.add_child(column)
	var help := Label.new()
	help.text = "Select named solid parts. Foliage is never included."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	for category_data: Dictionary in [
		{"id": "roots", "label": "Roots"},
		{"id": "trunk", "label": "Trunk"},
		{"id": "main_branches", "label": "Main branches"}
	]:
		var check := CheckBox.new()
		check.text = category_data.label
		check.button_pressed = false
		column.add_child(check)
		collision_import_checks[category_data.id] = check
	collision_import_dialog.confirmed.connect(_confirm_object_import)
	collision_import_dialog.canceled.connect(_cancel_object_import)

func _confirm_object_import() -> void:
	if pending_object_import_path.is_empty():
		return
	var categories: Dictionary = {}
	for category: String in collision_import_checks:
		var check: CheckBox = collision_import_checks[category]
		categories[category] = check.button_pressed
	editor.import_object_model(pending_object_import_path, categories)
	pending_object_import_path = ""
	_populate_palette()
	_update_active_box_content()

func _cancel_object_import() -> void:
	if not pending_object_import_path.is_empty():
		editor.import_object_model(pending_object_import_path, {})
		pending_object_import_path = ""
		_populate_palette()
		_update_active_box_content()

func _build_clutter_dialog() -> void:
	clutter_dialog = PanelContainer.new()
	clutter_dialog.name = "ClutterDialog"
	clutter_dialog.add_theme_stylebox_override("panel", _panel_style())
	add_child(clutter_dialog)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	clutter_dialog.add_child(column)

	var title := Label.new()
	title.text = "EDIT GROUND CLUTTER SETTINGS"
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	clutter_density_label = Label.new()
	clutter_density_label.text = "Clutter Density: 0.50×"
	column.add_child(clutter_density_label)

	clutter_density_slider = HSlider.new()
	clutter_density_slider.min_value = 0.0
	clutter_density_slider.max_value = 16.0
	clutter_density_slider.step = 0.05
	clutter_density_slider.value = 0.5
	clutter_density_slider.value_changed.connect(func(val: float):
		clutter_density_label.text = "Clutter Density: %.2f×" % val
		var entry := editor.current_texture()
		if not entry.is_empty():
			entry["clutter_density"] = val
			var references = get_tree().get_first_node_in_group("reference_objects")
			var config: Dictionary = references.active_map_config if references else MapConfig.load_map_config(MapConfig.active_map())
			if config.has("biomes") and config.biomes.has(entry.get("key", "")):
				config.biomes[entry.key]["clutter_density"] = val
				MapConfig.save_document(config, config.map_directory)
				var clutter = get_tree().get_first_node_in_group("clutter_manager")
				if clutter and clutter.has_method("reload_clutter"):
					clutter.reload_clutter())
	column.add_child(clutter_density_slider)

	var close_btn := _button("CLOSE CLUTTER EDIT", func(): set_clutter_dialog_open(false))
	column.add_child(close_btn)
	clutter_dialog.visible = false


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
	map_editor.asset_selector_ui = self
	scroll.add_child(map_editor)
	map_editor.generate_requested.connect(_on_generate_biome_pressed)
	map_editor.save_requested.connect(_save_map_definition)
	map_editor.save_as_requested.connect(func(): await _save_map_definition(true))
	map_editor.load_requested.connect(_activate_map)
	map_editor.new_requested.connect(_new_map)
	map_editor.import_map_requested.connect(_import_map)
	map_editor.export_map_requested.connect(_export_map)
	regen_dialog.visible = false

func _build_regen_workbench() -> void:
	regen_workbench = PanelContainer.new()
	regen_workbench.name = "RegenerationWorkbench"
	regen_workbench.add_theme_stylebox_override("panel", _panel_style())
	add_child(regen_workbench)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	regen_workbench.add_child(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	column.add_child(heading)
	var cancel_btn := _button("Back", func(): regen_workbench.visible = false)
	cancel_btn.custom_minimum_size = Vector2(76, 36)
	heading.add_child(cancel_btn)
	var title := Label.new()
	title.text = "MAP REGENERATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var intro := Label.new()
	intro.text = "Choose regeneration steps. Existing objects are cleared before new placements."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 12)
	column.add_child(intro)
	var options_scroll := ScrollContainer.new()
	options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_scroll.custom_minimum_size.y = 0
	options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(options_scroll)
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 2)
	options_scroll.add_child(options)
	var select_row := HBoxContainer.new()
	options.add_child(select_row)
	var select_all := _button("Select All", func(): _set_regeneration_options(true))
	select_all.custom_minimum_size.y = 36
	select_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_row.add_child(select_all)
	var select_none := _button("Select None", func(): _set_regeneration_options(false))
	select_none.custom_minimum_size.y = 36
	select_none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_row.add_child(select_none)
	regen_elevations_check = CheckBox.new()
	regen_elevations_check.text = "Regenerate elevations"
	regen_elevations_check.button_pressed = true
	regen_elevations_check.toggled.connect(func(_value): _update_regeneration_warning())
	options.add_child(regen_elevations_check)
	regen_terrain_check = CheckBox.new()
	regen_terrain_check.text = "Regenerate terrain / biome classification"
	regen_terrain_check.button_pressed = true
	regen_terrain_check.toggled.connect(func(_value): _update_regeneration_warning())
	options.add_child(regen_terrain_check)
	regen_smooth_check = CheckBox.new()
	regen_smooth_check.text = "Apply one smoothing pass to elevations"
	regen_smooth_check.toggled.connect(func(_value): _update_regeneration_warning())
	options.add_child(regen_smooth_check)
	regen_clear_objects_check = CheckBox.new()
	regen_clear_objects_check.text = "Clear existing objects"
	regen_clear_objects_check.button_pressed = true
	regen_clear_objects_check.toggled.connect(func(_value): _update_regeneration_warning())
	options.add_child(regen_clear_objects_check)
	regen_add_objects_check = CheckBox.new()
	regen_add_objects_check.text = "Generate / add objects"
	regen_add_objects_check.toggled.connect(func(_value): _update_regeneration_warning())
	options.add_child(regen_add_objects_check)
	regen_normalize_check = CheckBox.new()
	regen_normalize_check.text = "Normalize elevations to biome ranges"
	regen_normalize_check.button_pressed = true
	regen_normalize_check.toggled.connect(func(_value): _update_regeneration_warning())
	options.add_child(regen_normalize_check)
	for option in [regen_elevations_check, regen_terrain_check, regen_smooth_check, regen_clear_objects_check, regen_add_objects_check, regen_normalize_check]:
		option.custom_minimum_size.y = 32
		option.add_theme_font_size_override("font_size", 13)
	regen_warning_label = Label.new()
	regen_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	regen_warning_label.add_theme_font_size_override("font_size", 12)
	regen_warning_label.add_theme_color_override("font_color", Color(1.0, 0.68, 0.4))
	options.add_child(regen_warning_label)
	var run_btn := _button("RUN SELECTED SEQUENCE", _execute_map_regeneration)
	run_btn.name = "RunSelectedRegeneration"
	run_btn.custom_minimum_size = Vector2(0, 50)
	run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_btn.add_theme_stylebox_override("normal", _danger_style())
	run_btn.add_theme_stylebox_override("hover", _danger_style())
	run_btn.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(run_btn)
	regen_workbench.visible = false
	_set_regeneration_options(true)
	_update_regeneration_warning()

func _danger_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.82, 0.12, 0.14, 1.0)
	style.border_color = Color(1.0, 0.35, 0.35, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style

func _set_regeneration_options(enabled: bool) -> void:
	for option in [regen_elevations_check, regen_terrain_check, regen_smooth_check, regen_clear_objects_check, regen_add_objects_check, regen_normalize_check]:
		option.button_pressed = enabled
	_update_regeneration_warning()

func _update_regeneration_warning() -> void:
	if not regen_warning_label:
		return
	if not regen_elevations_check.button_pressed and not regen_terrain_check.button_pressed and not regen_smooth_check.button_pressed and not regen_clear_objects_check.button_pressed and not regen_add_objects_check.button_pressed and not regen_normalize_check.button_pressed:
		regen_warning_label.text = "No operations selected. Nothing will be changed."
	elif not regen_elevations_check.button_pressed and not regen_terrain_check.button_pressed and not regen_smooth_check.button_pressed and not regen_normalize_check.button_pressed and regen_clear_objects_check.button_pressed and not regen_add_objects_check.button_pressed:
		regen_warning_label.text = "This removes all existing placed objects but preserves the map's spawn points and terrain."
	elif regen_add_objects_check.button_pressed and not (regen_elevations_check.button_pressed and regen_terrain_check.button_pressed):
		regen_warning_label.text = "Object placement will reuse the loaded elevation and biome layers; existing objects are %s." % ("cleared first" if regen_clear_objects_check.button_pressed else "preserved")
	elif regen_clear_objects_check.button_pressed and regen_add_objects_check.button_pressed:
		regen_warning_label.text = "Existing objects will be cleared first; newly generated placements will then be added."
	elif not regen_elevations_check.button_pressed and not regen_terrain_check.button_pressed and (regen_smooth_check.button_pressed or regen_normalize_check.button_pressed):
		regen_warning_label.text = "Smoothing / normalization will reuse the map's saved elevation and biome layers; procedural generation will be skipped.%s" % (" Existing objects will also be cleared." if regen_clear_objects_check.button_pressed else "")
	elif regen_clear_objects_check.button_pressed:
		regen_warning_label.text = "Existing objects will be cleared. Terrain and elevation are replaced only if their options are selected."
	elif regen_add_objects_check.button_pressed:
		regen_warning_label.text = "Existing objects will be kept and generated placements appended."
	else:
		regen_warning_label.text = "Only selected terrain/elevation operations will run. Existing objects and spawn points are preserved."

func _build_progress_dialog() -> void:
	progress_dialog = PanelContainer.new()
	progress_dialog.name = "ProgressDialog"
	progress_dialog.z_as_relative = false
	progress_dialog.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	progress_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	progress_dialog.add_theme_stylebox_override("panel", _panel_style())
	add_child(progress_dialog)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	progress_dialog.add_child(column)

	progress_title_label = Label.new()
	progress_title_label.text = "REGENERATING WORLD MAP"
	progress_title_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	progress_title_label.add_theme_font_size_override("font_size", 15)
	progress_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(progress_title_label)

	# Bar 1 Label & Progress Bar
	progress_stage1_label = Label.new()
	progress_stage1_label.text = "1. Terrain & Biomes Generation"
	progress_stage1_label.add_theme_font_size_override("font_size", 11)
	progress_stage1_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	column.add_child(progress_stage1_label)

	gen_progress_bar = ProgressBar.new()
	gen_progress_bar.custom_minimum_size = Vector2(0, 20)
	gen_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	progress_stage2_label = Label.new()
	progress_stage2_label.text = "2. World Reload & 3D Objects Spawning"
	progress_stage2_label.add_theme_font_size_override("font_size", 11)
	progress_stage2_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	column.add_child(progress_stage2_label)

	reload_progress_bar = ProgressBar.new()
	reload_progress_bar.custom_minimum_size = Vector2(0, 20)
	reload_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

	var log_heading := Label.new()
	log_heading.text = "LIVE GENERATION LOG"
	log_heading.add_theme_font_size_override("font_size", 12)
	log_heading.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	column.add_child(log_heading)

	progress_log = RichTextLabel.new()
	progress_log.name = "RegenerationLiveLog"
	progress_log.bbcode_enabled = false
	progress_log.scroll_active = true
	progress_log.fit_content = false
	progress_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	progress_log.custom_minimum_size = Vector2(0, 116)
	progress_log.add_theme_font_size_override("normal_font_size", 11)
	column.add_child(progress_log)

	progress_dialog.visible = false

func _show_progress_dialog() -> void:
	if not is_instance_valid(progress_dialog):
		return
	_layout()
	progress_dialog.visible = true
	progress_dialog.move_to_front()
	_layout()
	queue_redraw()

func set_clutter_dialog_open(open: bool) -> void:
	if clutter_dialog:
		clutter_dialog.visible = open
		if open:
			_layout()

func _on_generate_biome_pressed() -> void:
	if regen_workbench:
		_update_regeneration_warning()
		regen_workbench.visible = false
		_layout()
		await get_tree().process_frame
		await get_tree().process_frame
		_layout()
		regen_workbench.visible = true
		regen_workbench.move_to_front()
		_layout()
		await get_tree().process_frame
		_layout()

func _append_progress_log(message: String) -> void:
	if not is_instance_valid(progress_log):
		return
	if progress_log.get_line_count() > 300:
		progress_log.clear()
		progress_log.append_text("Earlier log lines cleared to keep memory bounded.\n")
	progress_log.append_text(message.replace("\n", " ") + "\n")
	progress_log.scroll_to_line(progress_log.get_line_count())

func _read_placements(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"objects": [], "spawn_points": []}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("objects", []) is Array:
		return {"objects": [], "spawn_points": []}
	return parsed

func _merge_regenerated_layers(result: Dictionary, world: Node, cb: Callable = Callable()) -> Dictionary:
	var terrain_manager = world.terrain_manager
	if not regen_elevations_check.button_pressed:
		result.elevation_image = terrain_manager.create_elevation_image()
	if not regen_terrain_check.button_pressed:
		result.terrain_image = terrain_manager.create_terrain_image()
	var objects_path := MapConfig.get_object_map_path(world.active_map_config)
	var saved_placements := _read_placements(objects_path)
	var full_map_regeneration := regen_elevations_check.button_pressed and regen_terrain_check.button_pressed
	var generated_spawn_points: Array = result.objects_data.get("spawn_points", []).duplicate(true)
	var existing_objects: Array = saved_placements.get("objects", []).duplicate(true)
	var combined: Array = [] if regen_clear_objects_check.button_pressed else existing_objects
	var generated_objects: Array = result.objects_data.get("objects", []) if regen_add_objects_check.button_pressed else []
	for candidate in generated_objects:
		var item: Dictionary = candidate.duplicate(true)
		item.id = "regen_obj_%d" % (combined.size() + 1)
		combined.append(item)
	result.objects_data = saved_placements.duplicate(true)
	result.objects_data.objects = combined
	if full_map_regeneration and not generated_spawn_points.is_empty():
		result.objects_data.spawn_points = generated_spawn_points
	if not result.objects_data.has("spawn_points"):
		result.objects_data.spawn_points = []
	if regen_terrain_check.button_pressed:
		result.document.generation_report = result.report
		result.document.generation_warnings = result.warnings
	else:
		result.document.generation_report = map_editor.document.get("generation_report", {})
		result.document.generation_warnings = map_editor.document.get("generation_warnings", [])
	if regen_smooth_check.button_pressed:
		_smooth_elevation_image(result.elevation_image)
	if regen_normalize_check.button_pressed:
		_normalize_elevations_to_terrain(result.elevation_image, result.terrain_image, map_editor.document)
	var all_layers_regenerated := regen_elevations_check.button_pressed and regen_terrain_check.button_pressed
	if regen_add_objects_check.button_pressed and not all_layers_regenerated:
		var cached_scatter: Dictionary = await preload("res://scripts/map_generator.gd").generate_objects_from_layers(map_editor.document, result.elevation_image, result.terrain_image, cb)
		if cached_scatter.has("error"):
			return {"error": str(cached_scatter.error)}
		result.objects_data.objects = cached_scatter.objects
	if regen_add_objects_check.button_pressed:
		var terrain_class = preload("res://scripts/terrain_manager.gd")
		var final_heights: Image = result.elevation_image
		var variance := float(map_editor.document.geometry.elevation_variance_m)
		for item in result.objects_data.objects:
			var u := fposmod(float(item.theta) / TAU, 1.0)
			var v := clampf(float(item.z) / float(map_editor.document.geometry.cylinder_length_m) + 0.5, 0.0, 1.0)
			item.elevation = terrain_class.sample_image(final_heights, u, v) * variance
	return result

func _normalize_elevations_to_terrain(elevation_image: Image, terrain_image: Image, document: Dictionary) -> void:
	var w := elevation_image.get_width()
	var h := elevation_image.get_height()
	var tw := terrain_image.get_width()
	var th := terrain_image.get_height()
	var heights := elevation_image.get_data().to_float32_array()
	var terrain_ids := terrain_image.get_data()
	var variance := float(document.geometry.elevation_variance_m)
	var biome_by_id: Dictionary = {}
	for key in document.biomes:
		biome_by_id[int(document.biomes[key].raster_id)] = document.biomes[key]
	for y in h:
		var terrain_y := clampi(roundi(float(y) * float(th - 1) / float(maxi(h - 1, 1))), 0, th - 1)
		for x in w:
			var terrain_x := posmod(roundi(float(x) * float(tw) / float(w)), tw)
			var biome_id := int(terrain_ids[terrain_y * tw + terrain_x])
			var biome: Dictionary = biome_by_id.get(biome_id, {})
			if biome.is_empty():
				continue
			var biome_range: Array = biome.elevation_range_m
			var low := clampf(float(biome_range[0]), 0.0, variance)
			var high := clampf(float(biome_range[1]), low, variance)
			if biome.get("submerged", false):
				high = minf(high, float(document.geometry.water_sea_level_m))
			else:
				low = maxf(low, float(document.geometry.water_sea_level_m))
			heights[y * w + x] = clampf(lerpf(low, maxf(low, high), heights[y * w + x] / variance) / variance, 0.0, 1.0)
	elevation_image.set_data(w, h, false, Image.FORMAT_RF, heights.to_byte_array())

func _smooth_elevation_image(image: Image) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var source := image.get_data().to_float32_array()
	var smoothed := PackedFloat32Array()
	smoothed.resize(source.size())
	for y in h:
		for x in w:
			var total := 0.0
			for oy in range(-1, 2):
				var sy := clampi(y + oy, 0, h - 1)
				for ox in range(-1, 2):
					var sx := posmod(x + ox, w)
					total += source[sy * w + sx]
			smoothed[y * w + x] = total / 9.0
	image.set_data(w, h, false, Image.FORMAT_RF, smoothed.to_byte_array())

func _execute_map_regeneration() -> void:
	if not regen_elevations_check.button_pressed and not regen_terrain_check.button_pressed and not regen_smooth_check.button_pressed and not regen_clear_objects_check.button_pressed and not regen_add_objects_check.button_pressed and not regen_normalize_check.button_pressed:
		regen_warning_label.text = "Select at least one regeneration operation. Nothing has been changed."
		return
	if str(map_editor.document.get("name", "")).strip_edges().is_empty():
		_map_failure("Give the map a name before generating")
		return
	var world = get_tree().get_first_node_in_group("cylinder_world")
	if not world or not world.terrain_manager:
		_map_failure("The active terrain is unavailable")
		return
	if regen_add_objects_check.button_pressed and (world.terrain_manager.elevation_data.is_empty() or world.terrain_manager.terrain_data.is_empty()):
		regen_warning_label.text = "Object placement needs saved elevation and biome layers. Regenerate both layers first."
		return
	if regen_workbench:
		regen_workbench.visible = false
	_layout()
	progress_title_label.text = "REGENERATING SELECTED MAP DATA"
	progress_stage1_label.text = "1. Generation / selected passes"
	progress_stage2_label.text = "2. Save package and refresh runtime"
	gen_progress_bar.value = 0
	reload_progress_bar.value = 0
	progress_log.clear()
	_append_progress_log("Starting selected regeneration passes")
	_append_progress_log("Note: the current generator computes elevation and biome candidates together; unselected layer output is discarded and preserved from the active map.")
	_show_progress_dialog()
	# Let the progress panel render before generation performs any expensive work.
	await get_tree().process_frame
	var generator = preload("res://scripts/map_generator.gd")
	var cb = func(value: float, message: String):
		if is_instance_valid(gen_progress_bar):
			gen_progress_bar.value = value * 100
		if is_instance_valid(progress_status_label):
			progress_status_label.text = message
		_append_progress_log(message)
	var generation_document: Dictionary = map_editor.document.duplicate(true)
	var both_layers_selected := regen_elevations_check.button_pressed and regen_terrain_check.button_pressed
	generation_document.generation.skip_objects = not (regen_add_objects_check.button_pressed and both_layers_selected)
	var clear_objects_only := regen_clear_objects_check.button_pressed and not regen_elevations_check.button_pressed and not regen_terrain_check.button_pressed and not regen_smooth_check.button_pressed and not regen_add_objects_check.button_pressed and not regen_normalize_check.button_pressed
	var reuse_cached_layers := not regen_elevations_check.button_pressed and not regen_terrain_check.button_pressed
	var result: Dictionary
	if clear_objects_only:
		await cb.call(0.15, "Preparing a placements-only update; terrain and spawn points will be preserved")
		var current_placements := _read_placements(MapConfig.get_object_map_path(world.active_map_config))
		result = {
			"document": map_editor.document.duplicate(true),
			"elevation_image": world.terrain_manager.create_elevation_image(),
			"terrain_image": world.terrain_manager.create_terrain_image(),
			"objects_data": current_placements,
			"report": map_editor.document.get("generation_report", {}),
			"warnings": map_editor.document.get("generation_warnings", []),
			"pois": []
		}
	elif reuse_cached_layers:
		await cb.call(0.15, "Reusing the loaded map's saved elevation and biome layers; procedural generation skipped")
		result = {
			"document": map_editor.document.duplicate(true),
			"elevation_image": world.terrain_manager.create_elevation_image(),
			"terrain_image": world.terrain_manager.create_terrain_image(),
			"objects_data": _read_placements(MapConfig.get_object_map_path(world.active_map_config)),
			"report": map_editor.document.get("generation_report", {}),
			"warnings": map_editor.document.get("generation_warnings", []),
			"pois": []
		}
	else:
		result = await generator.generate(generation_document, cb)
	if result.has("error"):
		_map_failure(result.error)
		return
	result.document = map_editor.document.duplicate(true)
	result = await _merge_regenerated_layers(result, world, cb)
	if result.has("error"):
		_map_failure(result.error)
		return
	var directory = MapConfig.new_user_directory("generated")
	progress_status_label.text = "Saving generated map package..."
	gen_progress_bar.value = 90
	_append_progress_log("Writing generated package")
	await get_tree().process_frame
	if not generator.save_generated_map_package(result, directory, cb):
		_map_failure("Unable to save generated map: " + MapConfig.last_error)
		return
	gen_progress_bar.value = 100
	_append_progress_log("Generated package saved; activating it")
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
	if not world or not refs:
		_map_failure("The active world is unavailable")
		return false
	var storage = preload("res://scripts/world_edit_storage.gd")
	var terrain = world.terrain_manager
	var descriptor_changed := _authored_document(map_editor.document) != _authored_document(world.active_map_config)
	var placements_changed: bool = refs.placement_dirty or not storage.player_spawn_matches_current(refs, editor.player)
	var elevation_changed: bool = terrain != null and terrain.elevation_dirty
	var classification_changed: bool = terrain != null and terrain.terrain_dirty
	if not as_new and not descriptor_changed and not placements_changed and not elevation_changed and not classification_changed:
		map_editor.message.text = "No changes to save"
		status_label.text = "Map is already up to date"
		return true
	progress_title_label.text = "SAVING MAP"
	progress_stage1_label.text = "1. Package definition and changed data"
	progress_stage2_label.text = "2. Reload map and placements"
	gen_progress_bar.value = 0
	reload_progress_bar.value = 0
	progress_status_label.text = "Preparing map snapshot..."
	progress_log.clear()
	_append_progress_log("Starting map save")
	_show_progress_dialog()
	await get_tree().process_frame
	var directory = MapConfig.new_user_directory("edited")
	if MapConfig.copy_directory(world.active_map_config.map_directory, directory) != OK:
		_map_failure("Unable to prepare map save: " + MapConfig.last_error)
		return false
	gen_progress_bar.value = 20
	progress_status_label.text = "Packaging map definition and referenced assets..."
	_append_progress_log("Copied map package")
	await get_tree().process_frame
	var original_document: Dictionary = map_editor.document.duplicate(true)
	if as_new:
		map_editor.document.world_id = MapConfig.new_map_id()
	if not map_editor.package_imports(directory) or MapConfig.save_document(map_editor.document, directory) != OK:
		map_editor.document = original_document
		map_editor.rebuild()
		_map_failure("Unable to save definition and assets")
		return false
	gen_progress_bar.value = 45
	progress_status_label.text = "Writing changed placements and terrain..."
	_append_progress_log("Saved map definition and packaged assets")
	await get_tree().process_frame
	if (as_new or placements_changed) and storage.save(refs, MapConfig.get_object_map_path(map_editor.document), editor.player) != OK:
		map_editor.document = original_document
		map_editor.rebuild()
		_map_failure("Unable to save placed objects")
		return false
	if terrain:
		if elevation_changed and not terrain.save_elevation_map(MapConfig.get_elevation_map_path(map_editor.document)):
			map_editor.document = original_document
			map_editor.rebuild()
			_map_failure("Unable to save elevation layer: " + terrain.last_error)
			return false
		if classification_changed and not terrain.save_terrain_map(MapConfig.get_terrain_map_path(map_editor.document)):
			map_editor.document = original_document
			map_editor.rebuild()
			_map_failure("Unable to save biome layer")
			return false
	gen_progress_bar.value = 75
	_append_progress_log("Changed map data written")
	progress_status_label.text = "Loading saved map..."
	await get_tree().process_frame
	var activated: bool
	if as_new:
		activated = await _activate_map(directory)
	else:
		activated = await _activate_saved_map_selectively(directory, world.active_map_config, placements_changed, elevation_changed, classification_changed)
	if not activated:
		var failure_message = map_editor.message.text
		map_editor.document = original_document
		map_editor.rebuild()
		_map_failure(failure_message)
	return activated

func _authored_document(document: Dictionary) -> Dictionary:
	var authored := document.duplicate(true)
	authored.erase("map_directory")
	authored.erase("saved_at_unix")
	return authored

func _activate_saved_map_selectively(directory: String, old_doc: Dictionary, placements_changed: bool, elevation_changed: bool, classification_changed: bool) -> bool:
	var world = get_tree().get_first_node_in_group("cylinder_world")
	if not world:
		_map_failure("The active world is unavailable")
		return false
	var next_doc := MapConfig.load_map_config(directory)
	if next_doc.is_empty():
		_map_failure("Saved map failed validation: " + MapConfig.last_error)
		return false
	var geometry_changed: bool = old_doc.geometry != next_doc.geometry
	var mesh_render_changed := false
	for key in ["radial_segments", "length_segments", "include_end_caps", "end_cap_rings", "end_cap_dish_depth_m"]:
		if old_doc.rendering.get(key) != next_doc.rendering.get(key):
			mesh_render_changed = true
	var material_changed: bool = old_doc.biomes != next_doc.biomes or old_doc.rendering != next_doc.rendering or old_doc.environment.water != next_doc.environment.water or classification_changed
	var biome_ids_changed := false
	for biome_key in old_doc.biomes:
		if not next_doc.biomes.has(biome_key) or int(old_doc.biomes[biome_key].raster_id) != int(next_doc.biomes[biome_key].raster_id):
			biome_ids_changed = true
	for biome_key in next_doc.biomes:
		if not old_doc.biomes.has(biome_key):
			biome_ids_changed = true
	var catalog_changed: bool = old_doc.objects.model_catalog != next_doc.objects.model_catalog
	var clutter_changed: bool = old_doc.biomes != next_doc.biomes or old_doc.ground_clutter != next_doc.ground_clutter or catalog_changed or classification_changed or geometry_changed
	var reload_placements: bool = placements_changed or elevation_changed or geometry_changed or catalog_changed
	var rebuild_geometry: bool = geometry_changed or mesh_render_changed or elevation_changed or biome_ids_changed
	progress_status_label.text = "Applying only changed map systems..."
	_append_progress_log("Selective refresh: geometry=%s materials=%s clutter=%s placements=%s" % [str(rebuild_geometry), str(material_changed), str(clutter_changed), str(reload_placements)])
	await get_tree().process_frame
	var loaded: bool = world.load_map_package(directory, biome_ids_changed, rebuild_geometry, material_changed)
	if not loaded:
		_map_failure("Map could not apply saved changes: " + world.map_load_error)
		return false
	if MapConfig.activate(directory) != OK:
		world.load_map_package(str(old_doc.map_directory))
		_map_failure("Could not persist the active map selection")
		return false
	reload_progress_bar.value = 35
	if clutter_changed:
		var clutter = get_tree().get_first_node_in_group("clutter_manager")
		if clutter:
			clutter.reload_clutter()
	var refs = get_tree().get_first_node_in_group("reference_objects")
	if refs and reload_placements:
		var placement_progress = func(value: float, message: String):
			reload_progress_bar.value = 35.0 + value * 60.0
			progress_status_label.text = message
			_append_progress_log(message)
			await get_tree().process_frame
		await refs.load_object_map_with_progress(MapConfig.get_object_map_path(world.active_map_config), placement_progress)
		preload("res://scripts/world_edit_storage.gd").restore(refs)
	if geometry_changed and editor.player:
		editor.player.reset_to_spawn()
	map_editor.document = world.active_map_config.duplicate(true)
	map_editor.rebuild()
	if catalog_changed or old_doc.biomes != next_doc.biomes:
		editor.reload_catalog()
	for child in palette_grid.get_children():
		palette_grid.remove_child(child)
		child.queue_free()
	selection_buttons.clear()
	previews.clear()
	_update_current_object()
	reload_progress_bar.value = 100
	progress_dialog.visible = false
	status_label.text = "Saved; refreshed changed map systems"
	map_editor.message.text = "Saved. Only affected runtime systems were refreshed."
	return true

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
	if not world:
		_map_failure("Map failed validation: the world is unavailable; current world preserved")
		return false
	if not world.load_map_package(directory):
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
		var placement_progress = func(value: float, message: String):
			if progress_dialog.visible:
				reload_progress_bar.value = 35.0 + value * 60.0
				progress_status_label.text = message
				_append_progress_log(message)
				await get_tree().process_frame
		await refs.load_object_map_with_progress(MapConfig.get_object_map_path(world.active_map_config), placement_progress)
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
	_append_progress_log("ERROR: " + message)
	progress_dialog.visible = false
	status_label.text = message
	map_editor.message.text = message

func _populate_palette() -> void:
	_update_palette_columns()
	for child in palette_grid.get_children():
		palette_grid.remove_child(child)
		child.queue_free()
	selection_buttons.clear()
	previews.clear()

	if not editor:
		return

	if editor.sub_mode == Editor.SubMode.OBJECT:
		var object_entries := _map_selection_object_entries() if not map_asset_selection_kind.is_empty() else editor.catalog
		if palette_title_label:
			palette_title_label.text = "SELECT CLUTTER MODEL" if map_asset_selection_kind == "clutter" else "SELECT OBJECT"
		if import_palette_btn:
			import_palette_btn.text = "ADD CLUTTER MODEL" if map_asset_selection_kind == "clutter" else "ADD OBJECT"
		if edit_clutter_btn:
			edit_clutter_btn.visible = false

		if map_asset_selection_kind in ["object", "clutter"]:
			_add_empty_selection_card()
		for index in range(object_entries.size()):
			var entry := object_entries[index]
			var card := VBoxContainer.new()
			card.custom_minimum_size = Vector2(128, 164)
			palette_grid.add_child(card)
			var button := _button("", func(): _select(index))
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
			preview.name = "AssetMiniPreview"
			# The preview is visual content inside the selection button. Let the
			# button receive taps on the model instead of the child consuming them.
			preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(preview)
			preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			preview.offset_left = 6
			preview.offset_top = 6
			preview.offset_right = -6
			preview.offset_bottom = -6
			preview.show_model(entry.path, MapConfig.color(entry.get("tint", [1, 1, 1, 1])))
			previews.append(preview)
			var label := Label.new()
			label.text = str(entry.get("name", "Object"))
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 12)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(label)

	elif editor.sub_mode == Editor.SubMode.PAINTER:
		if palette_title_label:
			palette_title_label.text = "SELECT TERRAIN IMAGE"
		if import_palette_btn:
			import_palette_btn.text = "ADD TERRAIN IMAGE"
		if edit_clutter_btn:
			edit_clutter_btn.visible = true

		var texture_entries := editor.texture_catalog
		for index in range(texture_entries.size()):
			var entry := texture_entries[index]
			var card := VBoxContainer.new()
			card.custom_minimum_size = Vector2(128, 192)
			palette_grid.add_child(card)
			var button := _button("", func(): _select(index))
			button.custom_minimum_size = Vector2(128, 116)
			button.toggle_mode = true
			var normal_style := _panel_style()
			normal_style.bg_color = Color(0.09, 0.13, 0.18)
			button.add_theme_stylebox_override("normal", normal_style)
			var selected_style := normal_style.duplicate() as StyleBoxFlat
			selected_style.border_color = Color(0.35, 0.8, 1.0)
			selected_style.set_border_width_all(3)
			button.add_theme_stylebox_override("pressed", selected_style)
			button.tooltip_text = str(entry.get("name", "Terrain Image"))
			card.add_child(button)
			selection_buttons.append(button)

			var tex_path: String = str(entry.get("path", entry.get("texture", "")))
			var tex: Texture2D = MapAssetLoader.load_texture(tex_path) if not tex_path.is_empty() else null
			if tex:
				var swatch := TextureRect.new()
				swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				swatch.texture = tex
				swatch.self_modulate = MapConfig.color(entry.get("tint", [1,1,1,1]))
				swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
				button.add_child(swatch)
				swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				swatch.offset_left = 6
				swatch.offset_top = 6
				swatch.offset_right = -6
				swatch.offset_bottom = -6
			else:
				var swatch := ColorRect.new()
				swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
				button.add_child(swatch)
				swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				swatch.offset_left = 6
				swatch.offset_top = 6
				swatch.offset_right = -6
				swatch.offset_bottom = -6
				swatch.color = MapConfig.color(entry.get("tint", [1,1,1,1]))

			var label := Label.new()
			label.text = str(entry.get("name", "Terrain Image"))
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 12)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(label)

			var idx := index
			button.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
					_open_replace_image_dialog(idx)
			)

			var replace_btn := _button("REPLACE IMAGE", func(): _open_replace_image_dialog(idx))
			replace_btn.custom_minimum_size = Vector2(128, 22)
			replace_btn.add_theme_font_size_override("font_size", 10)
			replace_btn.tooltip_text = "Replace image file for " + str(entry.get("name", "Terrain"))
			card.add_child(replace_btn)

func _select(index: int) -> void:
	if not map_asset_selection_kind.is_empty():
		var selected: Dictionary = {}
		if map_asset_selection_kind == "texture":
			if index >= 0 and index < editor.texture_catalog.size():
				selected = editor.texture_catalog[index].duplicate(true)
		else:
			var entries := _map_selection_object_entries()
			if index >= 0 and index < entries.size():
				selected = entries[index].duplicate(true)
		_finish_map_asset_selection(selected)
		return
	if editor.sub_mode == Editor.SubMode.OBJECT:
		editor.selected_index = index
	elif editor.sub_mode == Editor.SubMode.PAINTER:
		editor.selected_texture_index = index
		if index >= 0 and index < editor.texture_catalog.size():
			editor.selected_biome_id = int(editor.texture_catalog[index].get("id", 0))
	_update_active_box_content()
	set_palette_open(false)

func _add_empty_selection_card() -> void:
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(128, 164)
	palette_grid.add_child(card)
	var choice := _button("NONE", func(): _finish_map_asset_selection({"empty_selection": true}))
	choice.custom_minimum_size = Vector2(128, 126)
	var style := _panel_style()
	style.bg_color = Color(0.12, 0.12, 0.14)
	choice.add_theme_stylebox_override("normal", style)
	card.add_child(choice)
	var hint := Label.new()
	hint.text = "Don't add a rule"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	card.add_child(hint)

func _map_selection_object_entries() -> Array[Dictionary]:
	if map_asset_selection_kind != "clutter" or not map_editor:
		return editor.catalog
	var entries: Array[Dictionary] = []
	for model_id in map_editor.document.get("ground_clutter", {}).get("models", {}):
		var definition: Dictionary = map_editor.document.ground_clutter.models[model_id].duplicate(true)
		var resolved := MapConfig.resolve_map_asset_path(map_editor.document, str(definition.get("scene_path", "")))
		var base_color := MapConfig.color(definition.get("base_color", [1, 1, 1, 1]))
		var tip_color := MapConfig.color(definition.get("tip_color", definition.get("base_color", [1, 1, 1, 1])))
		entries.append({
			"id": str(model_id), "name": str(model_id).replace("_", " ").capitalize(),
			"scene_path": str(definition.get("scene_path", "")), "path": resolved,
			"clutter_model_id": str(model_id), "definition": definition,
		"tint": MapConfig.rgba(base_color.lerp(tip_color, 0.5))
		})
	for catalog_entry in editor.catalog:
		var entry := catalog_entry.duplicate(true)
		entry["scene_path"] = str(entry.get("scene_path", ""))
		entry["object_asset_id"] = str(entry.get("id", ""))
		entries.append(entry)
	return entries

func request_map_asset_selection(kind: String, callback: Callable) -> void:
	if kind not in ["object", "texture", "clutter"] or not editor:
		return
	map_asset_selection_kind = kind
	map_asset_selection_callback = callback
	map_asset_selection_previous_submode = editor.sub_mode
	map_asset_selection_previous_object_index = editor.selected_index
	map_asset_selection_previous_texture_index = editor.selected_texture_index
	editor.sub_mode = Editor.SubMode.PAINTER if kind == "texture" else Editor.SubMode.OBJECT
	if kind == "texture":
		editor.reload_texture_catalog()
	else:
		editor.reload_catalog()
	_update_submode_buttons()
	_update_action_buttons()
	_update_active_box_content()
	set_palette_open(true)

func _finish_map_asset_selection(entry: Dictionary) -> void:
	var callback := map_asset_selection_callback
	var previous_submode := map_asset_selection_previous_submode
	var previous_object_index := map_asset_selection_previous_object_index
	var previous_texture_index := map_asset_selection_previous_texture_index
	map_asset_selection_kind = ""
	map_asset_selection_callback = Callable()
	editor.sub_mode = previous_submode
	editor.selected_index = previous_object_index
	editor.selected_texture_index = previous_texture_index
	_update_submode_buttons()
	_update_action_buttons()
	_update_active_box_content()
	set_palette_open(false)
	set_regen_dialog_open(true)
	if callback.is_valid():
		callback.call(entry)

func _cancel_map_asset_selection() -> void:
	if not map_asset_selection_kind.is_empty():
		_finish_map_asset_selection({})
	else:
		set_palette_open(false)

func _update_current_object() -> void:
	_update_active_box_content()

func _update_active_box_content() -> void:
	if not active_box or not editor:
		return
	if editor.sub_mode == Editor.SubMode.ELEVATION:
		active_box.visible = false
		return

	active_box.visible = editor.enabled

	if replace_active_button:
		replace_active_button.visible = (editor.sub_mode == Editor.SubMode.PAINTER)
	if rotate_checkbox:
		rotate_checkbox.visible = (editor.sub_mode == Editor.SubMode.PAINTER)

	if editor.sub_mode == Editor.SubMode.OBJECT:
		current_preview.visible = true
		if texture_swatch:
			texture_swatch.visible = false
		var entry := editor.current_object()
		if entry.is_empty():
			current_name.text = "No objects available"
			place_button.disabled = true
		else:
			current_name.text = str(entry.get("name", "Object"))
			current_preview.show_model(entry.path, MapConfig.color(entry.get("tint", [1, 1, 1, 1])))
			place_button.disabled = false
		for index in range(selection_buttons.size()):
			selection_buttons[index].set_pressed_no_signal(index == editor.selected_index)
	elif editor.sub_mode == Editor.SubMode.PAINTER:
		current_preview.visible = false
		if not texture_swatch:
			texture_swatch = TextureRect.new()
			texture_swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			current_preview.get_parent().add_child(texture_swatch)
			texture_swatch.mouse_filter = Control.MOUSE_FILTER_STOP
			texture_swatch.gui_input.connect(_on_active_preview_gui_input)
			texture_swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		texture_swatch.visible = true
		var entry := editor.current_texture()
		if entry.is_empty():
			current_name.text = "No terrain images available"
			if paint_button: paint_button.disabled = true
			if replace_active_button: replace_active_button.disabled = true
			if rotate_checkbox: rotate_checkbox.disabled = true
			texture_swatch.texture = null
		else:
			current_name.text = "Image: " + str(entry.get("name", "Terrain"))
			var tex_path: String = str(entry.get("path", entry.get("texture", "")))
			var tex: Texture2D = MapAssetLoader.load_texture(tex_path) if not tex_path.is_empty() else null
			texture_swatch.texture = tex
			texture_swatch.self_modulate = MapConfig.color(entry.get("tint", [1,1,1,1]))
			if paint_button: paint_button.disabled = false
			if replace_active_button: replace_active_button.disabled = false
			if rotate_checkbox:
				rotate_checkbox.disabled = false
				rotate_checkbox.set_pressed_no_signal(bool(entry.get("rotate", entry.get("blended", true))))
		for index in range(selection_buttons.size()):
			selection_buttons[index].set_pressed_no_signal(index == editor.selected_texture_index)



func set_edit_mode(active: bool) -> void:
	editor.enabled = active
	set_palette_open(false)
	set_regen_dialog_open(false)
	if clutter_dialog:
		clutter_dialog.visible = false
	if submode_bar:
		submode_bar.visible = active
	active_box.visible = active and editor.sub_mode != Editor.SubMode.ELEVATION
	actions.visible = active
	status_label.visible = active
	status_label.text = editor.status
	if active:
		_update_active_box_content()
		_update_submode_buttons()
		_update_action_buttons()
	queue_redraw()

func set_palette_open(open: bool) -> void:
	palette_open = open and editor.enabled
	palette.visible = palette_open
	if palette_open:
		_layout()
		_update_palette_columns()
		set_regen_dialog_open(false)
		if clutter_dialog:
			clutter_dialog.visible = false
		var aimed = editor.target_object(editor.ray_hit())
		if aimed:
			object_tint_picker.color = aimed.tint
			light_tint_picker.color = aimed.light_color
		_populate_palette()
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
		if clutter_dialog:
			clutter_dialog.visible = false
	queue_redraw()

func contains_ui_point(point: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	if palette_open or regen_open or (regen_workbench and regen_workbench.visible) or (progress_dialog and progress_dialog.visible) or (clutter_dialog and clutter_dialog.visible):
		return true
	var in_submode := submode_bar.get_global_rect().has_point(point) if submode_bar and submode_bar.visible else false
	var in_active := active_box.get_global_rect().has_point(point) if active_box and active_box.visible else false
	var in_actions := actions.get_global_rect().has_point(point) if actions and actions.visible else false
	return editor.enabled and (in_submode or in_active or in_actions)

func _layout() -> void:
	if not active_box:
		return
	var content_width := maxf(size.x - 16.0, 1.0)
	var active_width := minf(390.0, content_width)
	active_box.position = Vector2((size.x - active_width) * 0.5, 60)
	active_box.size = Vector2(active_width, 88)
	if submode_bar:
		submode_bar.position = Vector2((size.x - active_width) * 0.5, 154)
		submode_bar.size = Vector2(active_width, 36)
		var submode_button_width := maxf((active_width - 18.0) / 4.0, 1.0)
		for mode_button in [obj_mode_btn, paint_mode_btn, elev_mode_btn, map_button]:
			mode_button.custom_minimum_size.x = submode_button_width
	var actions_width := minf(280.0, content_width)
	actions.position = Vector2((size.x - actions_width) * 0.5, size.y - (360 if size.x < 640 else 84))
	actions.size = Vector2(actions_width, actions.size.y)
	status_label.position = Vector2(0, 196)
	status_label.size = Vector2(size.x, 24)
	var palette_width := maxf(minf(size.x - 16.0, 620.0), 1.0)
	var palette_height := maxf(minf(size.y - 32.0, 900.0), 1.0)
	palette.position = Vector2((size.x - palette_width) * 0.5, clampf(16.0, 0.0, maxf(size.y - palette_height, 0.0)))
	palette.size = Vector2(palette_width, palette_height)
	_update_palette_columns()

	if regen_dialog:
		var map_width := maxf(minf(620.0, content_width), 1.0)
		var map_height := maxf(minf(size.y - 56.0, 900.0), 1.0)
		regen_dialog.position = Vector2((size.x - map_width) * 0.5, clampf(40.0, 0.0, maxf(size.y - map_height, 0.0)))
		regen_dialog.size = Vector2(map_width, map_height)
	if regen_workbench:
		var workbench_width := maxf(minf(460.0, content_width), 1.0)
		var workbench_height := maxf(minf(size.y - 40.0, 420.0), 1.0)
		regen_workbench.position = Vector2((size.x - workbench_width) * 0.5, (size.y - workbench_height) * 0.5)
		regen_workbench.size = Vector2(workbench_width, workbench_height)
	if progress_dialog:
		var dialog_w := maxf(minf(500.0, content_width), 1.0)
		var dialog_h := maxf(minf(size.y - 16.0, 460.0), 1.0)
		progress_dialog.position = Vector2((size.x - dialog_w) * 0.5, (size.y - dialog_h) * 0.5)
		progress_dialog.size = Vector2(dialog_w, dialog_h)
	if clutter_dialog:
		var clutter_width := maxf(minf(320.0, content_width), 1.0)
		var clutter_height := minf(180.0, maxf(size.y - 16.0, 1.0))
		clutter_dialog.position = Vector2((size.x - clutter_width) * 0.5, (size.y - clutter_height) * 0.5)
		clutter_dialog.size = Vector2(clutter_width, clutter_height)
	queue_redraw()

func get_terrain_ground_normal() -> Vector3:
	if not editor or not editor.player or not editor.player.camera:
		return Vector3.UP

	var camera := editor.player.camera
	var hit := editor.ray_hit()
	var aim_pos: Vector3

	if not hit.is_empty() and hit.has("position"):
		aim_pos = hit.position
	else:
		var origin := camera.global_position
		var direction := -camera.global_basis.z
		aim_pos = origin + direction * editor.REACH

	var cylinder_world = get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator if is_inside_tree() else null
	if cylinder_world:
		var theta := atan2(aim_pos.y, aim_pos.x)
		var z := aim_pos.z
		var surface_info := cylinder_world.get_surface_mesh_point_and_normal(theta, z)
		if surface_info.has("normal") and not (surface_info.normal as Vector3).is_zero_approx():
			return (surface_info.normal as Vector3).normalized()

	var rad_pos := Vector3(aim_pos.x, aim_pos.y, 0.0)
	if not rad_pos.is_zero_approx():
		return -rad_pos.normalized()
	return Vector3.UP

func get_screen_tilted_circle_points(num_steps: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if not editor or not editor.player or not editor.player.camera:
		return pts

	var center := size * 0.5
	var camera := editor.player.camera
	var cam_right: Vector3 = camera.global_transform.basis.x.normalized()
	var cam_up: Vector3 = camera.global_transform.basis.y.normalized()
	var cam_forward: Vector3 = (-camera.global_transform.basis.z).normalized()

	var hit_normal := get_terrain_ground_normal()

	var u_vec := cam_right - hit_normal * cam_right.dot(hit_normal)
	if u_vec.is_zero_approx():
		u_vec = hit_normal.cross(cam_forward)
		if u_vec.is_zero_approx():
			u_vec = hit_normal.cross(Vector3.UP)
	u_vec = u_vec.normalized()
	var v_vec := hit_normal.cross(u_vec).normalized()

	var u_screen := Vector2(u_vec.dot(cam_right), -u_vec.dot(cam_up))
	var v_screen := Vector2(v_vec.dot(cam_right), -v_vec.dot(cam_up))

	var min_axis := 0.15
	if u_screen.length() < min_axis:
		u_screen = u_screen.normalized() * min_axis
	if v_screen.length() < min_axis:
		v_screen = v_screen.normalized() * min_axis

	# Base crosshair radius = 16px.
	# Size ranges from 1.0x to 9.0x Crosshair (allowing 3x the previous maximum size of 3.0x).
	var mult := 1.0 + clampf((editor.brush_radius_m - 5.0) / 70.0, 0.0, 1.0) * 8.0
	var r_screen := 16.0 * mult

	for i in range(num_steps + 1):
		var angle := float(i) / float(num_steps) * TAU
		var offset_2d := u_screen * cos(angle) + v_screen * sin(angle)
		pts.append(center + offset_2d * r_screen)
	return pts

func get_oblique_surface_points(num_steps: int = 32) -> PackedVector2Array:
	return get_screen_tilted_circle_points(num_steps)

func get_oblique_triangle_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	if not editor or not editor.player or not editor.player.camera:
		return pts
	var hit := editor.ray_hit()
	if hit.is_empty():
		return pts
	var camera := editor.player.camera
	var hit_pos: Vector3 = hit.position
	var hit_normal: Vector3 = hit.normal
	if hit_normal.is_zero_approx():
		return pts

	var cam_right := camera.global_transform.basis.x
	var u_vec := (cam_right - hit_normal * cam_right.dot(hit_normal)).normalized()
	if u_vec.is_zero_approx():
		u_vec = hit_normal.cross(Vector3.FORWARD).normalized()
		if u_vec.is_zero_approx():
			u_vec = hit_normal.cross(Vector3.UP).normalized()
	var v_vec := hit_normal.cross(u_vec).normalized()

	var r_m := editor.brush_radius_m
	var base_angle := -PI * 0.5
	for k in range(4):
		var angle := base_angle + float(k % 3) * (TAU / 3.0)
		var p_3d := hit_pos + (u_vec * cos(angle) + v_vec * sin(angle)) * r_m
		if not camera.is_position_behind(p_3d):
			pts.append(camera.unproject_position(p_3d))
	return pts

func is_painter_target_too_far() -> bool:
	if not editor or not editor.player or not editor.player.camera:
		return true
	var hit := editor.ray_hit()
	if hit.is_empty() or not hit.has("position"):
		return true
	var camera := editor.player.camera
	var hit_pos: Vector3 = hit.position
	var dist := camera.global_position.distance_to(hit_pos)
	return dist > 5000.0

func _draw() -> void:
	if not editor or not editor.enabled or palette_open or regen_open or (progress_dialog and progress_dialog.visible) or (clutter_dialog and clutter_dialog.visible):
		return
	var center := size * 0.5

	match editor.sub_mode:
		Editor.SubMode.OBJECT:
			for width in [4.0, 2.0]:
				var color := Color(0, 0, 0, 0.85) if width == 4.0 else Color.WHITE
				draw_line(center - Vector2(9, 0), center + Vector2(9, 0), color, width)
				draw_line(center - Vector2(0, 9), center + Vector2(0, 9), color, width)

		Editor.SubMode.PAINTER:
			if is_painter_target_too_far():
				var x_size := 12.0
				for width in [4.0, 2.0]:
					var color := Color(0, 0, 0, 0.85) if width == 4.0 else Color(1.0, 0.25, 0.25)
					draw_line(center + Vector2(-x_size, -x_size), center + Vector2(x_size, x_size), color, width)
					draw_line(center + Vector2(-x_size, x_size), center + Vector2(x_size, -x_size), color, width)
			else:
				# Draw center crosshair
				for width in [4.0, 2.0]:
					var color := Color(0, 0, 0, 0.85) if width == 4.0 else Color.WHITE
					draw_line(center - Vector2(9, 0), center + Vector2(9, 0), color, width)
					draw_line(center - Vector2(0, 9), center + Vector2(0, 9), color, width)

				# Draw screen-attached ground-tilted circle
				var pts := get_screen_tilted_circle_points(48)
				if pts.size() >= 3:
					for width in [4.0, 2.0]:
						var color := Color(0, 0, 0, 0.85) if width == 4.0 else Color(0.2, 0.85, 1.0)
						draw_polyline(pts, color, width)

		Editor.SubMode.ELEVATION:
			var pts := get_oblique_triangle_points()
			if pts.size() >= 3:
				for width in [4.0, 2.0]:
					var color := Color(0, 0, 0, 0.85) if width == 4.0 else Color(1.0, 0.85, 0.25)
					draw_polyline(pts, color, width)
			else:
				var tri_pts := PackedVector2Array([
					center + Vector2(0, -24),
					center + Vector2(20.78, 12),
					center + Vector2(-20.78, 12),
					center + Vector2(0, -24)
				])
				for width in [4.0, 2.0]:
					var color := Color(0, 0, 0, 0.85) if width == 4.0 else Color(1.0, 0.85, 0.25)
					draw_polyline(tri_pts, color, width)
