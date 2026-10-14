class_name MapEditorPanel
extends VBoxContainer

const Config = preload("res://scripts/map_config.gd")
const Assets = preload("res://scripts/map_asset_loader.gd")
const Preview = preload("res://scripts/object_preview.gd")
const ColorPickerUI = preload("res://scripts/color_picker_ui.gd")
signal save_requested
signal generate_requested
signal save_as_requested
signal load_requested(directory: String)
signal new_requested
signal import_map_requested(path: String)
signal export_map_requested(path: String)
var map_name: LineEdit
var map_picker: OptionButton
var archive_dialog: FileDialog
var biome_picker: OptionButton
var biome_editor_screen: VBoxContainer
var selected_biome_id: String = ""
var document: Dictionary = {}
var message: Label
var body: VBoxContainer
var main_view: VBoxContainer
var file_dialog: FileDialog
var import_callback: Callable
var asset_selector_ui: Control
var biome_detail_container: VBoxContainer
var selected_rule_type := ""
var selected_rule_index := -1
var selected_rule_biome_id := ""

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	document = Config.load_map_config(Config.active_map()).duplicate(true)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_view = VBoxContainer.new()
	add_child(main_view)
	main_view.add_child(message)
	archive_dialog = FileDialog.new()
	archive_dialog.access = FileDialog.ACCESS_FILESYSTEM
	archive_dialog.use_native_dialog = true
	archive_dialog.filters = PackedStringArray(["*.cylmap ; Cylinder map", "*.zip ; Map ZIP archive"])
	archive_dialog.file_selected.connect(func(path):
		if archive_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
			export_map_requested.emit(path)
		else:
			import_map_requested.emit(path))
	add_child(archive_dialog)
	body = VBoxContainer.new()
	main_view.add_child(body)
	biome_editor_screen = VBoxContainer.new()
	biome_editor_screen.visible = false
	add_child(biome_editor_screen)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.use_native_dialog = true
	file_dialog.file_selected.connect(_import_file)
	add_child(file_dialog)
	rebuild()

func refresh_maps() -> void:
	map_picker.clear()
	for directory in Config.list_available_maps():
		var doc = Config.load_map_config(directory)
		map_picker.add_item(str(doc.get("name", "Unnamed map")))
		var index = map_picker.item_count - 1
		map_picker.set_item_metadata(index, directory)
		if directory == document.get("map_directory", ""):
			map_picker.select(index)
	if map_picker.item_count == 0:
		map_picker.add_item(str(document.get("name", "Unnamed map")))
		map_picker.set_item_metadata(0, str(document.get("map_directory", "")))
		map_picker.select(0)

func _choose_archive(exporting: bool) -> void:
	archive_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	archive_dialog.title = "Export map" if exporting else "Import map"
	if exporting:
		archive_dialog.current_file = str(document.get("name", "map")).validate_filename() + ".cylmap"
	archive_dialog.popup_centered_ratio(0.85)

func button(parent: Node, label: String, callback: Callable) -> Button:
	var b = Button.new()
	b.text = label
	b.custom_minimum_size.y = 44
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func label(parent: Node, text: String) -> void:
	var l = Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)

func number(parent: Node, title: String, data: Dictionary, key: String, low: float, high: float, step: float) -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var l = Label.new()
	l.text = title
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var spin = SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = data[key]
	spin.custom_minimum_size = Vector2(120,44)
	spin.value_changed.connect(func(v): data[key] = v)
	row.add_child(spin)

func color_control(parent: Node, title: String, data: Dictionary, key: String) -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var l = Label.new()
	l.text = title
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var picker = ColorPickerButton.new()
	picker.edit_alpha = true
	picker.color = Config.color(data[key])
	picker.custom_minimum_size = Vector2(100,44)
	ColorPickerUI.configure(picker)
	picker.color_changed.connect(func(c): data[key] = Config.rgba(c))
	row.add_child(picker)

