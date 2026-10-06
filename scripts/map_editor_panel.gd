class_name MapEditorPanel
extends VBoxContainer

const Config = preload("res://scripts/map_config.gd")
const Assets = preload("res://scripts/map_asset_loader.gd")
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
var expanded: Dictionary = {}

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	document = Config.load_map_config(Config.active_map()).duplicate(true)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_view = VBoxContainer.new()
	add_child(main_view)
	main_view.add_child(message)
	var row = VBoxContainer.new()
	main_view.add_child(row)
	label(row, "Map name")
	map_name = LineEdit.new()
	map_name.placeholder_text = "Name this map"
	map_name.max_length = 100
	map_name.custom_minimum_size.y = 44
	map_name.text_changed.connect(func(value): document["name"] = value.strip_edges())
	row.add_child(map_name)
	button(row, "Save map", func(): save_requested.emit())
	button(row, "Save as a new map", func(): save_as_requested.emit())
	button(row, "Generate terrain", func(): generate_requested.emit())
	var library = VBoxContainer.new()
	row.add_child(library)
	label(library, "Load replaces unsaved edits. Save first to keep them.")
	map_picker = OptionButton.new()
	map_picker.custom_minimum_size.y = 44
	map_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_picker.clip_text = true
	library.add_child(map_picker)
	button(library, "Refresh saved maps", refresh_maps)
	button(library, "Load selected map", func():
		if map_picker.selected >= 0:
			load_requested.emit(str(map_picker.get_item_metadata(map_picker.selected))))
	button(library, "New map from current app template", func(): new_requested.emit())
	button(library, "Import map (.cylmap)", func(): _choose_archive(false))
	button(library, "Save and export map (.cylmap)", func(): _choose_archive(true))
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
	picker.color_changed.connect(func(c): data[key] = Config.rgba(c))
	row.add_child(picker)

