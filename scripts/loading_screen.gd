class_name LoadingScreen
extends CanvasLayer

signal loading_completed

@export var auto_start: bool = true
@export var min_display_time: float = 0.75

var root_control: Control = null
var background_rect: ColorRect = null
var center_container: CenterContainer = null
var card_panel: PanelContainer = null
var title_label: Label = null
var subtitle_label: Label = null
var status_label: Label = null
var substatus_label: Label = null
var progress_bar: ProgressBar = null
var percentage_label: Label = null
var spinner_label: Label = null

var current_progress: float = 0.0
var target_progress: float = 0.0
var is_loading_finished: bool = false
var elapsed_time: float = 0.0
var spinner_idx: int = 0
var spinner_timer: float = 0.0
const SPINNER_CHARS = ["◓", "◑", "◒", "◐"]

func _init() -> void:
	layer = 100

func _ready() -> void:
	layer = 100
	_build_ui()
	if auto_start:
		start_loading_sequence()

func _build_ui() -> void:
	root_control = get_node_or_null("LoadingRoot") as Control
	if not root_control:
		root_control = Control.new()
		root_control.name = "LoadingRoot"
		root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
		root_control.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(root_control)

	background_rect = root_control.get_node_or_null("Background") as ColorRect
	if not background_rect:
		background_rect = ColorRect.new()
		background_rect.name = "Background"
		background_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		background_rect.color = Color(0.025, 0.035, 0.05, 1.0)
		background_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		root_control.add_child(background_rect)

	center_container = root_control.get_node_or_null("CenterContainer") as CenterContainer
	if not center_container:
		center_container = CenterContainer.new()
		center_container.name = "CenterContainer"
		center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root_control.add_child(center_container)

	card_panel = center_container.get_node_or_null("CardPanel") as PanelContainer
	if not card_panel:
		card_panel = PanelContainer.new()
		card_panel.name = "CardPanel"
		card_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.06, 0.08, 0.12, 0.92)
		panel_style.border_width_left = 2
		panel_style.border_width_top = 2
		panel_style.border_width_right = 2
		panel_style.border_width_bottom = 2
		panel_style.border_color = Color(0.25, 0.55, 0.85, 0.75)
		panel_style.corner_radius_top_left = 10
		panel_style.corner_radius_top_right = 10
		panel_style.corner_radius_bottom_right = 10
		panel_style.corner_radius_bottom_left = 10
		panel_style.content_margin_left = 16.0
		panel_style.content_margin_top = 18.0
		panel_style.content_margin_right = 16.0
		panel_style.content_margin_bottom = 18.0
		card_panel.add_theme_stylebox_override("panel", panel_style)
		center_container.add_child(card_panel)

	var vbox = VBoxContainer.new()
	vbox.name = "ContentVBox"
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_panel.add_child(vbox)

	# Header tag
	var tag_label = Label.new()
	tag_label.text = "● CYLINDER HABITAT SIMULATION ●"
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag_label.add_theme_color_override("font_color", Color(0.35, 0.80, 1.0, 0.9))
	tag_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(tag_label)

	# Title
	title_label = Label.new()
	title_label.text = "O'NEILL CYLINDER"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
	title_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title_label)

	# Subtitle
	subtitle_label = Label.new()
	subtitle_label.text = "Island One Settlement • Atmospheric Physics Engine"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.90, 0.8))
	subtitle_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(subtitle_label)

	var sep1 = HSeparator.new()
	var sep_style = StyleBoxLine.new()
	sep_style.color = Color(0.25, 0.45, 0.65, 0.4)
	sep1.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep1)

	# Status row (Status + Percentage)
	var status_row = HBoxContainer.new()
	status_row.name = "StatusRow"
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(status_row)

	spinner_label = Label.new()
	spinner_label.text = "◓ "
	spinner_label.add_theme_color_override("font_color", Color(0.35, 0.80, 1.0, 1.0))
	spinner_label.add_theme_font_size_override("font_size", 13)
	status_row.add_child(spinner_label)

	status_label = Label.new()
	status_label.text = "Initializing Habitat Systems..."
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0, 0.95))
	status_label.add_theme_font_size_override("font_size", 12)
	status_row.add_child(status_label)

	percentage_label = Label.new()
	percentage_label.text = "0%"
	percentage_label.add_theme_color_override("font_color", Color(0.35, 0.80, 1.0, 1.0))
	percentage_label.add_theme_font_size_override("font_size", 12)
	status_row.add_child(percentage_label)

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.custom_minimum_size = Vector2(0.0, 10.0)
	progress_bar.show_percentage = false
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0

	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.11, 0.16, 0.9)
	bar_bg.corner_radius_top_left = 5
	bar_bg.corner_radius_top_right = 5
	bar_bg.corner_radius_bottom_right = 5
	bar_bg.corner_radius_bottom_left = 5
	progress_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill = StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.20, 0.68, 1.0, 0.95)
	bar_fill.border_width_top = 1
	bar_fill.border_width_bottom = 1
	bar_fill.border_color = Color(0.7, 0.9, 1.0, 0.8)
	bar_fill.corner_radius_top_left = 5
	bar_fill.corner_radius_top_right = 5
	bar_fill.corner_radius_bottom_right = 5
	bar_fill.corner_radius_bottom_left = 5
	progress_bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(progress_bar)

	# Substatus
	substatus_label = Label.new()
	substatus_label.text = "Preparing simulation parameters..."
	substatus_label.add_theme_color_override("font_color", Color(0.55, 0.70, 0.85, 0.75))
	substatus_label.add_theme_font_size_override("font_size", 11)
	substatus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(substatus_label)

	var sep2 = HSeparator.new()
	sep2.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep2)

	# Habitat Metrics footer
	var specs_label = Label.new()
	specs_label.text = "• Radius: 4,000 m  • Length: 18,000 m\n• Gravity: 1.00 G  • Surface Area: ~452 km²"
	specs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	specs_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	specs_label.add_theme_color_override("font_color", Color(0.45, 0.60, 0.75, 0.7))
	specs_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(specs_label)

	# Dynamic screen scaling listener
	var vp = get_viewport()
	if vp and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()