func rebuild() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	body.visible = true
	main_view.visible = true
	biome_editor_screen.visible = false
	if document.is_empty():
		message.text = Config.last_error
		return
	message.text = "Map settings · Choose a category to edit. Changes are kept until you save or regenerate."
	label(body, "Map name")
	map_name = LineEdit.new()
	map_name.placeholder_text = "Name this map"
	map_name.max_length = 100
	map_name.custom_minimum_size.y = 44
	map_name.text = str(document.get("name", "My habitat"))
	map_name.text_changed.connect(func(value: String): document["name"] = value.strip_edges())
	body.add_child(map_name)
	var save_row := HBoxContainer.new()
	body.add_child(save_row)
	var save_button := button(save_row, "Save map", func(): save_requested.emit())
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var save_as_button := button(save_row, "Save as new", func(): save_as_requested.emit())
	save_as_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	label(body, "Map package")
	label(body, "Loading a map replaces these settings. Save first to keep your edits.")
	map_picker = OptionButton.new()
	map_picker.custom_minimum_size.y = 44
	map_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_picker.clip_text = true
	body.add_child(map_picker)
	refresh_maps()
	var library_row := HBoxContainer.new()
	body.add_child(library_row)
	var refresh_button := button(library_row, "Refresh", refresh_maps)
	refresh_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var load_button := button(library_row, "Load selected", func():
		if map_picker.selected >= 0:
			load_requested.emit(str(map_picker.get_item_metadata(map_picker.selected)))
	)
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var package_row := HBoxContainer.new()
	body.add_child(package_row)
	for package_button in [
		button(package_row, "New map", func(): new_requested.emit()),
		button(package_row, "Import .cylmap", func(): _choose_archive(false)),
		button(package_row, "Export .cylmap", func(): _choose_archive(true))
	]:
		package_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	label(body, "Map properties")
	var category_grid := GridContainer.new()
	category_grid.columns = 2
	category_grid.add_theme_constant_override("h_separation", 8)
	category_grid.add_theme_constant_override("v_separation", 8)
	body.add_child(category_grid)
	for category in [
		["Biomes", "biomes"], ["Climate", "climate"],
		["Lighting", "lighting"], ["Time Cycles", "time_cycles"],
		["Weather", "weather"], ["Environment", "environment"],
		["Terrain & Generation", "terrain"], ["Assets & Objects", "assets"],
		["Simulation", "simulation"]
	]:
		var category_id := str(category[1])
		var category_button := button(category_grid, str(category[0]), func(): _show_category_page(category_id))
		category_button.name = "MapCategory_" + category_id
		category_button.custom_minimum_size.y = 52
		category_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var regenerate_button := button(body, "Regenerate Map", func(): generate_requested.emit())
	regenerate_button.name = "RegenerateMapButton"
	regenerate_button.custom_minimum_size.y = 52
	var danger := StyleBoxFlat.new()
	danger.bg_color = Color(0.72, 0.12, 0.14, 1.0)
	danger.set_corner_radius_all(6)
	regenerate_button.add_theme_stylebox_override("normal", danger)
	var danger_hover := danger.duplicate() as StyleBoxFlat
	danger_hover.bg_color = Color(0.9, 0.16, 0.18, 1.0)
	regenerate_button.add_theme_stylebox_override("hover", danger_hover)
	var danger_pressed := danger.duplicate() as StyleBoxFlat
	danger_pressed.bg_color = Color(0.55, 0.08, 0.1, 1.0)
	regenerate_button.add_theme_stylebox_override("pressed", danger_pressed)
	regenerate_button.add_theme_color_override("font_color", Color.WHITE)
	regenerate_button.add_theme_color_override("font_hover_color", Color.WHITE)

func _show_category_page(category: String) -> void:
	for child in biome_editor_screen.get_children():
		biome_editor_screen.remove_child(child)
		child.queue_free()
	main_view.visible = false
	biome_editor_screen.visible = true
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	biome_editor_screen.add_child(page)
	var page_header := HBoxContainer.new()
	page.add_child(page_header)
	var back := button(page_header, "‹ Back", _close_category_page)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.custom_minimum_size.y = 48
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 18)
	title.text = _category_title(category)
	page.add_child(title)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	page.add_child(content)

	match category:
		"biomes": _build_biome_list(content)
		"climate": _build_climate_page(content)
		"lighting": _build_lighting_page(content)
		"time_cycles": _build_time_cycles_page(content)
		"weather": _build_weather_page(content)
		"environment": _build_environment_page(content)
		"terrain": _build_terrain_page(content)
		"assets": _build_assets_page(content)
		"simulation": _build_simulation_page(content)
		"report": _build_report_page(content)
	var save_page_button := button(page, "Save", func(): save_requested.emit())
	save_page_button.custom_minimum_size.y = 48