func section(title: String) -> VBoxContainer:
	var panel = VBoxContainer.new()
	body.add_child(panel)
	var toggle = button(panel, title, func(): pass)
	var content = VBoxContainer.new()
	panel.add_child(content)
	content.visible = expanded.get(title, false)
	toggle.pressed.connect(func(): content.visible = not content.visible; expanded[title] = content.visible)
	return content

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
	map_name.text = str(document.get("name", "My habitat"))
	document["name"] = map_name.text
	map_picker.clear()
	map_picker.add_item(str(document.get("name", "My habitat")))
	map_picker.set_item_metadata(0, str(document.get("map_directory", "")))
	map_picker.select(0)
	message.text = "Map-owned definitions · Save applies appearance; Generate replaces terrain and placements."
	var geo = section("Geometry, resolution & generation")
	for key in document.geometry:
		number(geo, key.replace("_", " "), document.geometry, key, 0, 1000000, 1)
	for key in document.rendering:
		if Config.finite_number(document.rendering[key]):
			number(geo, key.replace("_", " "), document.rendering, key, 1, 4096, 1)
	var initial_dims = Config.get_grid_dimensions(document)
	if not document.generation.has("sample_pitch_m"):
		document.generation["sample_pitch_m"] = initial_dims.sample_pitch_m

	var pitch_row = VBoxContainer.new()
	geo.add_child(pitch_row)
	var pitch_label = Label.new()
	pitch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch_row.add_child(pitch_label)

	var update_pitch_info = func():
		var d = Config.get_grid_dimensions(document)
		document.generation["elevation_width"] = d.elevation_width
		document.generation["elevation_height"] = d.elevation_height
		document.generation["terrain_width"] = d.terrain_width
		document.generation["terrain_height"] = d.terrain_height
		pitch_label.text = "Sample Pitch: %.1fm  ·  Grid: %d × %d px" % [float(document.generation.sample_pitch_m), d.elevation_width, d.elevation_height]

	update_pitch_info.call()

	var spin_row = HBoxContainer.new()
	pitch_row.add_child(spin_row)
	var l = Label.new()
	l.text = "Terrain Sample Pitch (m/px)"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin_row.add_child(l)
	var spin = SpinBox.new()
	spin.min_value = 0.5
	spin.max_value = 64.0
	spin.step = 0.5
	spin.value = float(document.generation.sample_pitch_m)
	spin.custom_minimum_size = Vector2(120, 44)
	spin.value_changed.connect(func(v):
		document.generation["sample_pitch_m"] = v
		update_pitch_info.call())
	spin_row.add_child(spin)

	for key in document.generation:
		if key in ["elevation_width", "elevation_height", "terrain_width", "terrain_height", "sample_pitch_m"]:
			continue
		number(geo, key.replace("_", " "), document.generation, key, 0, 1000000, 0.01 if key in ["sea_center_v", "noise_gain", "detail_strength", "biome_region_strength"] else 1)
	var env = section("Sky, atmosphere & water")
	for key in document.environment:
		if document.environment[key] is Array:
			color_control(env, key.replace("_", " "), document.environment, key)
		elif Config.finite_number(document.environment[key]):
			number(env, key.replace("_", " "), document.environment, key, 0, 100000, 0.05)
	for key in document.environment.water:
		if document.environment.water[key] is Array:
			if document.environment.water[key].size() == 4:
				color_control(env, "Water " + key, document.environment.water, key)
		else:
			number(env, "Water " + key, document.environment.water, key, 0, 5, 0.01)
	for group in document.simulation:
		var sim_panel = section("Simulation: " + group.replace("_", " "))
		for key in document.simulation[group]:
			var values: Dictionary = document.simulation[group]
			if values[key] is Array:
				color_control(sim_panel, key.replace("_", " "), values, key)
			elif values[key] is bool:
				var toggle = CheckButton.new()
				toggle.text = key.replace("_", " ")
				toggle.button_pressed = values[key]
				toggle.toggled.connect(func(v): values[key] = v)
				sim_panel.add_child(toggle)
			elif Config.finite_number(values[key]):
				number(sim_panel, key.replace("_", " "), values, key, -100000, 100000, 0.1)
	var lighting = section("Lighting palette")
	for key in document.lighting_palette:
		color_control(lighting, key, document.lighting_palette, key)
	var weather = section("Weather palette")
	for key in document.weather_palette:
		color_control(weather, key, document.weather_palette, key)
	var catalog_panel = section("Object palette & imports")
	button(catalog_panel, "Import object (.glb)", func(): choose_import("model", func(path):
		var id = "asset_" + path.get_file().get_basename()
		document.objects.model_catalog[id] = {"name": path.get_file().get_basename(), "scene_path": path, "behavior_type": 5, "variant": -1, "tint": [1,1,1,1], "light_color": [1,1,1,1], "light_energy": 0, "light_range_m": 10, "flicker": false}
		rebuild()))
	for id in document.objects.model_catalog:
		var entry: Dictionary = document.objects.model_catalog[id]
		label(catalog_panel, entry.name)
		color_control(catalog_panel, "Object tint", entry, "tint")
		color_control(catalog_panel, "Emitted light", entry, "light_color")
		number(catalog_panel, "Light energy", entry, "light_energy", 0, 100, 0.1)
		number(catalog_panel, "Light range (m)", entry, "light_range_m", 0, 10000, 1)
	var biome_panel = section("Biomes")
	label(biome_panel, "Select a biome to edit its terrain, climate, clutter and object rules.")
	biome_picker = OptionButton.new()
	biome_picker.custom_minimum_size.y = 48
	biome_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var biome_ids = document.biomes.keys()
	biome_ids.sort()
	if not biome_ids.has(selected_biome_id):
		selected_biome_id = str(biome_ids[0]) if not biome_ids.is_empty() else ""
	for id in biome_ids:
		var biome: Dictionary = document.biomes[id]
		biome_picker.add_item("%s  ·  %.0f%%" % [biome.name, biome.weight * 100])
		var index = biome_picker.item_count - 1
		biome_picker.set_item_metadata(index, id)
		if id == selected_biome_id:
			biome_picker.select(index)
	biome_picker.item_selected.connect(func(index): selected_biome_id = str(biome_picker.get_item_metadata(index)))
	biome_panel.add_child(biome_picker)
	button(biome_panel, "Add biome", _add_biome)
	button(biome_panel, "Edit selected biome", _show_selected_biome)
	biome_editor_screen.visible = false
	for warning in document.get("generation_warnings", []):
		label(body, "Generation note: " + str(warning))
	if document.has("generation_report"):
		var report = section("Last generation: requested / achieved")
		for id in document.generation_report:
			var r: Dictionary = document.generation_report[id]
			label(report, "%s: %.1f%% / %.1f%%" % [id, r.requested * 100, r.achieved * 100])