func _on_viewport_resized() -> void:
	if not card_panel or not is_instance_valid(card_panel):
		return
	var vp = get_viewport()
	if not vp:
		return
	var vp_size = vp.get_visible_rect().size
	if vp_size.x <= 0:
		return
	# Scale card panel smoothly to screen width on mobile phone screens (320px..480px)
	var max_card_w = minf(vp_size.x - 24.0, 440.0)
	card_panel.custom_minimum_size.x = maxf(max_card_w, 280.0)

func _process(delta: float) -> void:
	elapsed_time += delta

	# Animate spinner
	spinner_timer += delta
	if spinner_timer >= 0.12:
		spinner_timer = 0.0
		spinner_idx = (spinner_idx + 1) % SPINNER_CHARS.size()
		if spinner_label:
			spinner_label.text = SPINNER_CHARS[spinner_idx] + " "

	# Smoothly interpolate progress bar
	current_progress = lerpf(current_progress, target_progress, clampf(delta * 12.0, 0.0, 1.0))
	if progress_bar:
		progress_bar.value = current_progress
	if percentage_label:
		percentage_label.text = "%d%%" % int(round(current_progress))

func _set_step(status_text: String, sub_text: String, progress: float) -> void:
	if status_label:
		status_label.text = status_text
	if substatus_label:
		substatus_label.text = sub_text
	target_progress = progress

func start_loading_sequence() -> void:
	var is_headless = DisplayServer.get_name() == "headless"

	# Fast-path for headless test runs
	if is_headless:
		_set_step("Habitat Systems Online", "Ready", 100.0)
		target_progress = 100.0
		current_progress = 100.0
		if progress_bar:
			progress_bar.value = 100.0
		if percentage_label:
			percentage_label.text = "100%"
		loading_completed.emit()
		queue_free()
		return

	# Step 1: Terrain & World Grid
	_set_step("Generating Habitat Terrain...", "Synthesizing elevation maps & cylindrical geometry (69,984 faces)...", 25.0)
	await get_tree().process_frame

	var cylinder_world = get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator
	if cylinder_world:
		if not cylinder_world.terrain_manager:
			cylinder_world._initialize_terrain_manager()
		cylinder_world.generate_cylinder()
	await get_tree().process_frame

	# Step 2: Atmospheric & Cloud Deck Physics
	_set_step("Synthesizing Atmospheric Cloud Layers...", "Generating toroidal C-infinity cloud noise texture & geometry...", 50.0)
	await get_tree().process_frame

	var weather = get_tree().get_first_node_in_group("weather_system") as WeatherSystem
	if weather:
		weather._warm_up_texture_caches()
		weather._build_cloud_mesh()
	await get_tree().process_frame

	# Step 3: Precipitation & Streak Surfaces
	_set_step("Initializing Precipitation Surfaces...", "Pre-baking rain/snow streaks & transparent shader material buffers...", 75.0)
	await get_tree().process_frame

	if weather:
		weather._warm_up_texture_caches()
		weather._build_rain_sheets()
		if weather.precipitation_rate_mmh > 0.05:
			weather._update_precipitation_emitter()
		weather.is_weather_ready = true
	await get_tree().process_frame

	# Step 4: Axial Lighting & Solar Array
	_set_step("Calibrating Axial Solar Array...", "Synchronizing volumetric lighting LUTs & diurnal cycle...", 90.0)
	await get_tree().process_frame

	var light_bar = get_tree().get_first_node_in_group("light_bar") as AxisLightBar
	if light_bar and light_bar.has_method("_apply_lut_to_materials"):
		light_bar._apply_lut_to_materials()
	await get_tree().process_frame

	# Step 5: GPU Shader Warmup & Locomotion Stabilization
	_set_step("Habitat Systems Ready", "Finalizing GPU render pipelines & centrifugal gravity...", 100.0)
	target_progress = 100.0

	# Ensure minimum display time for smooth visual flow and shader compilation
	while elapsed_time < min_display_time or current_progress < 98.0:
		await get_tree().process_frame

	# Extra frame buffer swaps for seamless presentation
	for f in range(4):
		await get_tree().process_frame

	_complete_and_fade_out()

func _complete_and_fade_out() -> void:
	if is_loading_finished:
		return
	is_loading_finished = true
	_set_step("Habitat Online", "Welcome to O'Neill Cylinder Island One.", 100.0)
	target_progress = 100.0
	current_progress = 100.0
	loading_completed.emit()

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(background_rect, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(center_container, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	queue_free()