func _category_title(category: String) -> String:
	var titles := {
		"biomes": "Biomes", "climate": "Climate", "lighting": "Lighting",
		"time_cycles": "Time Cycles", "weather": "Weather", "environment": "Environment",
		"terrain": "Terrain & Generation", "assets": "Assets & Objects",
		"simulation": "Simulation", "report": "Reports"
	}
	return str(titles.get(category, "Map Properties"))

func _close_category_page() -> void:
	biome_editor_screen.visible = false
	main_view.visible = true
	rebuild()

func _close_map_editor_page() -> void:
	if asset_selector_ui and asset_selector_ui.has_method("set_regen_dialog_open"):
		asset_selector_ui.call("set_regen_dialog_open", false)
	else:
		_close_category_page()

func _populate_fields(parent: Node, values: Dictionary, skip: Array = [], low: float = -100000.0, high: float = 100000.0, step: float = 0.1) -> void:
	for key in values.keys():
		if skip.has(key):
			continue
		var value: Variant = values[key]
		var title := str(key).replace("_", " ").capitalize()
		if value is Array:
			if value.size() == 4:
				color_control(parent, title, values, key)
		elif value is bool:
			var toggle := CheckButton.new()
			toggle.text = title
			toggle.button_pressed = value
			toggle.toggled.connect(func(enabled: bool): values[key] = enabled)
			parent.add_child(toggle)
		elif Config.finite_number(value):
			number(parent, title, values, key, low, high, 1.0 if value is int else step)

func _build_biome_list(parent: Node) -> void:
	label(parent, "Select a biome to edit its terrain, climate, texture, clutter, and generated-object rules.")
	biome_picker = OptionButton.new()
	biome_picker.custom_minimum_size.y = 48
	biome_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var biome_ids: Array = document.biomes.keys()
	biome_ids.sort()
	if not biome_ids.has(selected_biome_id):
		selected_biome_id = str(biome_ids[0]) if not biome_ids.is_empty() else ""
	for id in biome_ids:
		var biome: Dictionary = document.biomes[id]
		biome_picker.add_item("%s  ·  %.0f%%" % [biome.name, biome.weight * 100.0])
		var index := biome_picker.item_count - 1
		biome_picker.set_item_metadata(index, id)
		if id == selected_biome_id:
			biome_picker.select(index)
	biome_picker.item_selected.connect(func(index: int):
		selected_biome_id = str(biome_picker.get_item_metadata(index))
		selected_rule_type = ""
		selected_rule_index = -1
		selected_rule_biome_id = selected_biome_id
		_build_biome(selected_biome_id, biome_detail_container))
	parent.add_child(biome_picker)
	button(parent, "Add biome", _add_biome)
	biome_detail_container = VBoxContainer.new()
	biome_detail_container.name = "SelectedBiomeEditor"
	biome_detail_container.add_theme_constant_override("separation", 8)
	parent.add_child(biome_detail_container)
	_build_biome(selected_biome_id, biome_detail_container)

func _build_climate_page(parent: Node) -> void:
	label(parent, "Climate inputs used to derive the habitat's seasonal weather profile.")
	var weather: Dictionary = document.simulation.get("weather_system", {})
	_populate_fields(parent, weather, ["day_of_year", "cloud_altitude_m", "cloud_coverage", "cloud_thickness_m", "precipitation_rate_mmh", "dust_density", "humidity_density_gm3", "rain_sheet_layer_count", "spin_direction", "auto_weather_cycle_enabled", "tie_to_in_game_clock", "trajectory_speed_scale"])

func _build_lighting_page(parent: Node) -> void:
	label(parent, "Axial light bar and authored lighting colors.")
	var light_bar: Dictionary = document.simulation.get("light_bar", {})
	_populate_fields(parent, light_bar, ["day_of_year", "earth_latitude_deg", "solar_span_hours", "time_of_day_hours", "time_scale", "use_real_time", "uniform_follows_solar_cycle", "gradient_follows_solar_cycle"])
	label(parent, "Lighting palette")
	_populate_fields(parent, document.lighting_palette)

func _build_time_cycles_page(parent: Node) -> void:
	label(parent, "Day/year progression and links between the lighting and climate cycles.")
	var light_bar: Dictionary = document.simulation.get("light_bar", {})
	_populate_fields(parent, light_bar, ["bar_radius", "enable_shadows", "end_color", "end_intensity", "global_intensity_multiplier", "num_segments", "preset", "start_color", "start_intensity"])
	var weather: Dictionary = document.simulation.get("weather_system", {})
	_populate_fields(parent, weather, ["ambient_pressure_kpa", "base_gravity", "cloud_altitude_m", "cloud_coverage", "cloud_thickness_m", "dust_density", "endcap_air_temperature_c", "humidity_density_gm3", "latitude_deg", "precipitation_rate_mmh", "rain_sheet_layer_count", "spin_direction", "trajectory_speed_scale", "water_pipe_temperature_c", "yearly_precipitation_mm"])

