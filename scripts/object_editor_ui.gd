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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor = Editor.new()
	add_child(editor)
	_build_active_object()
	_build_actions()
	_build_palette()
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
		editor.save_edits()
		status_label.text = editor.status)
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
	for button in [place_button, remove_button]:
		button.custom_minimum_size = Vector2(104, 56)
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
	header.add_child(_button("CLOSE", func(): set_palette_open(false)))
	palette_scroll = ScrollContainer.new()
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(palette_scroll)
	palette_grid = GridContainer.new()
	palette_grid.add_theme_constant_override("h_separation", 10)
	palette_grid.add_theme_constant_override("v_separation", 10)
	palette_scroll.add_child(palette_grid)
	# Build the preview worlds lazily, only when the palette is first opened.

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
		_populate_palette()
		for index in range(selection_buttons.size()):
			selection_buttons[index].set_pressed_no_signal(index == editor.selected_index)
		for preview in previews:
			preview.refresh()
	palette_visibility_changed.emit(palette_open)
	queue_redraw()

func contains_ui_point(point: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	if palette_open:
		return true
	return editor.enabled and (active_box.get_global_rect().has_point(point) or actions.get_global_rect().has_point(point))

func _layout() -> void:
	if not active_box:
		return
	active_box.position = Vector2((size.x - 296) * 0.5, 64)
	active_box.size = Vector2(296, 88)
	# Narrow portrait layouts need a separate row above the debug box.
	actions.position = Vector2((size.x - 216) * 0.5, size.y - (360 if size.x < 640 else 84))
	status_label.position = Vector2(0, 158)
	status_label.size = Vector2(size.x, 24)
	palette.position = Vector2(20, 60)
	palette.size = Vector2(maxf(size.x - 40, 180), maxf(size.y - 80, 180))
	palette_grid.columns = maxi(1, int((palette.size.x - 44) / 138))
	queue_redraw()

func _draw() -> void:
	if not editor or not editor.enabled or palette_open:
		return
	var center := size * 0.5
	for width in [4.0, 2.0]:
		var color := Color(0, 0, 0, 0.85) if width == 4.0 else Color.WHITE
		draw_line(center - Vector2(9, 0), center + Vector2(9, 0), color, width)
		draw_line(center - Vector2(0, 9), center + Vector2(0, 9), color, width)