func _show_selected_biome() -> void:
	if not document.biomes.has(selected_biome_id):
		return
	main_view.visible = false
	biome_editor_screen.visible = true
	_build_biome(selected_biome_id)

func _close_biome_editor() -> void:
	biome_editor_screen.visible = false
	main_view.visible = true
	rebuild()

func _build_biome(id: String) -> void:
	for child in biome_editor_screen.get_children():
		biome_editor_screen.remove_child(child)
		child.queue_free()
	var b: Dictionary = document.biomes[id]
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	biome_editor_screen.add_child(box)
	var back = button(box, "‹ Back to map settings", _close_biome_editor)
	back.custom_minimum_size.y = 52
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
	button(box, "Import ground texture", func(): choose_import("texture", func(path): b.texture = path; message.text = "Imported texture for " + b.name))
	label(box, "Texture: " + str(b.texture))
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
	label(box, "Ground clutter — palette colors interpolate")
	var choose = OptionButton.new()
	for model in document.ground_clutter.models:
		choose.add_item(str(model))
	for asset in document.objects.model_catalog:
		choose.add_item("object:" + asset)
	box.add_child(choose)
	button(box, "Add selected clutter", func():
		if choose.item_count:
			var selected = choose.get_item_text(choose.selected)
			if selected.begins_with("object:"):
				var asset = selected.trim_prefix("object:")
				selected = "object_" + asset
				document.ground_clutter.models[selected] = {"scene_path": document.objects.model_catalog[asset].scene_path}
			b.clutter.append({"model": selected, "density_per_m2": 0.01, "scale_range": [1,1], "palette": [[1,1,1,1]]})
			_build_biome(id))
	button(box, "Import clutter model (.glb)", func(): choose_import("model", func(path):
		var model_id = path.get_file().get_basename()
		document.ground_clutter.models[model_id] = {"scene_path": path}
		b.clutter.append({"model": model_id, "density_per_m2": 0.01, "scale_range": [1,1], "palette": [[1,1,1,1]]})
		_build_biome(id)))
	for rule in b.clutter:
		label(box, str(rule.model))
		number(box, "Instances / m²", rule, "density_per_m2", 0, 1, 0.001)
		_scale_controls(box, rule)
		for i in rule.palette.size():
			var stop = {"color": rule.palette[i]}
			color_control(box, "Palette stop %d" % (i+1), stop, "color")
			var picker = box.get_child(box.get_child_count()-1).get_child(1)
			picker.color_changed.connect(func(c): rule.palette[i] = Config.rgba(c))
		button(box, "Add palette stop", func(): rule.palette.append(rule.palette.back().duplicate()); _build_biome(id))
		button(box, "Remove last palette stop", func():
			if rule.palette.size() > 1:
				rule.palette.pop_back()
				_build_biome(id))
		button(box, "Remove " + str(rule.model), func(): b.clutter.erase(rule); _build_biome(id))
	label(box, "Generated objects")
	var objects = OptionButton.new()
	for asset in document.objects.model_catalog:
		objects.add_item(asset)
	box.add_child(objects)
	button(box, "Add selected object rule", func():
		b.objects.append({"asset": objects.get_item_text(objects.selected), "density_per_sq_km": 1, "scale_range": [1,1]})
		_build_biome(id))
	for rule in b.objects:
		label(box, str(rule.asset))
		number(box, "Instances / km²", rule, "density_per_sq_km", 0, 10000, 0.1)
		_scale_controls(box, rule)
		button(box, "Remove object rule", func(): b.objects.erase(rule); _build_biome(id))

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