func _build_weather_page(parent: Node) -> void:
	label(parent, "Authored weather-system defaults and weather color palette.")
	var weather: Dictionary = document.simulation.get("weather_system", {})
	_populate_fields(parent, weather, ["day_of_year", "latitude_deg", "yearly_precipitation_mm"])
	label(parent, "Weather palette")
	_populate_fields(parent, document.weather_palette)

func _build_environment_page(parent: Node) -> void:
	label(parent, "Atmosphere, sky, and water appearance/physical parameters.")
	var environment: Dictionary = document.environment
	_populate_fields(parent, environment, ["water"], 0.0, 100000.0, 0.05)
	var water: Dictionary = environment.get("water", {})
	label(parent, "Water")
	_populate_fields(parent, water, [], 0.0, 5.0, 0.01)

func _build_terrain_page(parent: Node) -> void:
	label(parent, "World dimensions, render mesh resolution, and procedural terrain inputs.")
	button(parent, "Open Regeneration Workbench…", func(): generate_requested.emit())
	label(parent, "Geometry")
	_populate_fields(parent, document.geometry, [], 0.0, 1000000.0, 1.0)
	label(parent, "Rendering")
	_populate_fields(parent, document.rendering, [], 1.0, 4096.0, 1.0)
	label(parent, "Generation")
	var generation: Dictionary = document.generation
	var initial_dims := Config.get_grid_dimensions(document)
	if not generation.has("sample_pitch_m"):
		generation["sample_pitch_m"] = initial_dims.sample_pitch_m
	var pitch_label := Label.new()
	pitch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(pitch_label)
	var update_pitch := func():
		var dims := Config.get_grid_dimensions(document)
		generation["elevation_width"] = dims.elevation_width
		generation["elevation_height"] = dims.elevation_height
		generation["terrain_width"] = dims.terrain_width
		generation["terrain_height"] = dims.terrain_height
		pitch_label.text = "Sample pitch %.1f m/px · elevation grid %d × %d · terrain grid %d × %d" % [float(generation.sample_pitch_m), dims.elevation_width, dims.elevation_height, dims.terrain_width, dims.terrain_height]
	update_pitch.call()
	var pitch_data := {"sample_pitch_m": float(generation.sample_pitch_m)}
	number(parent, "Terrain sample pitch (m/px)", pitch_data, "sample_pitch_m", 0.5, 64.0, 0.5)
	parent.get_child(parent.get_child_count() - 1).get_child(1).value_changed.connect(func(value: float): generation["sample_pitch_m"] = value; update_pitch.call())
	_populate_fields(parent, generation, ["elevation_width", "elevation_height", "terrain_width", "terrain_height", "sample_pitch_m"], 0.0, 1000000.0, 0.01)

func _build_assets_page(parent: Node) -> void:
	label(parent, "Open the existing terrain-painting or object-placement interface to browse and edit world assets.")
	button(parent, "Open Terrain Interface", func():
		if asset_selector_ui and asset_selector_ui.has_method("open_terrain_interface"):
			asset_selector_ui.call("open_terrain_interface")
	)
	button(parent, "Open Objects Interface", func():
		if asset_selector_ui and asset_selector_ui.has_method("open_objects_interface"):
			asset_selector_ui.call("open_objects_interface")
	)

func _build_simulation_page(parent: Node) -> void:
	label(parent, "Player movement and particle-emitter defaults.")
	for group in ["player", "particle_emitter"]:
		if document.simulation.has(group):
			label(parent, group.replace("_", " ").capitalize())
			_populate_fields(parent, document.simulation[group])

func _build_report_page(parent: Node) -> void:
	label(parent, "Generation report")
	var warnings: Array = document.get("generation_warnings", [])
	if warnings.is_empty():
		label(parent, "No generation warnings.")
	else:
		label(parent, "Generation notes")
		for warning in warnings:
			label(parent, str(warning))
	if not document.has("generation_report"):
		label(parent, "No generation report is available yet.")
		return
	label(parent, "Requested / achieved biome coverage")
	for id in document.generation_report:
		var report: Dictionary = document.generation_report[id]
		label(parent, "%s: %.1f%% / %.1f%%" % [id, report.requested * 100.0, report.achieved * 100.0])

