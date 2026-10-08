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
var paint_button: Button
var raise_button: Button
var lower_button: Button
var smooth_button: Button
var brush_minus_btn: Button
var brush_plus_btn: Button
var select_button: Button
var save_button: Button
var regen_button: Button
var replace_active_button: Button
var rotate_checkbox: CheckBox
var target_replace_texture_index: int = -1

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
var clutter_dialog: PanelContainer
var clutter_density_slider: HSlider
var clutter_density_label: Label

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
	_build_submode_bar()
	_build_active_object()
	_build_actions()
	_build_palette()
	_build_clutter_dialog()
	_build_regen_dialog()
	_build_confirm_dialog()
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

	regen_button = _button("REGEN MAP", func(): set_regen_dialog_open(true))
	var red_style := StyleBoxFlat.new()
	red_style.bg_color = Color(0.85, 0.15, 0.15, 0.95)
	red_style.border_color = Color(1.0, 0.35, 0.35, 0.9)
	red_style.set_border_width_all(1)
	red_style.set_corner_radius_all(6)
	regen_button.add_theme_stylebox_override("normal", red_style)
	regen_button.add_theme_stylebox_override("hover", red_style)
	regen_button.add_theme_color_override("font_color", Color.WHITE)
	regen_button.tooltip_text = "REGEN MAP: WARNING - Regenerating will CLEAR all terrain, elevation, and placed objects!"

	for btn in [obj_mode_btn, paint_mode_btn, elev_mode_btn, regen_button]:
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

	regen_button = _button("MAP CFG", func():
		set_regen_dialog_open(true)
		map_editor.map_name.grab_focus())
	regen_button.custom_minimum_size.x = 80
	buttons.add_child(regen_button)

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

	import_palette_btn = _button("ADD OBJECT", func(): _open_import_dialog())
	header.add_child(import_palette_btn)

	edit_clutter_btn = _button("CLUTTER", func():
		set_clutter_dialog_open(true))
	edit_clutter_btn.visible = false
	header.add_child(edit_clutter_btn)

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

	var dialog_w := int(minf(700, size.x - 20))
	var dialog_h := int(minf(500, size.y - 20))
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
		editor.import_object_model(path)
	elif current_import_mode == "replace_texture":
		if target_replace_texture_index >= 0:
			editor.replace_ground_texture(target_replace_texture_index, path, rotate_setting)
			target_replace_texture_index = -1
	else:
		editor.import_ground_texture(path, rotate_setting)
	status_label.text = editor.status

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
	clutter_density_label.text = "Clutter Density: 0.50"
	column.add_child(clutter_density_label)

	clutter_density_slider = HSlider.new()
	clutter_density_slider.min_value = 0.0
	clutter_density_slider.max_value = 2.0
	clutter_density_slider.step = 0.05
	clutter_density_slider.value = 0.5
	clutter_density_slider.value_changed.connect(func(val: float):
		clutter_density_label.text = "Clutter Density: %.2f" % val
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

func set_clutter_dialog_open(open: bool) -> void:
	if clutter_dialog:
		clutter_dialog.visible = open
		if open:
			_layout()

func _on_generate_biome_pressed() -> void:
	_layout()
	if confirm_dialog:
		confirm_dialog.visible = true

func _execute_map_regeneration() -> void:
	if str(map_editor.document.get("name", "")).strip_edges().is_empty():
		_map_failure("Give the map a name before generating")
		return
	if confirm_dialog:
		confirm_dialog.visible = false
	_layout()
	if progress_dialog:
		progress_dialog.visible = true
	gen_progress_bar.value = 0
	reload_progress_bar.value = 0
	var generator = preload("res://scripts/map_generator.gd")
	var cb = func(value: float, message: String):
		if is_instance_valid(gen_progress_bar):
			gen_progress_bar.value = value * 100
		if is_instance_valid(progress_status_label):
			progress_status_label.text = message
		var tree = get_tree()
		if tree:
			await tree.process_frame
	var result = await generator.generate(map_editor.document, cb)
	if result.has("error"):
		_map_failure(result.error)
		return
	var directory = MapConfig.new_user_directory("generated")
	await cb.call(0.93, "Saving generated map")
	if not generator.save_generated_map_package(result, directory, cb):
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
	if world and world.terrain_manager:
		var elev_path = directory.path_join(map_editor.document.files.elevation_map)
		var terr_path = directory.path_join(map_editor.document.files.terrain_map)
		DirAccess.make_dir_recursive_absolute(elev_path.get_base_dir())
		DirAccess.make_dir_recursive_absolute(terr_path.get_base_dir())
		world.terrain_manager.save_elevation(elev_path)
		world.terrain_manager.save_terrain(terr_path)
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
	_update_palette_columns()
	for child in palette_grid.get_children():
		palette_grid.remove_child(child)
		child.queue_free()
	selection_buttons.clear()
	previews.clear()

	if not editor:
		return

	if editor.sub_mode == Editor.SubMode.OBJECT:
		if palette_title_label:
			palette_title_label.text = "SELECT OBJECT"
		if import_palette_btn:
			import_palette_btn.text = "ADD OBJECT"
		if edit_clutter_btn:
			edit_clutter_btn.visible = false

		for index in range(editor.catalog.size()):
			var entry := editor.catalog[index]
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

	elif editor.sub_mode == Editor.SubMode.PAINTER:
		if palette_title_label:
			palette_title_label.text = "SELECT TERRAIN IMAGE"
		if import_palette_btn:
			import_palette_btn.text = "ADD TERRAIN IMAGE"
		if edit_clutter_btn:
			edit_clutter_btn.visible = true

		for index in range(editor.texture_catalog.size()):
			var entry := editor.texture_catalog[index]
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
	if editor.sub_mode == Editor.SubMode.OBJECT:
		editor.selected_index = index
	elif editor.sub_mode == Editor.SubMode.PAINTER:
		editor.selected_texture_index = index
		if index >= 0 and index < editor.texture_catalog.size():
			editor.selected_biome_id = int(editor.texture_catalog[index].get("id", 0))
	_update_active_box_content()
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
			select_button.disabled = true
		else:
			current_name.text = str(entry.get("name", "Object"))
			current_preview.show_model(entry.path)
			place_button.disabled = false
			select_button.disabled = false
		for index in range(selection_buttons.size()):
			selection_buttons[index].set_pressed_no_signal(index == editor.selected_index)
	elif editor.sub_mode == Editor.SubMode.PAINTER:
		current_preview.visible = false
		if not texture_swatch:
			texture_swatch = TextureRect.new()
			texture_swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			current_preview.get_parent().add_child(texture_swatch)
			texture_swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		texture_swatch.visible = true
		var entry := editor.current_texture()
		if entry.is_empty():
			current_name.text = "No terrain images available"
			if paint_button: paint_button.disabled = true
			select_button.disabled = true
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
			select_button.disabled = false
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
	if palette_open or regen_open or (confirm_dialog and confirm_dialog.visible) or (progress_dialog and progress_dialog.visible) or (clutter_dialog and clutter_dialog.visible):
		return true
	var in_submode := submode_bar.get_global_rect().has_point(point) if submode_bar and submode_bar.visible else false
	var in_active := active_box.get_global_rect().has_point(point) if active_box and active_box.visible else false
	var in_actions := actions.get_global_rect().has_point(point) if actions and actions.visible else false
	return editor.enabled and (in_submode or in_active or in_actions)

func _layout() -> void:
	if not active_box:
		return
	active_box.position = Vector2((size.x - 390) * 0.5, 60)
	active_box.size = Vector2(390, 88)
	if submode_bar:
		submode_bar.position = Vector2((size.x - 390) * 0.5, 154)
		submode_bar.size = Vector2(390, 36)
	actions.position = Vector2((size.x - 280) * 0.5, size.y - (360 if size.x < 640 else 84))
	status_label.position = Vector2(0, 196)
	status_label.size = Vector2(size.x, 24)
	palette.position = Vector2(20, 60)
	palette.size = Vector2(maxf(size.x - 40, 180), maxf(size.y - 80, 180))
	_update_palette_columns()

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
	if clutter_dialog:
		clutter_dialog.position = Vector2((size.x - 320) * 0.5, (size.y - 180) * 0.5)
		clutter_dialog.size = Vector2(320, 180)
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