func _show_selected_biome() -> void:
	if not document.biomes.has(selected_biome_id):
		return
	_show_category_page("biomes")

func _close_biome_editor() -> void:
	_show_category_page("biomes")

func _build_biome(id: String, target: VBoxContainer = null) -> void:
	if not document.biomes.has(id):
		return
	var destination: VBoxContainer = target if target else biome_detail_container
	if not destination:
		return
	for child in destination.get_children():
		destination.remove_child(child)
		child.queue_free()
	var b: Dictionary = document.biomes[id]
	if selected_rule_biome_id != id:
		selected_rule_type = ""
		selected_rule_index = -1
		selected_rule_biome_id = id
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	destination.add_child(box)
	var title = Label.new()
	title.text = "EDIT BIOME · " + str(b.name)
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var name_field = LineEdit.new()
	name_field.text = b.name
	name_field.custom_minimum_size.y = 44
	name_field.text_changed.connect(func(value): b.name = value)
	box.add_child(name_field)
	var row = HBoxContainer.new()
	box.add_child(row)
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.01
	slider.value = b.weight
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 44
	row.add_child(slider)
	var value = Label.new()
	value.text = "Weight %.2f" % b.weight
	row.add_child(value)
	slider.value_changed.connect(func(v): b.weight = v; value.text = "Weight %.2f" % v)
	color_control(box, "Terrain RGBA tint", b, "tint")
	var blend = CheckButton.new()
	blend.text = "Blend with neighboring biomes"
	blend.button_pressed = b.blended
	blend.toggled.connect(func(v): b.blended = v)
	box.add_child(blend)
	button(box, "Select ground texture…", func(): _request_asset_selection("texture", func(entry: Dictionary):
		if not entry.is_empty():
			b.texture = str(entry.get("texture", entry.get("path", "")))
			message.text = "Selected texture for " + str(b.name)
		_build_biome(id, destination)))
	var texture_row := HBoxContainer.new()
	texture_row.add_theme_constant_override("separation", 8)
	box.add_child(texture_row)
	var texture_preview := TextureRect.new()
	texture_preview.name = "SelectedGroundTexturePreview"
	texture_preview.custom_minimum_size = Vector2(92, 64)
	texture_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_preview.texture = Assets.load_texture(Config.resolve_map_asset_path(document, str(b.texture))) if not str(b.texture).is_empty() else null
	texture_preview.self_modulate = Config.color(b.tint)
	texture_row.add_child(texture_preview)
	var texture_name := Label.new()
	texture_name.text = "Texture: " + str(b.texture)
	texture_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texture_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_row.add_child(texture_name)
	number(box, "Texture repeat (m)", b, "texture_size_m", 0.1, 10000, 0.1)
	number(box, "Roughness", b, "roughness", 0, 1, 0.01)
	number(box, "Maximum slope (degrees)", b, "max_slope_deg", 0, 90, 1)
	number(box, "Moisture preference", b, "moisture", 0, 1, 0.01)
	number(box, "Temperature preference", b, "temperature", 0, 1, 0.01)
	for i in 2:
		var bounds = {"value": b.elevation_range_m[i]}
		number(box, "Minimum elevation (m)" if i == 0 else "Maximum elevation (m)", bounds, "value", 0, document.geometry.elevation_variance_m, 0.1)
		var spin = box.get_child(box.get_child_count()-1).get_child(1)
		spin.value_changed.connect(func(v): b.elevation_range_m[i] = v)
	var underwater = CheckButton.new()
	underwater.text = "Submerged biome"
	underwater.button_pressed = b.submerged
	underwater.toggled.connect(func(v): b.submerged = v)
	box.add_child(underwater)
	label(box, "Ground clutter")
	button(box, "Select clutter model…", func(): _request_asset_selection("clutter", func(entry: Dictionary):
		if entry.get("empty_selection", false):
			message.text = "No clutter model added"
		elif not entry.is_empty():
			var selected := str(entry.get("clutter_model_id", ""))
			if selected.is_empty():
				var asset_id := str(entry.get("object_asset_id", entry.get("id", "")))
				selected = "object_" + asset_id
				document.ground_clutter.models[selected] = {"scene_path": str(entry.get("scene_path", ""))}
				_adopt_object_definition(entry)
			b.clutter.append({"model": selected, "density_per_m2": 0.01, "scale_range": [1,1], "palette": [[1,1,1,1]]})
		_build_biome(id, destination)))
	for rule_index in b.clutter.size():
		var rule: Dictionary = b.clutter[rule_index]
		var model_id := str(rule.get("model", ""))
		var model: Dictionary = document.ground_clutter.models.get(model_id, {})
		var palette: Array = rule.get("palette", [[1, 1, 1, 1]])
		var tint := _average_palette_color(palette)
		var model_path := Config.get_clutter_model_path(document, model_id)
		_build_asset_rule_row(box, model_id, model_path, tint, func():
			selected_rule_type = "clutter"
			selected_rule_index = rule_index
			selected_rule_biome_id = id
			_build_biome(id, destination), func():
			b.clutter.remove_at(rule_index)
			_clear_deleted_rule("clutter", rule_index)
			_build_biome(id, destination))
		if selected_rule_type == "clutter" and selected_rule_index == rule_index:
			_build_clutter_rule_detail(box, id, destination, b, rule, model)
	label(box, "Generated objects")
	button(box, "Select object for rule…", func(): _request_asset_selection("object", func(entry: Dictionary):
		if entry.get("empty_selection", false):
			message.text = "No generated-object rule added"
		elif not entry.is_empty():
			var asset_id := str(entry.get("id", ""))
			_adopt_object_definition(entry)
			b.objects.append({"asset": asset_id, "density_per_sq_km": 1, "scale_range": [1,1]})
		_build_biome(id, destination)))
	for rule_index in b.objects.size():
		var rule: Dictionary = b.objects[rule_index]
		var asset_id := str(rule.get("asset", ""))
		var asset: Dictionary = document.objects.model_catalog.get(asset_id, {})
		var asset_path := Config.resolve_map_asset_path(document, str(asset.get("scene_path", "")))
		var tint := Config.color(asset.get("tint", [1, 1, 1, 1]))
		_build_asset_rule_row(box, str(asset.get("name", asset_id)), asset_path, tint, func():
			selected_rule_type = "object"
			selected_rule_index = rule_index
			selected_rule_biome_id = id
			_build_biome(id, destination), func():
			b.objects.remove_at(rule_index)
			_clear_deleted_rule("object", rule_index)
			_build_biome(id, destination))
		if selected_rule_type == "object" and selected_rule_index == rule_index:
			_build_object_rule_detail(box, id, destination, b, rule)
func _build_asset_rule_row(parent: Node, display_name: String, model_path: String, tint: Color, open_detail: Callable, delete_rule: Callable) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.custom_minimum_size.y = 58
	parent.add_child(line)
	var row_button := Button.new()
	row_button.name = "BiomeAssetRule_" + display_name.validate_node_name()
	row_button.custom_minimum_size.y = 58
	row_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_button.pressed.connect(open_detail)
	line.add_child(row_button)
	var contents := HBoxContainer.new()
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_theme_constant_override("separation", 8)
	row_button.add_child(contents)
	contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contents.offset_left = 6
	contents.offset_right = -6
	var preview := Preview.new()
	preview.name = "BiomeAssetRulePreview"
	preview.custom_minimum_size = Vector2(48, 48)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_child(preview)
	if not model_path.is_empty():
		preview.show_model(model_path, tint)
	var name_label := Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_child(name_label)
	var delete_button := Button.new()
	delete_button.name = "DeleteBiomeAssetRule"
	delete_button.text = "×"
	delete_button.tooltip_text = "Remove this rule"
	delete_button.custom_minimum_size = Vector2(48, 48)
	delete_button.add_theme_font_size_override("font_size", 24)
	var red := StyleBoxFlat.new()
	red.bg_color = Color(0.72, 0.12, 0.14, 1.0)
	red.set_corner_radius_all(6)
	delete_button.add_theme_stylebox_override("normal", red)
	var red_hover := red.duplicate() as StyleBoxFlat
	red_hover.bg_color = Color(0.9, 0.16, 0.18, 1.0)
	delete_button.add_theme_stylebox_override("hover", red_hover)
	delete_button.add_theme_color_override("font_color", Color.WHITE)
	delete_button.pressed.connect(delete_rule)
	line.add_child(delete_button)

func _average_palette_color(palette: Array) -> Color:
	if palette.is_empty():
		return Color.WHITE
	var total := Color(0, 0, 0, 0)
	var count := 0
	for entry in palette:
		if entry is Array and entry.size() == 4:
			total += Config.color(entry)
			count += 1
	return total / float(count) if count > 0 else Color.WHITE

func _build_clutter_rule_detail(parent: Node, id: String, destination: VBoxContainer, biome: Dictionary, rule: Dictionary, model: Dictionary) -> void:
	label(parent, "CLUTTER DETAILS · " + str(rule.get("model", "")))
	var definition: Dictionary = model
	_populate_fields(parent, definition, ["scene_path", "type"], 0.0, 10000.0, 0.01)
	number(parent, "Instances / m²", rule, "density_per_m2", 0, 1, 0.001)
	_scale_controls(parent, rule)
	var palette: Array = rule.get("palette", [[1, 1, 1, 1]])
	label(parent, "Palette")
	var swatches := HFlowContainer.new()
	swatches.name = "ClutterColorSwatches"
	swatches.add_theme_constant_override("h_separation", 8)
	swatches.add_theme_constant_override("v_separation", 8)
	parent.add_child(swatches)
	for stop_index in palette.size():
		var picker := ColorPickerButton.new()
		picker.name = "ClutterPaletteColor_%d" % stop_index
		picker.tooltip_text = "Color %d · tap to edit · press and hold or right-click to delete" % (stop_index + 1)
		picker.custom_minimum_size = Vector2(76, 56)
		picker.edit_alpha = true
		picker.color = Config.color(palette[stop_index])
		ColorPickerUI.configure(picker)
		picker.color_changed.connect(func(color: Color): rule.palette[stop_index] = Config.rgba(color))
		swatches.add_child(picker)
		var press_state := {"long_press": false}
		var hold_timer := Timer.new()
		hold_timer.one_shot = true
		hold_timer.wait_time = 0.6
		picker.add_child(hold_timer)
		var menu := PopupMenu.new()
		menu.name = "PaletteColorContextMenu"
		menu.add_item("Delete color", 0)
		menu.set_item_disabled(0, palette.size() <= 1)
		picker.add_child(menu)
		menu.id_pressed.connect(func(action_id: int):
			if action_id == 0 and rule.palette.size() > 1:
				rule.palette.remove_at(stop_index)
				_build_biome(id, destination))
		menu.popup_hide.connect(func():
			press_state.long_press = false
			if is_instance_valid(picker):
				picker.disabled = false)
		hold_timer.timeout.connect(func():
			press_state.long_press = true
			_open_palette_color_menu(picker, menu))
		picker.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				press_state.long_press = true
				_open_palette_color_menu(picker, menu)
				picker.accept_event()
			elif event is InputEventScreenTouch:
				if event.pressed:
					press_state.long_press = false
					hold_timer.start()
				else:
					hold_timer.stop())
		picker.pressed.connect(func():
			if press_state.long_press:
				press_state.long_press = false)
	var add_color := button(parent, "+ Add color", func():
		rule.palette.append(rule.palette.back().duplicate(true) if not rule.palette.is_empty() else [1, 1, 1, 1])
		_build_biome(id, destination))
	add_color.name = "AddClutterPaletteColor"
	add_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _open_palette_color_menu(anchor: Control, menu: PopupMenu) -> void:
	anchor.disabled = true
	var rect := anchor.get_global_rect()
	var screen_size := DisplayServer.screen_get_size()
	var menu_position := Vector2i(rect.position.x, rect.end.y)
	if screen_size.x > 0 and screen_size.y > 0:
		menu_position.x = clampi(menu_position.x, 0, maxi(screen_size.x - 220, 0))
		menu_position.y = clampi(menu_position.y, 0, maxi(screen_size.y - 80, 0))
	menu.position = menu_position
	menu.popup()

func _build_object_rule_detail(parent: Node, id: String, destination: VBoxContainer, _biome: Dictionary, rule: Dictionary) -> void:
	label(parent, "MAP OBJECT DETAILS · " + str(rule.get("asset", "")))
	number(parent, "Instances / km²", rule, "density_per_sq_km", 0, 10000, 0.1)
	_scale_controls(parent, rule)

func _clear_deleted_rule(kind: String, deleted_index: int) -> void:
	if selected_rule_type != kind:
		return
	if selected_rule_index == deleted_index:
		selected_rule_type = ""
		selected_rule_index = -1
	elif selected_rule_index > deleted_index:
		selected_rule_index -= 1

func _request_asset_selection(kind: String, callback: Callable) -> void:
	if asset_selector_ui and asset_selector_ui.has_method("request_map_asset_selection"):
		asset_selector_ui.call("request_map_asset_selection", kind, callback)
	else:
		message.text = "The object/texture selector is unavailable"

func _adopt_object_definition(entry: Dictionary) -> void:
	var asset_id := str(entry.get("object_asset_id", entry.get("id", "")))
	if asset_id.is_empty() or document.objects.model_catalog.has(asset_id):
		return
	var definition: Dictionary = entry.get("definition", {}).duplicate(true)
	if definition.is_empty():
		for key in ["name", "scene_path", "behavior_type", "variant", "tint", "light_color", "light_energy", "light_range_m", "flicker", "ground_offset_m", "align_to_normal", "random_yaw", "allow_on_side", "on_side_chance", "solid", "collision_config"]:
			if entry.has(key):
				definition[key] = entry[key]
	if not definition.has("scene_path"):
		definition["scene_path"] = str(entry.get("path", ""))
	document.objects.model_catalog[asset_id] = definition

func _add_biome() -> void:
	var ids: Array = []
	for biome in document.biomes.values():
		ids.append(int(biome.raster_id))
	var id = 0
	while ids.has(id):
		id += 1
	if id > 255:
		message.text = "All 256 biome IDs are in use"
		return
	var b: Dictionary = document.biomes.values()[0].duplicate(true)
	b.raster_id = id
	b.name = "New biome %d" % id
	b.weight = 0
	b.clutter = []
	b.objects = []
	var new_key = "biome_%d" % id
	document.biomes[new_key] = b
	selected_biome_id = new_key
	rebuild()
	_show_selected_biome()

func choose_import(kind: String, callback: Callable) -> void:
	import_callback = callback
	file_dialog.set_meta("kind", kind)
	file_dialog.filters = PackedStringArray(["*.glb ; Self-contained GLB model"]) if kind == "model" else PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Ground texture"])
	file_dialog.popup_centered_ratio(0.85)

func _import_file(path: String) -> void:
	var bytes = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or bytes.size() > 67108864:
		message.text = "Import requires a nonempty file under 64 MiB"
		return
	# Content-addressed imports avoid accidental replacement of another asset.
	var hashing = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	var id = hashing.finish().hex_encode().left(24)
	var is_model = file_dialog.get_meta("kind") == "model"
	var path_out = "user://map_imports/" + id + (".glb" if is_model else ".png")
	DirAccess.make_dir_recursive_absolute("user://map_imports")
	if is_model:
		var f = FileAccess.open(path_out, FileAccess.WRITE)
		if not f:
			message.text = "Cannot write imported model"
			return
		f.store_buffer(bytes)
		f.close()
		var instance = Assets.instantiate_model(path_out)
		if not instance:
			message.text = "Model must be a valid self-contained GLB"
			return
		instance.free()
	else:
		var img = Assets.load_image(path)
		if not img or not Assets.texture_dimensions_allowed(Vector2i(img.get_width(), img.get_height())):
			message.text = "Texture limit: each side up to 8192 px and at most 16,777,216 total pixels"
			return
		if img.save_png(path_out) != OK:
			message.text = "Unable to save imported texture"
			return
	import_callback.call(path_out)
	message.text = "Imported; Save or Generate to include it in the map"

func package_imports(directory: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(directory.path_join("assets")) != OK:
		return false
	for biome in document.biomes.values():
		if not _package_path(biome, "texture", directory):
			return false
	for catalog in [document.objects.model_catalog, document.ground_clutter.models]:
		for definition in catalog.values():
			if not _package_path(definition, "scene_path", directory):
				return false
	return true

func _package_path(record: Dictionary, key: String, directory: String) -> bool:
	var path: String = record[key]
	if path.begins_with("user://map_imports/"):
		var relative = "assets/" + path.get_file()
		if DirAccess.copy_absolute(path, directory.path_join(relative)) != OK:
			return false
		record[key] = relative
	return true

func _scale_controls(parent: Node, rule: Dictionary) -> void:
	for i in 2:
		var value = {"scale": rule.scale_range[i]}
		number(parent, "Minimum scale" if i == 0 else "Maximum scale", value, "scale", 0.01, 100, 0.01)
		parent.get_child(parent.get_child_count()-1).get_child(1).value_changed.connect(func(v): rule.scale_range[i] = v)
