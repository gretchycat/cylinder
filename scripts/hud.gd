class_name HUD
extends CanvasLayer

const UIScaleManager = preload("res://scripts/ui_scale_manager.gd")
const INTERFACE_PANEL_SIDE_MARGIN: float = 15.0
const LANDSCAPE_TOUCH_CONTROL_MAX_SCALE: float = 1.25
const CylinderParticleEmitter = preload("res://scripts/cylinder_particle_emitter.gd")
const SurfaceLightObject = preload("res://scripts/surface_light_object.gd")

@export var player: PlayerController
@export var light_bar: AxisLightBar
@export var weather_system: WeatherSystem
@export var particle_emitter: CylinderParticleEmitter

# Root Container for Adaptive Scaling
@onready var ui_root: Control = $UIRoot
@onready var control_panel: PanelContainer = $UIRoot/ControlPanel
@onready var tab_container: TabContainer = get_node_or_null("UIRoot/ControlPanel/TabContainer")
@onready var toggle_controls_btn: Button = $UIRoot/ToggleControlsButton
@onready var toggle_telemetry_btn: Button = get_node_or_null("UIRoot/ToggleTelemetryButton")
@onready var toggle_log_btn: Button = get_node_or_null("UIRoot/ToggleLogButton")
@onready var toggle_keyboard_btn: Button = get_node_or_null("UIRoot/ToggleKeyboardButton")
@onready var telemetry_panel: PanelContainer = $UIRoot/TelemetryPanel
@onready var log_panel: PanelContainer = get_node_or_null("UIRoot/EventLogPanel")
@onready var touch_controls: MobileTouchControls = $UIRoot/TouchControls

# UI Node References (under UIRoot)
@onready var telemetry_label: Label = get_node_or_null("UIRoot/TelemetryPanel/VBoxContainer/TelemetryVBox/TelemetryLabel")
@onready var mode_badge: Label = get_node_or_null("UIRoot/TelemetryPanel/VBoxContainer/TelemetryVBox/ModeBadge")
@onready var horizon_status_label: Label = get_node_or_null("UIRoot/TelemetryPanel/VBoxContainer/TelemetryVBox/HorizonStatusLabel")
@onready var looking_at_terrain_label: Label = get_node_or_null("UIRoot/TelemetryPanel/VBoxContainer/LookingAtVBox/TerrainTypeLabel")
@onready var looking_at_object_label: Label = get_node_or_null("UIRoot/TelemetryPanel/VBoxContainer/LookingAtVBox/ObjectLabel")
@onready var looking_at_coords_label: Label = get_node_or_null("UIRoot/TelemetryPanel/VBoxContainer/LookingAtVBox/CoordsLabel")
@onready var event_log_text: RichTextLabel = get_node_or_null("UIRoot/EventLogPanel/EventLogVBox/EventLogRichText")
@onready var copy_log_btn: Button = get_node_or_null("UIRoot/EventLogPanel/EventLogVBox/LogHeader/CopyLogButton")
@onready var clear_log_btn: Button = get_node_or_null("UIRoot/EventLogPanel/EventLogVBox/LogHeader/ClearLogButton")

static var _instance: HUD = null
var event_log_history: Array[String] = []
var event_log_raw_history: Array[String] = []
const MAX_LOG_ENTRIES: int = 250

var solar_badge_label: Label = null
var weather_badge_label: Label = null
var fps_label: Label = null
var system_fps_label: Label = null
var fps_update_timer: float = 0.0
var last_locomotion_mode: String = ""
var last_water_submerged: bool = false
var last_tab_idx: int = -1

# Tab 0: Climate & Biomes UI Controls
var climate_name_label: Label = null
var climate_details_label: Label = null
var climate_mode_label: Label = null
var climate_lat_slider: HSlider = null
var climate_lat_val: Label = null
var climate_precip_slider: HSlider = null
var climate_precip_val: Label = null
var climate_doy_slider: HSlider = null
var climate_doy_val: Label = null
var climate_preset_option: OptionButton = null
var apply_climate_preset_btn: Button = null
var gen_weather_state_btn: Button = null
var force_snow_btn: Button = null
var force_downpour_btn: Button = null

# Tab 1: Weather & Atmosphere UI Controls
var auto_cycle_btn: Button = null
var clock_sync_btn: Button = null
var skip_trajectory_btn: Button = null
var clear_queue_btn: Button = null
var add_preset_to_queue_btn: Button = null
var queue_current_sliders_btn: Button = null
var preset_queue_option: OptionButton = null
var duration_queue_option: OptionButton = null
var trajectory_status_label: Label = null
var queue_list_label: Label = null
var spin_direction_btn: Button = null
var cloud_cover_slider: HSlider = null
var cloud_cover_val: Label = null
var cloud_thickness_slider: HSlider = null
var cloud_thickness_val: Label = null
var precipitation_slider: HSlider = null
var precipitation_val: Label = null
var dust_slider: HSlider = null
var dust_val: Label = null
var fog_slider: HSlider = null
var fog_val: Label = null
var humidity_slider: HSlider = null
var humidity_val: Label = null
var hvac_air_slider: HSlider = null
var hvac_air_val: Label = null
var water_pipe_slider: HSlider = null
var water_pipe_val: Label = null
var cloud_status_label: Label = null

# Tab 2: Lighting UI Controls
var light_preset_option: OptionButton = null
var light_intensity_slider: HSlider = null
var light_intensity_val: Label = null

# Tab 3: Time & Diurnal Clock UI Controls
var solar_time_slider: HSlider = null
var solar_time_val: Label = null
var sync_real_time_btn: Button = null
var time_scale_slider: HSlider = null
var time_scale_val: Label = null
var latitude_slider: HSlider = null
var latitude_val: Label = null
var solar_status_label: Label = null

# Tab 4: Physics & Habitat UI Controls
var gravity_slider: HSlider = null
var gravity_val: Label = null
var reset_spawn_btn: Button = null
var south_cap_btn: Button = null
var north_cap_btn: Button = null

# Particle Emitter Controls
var launch_speed: float = 35.0
var launch_speed_slider: HSlider = null
var launch_speed_val: Label = null
var launch_up_btn: Button = null
var launch_prograde_btn: Button = null
var launch_retrograde_btn: Button = null
var launch_aimed_btn: Button = null
var toggle_rain_stream_btn: Button = null
var toggle_trajectories_btn: Button = null
var clear_trajectories_btn: Button = null

# Tab 5: Performance & Optimization UI Controls
var perf_culling_slider: HSlider = null
var perf_culling_val: Label = null
var perf_scale_slider: HSlider = null
var perf_scale_val: Label = null
var perf_preset_option: OptionButton = null
var perf_rain_layers_option: OptionButton = null
var perf_fps_limit_option: OptionButton = null
var perf_near_clouds_btn: Button = null
var perf_far_clouds_btn: Button = null
var perf_water_mesh_btn: Button = null
var perf_glow_btn: Button = null
var perf_fog_btn: Button = null
var perf_light_dist_slider: HSlider = null
var perf_light_dist_val: Label = null
var perf_clutter_dist_slider: HSlider = null
var perf_clutter_dist_val: Label = null
var perf_clutter_density_slider: HSlider = null
var perf_clutter_density_val: Label = null
var perf_clutter_auto_label: Label = null
var perf_profiler_label: Label = null
var clutter_auto_timer: float = 0.0
var clutter_auto_fps_average: float = 0.0
var clutter_auto_low_samples: int = 0
var clutter_auto_good_samples: int = 0
var clutter_auto_probe_kind: String = ""
var clutter_auto_probe_samples: int = 0
var clutter_auto_probe_fps_before: float = 0.0
var clutter_auto_probe_draw_before: float = 1.0
var clutter_auto_probe_density_before: float = 1.0
var clutter_auto_probe_precipitation_before: float = 1.0
var clutter_auto_probe_light_before: float = 1.0
var clutter_auto_draw_effect: String = "not measured"
var clutter_auto_density_effect: String = "not measured"
var clutter_auto_precipitation_effect: String = "not measured"
var clutter_auto_light_effect: String = "not measured"
var clutter_auto_draw_reduction_ineffective: bool = false
var clutter_auto_density_reduction_ineffective: bool = false
var clutter_auto_precipitation_reduction_ineffective: bool = false
var clutter_auto_light_reduction_ineffective: bool = false
var clutter_auto_light_quality_ceiling: float = 1.5
var clutter_auto_draw_quality_ceiling: float = 1.5

# Tab 6: System & Scale UI Controls
var scale_slider: HSlider = null
var scale_val: Label = null
var reset_scale_btn: Button = null

var current_ui_scale: float = 1.0
var is_scale_auto: bool = true
var auto_scale_info: Dictionary = {}

var underwater_overlay: ColorRect = null

# Looking At / Target Inspector UI Controls (defaults to OFF)
var looking_at_enabled: bool = false
var toggle_looking_at_btn: Button = null
var toggle_looking_at_sys_btn: Button = null
var toggle_looking_at_header_btn: Button = null
var looking_at_panel: PanelContainer = null
var looking_at_header_label: Label = null
var crosshair_node: Control = null
var looking_at_update_timer: float = 0.0
var last_looking_at_data: Dictionary = {}

var last_virtual_keyboard_height: int = 0
var keyboard_check_timer: float = 0.0

func _ready() -> void:
	_instance = self
	add_to_group("hud")
	if not player:
		player = get_tree().get_first_node_in_group("player")
	if not light_bar:
		light_bar = get_tree().get_first_node_in_group("light_bar")
	if not weather_system:
		weather_system = get_tree().get_first_node_in_group("weather_system")
	if not particle_emitter:
		particle_emitter = get_tree().get_first_node_in_group("particle_emitter")

	_setup_underwater_overlay()
	_setup_looking_at_ui()
	_setup_touch_controls_layout()

	if player:
		player.telemetry_updated.connect(_on_telemetry_updated)
	if weather_system:
		weather_system.weather_updated.connect(_on_weather_updated)

	_setup_ui_scaling()
	_setup_control_panel()

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

	fps_label = get_node_or_null("UIRoot/FPSLabel") as Label
	if not fps_label:
		fps_label = Label.new()
		fps_label.name = "FPSLabel"
		fps_label.add_theme_font_size_override("font_size", 16)
		fps_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.15, 1.0))
		fps_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		fps_label.add_theme_constant_override("outline_size", 6)
		fps_label.text = "-- FPS"
		if ui_root:
			ui_root.add_child(fps_label)

	if fps_label:
		fps_label.position = Vector2(15.0, 15.0)

	if not telemetry_label:
		telemetry_label = find_child("TelemetryLabel", true, false) as Label
	if not mode_badge:
		mode_badge = find_child("ModeBadge", true, false) as Label
	if not horizon_status_label:
		horizon_status_label = find_child("HorizonStatusLabel", true, false) as Label
	if not event_log_text:
		event_log_text = find_child("EventLogRichText", true, false) as RichTextLabel
	if not copy_log_btn:
		copy_log_btn = find_child("CopyLogButton", true, false) as Button
	if not clear_log_btn:
		clear_log_btn = find_child("ClearLogButton", true, false) as Button

	var telem_vbox = get_node_or_null("UIRoot/TelemetryPanel/VBoxContainer/TelemetryVBox")
	if not telem_vbox:
		telem_vbox = find_child("TelemetryVBox", true, false) as VBoxContainer
	if telem_vbox:
		solar_badge_label = Label.new()
		solar_badge_label.name = "SolarBadgeLabel"
		solar_badge_label.add_theme_font_size_override("font_size", 11)
		solar_badge_label.text = "SOLAR: --:--:-- [--]"
		telem_vbox.add_child(solar_badge_label)
		telem_vbox.move_child(solar_badge_label, 3)

		weather_badge_label = Label.new()
		weather_badge_label.name = "WeatherBadgeLabel"
		weather_badge_label.add_theme_font_size_override("font_size", 11)
		weather_badge_label.text = "WEATHER: Initializing..."
		weather_badge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		weather_badge_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		weather_badge_label.custom_minimum_size.x = 0.0
		telem_vbox.add_child(weather_badge_label)
		telem_vbox.move_child(weather_badge_label, 4)

	if copy_log_btn and not copy_log_btn.pressed.is_connected(_on_copy_log_pressed):
		copy_log_btn.pressed.connect(_on_copy_log_pressed)

	if clear_log_btn and not clear_log_btn.pressed.is_connected(_on_clear_log_pressed):
		clear_log_btn.pressed.connect(_on_clear_log_pressed)

	if tab_container and not tab_container.tab_changed.is_connected(_on_tab_changed):
		tab_container.tab_changed.connect(_on_tab_changed)
	if tab_container and not tab_container.resized.is_connected(_on_tab_container_resized):
		tab_container.resized.connect(_on_tab_container_resized)

	if toggle_controls_btn and not toggle_controls_btn.pressed.is_connected(_on_toggle_controls_pressed):
		toggle_controls_btn.focus_mode = Control.FOCUS_NONE
		toggle_controls_btn.pressed.connect(_on_toggle_controls_pressed)

	if toggle_telemetry_btn and not toggle_telemetry_btn.pressed.is_connected(_on_toggle_telemetry_pressed):
		toggle_telemetry_btn.focus_mode = Control.FOCUS_NONE
		toggle_telemetry_btn.pressed.connect(_on_toggle_telemetry_pressed)

	if toggle_log_btn and not toggle_log_btn.pressed.is_connected(_on_toggle_log_pressed):
		toggle_log_btn.focus_mode = Control.FOCUS_NONE
		toggle_log_btn.pressed.connect(_on_toggle_log_pressed)

	if toggle_keyboard_btn and not toggle_keyboard_btn.pressed.is_connected(_on_toggle_keyboard_pressed):
		toggle_keyboard_btn.focus_mode = Control.FOCUS_NONE
		toggle_keyboard_btn.pressed.connect(_on_toggle_keyboard_pressed)

	_setup_virtual_keyboard_receiver()

	if reset_spawn_btn and not reset_spawn_btn.pressed.is_connected(_on_reset_spawn_pressed):
		reset_spawn_btn.focus_mode = Control.FOCUS_NONE
		reset_spawn_btn.pressed.connect(_on_reset_spawn_pressed)

	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_update_panel_constraints()
	log_event("Habitat engine systems online. Centrifugal gravity: 1.00 G.", "#55ffaa")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Toggle Event Log console with backtick ` (KEY_QUOTELEFT or KEY_ASCIITILDE)
		if event.keycode == KEY_QUOTELEFT or event.keycode == KEY_ASCIITILDE or event.physical_keycode == KEY_QUOTELEFT:
			_on_toggle_log_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F1:
			_on_toggle_controls_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_I or event.keycode == KEY_F2:
			_on_toggle_telemetry_pressed()
			get_viewport().set_input_as_handled()

var solar_ui_timer: float = 0.0

func _process(delta: float) -> void:
	solar_ui_timer += delta
	if solar_ui_timer >= 0.25:
		solar_ui_timer = 0.0
		_update_solar_ui()

	telemetry_ui_timer += delta
	if telemetry_ui_timer >= 0.05:
		telemetry_ui_timer = 0.0
		if telemetry_panel and telemetry_panel.visible:
			if not cached_telemetry_data.is_empty():
				_render_telemetry_ui(cached_telemetry_data)
			_update_looking_at_inspection()

	_update_fps_display(delta)
	_update_clutter_auto_tuning(delta)
	
	keyboard_check_timer += delta
	if keyboard_check_timer >= 0.1:
		keyboard_check_timer = 0.0
		_check_virtual_keyboard()

func _check_virtual_keyboard() -> void:
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		return
	var kb_height = DisplayServer.virtual_keyboard_get_height()
	if kb_height != last_virtual_keyboard_height:
		last_virtual_keyboard_height = kb_height
		_update_panel_constraints()

func _setup_underwater_overlay() -> void:
	underwater_overlay = ColorRect.new()
	underwater_overlay.name = "UnderwaterScreenTint"
	underwater_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	underwater_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater_overlay.color = Color(1.0, 1.0, 1.0, 1.0)
	underwater_overlay.visible = false

	var overlay_shader = load("res://assets/shaders/underwater_overlay.gdshader") as Shader
	if overlay_shader:
		var overlay_mat = ShaderMaterial.new()
		overlay_mat.shader = overlay_shader
		preload("res://scripts/map_runtime.gd").shader_parameters(overlay_mat, preload("res://scripts/map_runtime.gd").document(self))
		underwater_overlay.material = overlay_mat

	if ui_root:
		ui_root.add_child(underwater_overlay)
		ui_root.move_child(underwater_overlay, 0)

func _setup_ui_scaling() -> void:
	auto_scale_info = UIScaleManager.calculate_intelligent_scale(-1.0, Vector2.ZERO, OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"))
	var saved_pref = UIScaleManager.load_user_scale()

	# If running on a mobile device, ignore any saved manual scale and enforce auto scaling
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		is_scale_auto = true
		apply_ui_scale(auto_scale_info["scale"], true)
	elif saved_pref.get("has_saved", false) and not saved_pref.get("is_auto", true):
		is_scale_auto = false
		apply_ui_scale(saved_pref.get("scale", auto_scale_info["scale"]), false)
	else:
		is_scale_auto = true
		apply_ui_scale(auto_scale_info["scale"], true)

	if scale_slider:
		scale_slider.value_changed.connect(_on_scale_slider_changed)
	if reset_scale_btn:
		reset_scale_btn.pressed.connect(_on_reset_scale_pressed)

func apply_ui_scale(target_scale: float, auto_mode: bool) -> void:
	var old_scale = current_ui_scale
	current_ui_scale = clampf(target_scale, 0.5, 3.5)
	is_scale_auto = auto_mode

	if ui_root:
		ui_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		ui_root.anchor_left = 0.0
		ui_root.anchor_top = 0.0
		ui_root.anchor_right = 0.0
		ui_root.anchor_bottom = 0.0
		ui_root.offset_left = 0.0
		ui_root.offset_top = 0.0
		ui_root.offset_right = 0.0
		ui_root.offset_bottom = 0.0

		var vp_size = get_viewport().get_visible_rect().size
		ui_root.size = vp_size / current_ui_scale
		ui_root.scale = Vector2(current_ui_scale, current_ui_scale)

	if touch_controls:
		touch_controls.ui_scale = current_ui_scale
		_setup_touch_controls_layout()

	_update_panel_constraints()
	_update_scale_slider_ui()
	UIScaleManager.save_user_scale(current_ui_scale, is_scale_auto)
	if not is_equal_approx(old_scale, current_ui_scale):
		log_event("UI Interface -> Scale adjusted to %.2fx (Mode: %s)" % [current_ui_scale, "Auto-Adaptive" if is_scale_auto else "Manual"], "#ffbb77")

var is_virtual_keyboard_shown: bool = false
var virtual_keyboard_receiver: LineEdit = null

func _setup_virtual_keyboard_receiver() -> void:
	if not ui_root:
		return
	virtual_keyboard_receiver = ui_root.get_node_or_null("VirtualKeyboardReceiver") as LineEdit
	if not virtual_keyboard_receiver:
		virtual_keyboard_receiver = LineEdit.new()
		virtual_keyboard_receiver.name = "VirtualKeyboardReceiver"
		virtual_keyboard_receiver.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
		virtual_keyboard_receiver.virtual_keyboard_enabled = true
		virtual_keyboard_receiver.focus_mode = Control.FOCUS_ALL
		virtual_keyboard_receiver.modulate = Color(1, 1, 1, 0.0) # Transparent / invisible
		virtual_keyboard_receiver.custom_minimum_size = Vector2(1, 1)
		virtual_keyboard_receiver.size = Vector2(1, 1)
		virtual_keyboard_receiver.position = Vector2(-200, -200) # Off-screen
		virtual_keyboard_receiver.text_changed.connect(_on_virtual_keyboard_text_changed)
		virtual_keyboard_receiver.gui_input.connect(_on_virtual_keyboard_gui_input)
		virtual_keyboard_receiver.focus_exited.connect(_on_virtual_keyboard_focus_exited)
		ui_root.add_child(virtual_keyboard_receiver)

func _on_toggle_keyboard_pressed() -> void:
	if not virtual_keyboard_receiver:
		_setup_virtual_keyboard_receiver()

	var kb_h = DisplayServer.virtual_keyboard_get_height()
	if kb_h > 0 or is_virtual_keyboard_shown:
		if virtual_keyboard_receiver:
			virtual_keyboard_receiver.release_focus()
		DisplayServer.virtual_keyboard_hide()
		is_virtual_keyboard_shown = false
		log_event("UI Interface -> On-screen keyboard hidden", "#ffaa55")
	else:
		is_virtual_keyboard_shown = true
		if virtual_keyboard_receiver:
			virtual_keyboard_receiver.text = ""
			virtual_keyboard_receiver.grab_focus()
		DisplayServer.virtual_keyboard_show("")
		log_event("UI Interface -> On-screen keyboard active (IME bridged)", "#55ffaa")

	if toggle_keyboard_btn:
		toggle_keyboard_btn.release_focus()
	_update_panel_constraints()

func _on_virtual_keyboard_text_changed(new_text: String) -> void:
	if new_text.is_empty():
		return

	for i in range(new_text.length()):
		var ch = new_text[i]
		var upper_ch = ch.to_upper()
		var keycode: Key = KEY_NONE

		match upper_ch:
			"W": keycode = KEY_W
			"S": keycode = KEY_S
			"A": keycode = KEY_A
			"D": keycode = KEY_D
			" ": keycode = KEY_SPACE
			"F": keycode = KEY_F
			"R": keycode = KEY_R
			"T": keycode = KEY_T
			"C": keycode = KEY_C
			"L": keycode = KEY_L
			"P": keycode = KEY_P
			"G": keycode = KEY_G
			"I": keycode = KEY_I
			"H": keycode = KEY_H
			"\n": keycode = KEY_ENTER
			_:
				var u = ch.unicode_at(0)
				keycode = u as Key

		if keycode != KEY_NONE:
			_dispatch_virtual_key(keycode, ch.unicode_at(0))

	if virtual_keyboard_receiver:
		virtual_keyboard_receiver.text = ""

func _on_virtual_keyboard_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_BACKSPACE or event.keycode == KEY_ESCAPE:
			_dispatch_virtual_key(event.keycode, event.unicode)
			if virtual_keyboard_receiver:
				virtual_keyboard_receiver.accept_event()

func _on_virtual_keyboard_focus_exited() -> void:
	if is_virtual_keyboard_shown:
		is_virtual_keyboard_shown = false
		_update_panel_constraints()

func _dispatch_virtual_key(keycode: Key, unicode: int = 0) -> void:
	var ev_press = InputEventKey.new()
	ev_press.keycode = keycode
	ev_press.physical_keycode = keycode
	ev_press.key_label = keycode
	ev_press.unicode = unicode
	ev_press.pressed = true
	ev_press.echo = false
	Input.parse_input_event(ev_press)

	var timer = get_tree().create_timer(0.06)
	timer.timeout.connect(func():
		var ev_release = InputEventKey.new()
		ev_release.keycode = keycode
		ev_release.physical_keycode = keycode
		ev_release.key_label = keycode
		ev_release.unicode = unicode
		ev_release.pressed = false
		ev_release.echo = false
		Input.parse_input_event(ev_release)
	)

func _update_panel_constraints() -> void:
	_reflow_settings_rows()
	if not ui_root:
		return

	var is_mobile_platform = OS.has_feature("android") or OS.has_feature("mobile") or OS.has_feature("ios")
	if toggle_keyboard_btn:
		toggle_keyboard_btn.visible = is_mobile_platform or DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)

	var kb_height = DisplayServer.virtual_keyboard_get_height() if (is_mobile_platform or is_virtual_keyboard_shown) else 0
	var kb_offset = float(kb_height) / current_ui_scale if current_ui_scale > 0.0 else 0.0
	var is_kb_open = (kb_offset > 10.0 or is_virtual_keyboard_shown)

	# Update Top Buttons (Info, Log, Settings, Keyboard) Position
	var buttons = [toggle_telemetry_btn, toggle_log_btn, toggle_controls_btn, toggle_keyboard_btn]
	for btn in buttons:
		if btn:
			if is_kb_open and kb_offset > 10.0:
				# Move buttons to bottom above virtual keyboard
				btn.anchor_top = 1.0
				btn.anchor_bottom = 1.0
				btn.offset_bottom = -kb_offset - 10.0
				btn.offset_top = -kb_offset - 43.0
			else:
				# Standard top placement
				btn.anchor_top = 0.0
				btn.anchor_bottom = 0.0
				btn.offset_top = 15.0
				btn.offset_bottom = 48.0

	# 1. Info / TelemetryPanel: Exact width of screen minus margins (offset_left = 15.0, offset_right = -15.0)
	if telemetry_panel:
		telemetry_panel.clip_contents = true
		telemetry_panel.anchor_top = 0.0
		telemetry_panel.anchor_bottom = 0.0
		telemetry_panel.offset_top = 58.0 if not (is_kb_open and kb_offset > 10.0) else 15.0
		telemetry_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		telemetry_panel.grow_vertical = Control.GROW_DIRECTION_END
		_fit_interface_panel_width(telemetry_panel)
		_fit_info_panel_height()

	# 2. Debug configuration window (ControlPanel): Same width configuration as info box (screen width minus margins),
	# and minimum height to comfortably fit all tabs without excessive empty bottom space.
	if control_panel:
		control_panel.clip_contents = true
		control_panel.anchor_top = 0.0
		control_panel.anchor_bottom = 0.0
		control_panel.offset_left = INTERFACE_PANEL_SIDE_MARGIN
		control_panel.offset_right = -INTERFACE_PANEL_SIDE_MARGIN
		var top_offset = 58.0 if not (is_kb_open and kb_offset > 10.0) else 15.0
		control_panel.offset_top = top_offset

		var available_h = ui_root.size.y if ui_root else 720.0
		var max_allowed_h = available_h - 260.0 if not (is_kb_open and kb_offset > 10.0) else (available_h - kb_offset - 70.0)
		var target_min_h = clampf(390.0, 220.0, maxf(max_allowed_h, 220.0))
		control_panel.offset_bottom = top_offset + target_min_h
		control_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		control_panel.grow_vertical = Control.GROW_DIRECTION_END
		_fit_interface_panel_width(control_panel)

	# 3. LogPanel: Fill the viewport between the screen margins.
	if log_panel:
		log_panel.clip_contents = true
		log_panel.anchors_preset = Control.PRESET_TOP_WIDE
		log_panel.anchor_left = 0.0
		log_panel.anchor_right = 1.0
		log_panel.anchor_top = 0.0
		log_panel.anchor_bottom = 1.0
		var screen_margin = INTERFACE_PANEL_SIDE_MARGIN / maxf(current_ui_scale, 0.01)
		log_panel.offset_left = screen_margin
		log_panel.offset_right = -screen_margin
		log_panel.offset_top = screen_margin
		log_panel.offset_bottom = -screen_margin - kb_offset if (is_kb_open and kb_offset > 10.0) else -screen_margin

	_update_touch_controls_visibility()

func _update_touch_controls_visibility() -> void:
	if not touch_controls:
		return
	var overlay_is_open = (control_panel and control_panel.visible) or (log_panel and log_panel.visible)
	touch_controls.visible = not overlay_is_open

func _fit_interface_panel_width(panel: PanelContainer) -> void:
	if not ui_root or not panel:
		return
	if panel == telemetry_panel:
		for node in panel.find_children("*", "Label", true, false):
			var label := node as Label
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.custom_minimum_size.x = 0.0
	var scaled_margin = INTERFACE_PANEL_SIDE_MARGIN / maxf(current_ui_scale, 0.01)
	var max_width = maxf(ui_root.size.x - scaled_margin * 2.0, 1.0)
	panel.custom_minimum_size.x = 0.0
	var layout_width = max_width
	if panel == control_panel:
		layout_width = maxf(max_width, panel.get_combined_minimum_size().x)
	# Center on UIRoot and convert the screen margins into its scaled coordinates.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -layout_width * 0.5
	panel.offset_right = layout_width * 0.5
	panel.size.x = layout_width
	panel.clip_contents = true
	panel.pivot_offset = Vector2(layout_width * 0.5, 0.0)
	var fit_scale_x = minf(1.0, max_width / layout_width)
	panel.scale = Vector2(fit_scale_x, 1.0)

func _fit_info_panel_height() -> void:
	if not telemetry_panel:
		return
	telemetry_panel.custom_minimum_size.y = 0.0
	telemetry_panel.size.y = telemetry_panel.get_combined_minimum_size().y
	telemetry_panel.offset_bottom = telemetry_panel.offset_top + telemetry_panel.size.y

func _on_tab_container_resized() -> void:
	if tab_container:
		tab_container.pivot_offset = tab_container.size * 0.5

func _update_scale_slider_ui() -> void:
	if scale_slider and not is_equal_approx(scale_slider.value, current_ui_scale):
		scale_slider.set_value_no_signal(current_ui_scale)

	if scale_val:
		var mode_str = auto_scale_info.get("device_type", "Auto") if is_scale_auto else "Custom"
		scale_val.text = "%.2fx [%s]" % [current_ui_scale, mode_str]

func _on_scale_slider_changed(value: float) -> void:
	apply_ui_scale(value, false)

func _on_reset_scale_pressed() -> void:
	auto_scale_info = UIScaleManager.calculate_intelligent_scale()
	apply_ui_scale(auto_scale_info["scale"], true)

func _on_viewport_size_changed() -> void:
	if is_scale_auto:
		auto_scale_info = UIScaleManager.calculate_intelligent_scale()
		apply_ui_scale(auto_scale_info["scale"], true)
	elif ui_root:
		var vp_size = get_viewport().get_visible_rect().size
		ui_root.size = vp_size / current_ui_scale
		_update_panel_constraints()
	_setup_touch_controls_layout()

func _setup_touch_controls_layout() -> void:
	if not touch_controls or not is_instance_valid(touch_controls) or not is_inside_tree():
		return
	# Keep the touch surface anchored to the actual viewport, independent of the
	# scaled settings/HUD root. This prevents bottom-anchored controls drifting
	# upward when mobile DPI scaling or orientation changes resize that root.
	if touch_controls.get_parent() != self:
		touch_controls.reparent(self)
	touch_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	touch_controls.anchor_left = 0.0
	touch_controls.anchor_top = 0.0
	touch_controls.anchor_right = 0.0
	touch_controls.anchor_bottom = 0.0
	touch_controls.position = Vector2.ZERO
	var viewport_size = get_viewport().get_visible_rect().size
	var is_portrait = viewport_size.y > viewport_size.x
	var base_scale = maxf(current_ui_scale, 1.0)
	var scale_value = base_scale * 0.80 if is_portrait else minf(base_scale, LANDSCAPE_TOUCH_CONTROL_MAX_SCALE)
	touch_controls.scale = Vector2.ONE * scale_value
	touch_controls.size = viewport_size / scale_value
	touch_controls.ui_scale = scale_value

static func slider_pos_to_intensity(s: float) -> float:
	var s_clamped = clampf(s, 0.0, 1.0)
	const MIN_INTENSITY: float = 0.001
	const MAX_INTENSITY: float = 3.5
	return MIN_INTENSITY * pow(MAX_INTENSITY / MIN_INTENSITY, s_clamped)

static func intensity_to_slider_pos(intensity: float) -> float:
	const MIN_INTENSITY: float = 0.001
	const MAX_INTENSITY: float = 3.5
	if intensity <= MIN_INTENSITY:
		return 0.0
	return clampf(log(intensity / MIN_INTENSITY) / log(MAX_INTENSITY / MIN_INTENSITY), 0.0, 1.0)

func _is_narrow_interface() -> bool:
	return get_viewport().get_visible_rect().size.x < 560.0

func _new_settings_row() -> BoxContainer:
	var row: BoxContainer = VBoxContainer.new() if _is_narrow_interface() else HBoxContainer.new()
	row.add_to_group("responsive_settings_rows")
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row

func _reflow_settings_rows() -> void:
	var use_vertical_rows = _is_narrow_interface()
	for node in get_tree().get_nodes_in_group("responsive_settings_rows"):
		if not is_instance_valid(node) or not node is BoxContainer:
			continue
		var old_row := node as BoxContainer
		if (old_row is VBoxContainer) == use_vertical_rows:
			continue
		var parent := old_row.get_parent()
		if not parent:
			continue
		var old_index = old_row.get_index()
		var new_row: BoxContainer = VBoxContainer.new() if use_vertical_rows else HBoxContainer.new()
		new_row.name = old_row.name
		new_row.add_to_group("responsive_settings_rows")
		new_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		new_row.add_theme_constant_override("separation", 4)
		parent.add_child(new_row)
		parent.move_child(new_row, old_index)
		for child in old_row.get_children():
			old_row.remove_child(child)
			new_row.add_child(child)
		old_row.remove_from_group("responsive_settings_rows")
		old_row.queue_free()

func _create_slider_row(parent: VBoxContainer, label_text: String, min_val: float, max_val: float, step_val: float, init_val: float, callback: Callable) -> Array:
	var box = VBoxContainer.new()
	var header: BoxContainer = _new_settings_row()

	var lbl = Label.new()
	lbl.text = label_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 11)
	header.add_child(lbl)

	var vlbl = Label.new()
	vlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vlbl.custom_minimum_size.x = 0.0
	vlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vlbl.add_theme_font_size_override("font_size", 11)
	header.add_child(vlbl)
	box.add_child(header)

	var slider = HSlider.new()
	slider.focus_mode = Control.FOCUS_NONE
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.value = init_val
	slider.value_changed.connect(callback)
	box.add_child(slider)

	parent.add_child(box)
	return [slider, vlbl]

func _setup_control_panel() -> void:
	if tab_container:
		if _is_narrow_interface():
			tab_container.add_theme_font_size_override("font_size", 9)
			tab_container.set_tab_title(0, "Clim")
			tab_container.set_tab_title(1, "Weath")
			tab_container.set_tab_title(2, "Light")
			tab_container.set_tab_title(3, "Time")
			tab_container.set_tab_title(4, "Phys")
			tab_container.set_tab_title(5, "Perf")
			tab_container.set_tab_title(6, "Sys")
		else:
			tab_container.add_theme_font_size_override("font_size", 11)
			tab_container.set_tab_title(0, "🌍 Climate")
			tab_container.set_tab_title(1, "☁️ Weather")
			tab_container.set_tab_title(2, "☀️ Lighting")
			tab_container.set_tab_title(3, "⏳ Time")
			tab_container.set_tab_title(4, "🌐 Physics")
			tab_container.set_tab_title(5, "⚡ Performance")
			tab_container.set_tab_title(6, "⚙️ System")

	var vbox_climate = get_node_or_null("UIRoot/ControlPanel/TabContainer/Climate/VBoxClimate") as VBoxContainer
	if vbox_climate:
		_setup_climate_tab(vbox_climate)

	var vbox_weather = get_node_or_null("UIRoot/ControlPanel/TabContainer/Weather/VBoxWeather") as VBoxContainer
	if vbox_weather:
		_setup_weather_tab(vbox_weather)

	var vbox_lighting = get_node_or_null("UIRoot/ControlPanel/TabContainer/Lighting/VBoxLighting") as VBoxContainer
	if vbox_lighting:
		_setup_lighting_tab(vbox_lighting)

	var vbox_time = get_node_or_null("UIRoot/ControlPanel/TabContainer/Time/VBoxTime") as VBoxContainer
	if vbox_time:
		_setup_time_tab(vbox_time)

	var vbox_physics = get_node_or_null("UIRoot/ControlPanel/TabContainer/Physics/VBoxPhysics") as VBoxContainer
	if vbox_physics:
		_setup_physics_tab(vbox_physics)

	var vbox_perf = get_node_or_null("UIRoot/ControlPanel/TabContainer/Performance/VBoxPerformance") as VBoxContainer
	if vbox_perf:
		_setup_performance_tab(vbox_perf)

	var vbox_system = get_node_or_null("UIRoot/ControlPanel/TabContainer/System/VBoxSystem") as VBoxContainer
	if vbox_system:
		_setup_system_tab(vbox_system)

	_update_solar_ui()

func _setup_climate_tab(vbox: VBoxContainer) -> void:
	climate_name_label = Label.new()
	climate_name_label.name = "ClimateNameLabel"
	climate_name_label.add_theme_font_size_override("font_size", 12)
	climate_name_label.text = "🌍 Biome: Initializing..."
	climate_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	climate_name_label.modulate = Color(0.4, 1.0, 0.7)
	vbox.add_child(climate_name_label)

	climate_details_label = Label.new()
	climate_details_label.name = "ClimateDetailsLabel"
	climate_details_label.add_theme_font_size_override("font_size", 10)
	climate_details_label.text = "Season: Summer | Surface Temp: 22.0 °C\nAnnual Rain: 950 mm | Latitude: 40.0° N"
	climate_details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	climate_details_label.modulate = Color(0.8, 0.95, 1.0)
	vbox.add_child(climate_details_label)

	climate_mode_label = Label.new()
	climate_mode_label.name = "ClimateModeLabel"
	climate_mode_label.add_theme_font_size_override("font_size", 10)
	climate_mode_label.text = "Precipitation Mode: 🌧️ Rain (> 4°C)"
	climate_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	climate_mode_label.modulate = Color(0.6, 0.85, 1.0)
	vbox.add_child(climate_mode_label)

	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	var init_lat = weather_system.latitude_deg if weather_system else (light_bar.earth_latitude_deg if light_bar else 40.0)
	var r_lat = _create_slider_row(vbox, "Habitat Latitude (-90°S to +90°N):", -90.0, 90.0, 0.5, init_lat, _on_climate_lat_changed)
	climate_lat_slider = r_lat[0]
	climate_lat_val = r_lat[1]
	_update_lat_label(init_lat)

	var init_precip = weather_system.yearly_precipitation_mm if weather_system else 950.0
	var r_precip = _create_slider_row(vbox, "Annual Precipitation (Yearly mm):", 50.0, 4000.0, 25.0, init_precip, _on_climate_precip_changed)
	climate_precip_slider = r_precip[0]
	climate_precip_val = r_precip[1]
	_update_precip_label(init_precip)

	var init_doy = weather_system.day_of_year if weather_system else 172
	var r_doy = _create_slider_row(vbox, "Day of Year (Seasonal Cycle):", 1.0, 365.0, 1.0, float(init_doy), _on_climate_doy_changed)
	climate_doy_slider = r_doy[0]
	climate_doy_val = r_doy[1]
	_update_doy_label(init_doy)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var preset_label = Label.new()
	preset_label.text = "Quick Biome / Climate Presets:"
	preset_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(preset_label)

	var hbox_presets = _new_settings_row()
	climate_preset_option = OptionButton.new()
	climate_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	climate_preset_option.focus_mode = Control.FOCUS_NONE
	climate_preset_option.add_item("Tropical Rainforest (Lat 0°, 3000mm)", 0)
	climate_preset_option.add_item("Tropical Savanna (Lat 12°, 480mm)", 1)
	climate_preset_option.add_item("Hot Subtropical Desert (Lat 28°, 100mm)", 2)
	climate_preset_option.add_item("Mediterranean Chaparral (Lat 35°, 450mm)", 3)
	climate_preset_option.add_item("Temperate Deciduous Forest (Lat 42°, 1100mm)", 4)
	climate_preset_option.add_item("Temperate Rainforest (Lat 48°, 2400mm)", 5)
	climate_preset_option.add_item("Cold Steppe / Grassland (Lat 50°, 350mm)", 6)
	climate_preset_option.add_item("Boreal Taiga Forest (Lat 62°, 700mm)", 7)
	climate_preset_option.add_item("Arctic Tundra Desert (Lat 68°, 200mm)", 8)
	climate_preset_option.add_item("Polar Ice Sheet (Lat 82°, 120mm)", 9)
	climate_preset_option.select(4)
	hbox_presets.add_child(climate_preset_option)

	apply_climate_preset_btn = Button.new()
	apply_climate_preset_btn.text = "Apply Biome"
	apply_climate_preset_btn.focus_mode = Control.FOCUS_NONE
	apply_climate_preset_btn.add_theme_font_size_override("font_size", 10)
	apply_climate_preset_btn.pressed.connect(_on_apply_climate_preset_pressed)
	hbox_presets.add_child(apply_climate_preset_btn)
	vbox.add_child(hbox_presets)

	var hbox_triggers = _new_settings_row()
	vbox.add_child(hbox_triggers)

	gen_weather_state_btn = Button.new()
	gen_weather_state_btn.text = "⚡ Next Weather"
	gen_weather_state_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gen_weather_state_btn.focus_mode = Control.FOCUS_NONE
	gen_weather_state_btn.add_theme_font_size_override("font_size", 10)
	gen_weather_state_btn.pressed.connect(_on_gen_weather_state_pressed)
	hbox_triggers.add_child(gen_weather_state_btn)

	force_snow_btn = Button.new()
	force_snow_btn.text = "❄️ Trigger Snow (<4°C)"
	force_snow_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	force_snow_btn.focus_mode = Control.FOCUS_NONE
	force_snow_btn.add_theme_font_size_override("font_size", 10)
	force_snow_btn.pressed.connect(_on_force_snow_pressed)
	hbox_triggers.add_child(force_snow_btn)

	force_downpour_btn = Button.new()
	force_downpour_btn.text = "🌧️ Trigger Downpour"
	force_downpour_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	force_downpour_btn.focus_mode = Control.FOCUS_NONE
	force_downpour_btn.add_theme_font_size_override("font_size", 10)
	force_downpour_btn.pressed.connect(_on_force_downpour_pressed)
	hbox_triggers.add_child(force_downpour_btn)

func _setup_weather_tab(vbox: VBoxContainer) -> void:
	# 1. Active Trajectory & Queue Readout
	trajectory_status_label = Label.new()
	trajectory_status_label.name = "TrajectoryStatusLabel"
	trajectory_status_label.add_theme_font_size_override("font_size", 11)
	trajectory_status_label.text = "Forecast: Initializing Trajectory..."
	trajectory_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trajectory_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trajectory_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trajectory_status_label.custom_minimum_size.x = 0.0
	vbox.add_child(trajectory_status_label)

	queue_list_label = Label.new()
	queue_list_label.name = "QueueListLabel"
	queue_list_label.add_theme_font_size_override("font_size", 10)
	queue_list_label.text = "Queue: [Empty - Auto-Looping Presets]"
	queue_list_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queue_list_label.modulate = Color(0.7, 0.9, 1.0)
	vbox.add_child(queue_list_label)

	# 2. Queue Dispatch Controls
	var queue_box = VBoxContainer.new()
	
	var hbox_preset_row = _new_settings_row()
	queue_box.add_child(hbox_preset_row)

	preset_queue_option = OptionButton.new()
	preset_queue_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_queue_option.focus_mode = Control.FOCUS_NONE
	preset_queue_option.add_item("Clear Solar Sky", 0)
	preset_queue_option.add_item("Fair Cumulus Skies", 1)
	preset_queue_option.add_item("Overcast Cloud Deck", 2)
	preset_queue_option.add_item("Light Rain & Mist", 3)
	preset_queue_option.add_item("Heavy Atmospheric Downpour", 4)
	preset_queue_option.add_item("Gentle Snowfall & Flurries (❄️)", 5)
	preset_queue_option.add_item("Frigid Arctic Blizzard (❄️)", 6)
	preset_queue_option.add_item("Atmospheric Dust & Haze", 7)
	hbox_preset_row.add_child(preset_queue_option)

	duration_queue_option = OptionButton.new()
	duration_queue_option.focus_mode = Control.FOCUS_NONE
	duration_queue_option.add_item("15s (Fast)", 15)
	duration_queue_option.add_item("30s (Smooth)", 30)
	duration_queue_option.add_item("45s (Gradual)", 45)
	duration_queue_option.add_item("60s (Slow)", 60)
	duration_queue_option.add_item("90s (Cinematic)", 90)
	duration_queue_option.select(1) # Default 30s
	hbox_preset_row.add_child(duration_queue_option)

	var hbox_actions = _new_settings_row()
	queue_box.add_child(hbox_actions)

	add_preset_to_queue_btn = Button.new()
	add_preset_to_queue_btn.text = "➕ Queue Preset"
	add_preset_to_queue_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_preset_to_queue_btn.focus_mode = Control.FOCUS_NONE
	add_preset_to_queue_btn.add_theme_font_size_override("font_size", 10)
	add_preset_to_queue_btn.pressed.connect(_on_add_preset_to_queue_pressed)
	hbox_actions.add_child(add_preset_to_queue_btn)

	queue_current_sliders_btn = Button.new()
	queue_current_sliders_btn.text = "🎯 Queue Sliders Target"
	queue_current_sliders_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_current_sliders_btn.focus_mode = Control.FOCUS_NONE
	queue_current_sliders_btn.add_theme_font_size_override("font_size", 10)
	queue_current_sliders_btn.pressed.connect(_on_queue_current_sliders_pressed)
	hbox_actions.add_child(queue_current_sliders_btn)

	var hbox_q_mgmt = _new_settings_row()
	queue_box.add_child(hbox_q_mgmt)

	skip_trajectory_btn = Button.new()
	skip_trajectory_btn.text = "⏭️ Skip Active"
	skip_trajectory_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skip_trajectory_btn.focus_mode = Control.FOCUS_NONE
	skip_trajectory_btn.add_theme_font_size_override("font_size", 10)
	skip_trajectory_btn.pressed.connect(_on_skip_trajectory_pressed)
	hbox_q_mgmt.add_child(skip_trajectory_btn)

	clear_queue_btn = Button.new()
	clear_queue_btn.text = "🧹 Clear Queue"
	clear_queue_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_queue_btn.focus_mode = Control.FOCUS_NONE
	clear_queue_btn.add_theme_font_size_override("font_size", 10)
	clear_queue_btn.pressed.connect(_on_clear_queue_pressed)
	hbox_q_mgmt.add_child(clear_queue_btn)

	auto_cycle_btn = Button.new()
	var is_auto = weather_system.auto_weather_cycle_enabled if weather_system else true
	auto_cycle_btn.text = "Auto: %s" % ("ON" if is_auto else "OFF")
	auto_cycle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_cycle_btn.focus_mode = Control.FOCUS_NONE
	auto_cycle_btn.add_theme_font_size_override("font_size", 10)
	auto_cycle_btn.pressed.connect(_on_auto_cycle_toggle_pressed)
	hbox_q_mgmt.add_child(auto_cycle_btn)

	clock_sync_btn = Button.new()
	var is_clock = weather_system.tie_to_in_game_clock if weather_system else true
	clock_sync_btn.text = "Clock: %s" % ("ON" if is_clock else "OFF")
	clock_sync_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_sync_btn.focus_mode = Control.FOCUS_NONE
	clock_sync_btn.add_theme_font_size_override("font_size", 10)
	clock_sync_btn.pressed.connect(_on_clock_sync_toggle_pressed)
	hbox_q_mgmt.add_child(clock_sync_btn)

	vbox.add_child(queue_box)

	var sep_cycle = HSeparator.new()
	vbox.add_child(sep_cycle)

	spin_direction_btn = Button.new()
	var is_ccw_init = (weather_system.spin_direction == WeatherSystem.SpinDirection.COUNTER_CLOCKWISE) if weather_system else true
	spin_direction_btn.text = "Cylinder Spin: %s" % ("Counter-Clockwise (CCW)" if is_ccw_init else "Clockwise (CW)")
	spin_direction_btn.focus_mode = Control.FOCUS_NONE
	spin_direction_btn.add_theme_font_size_override("font_size", 11)
	spin_direction_btn.pressed.connect(_on_spin_direction_toggle_pressed)
	vbox.add_child(spin_direction_btn)

	var cur_cov = weather_system.cloud_coverage if weather_system else 0.55
	var r_cov = _create_slider_row(vbox, "Cloud Cover (Overcast):", 0.0, 1.0, 0.01, cur_cov, _on_cloud_cover_slider_changed)
	cloud_cover_slider = r_cov[0]
	cloud_cover_val = r_cov[1]
	cloud_cover_val.text = "%d%%" % int(round(cur_cov * 100.0))

	var cur_thick = weather_system.cloud_thickness_m if weather_system else 250.0
	var r_thick = _create_slider_row(vbox, "Cloud Deck Thickness:", 50.0, 800.0, 10.0, cur_thick, _on_cloud_thickness_slider_changed)
	cloud_thickness_slider = r_thick[0]
	cloud_thickness_val = r_thick[1]
	cloud_thickness_val.text = "%.0f m" % cur_thick

	var cur_precip = weather_system.precipitation_rate_mmh if weather_system else 0.0
	var r_precip = _create_slider_row(vbox, "Precipitation (Rain/Mist):", 0.0, 50.0, 0.5, cur_precip, _on_precipitation_slider_changed)
	precipitation_slider = r_precip[0]
	precipitation_val = r_precip[1]
	precipitation_val.text = "%.1f mm/hr" % cur_precip if cur_precip > 0.0 else "0.0 mm/hr [None]"

	var cur_dust = weather_system.dust_density if weather_system else 0.20
	var r_dust = _create_slider_row(vbox, "Atmospheric Dust & Haze:", 0.0, 1.0, 0.01, cur_dust, _on_dust_slider_changed)
	dust_slider = r_dust[0]
	dust_val = r_dust[1]
	dust_val.text = "%d%%" % int(round(cur_dust * 100.0))

	var cylinder_world = get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator if is_inside_tree() else null
	var cur_fog = cylinder_world.air_density if cylinder_world else 1.25
	var r_fog = _create_slider_row(vbox, "Fog Opacity / Density:", 0.0, 2.0, 0.01, cur_fog, _on_fog_changed)
	fog_slider = r_fog[0]
	fog_val = r_fog[1]
	fog_val.text = "%d%%" % int(round(cur_fog * 100.0))

	var cur_hum = weather_system.humidity_density_gm3 if weather_system else 14.5
	var r_hum = _create_slider_row(vbox, "Humidity Density:", 2.0, 30.0, 0.5, cur_hum, _on_humidity_slider_changed)
	humidity_slider = r_hum[0]
	humidity_val = r_hum[1]
	humidity_val.text = "%.1f g/m³" % cur_hum

	var cur_hvac = weather_system.endcap_air_temperature_c if weather_system else 22.5
	var r_hvac = _create_slider_row(vbox, "HVAC End-Cap Air Temp:", 10.0, 40.0, 0.5, cur_hvac, _on_hvac_air_slider_changed)
	hvac_air_slider = r_hvac[0]
	hvac_air_val = r_hvac[1]
	hvac_air_val.text = "%.1f °C" % cur_hvac

	var cur_water = weather_system.water_pipe_temperature_c if weather_system else 24.0
	var r_water = _create_slider_row(vbox, "Water Heating Pipe Temp:", 10.0, 40.0, 0.5, cur_water, _on_water_pipe_slider_changed)
	water_pipe_slider = r_water[0]
	water_pipe_val = r_water[1]
	water_pipe_val.text = "%.1f °C" % cur_water

	cloud_status_label = Label.new()
	cloud_status_label.name = "CloudStatusLabel"
	cloud_status_label.add_theme_font_size_override("font_size", 10)
	cloud_status_label.text = "Cloud Base: 1.25 km | RH: 68%"
	cloud_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cloud_status_label)

func _setup_lighting_tab(vbox: VBoxContainer) -> void:
	var preset_box = VBoxContainer.new()
	var preset_lbl = Label.new()
	preset_lbl.text = "Lighting Preset:"
	preset_lbl.add_theme_font_size_override("font_size", 11)
	preset_box.add_child(preset_lbl)

	light_preset_option = OptionButton.new()
	light_preset_option.focus_mode = Control.FOCUS_NONE
	light_preset_option.add_item("Uniform Daylight", 0)
	light_preset_option.add_item("Gradient (Diurnal Solar Cycle)", 1)
	light_preset_option.add_item("Day/Night Wave (Animated)", 2)
	light_preset_option.add_item("Neon Aurora (Animated)", 3)
	light_preset_option.add_item("Warm Sunset", 4)
	light_preset_option.add_item("Solar Day/Night Cycle", 5)

	var cur_sel = 1
	if light_bar:
		match light_bar.preset:
			AxisLightBar.LightingPreset.UNIFORM: cur_sel = 0
			AxisLightBar.LightingPreset.GRADIENT: cur_sel = 1
			AxisLightBar.LightingPreset.DAY_NIGHT_WAVE: cur_sel = 2
			AxisLightBar.LightingPreset.NEON_AURORA: cur_sel = 3
			AxisLightBar.LightingPreset.WARM_SUNSET: cur_sel = 4
			AxisLightBar.LightingPreset.SOLAR_CYCLE: cur_sel = 5
	light_preset_option.select(cur_sel)
	light_preset_option.item_selected.connect(_on_light_preset_selected)
	preset_box.add_child(light_preset_option)
	vbox.add_child(preset_box)

	var cur_intensity = light_bar.global_intensity_multiplier if light_bar else 3.5
	var r_int = _create_slider_row(vbox, "Light Bar Intensity:", 0.0, 1.0, 0.002, intensity_to_slider_pos(cur_intensity), _on_light_slider_changed)
	light_intensity_slider = r_int[0]
	light_intensity_val = r_int[1]
	_update_intensity_display(cur_intensity)

func _setup_time_tab(vbox: VBoxContainer) -> void:
	# Solar / Habitat In-Game Clock Time of Day
	var cur_time = light_bar.time_of_day_hours if light_bar else 12.0
	var r_time = _create_slider_row(vbox, "In-Game Time of Day:", 0.0, 24.0, 0.0005, cur_time, _on_solar_time_slider_changed)
	solar_time_slider = r_time[0]
	solar_time_val = r_time[1]
	solar_time_val.text = "12:00:00 [Real-Time]"

	sync_real_time_btn = Button.new()
	sync_real_time_btn.text = "🔄 Sync to Real-Time Clock"
	sync_real_time_btn.focus_mode = Control.FOCUS_NONE
	sync_real_time_btn.add_theme_font_size_override("font_size", 11)
	sync_real_time_btn.pressed.connect(_on_sync_real_time_pressed)
	vbox.add_child(sync_real_time_btn)

	var sep_speed = HSeparator.new()
	vbox.add_child(sep_speed)

	# Simulation Time Speed / Progression Multiplier
	var cur_scale = light_bar.time_scale if light_bar else 1.0
	var r_scale = _create_slider_row(vbox, "Simulation Time Speed:", 0.0, 360.0, 1.0, cur_scale, _on_time_scale_slider_changed)
	time_scale_slider = r_scale[0]
	time_scale_val = r_scale[1]
	_update_time_scale_display(cur_scale)

	var sep_lat = HSeparator.new()
	vbox.add_child(sep_lat)

	# Earth Latitude
	var cur_lat = light_bar.earth_latitude_deg if light_bar else 40.0
	var r_lat = _create_slider_row(vbox, "Earth Latitude Reference:", -90.0, 90.0, 1.0, cur_lat, _on_latitude_slider_changed)
	latitude_slider = r_lat[0]
	latitude_val = r_lat[1]
	latitude_val.text = "+40.0° N (Temperate)"

	solar_status_label = Label.new()
	solar_status_label.name = "SolarStatusLabel"
	solar_status_label.add_theme_font_size_override("font_size", 11)
	solar_status_label.text = "Solar Elev: +0.0° | Phase: Daylight"
	solar_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(solar_status_label)

func _setup_physics_tab(vbox: VBoxContainer) -> void:
	var cur_grav = player.base_gravity if player else 9.5
	var r_grav = _create_slider_row(vbox, "Base Surface Gravity:", 0.0, 25.0, 0.5, cur_grav, _on_gravity_changed)
	gravity_slider = r_grav[0]
	gravity_val = r_grav[1]
	gravity_val.text = "-%.1f m/s²" % cur_grav

	var spawn_pts_lbl = Label.new()
	spawn_pts_lbl.text = "📍 Fast Travel & Spawn Locations:"
	spawn_pts_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(spawn_pts_lbl)

	var spawn_option = OptionButton.new()
	spawn_option.name = "SpawnLocationOption"
	spawn_option.focus_mode = Control.FOCUS_NONE
	spawn_option.add_theme_font_size_override("font_size", 11)
	var spawn_pts = player.get_spawn_points() if player else []
	for idx in range(spawn_pts.size()):
		var sp = spawn_pts[idx]
		var sp_name = sp.get("name", "Spawn Point %d" % (idx + 1))
		spawn_option.add_item(sp_name, idx)
	spawn_option.item_selected.connect(func(idx: int):
		if player and idx < spawn_pts.size():
			player.teleport_to_spawn_data(spawn_pts[idx])
			log_event("Fast Travel -> Teleported to %s" % spawn_pts[idx].get("name", ""), "#ffaa55")
	)
	vbox.add_child(spawn_option)

	reset_spawn_btn = Button.new()
	reset_spawn_btn.text = "🔄 Reset to Default Spawn"
	reset_spawn_btn.focus_mode = Control.FOCUS_NONE
	reset_spawn_btn.add_theme_font_size_override("font_size", 11)
	reset_spawn_btn.pressed.connect(_on_reset_spawn_pressed)
	vbox.add_child(reset_spawn_btn)

	toggle_looking_at_btn = Button.new()
	toggle_looking_at_btn.text = "👁️ Target Inspector (Looking At): OFF"
	toggle_looking_at_btn.focus_mode = Control.FOCUS_NONE
	toggle_looking_at_btn.add_theme_font_size_override("font_size", 11)
	toggle_looking_at_btn.pressed.connect(_on_toggle_looking_at_pressed)
	vbox.add_child(toggle_looking_at_btn)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	south_cap_btn = Button.new()
	south_cap_btn.text = "Inspect South End Cap (z = -8.5 km)"
	south_cap_btn.focus_mode = Control.FOCUS_NONE
	south_cap_btn.add_theme_font_size_override("font_size", 11)
	south_cap_btn.pressed.connect(_on_view_south_cap_pressed)
	vbox.add_child(south_cap_btn)

	north_cap_btn = Button.new()
	north_cap_btn.text = "Inspect North End Cap (z = +8.5 km)"
	north_cap_btn.focus_mode = Control.FOCUS_NONE
	north_cap_btn.add_theme_font_size_override("font_size", 11)
	north_cap_btn.pressed.connect(_on_view_north_cap_pressed)
	vbox.add_child(north_cap_btn)

	var p_sep = HSeparator.new()
	vbox.add_child(p_sep)

	var emitter_title = Label.new()
	emitter_title.text = "🚀 Coriolis Particle Launcher"
	emitter_title.add_theme_font_size_override("font_size", 12)
	emitter_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(emitter_title)

	var r_spd = _create_slider_row(vbox, "Launch Speed (m/s):", 5.0, 150.0, 5.0, launch_speed, _on_launch_speed_changed)
	launch_speed_slider = r_spd[0]
	launch_speed_val = r_spd[1]
	launch_speed_val.text = "%.0f m/s" % launch_speed

	var cur_drag = particle_emitter.air_drag_coefficient if particle_emitter else 0.0
	_create_slider_row(vbox, "Aerodynamic Drag:", 0.0, 0.05, 0.002, cur_drag, _on_particle_drag_changed)

	launch_up_btn = Button.new()
	launch_up_btn.text = "🚀 Toss Upward (Coriolis Curve)"
	launch_up_btn.focus_mode = Control.FOCUS_NONE
	launch_up_btn.add_theme_font_size_override("font_size", 11)
	launch_up_btn.pressed.connect(_on_launch_up_pressed)
	vbox.add_child(launch_up_btn)

	var hbox_pro_ret = _new_settings_row()
	vbox.add_child(hbox_pro_ret)

	launch_prograde_btn = Button.new()
	launch_prograde_btn.text = "➡️ Prograde (+θ)"
	launch_prograde_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch_prograde_btn.focus_mode = Control.FOCUS_NONE
	launch_prograde_btn.add_theme_font_size_override("font_size", 10)
	launch_prograde_btn.pressed.connect(_on_launch_prograde_pressed)
	hbox_pro_ret.add_child(launch_prograde_btn)

	launch_retrograde_btn = Button.new()
	launch_retrograde_btn.text = "⬅️ Retrograde (-θ)"
	launch_retrograde_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch_retrograde_btn.focus_mode = Control.FOCUS_NONE
	launch_retrograde_btn.add_theme_font_size_override("font_size", 10)
	launch_retrograde_btn.pressed.connect(_on_launch_retrograde_pressed)
	hbox_pro_ret.add_child(launch_retrograde_btn)

	launch_aimed_btn = Button.new()
	launch_aimed_btn.text = "🎯 Launch in View Direction (HotKey: P)"
	launch_aimed_btn.focus_mode = Control.FOCUS_NONE
	launch_aimed_btn.add_theme_font_size_override("font_size", 11)
	launch_aimed_btn.pressed.connect(_on_launch_aimed_pressed)
	vbox.add_child(launch_aimed_btn)

	toggle_rain_stream_btn = Button.new()
	var is_rain_stream = particle_emitter.rain_stream_enabled if particle_emitter else false
	toggle_rain_stream_btn.text = "🌧️ Cloud Rain Stream: %s" % ("ON" if is_rain_stream else "OFF")
	toggle_rain_stream_btn.focus_mode = Control.FOCUS_NONE
	toggle_rain_stream_btn.add_theme_font_size_override("font_size", 11)
	toggle_rain_stream_btn.pressed.connect(_on_toggle_rain_stream_pressed)
	vbox.add_child(toggle_rain_stream_btn)

	var hbox_traj = _new_settings_row()
	vbox.add_child(hbox_traj)

	toggle_trajectories_btn = Button.new()
	var show_traj = particle_emitter.show_trajectories if particle_emitter else true
	toggle_trajectories_btn.text = "Trajectories: %s" % ("ON" if show_traj else "OFF")
	toggle_trajectories_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_trajectories_btn.focus_mode = Control.FOCUS_NONE
	toggle_trajectories_btn.add_theme_font_size_override("font_size", 10)
	toggle_trajectories_btn.pressed.connect(_on_toggle_trajectories_pressed)
	hbox_traj.add_child(toggle_trajectories_btn)

	clear_trajectories_btn = Button.new()
	clear_trajectories_btn.text = "🧹 Clear Trails"
	clear_trajectories_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_trajectories_btn.focus_mode = Control.FOCUS_NONE
	clear_trajectories_btn.add_theme_font_size_override("font_size", 10)
	clear_trajectories_btn.pressed.connect(_on_clear_trajectories_pressed)
	hbox_traj.add_child(clear_trajectories_btn)

func _setup_performance_tab(vbox: VBoxContainer) -> void:
	perf_profiler_label = Label.new()
	perf_profiler_label.name = "PerformanceProfilerLabel"
	perf_profiler_label.add_theme_font_size_override("font_size", 10)
	perf_profiler_label.text = "Performance Profiler: Initializing..."
	perf_profiler_label.modulate = Color(0.4, 0.9, 1.0)
	vbox.add_child(perf_profiler_label)

	var sep0 = HSeparator.new()
	vbox.add_child(sep0)

	var preset_lbl = Label.new()
	preset_lbl.text = "⚡ Quick Performance Preset:"
	preset_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(preset_lbl)

	perf_preset_option = OptionButton.new()
	perf_preset_option.focus_mode = Control.FOCUS_NONE
	perf_preset_option.add_theme_font_size_override("font_size", 11)
	perf_preset_option.add_item("🚀 Ultra Performance (60 FPS Mobile)", 0)
	perf_preset_option.add_item("📱 Balanced Mobile (30-60 FPS)", 1)
	perf_preset_option.add_item("💻 High Quality (Desktop / Fast GPU)", 2)
	perf_preset_option.add_item("🌌 Cinematic (Full 40km Distance)", 3)
	perf_preset_option.select(1 if (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")) else 2)
	perf_preset_option.item_selected.connect(_on_perf_preset_selected)
	vbox.add_child(perf_preset_option)

	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	var cur_far = 40000.0
	if player and player.camera:
		player.camera.far = cur_far
	var r_cull = _create_slider_row(vbox, "Camera Culling Distance:", 500.0, 40000.0, 250.0, cur_far, _on_perf_culling_changed)
	perf_culling_slider = r_cull[0]
	_limit_performance_slider_width(perf_culling_slider)
	perf_culling_val = r_cull[1]
	_update_culling_label(cur_far)

	var cur_scale = 1.0
	if get_viewport():
		get_viewport().scaling_3d_scale = cur_scale
	var r_scale = _create_slider_row(vbox, "3D Render Resolution Scale:", 0.25, 1.0, 0.05, cur_scale, _on_perf_scale_changed)
	perf_scale_slider = r_scale[0]
	_limit_performance_slider_width(perf_scale_slider)
	perf_scale_val = r_scale[1]
	_update_perf_scale_label(cur_scale)

	var rain_lbl = Label.new()
	rain_lbl.text = "🌧️ Rain / Snow Particle Density:"
	rain_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(rain_lbl)

	perf_rain_layers_option = OptionButton.new()
	perf_rain_layers_option.focus_mode = Control.FOCUS_NONE
	perf_rain_layers_option.add_theme_font_size_override("font_size", 11)
	perf_rain_layers_option.add_item("Precipitation: Disabled", 0)
	perf_rain_layers_option.add_item("Precipitation: Low (0.5×)", 2)
	perf_rain_layers_option.add_item("Precipitation: Balanced (1×)", 4)
	perf_rain_layers_option.add_item("Precipitation: Dense (1.5×)", 6)
	perf_rain_layers_option.add_item("Precipitation: Ultra (2×)", 8)
	var cur_rain_layers = weather_system.rain_sheet_layer_count if weather_system else 4
	var select_idx = 2
	match cur_rain_layers:
		0: select_idx = 0
		2: select_idx = 1
		4: select_idx = 2
		6: select_idx = 3
		8: select_idx = 4
		_: select_idx = 2
	perf_rain_layers_option.select(select_idx)
	perf_rain_layers_option.item_selected.connect(_on_perf_rain_layers_selected)
	vbox.add_child(perf_rain_layers_option)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var cur_light_dist = SurfaceLightObject.global_active_light_distance
	var r_light = _create_slider_row(vbox, "Surface Light Active Range:", 0.0, 8000.0, 50.0, cur_light_dist, _on_perf_light_dist_changed)
	perf_light_dist_slider = r_light[0]
	_limit_performance_slider_width(perf_light_dist_slider)
	perf_light_dist_val = r_light[1]
	_update_light_dist_label(cur_light_dist)

	var clutter_mgr = get_tree().get_first_node_in_group("clutter_manager") as ClutterManager if is_inside_tree() else null
	var cur_clutter_dist = clutter_mgr.view_radius if clutter_mgr else 500.0
	var r_clutter = _create_slider_row(vbox, "Ground Clutter Draw Distance:", 0.0, 1000.0, 25.0, cur_clutter_dist, _on_perf_clutter_dist_changed)
	perf_clutter_dist_slider = r_clutter[0]
	_limit_performance_slider_width(perf_clutter_dist_slider)
	perf_clutter_dist_val = r_clutter[1]
	_update_clutter_dist_label(cur_clutter_dist)
	var cur_clutter_density = clutter_mgr.density_multiplier if clutter_mgr else 1.0
	var r_clutter_density = _create_slider_row(vbox, "Ground Clutter Density:", 0.0, 2.0, 0.1, cur_clutter_density, _on_perf_clutter_density_changed)
	perf_clutter_density_slider = r_clutter_density[0]
	_limit_performance_slider_width(perf_clutter_density_slider)
	perf_clutter_density_val = r_clutter_density[1]
	_update_clutter_density_label(cur_clutter_density)
	perf_clutter_auto_label = Label.new()
	perf_clutter_auto_label.name = "GroundClutterAutoTuneStatus"
	perf_clutter_auto_label.add_theme_font_size_override("font_size", 10)
	perf_clutter_auto_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perf_clutter_auto_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	perf_clutter_auto_label.custom_minimum_size.x = 0.0
	perf_clutter_auto_label.modulate = Color(0.72, 0.84, 0.92)
	perf_clutter_auto_label.text = "Auto-tune activates when a target FPS is selected."
	vbox.add_child(perf_clutter_auto_label)

	var fps_limit_lbl = Label.new()
	fps_limit_lbl.text = "🎯 Target Frame Rate (FPS Limit):"
	fps_limit_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(fps_limit_lbl)

	perf_fps_limit_option = OptionButton.new()
	perf_fps_limit_option.focus_mode = Control.FOCUS_NONE
	perf_fps_limit_option.add_theme_font_size_override("font_size", 11)
	perf_fps_limit_option.add_item("Native / Unlimited", 0)
	perf_fps_limit_option.add_item("30 FPS (Power Saver)", 30)
	perf_fps_limit_option.add_item("45 FPS (Smooth Battery)", 45)
	perf_fps_limit_option.add_item("60 FPS (Target Standard)", 60)
	perf_fps_limit_option.add_item("90 FPS (High Refresh)", 90)
	perf_fps_limit_option.add_item("120 FPS (Ultra Refresh)", 120)
	var cur_fps_limit = Engine.max_fps
	var selected_idx = 0
	match cur_fps_limit:
		30: selected_idx = 1
		45: selected_idx = 2
		60: selected_idx = 3
		90: selected_idx = 4
		120: selected_idx = 5
		_: selected_idx = 0
	perf_fps_limit_option.select(selected_idx)
	perf_fps_limit_option.item_selected.connect(_on_perf_fps_limit_selected)
	vbox.add_child(perf_fps_limit_option)

	var sep3 = HSeparator.new()
	vbox.add_child(sep3)

	var toggles_lbl = Label.new()
	toggles_lbl.text = "👁️ Graphics Feature Toggles:"
	toggles_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(toggles_lbl)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	perf_near_clouds_btn = Button.new()
	perf_near_clouds_btn.text = "Near Clouds: ON"
	perf_near_clouds_btn.focus_mode = Control.FOCUS_NONE
	perf_near_clouds_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	perf_near_clouds_btn.add_theme_font_size_override("font_size", 10)
	perf_near_clouds_btn.pressed.connect(_on_perf_near_clouds_toggle)
	grid.add_child(perf_near_clouds_btn)

	perf_far_clouds_btn = Button.new()
	perf_far_clouds_btn.text = "Far Clouds: ON"
	perf_far_clouds_btn.focus_mode = Control.FOCUS_NONE
	perf_far_clouds_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	perf_far_clouds_btn.add_theme_font_size_override("font_size", 10)
	perf_far_clouds_btn.pressed.connect(_on_perf_far_clouds_toggle)
	grid.add_child(perf_far_clouds_btn)

	perf_water_mesh_btn = Button.new()
	perf_water_mesh_btn.text = "Water Mesh: ON"
	perf_water_mesh_btn.focus_mode = Control.FOCUS_NONE
	perf_water_mesh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	perf_water_mesh_btn.add_theme_font_size_override("font_size", 10)
	perf_water_mesh_btn.pressed.connect(_on_perf_water_mesh_toggle)
	grid.add_child(perf_water_mesh_btn)

	perf_glow_btn = Button.new()
	perf_glow_btn.text = "HDR Glow: ON"
	perf_glow_btn.focus_mode = Control.FOCUS_NONE
	perf_glow_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	perf_glow_btn.add_theme_font_size_override("font_size", 10)
	perf_glow_btn.pressed.connect(_on_perf_glow_toggle)
	grid.add_child(perf_glow_btn)

	perf_fog_btn = Button.new()
	perf_fog_btn.text = "Depth Fog: ON"
	perf_fog_btn.focus_mode = Control.FOCUS_NONE
	perf_fog_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	perf_fog_btn.add_theme_font_size_override("font_size", 10)
	perf_fog_btn.pressed.connect(_on_perf_fog_toggle)
	grid.add_child(perf_fog_btn)

	var is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	var default_preset = 1 if is_mobile else 2
	_on_perf_preset_selected(default_preset)

func _limit_performance_slider_width(slider: HSlider) -> void:
	if not slider:
		return
	var screen_width = get_viewport().get_visible_rect().size.x
	var available_width = maxf((screen_width - INTERFACE_PANEL_SIDE_MARGIN * 2.0) / maxf(current_ui_scale, 0.01), 1.0)
	slider.custom_minimum_size.x = available_width * 0.75
	slider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

func _setup_system_tab(vbox: VBoxContainer) -> void:
	var r_scale = _create_slider_row(vbox, "UI Scaling Factor:", 0.75, 3.5, 0.05, current_ui_scale, _on_scale_slider_changed)
	scale_slider = r_scale[0]
	scale_val = r_scale[1]
	_update_scale_slider_ui()

	reset_scale_btn = Button.new()
	reset_scale_btn.text = "Reset to Auto-Calculated Scale"
	reset_scale_btn.focus_mode = Control.FOCUS_NONE
	reset_scale_btn.add_theme_font_size_override("font_size", 10)
	reset_scale_btn.pressed.connect(_on_reset_scale_pressed)
	vbox.add_child(reset_scale_btn)

	toggle_looking_at_sys_btn = Button.new()
	toggle_looking_at_sys_btn.text = "👁️ Target Inspector (Looking At): OFF"
	toggle_looking_at_sys_btn.focus_mode = Control.FOCUS_NONE
	toggle_looking_at_sys_btn.add_theme_font_size_override("font_size", 10)
	toggle_looking_at_sys_btn.pressed.connect(_on_toggle_looking_at_pressed)
	vbox.add_child(toggle_looking_at_sys_btn)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	system_fps_label = Label.new()
	system_fps_label.name = "SystemPerformanceLabel"
	system_fps_label.add_theme_font_size_override("font_size", 10)
	system_fps_label.text = "Performance: Initializing..."
	system_fps_label.modulate = Color(0.6, 0.9, 1.0)
	vbox.add_child(system_fps_label)

func _update_fps_display(delta: float) -> void:
	fps_update_timer += delta
	if fps_update_timer < 0.1:
		return
	fps_update_timer = 0.0

	var fps = Engine.get_frames_per_second()
	var frame_ms = (1.0 / maxf(float(fps), 1.0)) * 1000.0
	if is_zero_approx(fps):
		frame_ms = delta * 1000.0

	if fps_label:
		fps_label.text = "%d FPS (%.1f ms)" % [fps, frame_ms]

	if perf_profiler_label and is_instance_valid(perf_profiler_label) and perf_profiler_label.is_visible_in_tree():
		var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
		var process_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var far_dist = player.camera.far if (player and player.camera) else 0.0
		var scale_3d = get_viewport().scaling_3d_scale if get_viewport() else 1.0
		perf_profiler_label.text = "⚡ %d FPS (%.1f ms) | Proc: %.1f ms | Phys: %.1f ms\nDraw Calls: %d | Primitives: %d | VRAM: %.1f MB\nCamera Far: %.0fm (%.1fkm) | 3D Scale: %.0f%%" % [
			fps, frame_ms, process_ms, physics_ms, int(draw_calls), int(objects), vram_mb, far_dist, far_dist / 1000.0, scale_3d * 100.0
		]

	if system_fps_label and is_instance_valid(system_fps_label) and system_fps_label.is_visible_in_tree():
		var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
		var process_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		system_fps_label.text = "Engine: %d FPS | Frame: %.1f ms (Proc: %.1f ms | Phys: %.1f ms)\nDraw Calls: %d | Objects: %d | VRAM: %.1f MB" % [
			fps, frame_ms, process_ms, physics_ms, int(draw_calls), int(objects), vram_mb
		]

var telemetry_ui_timer: float = 0.0
var cached_telemetry_data: Dictionary = {}

func _on_telemetry_updated(data: Dictionary) -> void:
	cached_telemetry_data = data
	var is_flying: bool = data.get("is_flying", false)
	var locomotion_state: String = data.get("locomotion_state", "IDLE")

	if locomotion_state != last_locomotion_mode:
		if not last_locomotion_mode.is_empty():
			log_event("Player Locomotion -> %s" % locomotion_state, "#66ddaa")
		last_locomotion_mode = locomotion_state

	var is_in_water: bool = data.get("is_in_water", false)
	if is_in_water != last_water_submerged:
		last_water_submerged = is_in_water
		if is_in_water:
			log_event("Player Environment -> Submerged in Water Basin", "#33ccff")
		else:
			log_event("Player Environment -> Emerged from Water Basin", "#33ffcc")

	var is_camera_underwater: bool = data.get("is_camera_underwater", is_in_water)
	if underwater_overlay:
		underwater_overlay.visible = is_camera_underwater

func _render_telemetry_ui(data: Dictionary) -> void:
	var locomotion_state: String = data.get("locomotion_state", "IDLE")
	var grav_ms2: float = data.get("gravity_ms2", 0.0)
	var grav_g: float = data.get("gravity_g", 0.0)
	var dist_axis: float = data.get("dist_from_axis", 0.0)
	var dist_surface: float = data.get("dist_to_surface", 0.0)
	var speed: float = data.get("speed", 0.0)
	var pos_z: float = data.get("pos_z", 0.0)
	var ring_deg: float = data.get("ring_angle_deg", 0.0)
	var wobble_deg: float = data.get("wobble_deg", 0.0)
	var correction_rate: float = data.get("wobble_correction_rate", 16.0)
	var is_in_water: bool = data.get("is_in_water", false)

	if telemetry_label:
		var text = ""
		text += "CENTRIFUGAL GRAVITY: %4.2f G  (%4.1f m/s²)\n" % [grav_g, grav_ms2]
		text += "AXIS DISTANCE:       %5.1f m / %4.1f m\n" % [dist_axis, player.cylinder_radius if player else 4000.0]
		if is_in_water:
			text += "SURFACE ALTITUDE:    %5.1f m [WATER BASIN]\n" % dist_surface
		else:
			text += "SURFACE ALTITUDE:    %5.1f m\n" % dist_surface
		text += "VELOCITY:            %5.1f m/s\n" % speed
		text += "COORDINATES:         Angle: %5.1f° | Z: %5.1f m" % [ring_deg, pos_z]
		telemetry_label.text = text

	if mode_badge:
		match locomotion_state:
			"FLYING":
				mode_badge.text = "MODE: [3D FLIGHT / FREE CAM]"
				mode_badge.modulate = Color(0.2, 0.9, 1.0)
			"RUNNING":
				mode_badge.text = "MODE: [SPRINT / RUNNING]"
				mode_badge.modulate = Color(1.0, 0.85, 0.2)
			"WALKING":
				mode_badge.text = "MODE: [SURFACE WALKING]"
				mode_badge.modulate = Color(0.4, 1.0, 0.4)
			"JUMPING":
				mode_badge.text = "MODE: [JUMPING - ASCENDING]"
				mode_badge.modulate = Color(0.5, 0.7, 1.0)
			"FALLING":
				mode_badge.text = "MODE: [AIRBORNE - GRAVITY FALL]"
				mode_badge.modulate = Color(0.8, 0.5, 1.0)
			"IDLE":
				mode_badge.text = "MODE: [GROUNDED / IDLE]"
				mode_badge.modulate = Color(0.7, 0.9, 0.8)

	if horizon_status_label:
		if absf(wobble_deg) < 0.8:
			horizon_status_label.text = "HORIZON: [PERPENDICULAR - LOCKED]"
			horizon_status_label.modulate = Color(0.2, 1.0, 0.5)
		else:
			horizon_status_label.text = "HORIZON: [CORRECTING: %+.1f° | Rate: %.1f/s]" % [wobble_deg, correction_rate]
			horizon_status_label.modulate = Color(1.0, 0.7, 0.2)

func _on_light_preset_selected(index: int) -> void:
	if not light_bar:
		return
	var preset_name = "Uniform"
	match index:
		0:
			light_bar.uniform_follows_solar_cycle = false
			light_bar.preset = AxisLightBar.LightingPreset.UNIFORM
			preset_name = "Uniform White (3.5x)"
		1:
			light_bar.preset = AxisLightBar.LightingPreset.GRADIENT
			light_bar.gradient_follows_solar_cycle = true
			preset_name = "Solar Gradient"
		2:
			light_bar.preset = AxisLightBar.LightingPreset.DAY_NIGHT_WAVE
			preset_name = "Day/Night Wave"
		3:
			light_bar.preset = AxisLightBar.LightingPreset.NEON_AURORA
			preset_name = "Neon Aurora Borealis"
		4:
			light_bar.preset = AxisLightBar.LightingPreset.WARM_SUNSET
			preset_name = "Warm Golden Sunset"
		5:
			light_bar.preset = AxisLightBar.LightingPreset.SOLAR_CYCLE
			preset_name = "Realistic 24hr Solar Cycle"
	_update_solar_ui()
	log_event("Lighting System -> Preset set to '%s'" % preset_name, "#ffee66")

func _on_solar_time_slider_changed(value: float) -> void:
	if light_bar:
		light_bar.set_time_of_day(value, true)
	if weather_system and weather_system.tie_to_in_game_clock:
		weather_system.apply_time_of_day_weather(value)
	_update_solar_ui()
	var total_sec = int(fposmod(value, 24.0) * 3600.0)
	var h = (total_sec / 3600) % 24
	var m = (total_sec / 60) % 60
	var s = total_sec % 60
	log_event("Forced Time Adjustment -> Scrubbed Solar Time to %02d:%02d:%02d (%.2f hrs)" % [h, m, s, value], "#ffcc44")

func _on_time_scale_slider_changed(value: float) -> void:
	if light_bar:
		light_bar.time_scale = value
		light_bar.use_real_time = false
	_update_time_scale_display(value)
	_update_solar_ui()
	log_event("Time Simulation -> Speed Multiplier set to %.0fx (%s)" % [value, "Paused" if is_zero_approx(value) else "Running"], "#ffcc44")

func _update_time_scale_display(value: float) -> void:
	if not time_scale_val:
		return
	if is_zero_approx(value):
		time_scale_val.text = "0x [Paused]"
	elif is_equal_approx(value, 1.0):
		time_scale_val.text = "1x [Real-Time 1s/s]"
	elif value < 60.0:
		time_scale_val.text = "%.0fx (%.1fs/s)" % [value, value]
	elif is_equal_approx(value, 60.0):
		time_scale_val.text = "60x [1 min/s]"
	elif is_equal_approx(value, 360.0):
		time_scale_val.text = "360x [6 min/s]"
	else:
		time_scale_val.text = "%.0fx (%.1f min/s)" % [value, value / 60.0]

func _on_sync_real_time_pressed() -> void:
	if sync_real_time_btn:
		sync_real_time_btn.release_focus()
	if light_bar:
		light_bar.sync_to_system_clock()
	if time_scale_slider:
		time_scale_slider.set_value_no_signal(1.0)
	_update_time_scale_display(1.0)
	_update_solar_ui()
	log_event("Time Simulation -> Synchronized to System Clock (1.0x Real-Time)", "#ffdd55")

func _on_latitude_slider_changed(value: float) -> void:
	if light_bar:
		light_bar.set_earth_latitude(value)
	_update_solar_ui()
	var hemi = "N" if value >= 0.0 else "S"
	log_event("Solar System -> Habitat Latitude adjusted to %+.1f°%s" % [absf(value), hemi], "#ffcc44")

func _update_solar_ui() -> void:
	if not light_bar:
		return
	var status = light_bar.get_solar_status()
	var t_hours: float = status.get("time_hours", 12.0)
	var is_rt: bool = status.get("is_real_time", true)
	var elev: float = status.get("solar_elevation", 0.0)
	var phase: String = status.get("phase_name", "Daylight")
	var lat: float = status.get("latitude", 40.0)
	var t_scale: float = status.get("time_scale", 1.0)

	var total_sec = int(t_hours * 3600.0)
	var hours = (total_sec / 3600) % 24
	var mins = (total_sec / 60) % 60
	var secs = total_sec % 60
	var mode_tag = "Real-Time" if is_rt else ("Paused" if is_zero_approx(t_scale) else ("%.0fx" % t_scale))

	if solar_badge_label and telemetry_panel and telemetry_panel.visible:
		solar_badge_label.text = "SOLAR TIME: %02d:%02d:%02d [%s]\nELEVATION: %+.1f° (%s)" % [
			hours, mins, secs, mode_tag, elev, phase
		]
		if elev >= 20.0:
			solar_badge_label.modulate = Color(0.4, 0.9, 1.0)
		elif elev >= 0.0:
			solar_badge_label.modulate = Color(1.0, 0.8, 0.3)
		elif elev >= -6.0:
			solar_badge_label.modulate = Color(0.9, 0.45, 0.6)
		elif elev >= -18.0:
			solar_badge_label.modulate = Color(0.35, 0.5, 0.9)
		else:
			solar_badge_label.modulate = Color(0.5, 0.6, 0.8)

	if control_panel and control_panel.visible:
		if solar_time_val:
			solar_time_val.text = "%02d:%02d:%02d [%s]" % [hours, mins, secs, mode_tag]

		if solar_time_slider:
			solar_time_slider.set_value_no_signal(t_hours)

		if latitude_val:
			var hemi = "N" if lat >= 0.0 else "S"
			var desc = "Arctic" if absf(lat) > 66.5 else ("Equator" if absf(lat) < 5.0 else ("Tropical" if absf(lat) < 23.5 else "Temperate"))
			latitude_val.text = "%+.0f°%s (%s)" % [absf(lat), hemi, desc]

		if solar_status_label:
			solar_status_label.text = "Solar Elev: %+.1f° | Phase: %s" % [elev, phase]

func _on_light_slider_changed(slider_pos: float) -> void:
	var intensity = slider_pos_to_intensity(slider_pos)
	_apply_light_intensity(intensity)

func _on_light_intensity_changed(value: float) -> void:
	if light_intensity_slider:
		light_intensity_slider.set_value_no_signal(intensity_to_slider_pos(value))
	_apply_light_intensity(value)

func _apply_light_intensity(intensity: float) -> void:
	if light_bar:
		light_bar.global_intensity_multiplier = intensity
	_update_intensity_display(intensity)
	log_event("Axial Lighting -> Global Intensity set to %.3fx" % intensity, "#ffee66")

func _update_intensity_display(intensity: float) -> void:
	if not light_intensity_val:
		return
	if is_zero_approx(intensity):
		light_intensity_val.text = "0.0x [Dark]"
	elif intensity < 0.01:
		light_intensity_val.text = "%.3fx" % intensity
	elif intensity < 1.0:
		light_intensity_val.text = "%.2fx" % intensity
	else:
		light_intensity_val.text = "%.1fx" % intensity

func _on_fog_changed(value: float) -> void:
	var cylinder_world = get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator
	if cylinder_world:
		cylinder_world.air_density = value
	if fog_val:
		fog_val.text = "%d%%" % int(round(value * 100.0))
	log_event("Terrain Atmosphere -> Air Fog Density set to %d%%" % int(round(value * 100.0)), "#aaccff")

func _on_gravity_changed(value: float) -> void:
	if player:
		player.base_gravity = value
	if weather_system:
		weather_system.base_gravity = value
	if gravity_val:
		gravity_val.text = "-%.1f m/s²" % value
	log_event("Centrifugal Physics -> Surface Gravity set to %.1f m/s² (%.2f G)" % [value, value / 9.8], "#ffee55")

func _on_auto_cycle_toggle_pressed() -> void:
	if auto_cycle_btn:
		auto_cycle_btn.release_focus()
	if not weather_system:
		return
	weather_system.set_auto_weather_cycle(not weather_system.auto_weather_cycle_enabled)
	if auto_cycle_btn:
		auto_cycle_btn.text = "Auto-Loop: %s" % ("ON" if weather_system.auto_weather_cycle_enabled else "OFF")
	log_event("Weather System -> Auto-Cycle Loop: %s" % ("ON" if weather_system.auto_weather_cycle_enabled else "OFF"), "#77bbff")

func _update_lat_label(lat: float) -> void:
	if not climate_lat_val:
		return
	var hemi = "N" if lat >= 0.0 else "S"
	var abs_lat = absf(lat)
	var zone = "Polar" if abs_lat >= 75.0 else ("Arctic/Boreal" if abs_lat >= 60.0 else ("Temperate" if abs_lat >= 45.0 else ("Subtropical" if abs_lat >= 25.0 else "Tropical")))
	climate_lat_val.text = "%+.1f°%s (%s)" % [abs_lat, hemi, zone]

func _update_precip_label(precip: float) -> void:
	if not climate_precip_val:
		return
	var cat = "Hyper-Arid" if precip < 200.0 else ("Semi-Arid" if precip < 500.0 else ("Moderate" if precip < 1000.0 else ("Humid" if precip < 2000.0 else "Rainforest")))
	climate_precip_val.text = "%.0f mm/yr (%s)" % [precip, cat]

func _update_doy_label(doy: int) -> void:
	if not climate_doy_val:
		return
	var month_names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var d = doy
	var m_idx = 0
	for m in range(12):
		if d <= days_in_month[m]:
			m_idx = m
			break
		d -= days_in_month[m]
	climate_doy_val.text = "Day %d (~%s %d)" % [doy, month_names[m_idx], max(d, 1)]

func _on_climate_lat_changed(value: float) -> void:
	_update_lat_label(value)
	if weather_system:
		weather_system.latitude_deg = value
	if light_bar:
		light_bar.earth_latitude_deg = value
	if latitude_slider and not is_equal_approx(latitude_slider.value, value):
		latitude_slider.set_value_no_signal(value)
	if latitude_val:
		var hemi = "N" if value >= 0.0 else "S"
		latitude_val.text = "%+.0f°%s" % [absf(value), hemi]

func _on_climate_precip_changed(value: float) -> void:
	_update_precip_label(value)
	if weather_system:
		weather_system.yearly_precipitation_mm = value

func _on_climate_doy_changed(value: float) -> void:
	var doy = int(round(value))
	_update_doy_label(doy)
	if weather_system:
		weather_system.day_of_year = doy
	if light_bar:
		light_bar.day_of_year = doy

func _on_apply_climate_preset_pressed() -> void:
	if apply_climate_preset_btn:
		apply_climate_preset_btn.release_focus()
	if not climate_preset_option:
		return
	var idx = climate_preset_option.selected
	var lat = 40.0
	var precip = 950.0
	var doy = 172
	match idx:
		0: lat = 0.0; precip = 3000.0; doy = 172 # Tropical Rainforest
		1: lat = 12.0; precip = 480.0; doy = 172 # Tropical Savanna
		2: lat = 28.0; precip = 100.0; doy = 172 # Subtropical Desert
		3: lat = 35.0; precip = 450.0; doy = 172 # Mediterranean
		4: lat = 42.0; precip = 1100.0; doy = 172 # Temperate Deciduous
		5: lat = 48.0; precip = 2400.0; doy = 172 # Temperate Rainforest
		6: lat = 50.0; precip = 350.0; doy = 172 # Cold Steppe
		7: lat = 62.0; precip = 700.0; doy = 355 # Boreal Taiga (Winter)
		8: lat = 68.0; precip = 200.0; doy = 355 # Arctic Tundra (Winter)
		9: lat = 82.0; precip = 120.0; doy = 355 # Polar Ice Sheet (Winter)

	if climate_lat_slider:
		climate_lat_slider.set_value_no_signal(lat)
	_on_climate_lat_changed(lat)

	if climate_precip_slider:
		climate_precip_slider.set_value_no_signal(precip)
	_on_climate_precip_changed(precip)

	if climate_doy_slider:
		climate_doy_slider.set_value_no_signal(doy)
	_on_climate_doy_changed(doy)

	if weather_system:
		weather_system.skip_current_trajectory()

	log_event("Biome Preset Applied -> %s (Lat: %+.0f°, Rain: %.0fmm, DOY: %d)" % [
		climate_preset_option.get_item_text(idx), lat, precip, doy
	], "#55ffaa")

func _on_gen_weather_state_pressed() -> void:
	if gen_weather_state_btn:
		gen_weather_state_btn.release_focus()
	if weather_system:
		weather_system.skip_current_trajectory()
	log_event("Weather System -> Skipped to Next State", "#77ccff")

func _on_force_snow_pressed() -> void:
	if force_snow_btn:
		force_snow_btn.release_focus()
	if weather_system:
		var snow_state = {
			"name": "Forced Blizzard & Snowfall (❄️)",
			"cloud_coverage": 0.95,
			"cloud_thickness_m": 650.0,
			"precipitation_rate_mmh": 22.0,
			"humidity_density_gm3": 6.5,
			"dust_density": 0.05,
			"endcap_air_temperature_c": -8.0,
			"water_pipe_temperature_c": -3.0,
			"duration": 30.0
		}
		weather_system.push_weather_state(snow_state, true)
	log_event("Forced Weather Triggered -> ❄️ Frigid Blizzard & Snowfall (<4°C)", "#88ddff")

func _on_force_downpour_pressed() -> void:
	if force_downpour_btn:
		force_downpour_btn.release_focus()
	if weather_system:
		var rain_state = {
			"name": "Forced Tropical Downpour (🌧️)",
			"cloud_coverage": 0.98,
			"cloud_thickness_m": 720.0,
			"precipitation_rate_mmh": 35.0,
			"humidity_density_gm3": 27.0,
			"dust_density": 0.03,
			"endcap_air_temperature_c": 24.0,
			"water_pipe_temperature_c": 26.0,
			"duration": 30.0
		}
		weather_system.push_weather_state(rain_state, true)
	log_event("Forced Weather Triggered -> 🌧️ Heavy Atmospheric Downpour", "#55aaff")

func _on_add_preset_to_queue_pressed() -> void:
	if add_preset_to_queue_btn:
		add_preset_to_queue_btn.release_focus()
	if not weather_system or not preset_queue_option or not duration_queue_option:
		return
	var preset_idx = preset_queue_option.selected
	var dur = float(duration_queue_option.get_selected_id())
	var state: Dictionary = {}
	match preset_idx:
		0:
			state = {
				"name": "Clear Solar Sky",
				"cloud_coverage": 0.05,
				"cloud_thickness_m": 80.0,
				"precipitation_rate_mmh": 0.0,
				"humidity_density_gm3": 6.0,
				"dust_density": 0.15,
				"duration": dur
			}
		1:
			state = {
				"name": "Fair Cumulus Skies",
				"cloud_coverage": 0.35,
				"cloud_thickness_m": 220.0,
				"precipitation_rate_mmh": 0.0,
				"humidity_density_gm3": 12.0,
				"dust_density": 0.12,
				"duration": dur
			}
		2:
			state = {
				"name": "Overcast Cloud Deck",
				"cloud_coverage": 0.85,
				"cloud_thickness_m": 480.0,
				"precipitation_rate_mmh": 0.5,
				"humidity_density_gm3": 19.0,
				"dust_density": 0.08,
				"duration": dur
			}
		3:
			state = {
				"name": "Light Rain & Mist",
				"cloud_coverage": 0.88,
				"cloud_thickness_m": 520.0,
				"precipitation_rate_mmh": 7.5,
				"humidity_density_gm3": 22.0,
				"dust_density": 0.06,
				"endcap_air_temperature_c": 19.5,
				"water_pipe_temperature_c": 22.0,
				"duration": dur
			}
		4:
			state = {
				"name": "Heavy Atmospheric Downpour",
				"cloud_coverage": 0.98,
				"cloud_thickness_m": 720.0,
				"precipitation_rate_mmh": 32.0,
				"humidity_density_gm3": 26.5,
				"dust_density": 0.04,
				"endcap_air_temperature_c": 21.0,
				"water_pipe_temperature_c": 23.0,
				"duration": dur
			}
		5:
			state = {
				"name": "Gentle Snowfall & Flurries (❄️)",
				"cloud_coverage": 0.85,
				"cloud_thickness_m": 420.0,
				"precipitation_rate_mmh": 6.0,
				"humidity_density_gm3": 7.0,
				"dust_density": 0.10,
				"endcap_air_temperature_c": -1.5,
				"water_pipe_temperature_c": 0.5,
				"duration": dur
			}
		6:
			state = {
				"name": "Frigid Arctic Blizzard (❄️)",
				"cloud_coverage": 0.98,
				"cloud_thickness_m": 750.0,
				"precipitation_rate_mmh": 28.0,
				"humidity_density_gm3": 8.5,
				"dust_density": 0.05,
				"endcap_air_temperature_c": -12.0,
				"water_pipe_temperature_c": -6.0,
				"duration": dur
			}
		7:
			state = {
				"name": "Atmospheric Dust & Haze",
				"cloud_coverage": 0.15,
				"cloud_thickness_m": 120.0,
				"precipitation_rate_mmh": 0.0,
				"humidity_density_gm3": 5.0,
				"dust_density": 0.65,
				"endcap_air_temperature_c": 27.0,
				"water_pipe_temperature_c": 28.0,
				"duration": dur
			}
	weather_system.push_weather_state(state, false)
	log_event("Weather Queue -> Added Preset '%s' (Duration: %.0fs)" % [state.get("name", "Preset"), dur], "#88bbff")

func _on_queue_current_sliders_pressed() -> void:
	if queue_current_sliders_btn:
		queue_current_sliders_btn.release_focus()
	if not weather_system or not duration_queue_option:
		return
	var dur = float(duration_queue_option.get_selected_id())
	var target_params = {
		"cloud_coverage": cloud_cover_slider.value if cloud_cover_slider else weather_system.cloud_coverage,
		"cloud_thickness_m": cloud_thickness_slider.value if cloud_thickness_slider else weather_system.cloud_thickness_m,
		"precipitation_rate_mmh": precipitation_slider.value if precipitation_slider else weather_system.precipitation_rate_mmh,
		"dust_density": dust_slider.value if dust_slider else weather_system.dust_density,
		"humidity_density_gm3": humidity_slider.value if humidity_slider else weather_system.humidity_density_gm3,
		"endcap_air_temperature_c": hvac_air_slider.value if hvac_air_slider else weather_system.endcap_air_temperature_c,
		"water_pipe_temperature_c": water_pipe_slider.value if water_pipe_slider else weather_system.water_pipe_temperature_c
	}
	weather_system.enqueue_custom_target(target_params, dur)
	log_event("Weather Queue -> Enqueued Slider Target (Duration: %.0fs)" % dur, "#88bbff")

func _on_skip_trajectory_pressed() -> void:
	if skip_trajectory_btn:
		skip_trajectory_btn.release_focus()
	if weather_system:
		weather_system.skip_current_trajectory()
	log_event("Weather Queue -> Force skipped current trajectory", "#88bbff")

func _on_clear_queue_pressed() -> void:
	if clear_queue_btn:
		clear_queue_btn.release_focus()
	if weather_system:
		weather_system.clear_weather_queue()
	log_event("Weather Queue -> Cleared all manual queued items", "#88bbff")

func _on_clock_sync_toggle_pressed() -> void:
	if clock_sync_btn:
		clock_sync_btn.release_focus()
	if not weather_system:
		return
	weather_system.set_tie_to_in_game_clock(not weather_system.tie_to_in_game_clock)
	if clock_sync_btn:
		clock_sync_btn.text = "Clock: %s" % ("ON" if weather_system.tie_to_in_game_clock else "OFF")
	log_event("Weather System -> In-game diurnal clock sync: %s" % ("ON" if weather_system.tie_to_in_game_clock else "OFF"), "#88bbff")

func _on_weather_updated(data: Dictionary) -> void:
	var is_trans = data.get("is_transitioning", false)
	var is_auto = data.get("auto_cycle_enabled", true)
	var is_clock = data.get("tie_to_in_game_clock", true)
	var traj_name = data.get("trajectory_name", "Fair Cumulus Morning")
	var traj_rem = data.get("trajectory_time_remaining", 0.0)
	var traj_prog = data.get("trajectory_progress", 0.0)
	var q_size = data.get("queue_size", 0)
	var q_items = data.get("queue_items", [])
	var cloud_rot_deg = data.get("cloud_deck_rotation_deg", 0.0)
	var cloud_z_drift = data.get("cloud_deck_drift_z", 0.0)

	if auto_cycle_btn:
		auto_cycle_btn.text = "Auto: %s" % ("ON" if is_auto else "OFF")
	if clock_sync_btn:
		clock_sync_btn.text = "Clock: %s" % ("ON" if is_clock else "OFF")

	var wind_ms = float(data.get("wind_speed_m_s", 6.0))
	var wind_kmh = float(data.get("wind_speed_km_h", 21.6))

	if control_panel and control_panel.visible:
		if trajectory_status_label:
			if is_trans:
				var clock_tag = "⏱️ Clock Tied" if is_clock else "⏱️ Real-Time"
				trajectory_status_label.text = "Active Target: %s [%d%% | %ds left] (%s)\nCloud rotation: %.1f°\nWind: %.1f m/s (%.0f km/h)" % [
					traj_name, int(round(traj_prog * 100.0)), int(round(traj_rem)), clock_tag, cloud_rot_deg, wind_ms, wind_kmh
				]
			else:
				trajectory_status_label.text = "Active Weather: %s\nCloud rotation: %.1f°\nWind: %.1f m/s (%.0f km/h)" % [
					data.get("weather_state", "Fair Cumulus"), cloud_rot_deg, wind_ms, wind_kmh
				]

		if queue_list_label:
			if q_size > 0:
				var q_str = " -> ".join(q_items.slice(0, 2))
				if q_size > 2:
					q_str += " (+%d more)" % (q_size - 2)
				queue_list_label.text = "Queue (%d): %s" % [q_size, q_str]
				queue_list_label.modulate = Color(0.4, 1.0, 0.7)
			elif is_auto:
				queue_list_label.text = "Queue: [Empty - Auto-Looping Presets]"
				queue_list_label.modulate = Color(0.7, 0.9, 1.0)
			else:
				queue_list_label.text = "Queue: [Empty - Manual Mode]"
				queue_list_label.modulate = Color(0.8, 0.8, 0.8)

		if (is_trans or is_auto) and (weather_system and (weather_system.auto_weather_cycle_enabled or weather_system.is_transitioning)):
			# Gradually move all sliders in real time to the specified trajectory values
			var cov = float(data.get("cloud_coverage_pct", 55)) / 100.0
			var thick = float(data.get("cloud_thickness_m", 250.0))
			var precip = float(data.get("precipitation_rate_mmh", 0.0))
			var dust = float(data.get("dust_density_pct", 20)) / 100.0
			var hum = float(data.get("humidity_density_gm3", 14.5))
			var hvac_t = float(data.get("endcap_air_temp_c", 22.5))
			var water_t = float(data.get("water_pipe_temp_c", 24.0))

			if cloud_cover_slider:
				cloud_cover_slider.set_value_no_signal(cov)
			if cloud_cover_val:
				cloud_cover_val.text = "%d%%" % int(round(cov * 100.0))

			if cloud_thickness_slider:
				cloud_thickness_slider.set_value_no_signal(thick)
			if cloud_thickness_val:
				cloud_thickness_val.text = "%.0f m" % thick

			if precipitation_slider:
				precipitation_slider.set_value_no_signal(precip)
			if precipitation_val:
				if precip <= 0.05:
					precipitation_val.text = "0.0 mm/hr [None]"
				elif precip < 8.0:
					precipitation_val.text = "%.1f mm/hr [Mist]" % precip
				elif precip < 25.0:
					precipitation_val.text = "%.1f mm/hr [Rain]" % precip
				else:
					precipitation_val.text = "%.1f mm/hr [Heavy]" % precip

			if dust_slider:
				dust_slider.set_value_no_signal(dust)
			if dust_val:
				dust_val.text = "%d%%" % int(round(dust * 100.0))

			if humidity_slider:
				humidity_slider.set_value_no_signal(hum)
			if humidity_val:
				humidity_val.text = "%.1f g/m³" % hum

			if hvac_air_slider:
				hvac_air_slider.set_value_no_signal(hvac_t)
			if hvac_air_val:
				hvac_air_val.text = "%.1f °C" % hvac_t

			if water_pipe_slider:
				water_pipe_slider.set_value_no_signal(water_t)
			if water_pipe_val:
				water_pipe_val.text = "%.1f °C" % water_t

		if climate_name_label:
			var c_name = data.get("climate_name", "Temperate Mixed Forest")
			climate_name_label.text = "🌍 Biome: %s" % c_name

		if climate_details_label:
			var season = data.get("season_name", "Summer")
			var s_temp = float(data.get("surface_temperature_c", 22.0))
			var yr_precip = float(data.get("yearly_precipitation_mm", 950.0))
			var lat = float(data.get("latitude_deg", 40.0))
			var hemi = "N" if lat >= 0.0 else "S"
			climate_details_label.text = "Season: %s | Temp: %.1f °C (%.1f °F)\nAnnual Rain: %.0f mm | Latitude: %+.1f°%s" % [
				season, s_temp, s_temp * 1.8 + 32.0, yr_precip, absf(lat), hemi
			]

		if climate_mode_label:
			var is_snow = bool(data.get("is_snow_mode", false))
			if is_snow:
				climate_mode_label.text = "Precipitation Mode: ❄️ SNOW / BLIZZARD (Temp <= 4°C)"
				climate_mode_label.modulate = Color(0.7, 0.9, 1.0)
			else:
				climate_mode_label.text = "Precipitation Mode: 🌧️ RAIN / MIST (Temp > 4°C)"
				climate_mode_label.modulate = Color(0.5, 0.8, 1.0)

		if cloud_status_label:
			var dew = data.get("dew_point_c", 15.2)
			var hvac_t = data.get("endcap_air_temp_c", 22.5)
			var water_t = data.get("water_pipe_temp_c", 24.0)
			var precip = data.get("precipitation_rate_mmh", 0.0)
			var is_snow = bool(data.get("is_snow_mode", false))
			var p_name = "Snow" if is_snow else "Rain"
			cloud_status_label.text = "LCL Base: %.2f km | Dew: %.1f°C | %s: %.1f mm/h\nHVAC Air: %.1f°C | Water Pipes: %.1f°C" % [
				data.get("cloud_altitude_km", 1.25), dew, p_name, precip, hvac_t, water_t
			]

	if weather_badge_label and telemetry_panel and telemetry_panel.visible:
		var w_state = data.get("weather_state", "Fair Cumulus")
		var rh = data.get("relative_humidity_pct", 68.0)
		var cloud_km = data.get("cloud_altitude_km", 1.25)
		var cloud_th = data.get("cloud_thickness_m", 250.0)
		var density_gm3 = data.get("humidity_density_gm3", 14.5)
		var precip = data.get("precipitation_rate_mmh", 0.0)
		var dust_pct = data.get("dust_density_pct", 20)
		var is_snow = bool(data.get("is_snow_mode", false))

		var precip_str = ""
		if precip > 0.05:
			var p_label = "Snow" if is_snow else "Rain"
			precip_str = "PRECIPITATION: %s %.1f mm/h\n" % [p_label, precip]

		var queue_tag = "[Queue: %d]" % q_size if q_size > 0 else ("[Auto-Climate]" if is_auto else "[Manual]")
		weather_badge_label.text = "WEATHER %s: %s\nWIND: %.1f m/s (%.0f km/h)\n%sCLOUD DECK: %.2f km AGL\nTHICKNESS: %.0f m | ROTATION: %.1f°\nHUMIDITY: %d%%" % [
			queue_tag, traj_name if is_trans else w_state.to_upper(), wind_ms, wind_kmh, precip_str, cloud_km, cloud_th, cloud_rot_deg, int(round(rh))
		]
		_fit_info_panel_height()
		if is_snow:
			weather_badge_label.modulate = Color(0.8, 0.95, 1.0)
		else:
			match w_state:
				"Clear Solar Sky", "Clear Sky":
					weather_badge_label.modulate = Color(0.4, 0.9, 1.0)
				"Fair Cumulus Skies", "Fair Cumulus":
					weather_badge_label.modulate = Color(0.5, 1.0, 0.7)
				"Scattered Clouds":
					weather_badge_label.modulate = Color(0.9, 0.9, 0.5)
				"Overcast Cloud Deck", "Overcast Deck":
					weather_badge_label.modulate = Color(0.8, 0.8, 0.9)
				_:
					weather_badge_label.modulate = Color(0.55, 0.75, 1.0)

func _disable_auto_weather_for_manual_control() -> void:
	if weather_system:
		weather_system.auto_weather_cycle_enabled = false
		weather_system.is_transitioning = false
		weather_system.clear_weather_queue()
	if auto_cycle_btn:
		auto_cycle_btn.text = "Auto: OFF"

func _on_spin_direction_toggle_pressed() -> void:
	if spin_direction_btn:
		spin_direction_btn.release_focus()
	if not weather_system:
		return
	var is_currently_ccw = (weather_system.spin_direction == WeatherSystem.SpinDirection.COUNTER_CLOCKWISE)
	weather_system.set_spin_direction(not is_currently_ccw)
	var new_is_ccw = (weather_system.spin_direction == WeatherSystem.SpinDirection.COUNTER_CLOCKWISE)
	if spin_direction_btn:
		spin_direction_btn.text = "Cylinder Spin: %s" % ("Counter-Clockwise (CCW)" if new_is_ccw else "Clockwise (CW)")
	log_event("Cylinder Coriolis Dynamics -> Spin Direction: %s" % ("Counter-Clockwise (+Z)" if new_is_ccw else "Clockwise (-Z)"), "#99bbff")

func _on_humidity_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.humidity_density_gm3 = val
	if humidity_val:
		humidity_val.text = "%.1f g/m³" % val
	log_event("Manual Weather Override -> Absolute Humidity: %.1f g/m³" % val, "#eedd66")

func _on_cloud_cover_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.cloud_coverage = val
	if cloud_cover_val:
		cloud_cover_val.text = "%d%%" % int(round(val * 100.0))
	log_event("Manual Weather Override -> Cloud Coverage: %d%%" % int(round(val * 100.0)), "#eedd66")

func _on_cloud_thickness_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.cloud_thickness_m = val
	if cloud_thickness_val:
		cloud_thickness_val.text = "%.0f m" % val
	log_event("Manual Weather Override -> Cloud Deck Thickness: %.0f m" % val, "#eedd66")

func _on_precipitation_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.precipitation_rate_mmh = val
	if precipitation_val:
		if val <= 0.05:
			precipitation_val.text = "0.0 mm/hr [None]"
		elif val < 8.0:
			precipitation_val.text = "%.1f mm/hr [Mist]" % val
		elif val < 25.0:
			precipitation_val.text = "%.1f mm/hr [Rain]" % val
		else:
			precipitation_val.text = "%.1f mm/hr [Heavy]" % val
	log_event("Manual Weather Override -> Precipitation Rate: %.1f mm/hr" % val, "#eedd66")

func _on_dust_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.dust_density = val
	if dust_val:
		dust_val.text = "%d%%" % int(round(val * 100.0))
	log_event("Manual Weather Override -> Atmospheric Dust: %d%%" % int(round(val * 100.0)), "#eedd66")

func _on_hvac_air_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.endcap_air_temperature_c = val
	if hvac_air_val:
		hvac_air_val.text = "%.1f °C" % val
	log_event("Manual Climate Override -> Endcap HVAC Air Temp: %.1f°C" % val, "#eedd66")

func _on_water_pipe_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.water_pipe_temperature_c = val
	if water_pipe_val:
		water_pipe_val.text = "%.1f °C" % val
	log_event("Manual Climate Override -> Subsurface Water Pipe Temp: %.1f°C" % val, "#eedd66")


func _on_toggle_controls_pressed() -> void:
	if toggle_controls_btn:
		toggle_controls_btn.release_focus()
	if control_panel:
		control_panel.visible = not control_panel.visible
		if control_panel.visible:
			_update_panel_constraints()
			if telemetry_panel:
				telemetry_panel.visible = false
			if log_panel:
				log_panel.visible = false
			if crosshair_node:
				crosshair_node.visible = false
		var cur_tab = tab_container.get_tab_title(tab_container.current_tab) if tab_container else "Overview"
		var status_str = "SHOWN (Tab: %s)" % cur_tab if control_panel.visible else "HIDDEN"
		_update_touch_controls_visibility()
		log_event("UI Interface -> Tuning Settings Panel %s" % status_str, "#ffaa55")

func _on_toggle_telemetry_pressed() -> void:
	if toggle_telemetry_btn:
		toggle_telemetry_btn.release_focus()
	if telemetry_panel:
		telemetry_panel.visible = not telemetry_panel.visible
		looking_at_enabled = telemetry_panel.visible
		if telemetry_panel.visible:
			_update_panel_constraints()
			if control_panel:
				control_panel.visible = false
			if log_panel:
				log_panel.visible = false
			_update_looking_at_inspection()
		if crosshair_node:
			crosshair_node.visible = telemetry_panel.visible
		if toggle_looking_at_btn:
			toggle_looking_at_btn.text = "👁️ Target Inspector (Looking At): %s" % ("ON" if telemetry_panel.visible else "OFF")
		if toggle_looking_at_sys_btn:
			toggle_looking_at_sys_btn.text = "👁️ Target Inspector (Looking At): %s" % ("ON" if telemetry_panel.visible else "OFF")
		var status_str = "SHOWN" if telemetry_panel.visible else "HIDDEN"
		log_event("UI Interface -> Habitat Info & Target Inspection %s" % status_str, "#ffaa55")

func _on_toggle_log_pressed() -> void:
	if toggle_log_btn:
		toggle_log_btn.release_focus()
	if log_panel:
		log_panel.visible = not log_panel.visible
		if log_panel.visible:
			_update_panel_constraints()
			if control_panel:
				control_panel.visible = false
			if telemetry_panel:
				telemetry_panel.visible = false
			if event_log_text and is_instance_valid(event_log_text):
				event_log_text.text = "\n".join(event_log_history)
		var status_str = "SHOWN" if log_panel.visible else "HIDDEN"
		_update_touch_controls_visibility()
		log_event("UI Interface -> System Event Log Console %s" % status_str, "#ffaa55")

func _on_tab_changed(tab_idx: int) -> void:
	if not tab_container or tab_idx == last_tab_idx:
		return
	last_tab_idx = tab_idx
	var tab_title = tab_container.get_tab_title(tab_idx)
	log_event("UI Interface -> Tuning Settings Tab switched to '%s'" % tab_title, "#ddaaff")

static func log_event(message: String, category_color: String = "#88ff88") -> void:
	if _instance and is_instance_valid(_instance):
		_instance._append_event_log(message, category_color)

func _append_event_log(message: String, category_color: String = "#88ff88") -> void:
	var dt = Time.get_time_dict_from_system()
	var real_str = "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]

	var sim_str = "Sim --:--:--"
	var light_bar_node = get_tree().get_first_node_in_group("light_bar") as AxisLightBar if is_inside_tree() else null
	if light_bar_node:
		var total_sec = int(fposmod(light_bar_node.time_of_day_hours, 24.0) * 3600.0)
		var h = (total_sec / 3600) % 24
		var m = (total_sec / 60) % 60
		var s = total_sec % 60
		sim_str = "Sim %02d:%02d:%02d" % [h, m, s]

	var initial_fps = Engine.get_frames_per_second()
	var fps_color = "#66ff88" if initial_fps >= 50 else ("#ffdd44" if initial_fps >= 30 else "#ff5555")

	var bbcode_entry = "[color=#70d4ff][%s][/color] [color=#ffc055][%s][/color] [color=%s][%d FPS][/color] [color=%s]%s[/color]" % [
		real_str, sim_str, fps_color, initial_fps, category_color, message
	]
	var raw_entry = "[%s | %s | %d FPS] %s" % [real_str, sim_str, initial_fps, message]

	event_log_history.append(bbcode_entry)
	event_log_raw_history.append(raw_entry)
	if event_log_history.size() > MAX_LOG_ENTRIES:
		event_log_history.pop_front()
	if event_log_raw_history.size() > MAX_LOG_ENTRIES:
		event_log_raw_history.pop_front()

	if event_log_text and is_instance_valid(event_log_text) and log_panel and log_panel.visible:
		event_log_text.text = "\n".join(event_log_history)

	# Measure settled post-task framerate after 0.8s once new render state is active
	if is_inside_tree():
		var tree = get_tree()
		if tree:
			var timer = tree.create_timer(0.8)
			timer.timeout.connect(func():
				_update_settled_fps_for_entry(real_str, sim_str, initial_fps, category_color, message)
			)

func _update_settled_fps_for_entry(real_str: String, sim_str: String, initial_fps: int, category_color: String, message: String) -> void:
	var settled_fps = Engine.get_frames_per_second()
	var settled_color = "#66ff88" if settled_fps >= 50 else ("#ffdd44" if settled_fps >= 30 else "#ff5555")

	var fps_bbcode: String
	var fps_raw: String

	if abs(settled_fps - initial_fps) >= 4:
		# Framerate changed significantly after performing the task (e.g. 60 -> 11 FPS)
		fps_bbcode = "[color=#70d4ff][%s][/color] [color=#ffc055][%s][/color] [color=%s][%d->%d FPS][/color] [color=%s]%s[/color]" % [
			real_str, sim_str, settled_color, initial_fps, settled_fps, category_color, message
		]
		fps_raw = "[%s | %s | %d->%d FPS] %s" % [real_str, sim_str, initial_fps, settled_fps, message]
	else:
		fps_bbcode = "[color=#70d4ff][%s][/color] [color=#ffc055][%s][/color] [color=%s][%d FPS][/color] [color=%s]%s[/color]" % [
			real_str, sim_str, settled_color, settled_fps, category_color, message
		]
		fps_raw = "[%s | %s | %d FPS] %s" % [real_str, sim_str, settled_fps, message]

	for i in range(event_log_history.size() - 1, -1, -1):
		if event_log_history[i].contains(message) and event_log_history[i].contains(real_str):
			event_log_history[i] = fps_bbcode
			if i < event_log_raw_history.size():
				event_log_raw_history[i] = fps_raw
			break

	if event_log_text and is_instance_valid(event_log_text) and log_panel and log_panel.visible:
		event_log_text.text = "\n".join(event_log_history)

func get_raw_event_log_text() -> String:
	return "\n".join(event_log_raw_history)

func _on_copy_log_pressed() -> void:
	if copy_log_btn:
		copy_log_btn.release_focus()
	if event_log_raw_history.is_empty():
		return
	var text_to_copy = get_raw_event_log_text()
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(text_to_copy)
	if copy_log_btn:
		var orig_text = copy_log_btn.text
		copy_log_btn.text = "✓ COPIED"
		get_tree().create_timer(1.2).timeout.connect(func():
			if copy_log_btn and is_instance_valid(copy_log_btn):
				copy_log_btn.text = orig_text
		)
	log_event("Event log copied to system clipboard (%d entries recorded)." % event_log_raw_history.size(), "#55ffff")

func _on_clear_log_pressed() -> void:
	if clear_log_btn:
		clear_log_btn.release_focus()
	event_log_history.clear()
	event_log_raw_history.clear()
	if event_log_text:
		event_log_text.text = ""

func _on_reset_spawn_pressed() -> void:
	if reset_spawn_btn:
		reset_spawn_btn.release_focus()
	if player:
		player.reset_to_spawn()
	log_event("Player -> Position reset to safe terrain spawn", "#ff7777")

func _on_view_south_cap_pressed() -> void:
	if south_cap_btn:
		south_cap_btn.release_focus()
	if player and player.has_method("teleport_to_z"):
		player.teleport_to_z(-8500.0, true)
	log_event("Player Teleport -> South End Cap (Z=-8500m)", "#ff99cc")

func _on_view_north_cap_pressed() -> void:
	if north_cap_btn:
		north_cap_btn.release_focus()
	if player and player.has_method("teleport_to_z"):
		player.teleport_to_z(8500.0, true)
	log_event("Player Teleport -> North End Cap (Z=+8500m)", "#ff99cc")

func _on_launch_speed_changed(val: float) -> void:
	launch_speed = val
	if launch_speed_val:
		launch_speed_val.text = "%.0f m/s" % val

func _on_particle_drag_changed(val: float) -> void:
	if particle_emitter:
		particle_emitter.air_drag_coefficient = val
	log_event("Physics Emitter -> Air Drag Coefficient: %.2f" % val, "#ddff77")

func _on_launch_up_pressed() -> void:
	if launch_up_btn:
		launch_up_btn.release_focus()
	if player:
		player.launch_vertical_particle(launch_speed)
	log_event("Physics Emitter -> Launched Vertical Particle (%.0f m/s)" % launch_speed, "#ffdd44")

func _on_launch_prograde_pressed() -> void:
	if launch_prograde_btn:
		launch_prograde_btn.release_focus()
	if particle_emitter and player:
		var spawn_pos = player.global_position + player.global_basis.y * 1.5
		particle_emitter.launch_relative_to_surface(spawn_pos, launch_speed, 5.0, 0.0, {
			"color": Color(0.2, 1.0, 0.4, 1.0),
			"size": 1.2
		})
	log_event("Physics Emitter -> Launched Prograde Particle (+%.0f m/s)" % launch_speed, "#55ff88")

func _on_launch_retrograde_pressed() -> void:
	if launch_retrograde_btn:
		launch_retrograde_btn.release_focus()
	if particle_emitter and player:
		var spawn_pos = player.global_position + player.global_basis.y * 1.5
		particle_emitter.launch_relative_to_surface(spawn_pos, -launch_speed, 5.0, 0.0, {
			"color": Color(1.0, 0.3, 0.7, 1.0),
			"size": 1.2
		})
	log_event("Physics Emitter -> Launched Retrograde Particle (-%.0f m/s)" % launch_speed, "#ff55bb")

func _on_launch_aimed_pressed() -> void:
	if launch_aimed_btn:
		launch_aimed_btn.release_focus()
	if player:
		player.launch_aimed_particle(launch_speed)
	log_event("Physics Emitter -> Launched Aimed Particle (%.0f m/s)" % launch_speed, "#ffff55")

func _on_toggle_rain_stream_pressed() -> void:
	if toggle_rain_stream_btn:
		toggle_rain_stream_btn.release_focus()
	if particle_emitter:
		particle_emitter.rain_stream_enabled = not particle_emitter.rain_stream_enabled
		if toggle_rain_stream_btn:
			toggle_rain_stream_btn.text = "🌧️ Cloud Rain Stream: %s" % ("ON" if particle_emitter.rain_stream_enabled else "OFF")
	log_event("Physics Emitter -> Cloud Rain Stream: %s" % ("ON" if (particle_emitter and particle_emitter.rain_stream_enabled) else "OFF"), "#77bbff")

func _on_toggle_trajectories_pressed() -> void:
	if toggle_trajectories_btn:
		toggle_trajectories_btn.release_focus()
	if particle_emitter:
		particle_emitter.show_trajectories = not particle_emitter.show_trajectories
		if toggle_trajectories_btn:
			toggle_trajectories_btn.text = "Trajectories: %s" % ("ON" if particle_emitter.show_trajectories else "OFF")
	log_event("Physics Emitter -> Trajectory Trails: %s" % ("ON" if (particle_emitter and particle_emitter.show_trajectories) else "OFF"), "#ddff77")

func _on_clear_trajectories_pressed() -> void:
	if clear_trajectories_btn:
		clear_trajectories_btn.release_focus()
	if particle_emitter:
		particle_emitter.clear_all()
	log_event("Physics Emitter -> Cleared all active particles & trajectory trails", "#ddff77")

# Performance Tab Callbacks & Methods
func _get_world_environment() -> WorldEnvironment:
	if not is_inside_tree():
		return null
	return get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment

func _get_cylinder_world() -> CylinderGenerator:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator

func _on_perf_culling_changed(val: float) -> void:
	if player and player.camera:
		player.camera.far = val
	_update_culling_label(val)
	log_event("Performance Setting -> Camera Far Culling set to %.0f m (%.1f km)" % [val, val / 1000.0], "#ddaaff")

func _update_culling_label(val: float) -> void:
	if perf_culling_val:
		perf_culling_val.text = "%.0f m (%.1f km)" % [val, val / 1000.0]

func _on_perf_scale_changed(val: float) -> void:
	if get_viewport():
		get_viewport().scaling_3d_scale = val
	_update_perf_scale_label(val)
	log_event("Performance Setting -> 3D Resolution Scale set to %d%% (%.2fx)" % [int(round(val * 100.0)), val], "#ddaaff")

func _update_perf_scale_label(val: float) -> void:
	if perf_scale_val:
		perf_scale_val.text = "%d%% (%.2fx)" % [int(round(val * 100.0)), val]

func _on_perf_rain_layers_selected(idx: int) -> void:
	if weather_system and perf_rain_layers_option:
		var layer_count = perf_rain_layers_option.get_item_id(idx)
		weather_system.rain_sheet_layer_count = layer_count
		log_event("Performance Setting -> Rain/Snow Particle Density set to %.1fx" % (float(layer_count) / 4.0), "#ddaaff")

func _on_perf_light_dist_changed(val: float) -> void:
	SurfaceLightObject.global_active_light_distance = val
	_update_light_dist_label(val)
	log_event("Performance Setting -> Active Light Distance set to %.0f m" % val, "#ddaaff")

func _update_light_dist_label(val: float) -> void:
	if perf_light_dist_val:
		if val <= 0.0:
			perf_light_dist_val.text = "Disabled (0 m)"
		else:
			perf_light_dist_val.text = "%.0f m" % val

func _on_perf_clutter_dist_changed(val: float) -> void:
	var clutter_mgr = get_tree().get_first_node_in_group("clutter_manager") as ClutterManager if is_inside_tree() else null
	if clutter_mgr:
		if val <= 0.0:
			clutter_mgr.enabled = false
		else:
			clutter_mgr.enabled = true
			clutter_mgr.view_radius = val
	_update_clutter_dist_label(val)
	log_event("Performance Setting -> Ground Clutter Distance set to %s" % ("Disabled (0 m)" if val <= 0.0 else ("%.0f m" % val)), "#ddaaff")

func _update_clutter_dist_label(val: float) -> void:
	if perf_clutter_dist_val:
		if val <= 0.0:
			perf_clutter_dist_val.text = "Disabled (0 m)"
		else:
			perf_clutter_dist_val.text = "%.0f m" % val

func _on_perf_clutter_density_changed(val: float) -> void:
	var clutter_mgr = get_tree().get_first_node_in_group("clutter_manager") as ClutterManager if is_inside_tree() else null
	if clutter_mgr:
		clutter_mgr.density_multiplier = val
	_update_clutter_density_label(val)
	log_event("Performance Setting -> Ground Clutter Density set to %.1fx" % val, "#ddaaff")

func _update_clutter_density_label(val: float) -> void:
	if perf_clutter_density_val:
		perf_clutter_density_val.text = "Disabled (0.0x)" if val <= 0.0 else "%.1fx" % val

func _on_perf_fps_limit_selected(idx: int) -> void:
	if perf_fps_limit_option:
		var target_fps = perf_fps_limit_option.get_item_id(idx)
		Engine.max_fps = target_fps
		_reset_clutter_auto_measurements()
		if target_fps > 0:
			if get_viewport():
				get_viewport().scaling_3d_scale = 1.0
			if perf_scale_slider:
				perf_scale_slider.set_value_no_signal(1.0)
			_update_perf_scale_label(1.0)
			if player and player.camera:
				player.camera.far = 40000.0
			if perf_culling_slider:
				perf_culling_slider.set_value_no_signal(40000.0)
			_update_culling_label(40000.0)
		log_event("Performance Setting -> Engine Max FPS Limit set to %s" % ("Unlimited" if target_fps == 0 else ("%d FPS" % target_fps)), "#ddaaff")

func _reset_clutter_auto_measurements() -> void:
	clutter_auto_fps_average = 0.0
	clutter_auto_low_samples = 0
	clutter_auto_good_samples = 0
	clutter_auto_probe_kind = ""
	clutter_auto_draw_effect = "not measured"
	clutter_auto_density_effect = "not measured"
	clutter_auto_precipitation_effect = "not measured"
	clutter_auto_light_effect = "not measured"
	clutter_auto_draw_reduction_ineffective = false
	clutter_auto_density_reduction_ineffective = false
	clutter_auto_precipitation_reduction_ineffective = false
	clutter_auto_light_reduction_ineffective = false
	clutter_auto_draw_quality_ceiling = 1.5
	clutter_auto_light_quality_ceiling = 1.5
	var clutter_mgr = get_tree().get_first_node_in_group("clutter_manager") as ClutterManager if is_inside_tree() else null
	if clutter_mgr:
		clutter_mgr.set_adaptive_quality(1.0, 1.0)
	if weather_system:
		weather_system.set_adaptive_precipitation_scale(1.0)
	SurfaceLightObject.set_adaptive_active_light_scale(1.0)

func _update_clutter_auto_tuning(delta: float) -> void:
	clutter_auto_timer += delta
	if clutter_auto_timer < 1.0:
		return
	clutter_auto_timer = fposmod(clutter_auto_timer, 1.0)

	var clutter_mgr = get_tree().get_first_node_in_group("clutter_manager") as ClutterManager if is_inside_tree() else null
	var target_fps = Engine.max_fps
	if not clutter_mgr:
		if perf_clutter_auto_label:
			perf_clutter_auto_label.text = "Auto-tune unavailable: no ground clutter manager."
		return
	if target_fps <= 0 or not clutter_mgr.enabled:
		clutter_mgr.set_adaptive_quality(1.0, 1.0)
		clutter_auto_fps_average = 0.0
		clutter_auto_low_samples = 0
		clutter_auto_good_samples = 0
		clutter_auto_probe_kind = ""
		if weather_system:
			weather_system.set_adaptive_precipitation_scale(1.0)
		SurfaceLightObject.set_adaptive_active_light_scale(1.0)
		if perf_clutter_auto_label:
			perf_clutter_auto_label.text = "Auto-tune %s." % ("paused while clutter is disabled" if not clutter_mgr.enabled else "off (FPS target is unlimited)")
		return

	var measured_fps = float(Engine.get_frames_per_second())
	if measured_fps <= 0.0:
		return
	if clutter_auto_fps_average <= 0.0:
		clutter_auto_fps_average = measured_fps
	else:
		clutter_auto_fps_average = lerpf(clutter_auto_fps_average, measured_fps, 0.35)

	if not clutter_auto_probe_kind.is_empty():
		clutter_auto_probe_samples -= 1
		if clutter_auto_probe_samples <= 0:
			var fps_delta = clutter_auto_fps_average - clutter_auto_probe_fps_before
			var minimum_gain = maxf(0.5, float(target_fps) * 0.01)
			if clutter_auto_probe_kind == "draw_down":
				clutter_auto_draw_effect = "-%d%% range: %+.1f FPS" % [int(round((clutter_auto_probe_draw_before - clutter_mgr.adaptive_draw_distance_scale) * 100.0)), fps_delta]
				if fps_delta < minimum_gain:
					clutter_mgr.set_adaptive_quality(clutter_auto_probe_draw_before, clutter_mgr.adaptive_density_scale)
					clutter_auto_draw_reduction_ineffective = true
					clutter_auto_draw_effect = "no gain; range restored"
			elif clutter_auto_probe_kind == "density_down":
				clutter_auto_density_effect = "-%d%% instances: %+.1f FPS" % [int(round((clutter_auto_probe_density_before - clutter_mgr.adaptive_density_scale) * 100.0)), fps_delta]
				if fps_delta < minimum_gain:
					clutter_mgr.set_adaptive_quality(clutter_mgr.adaptive_draw_distance_scale, clutter_auto_probe_density_before)
					clutter_auto_density_reduction_ineffective = true
					clutter_auto_density_effect = "no gain; density restored"
			elif clutter_auto_probe_kind == "precipitation_down":
				var current_precip_scale = weather_system.adaptive_precipitation_scale if weather_system else 1.0
				clutter_auto_precipitation_effect = "-%d%% particles: %+.1f FPS" % [int(round((clutter_auto_probe_precipitation_before - current_precip_scale) * 100.0)), fps_delta]
				if not weather_system or not weather_system.is_precip_active:
					if weather_system:
						weather_system.set_adaptive_precipitation_scale(clutter_auto_probe_precipitation_before)
					clutter_auto_precipitation_effect = "probe interrupted; rain unchanged"
				elif fps_delta < minimum_gain:
					weather_system.set_adaptive_precipitation_scale(clutter_auto_probe_precipitation_before)
					clutter_auto_precipitation_reduction_ineffective = true
					clutter_auto_precipitation_effect = "no gain; particles restored"
			elif clutter_auto_probe_kind == "light_down":
				var current_light_scale = SurfaceLightObject.adaptive_active_light_scale
				clutter_auto_light_effect = "-%d%% range: %+.1f FPS" % [int(round((clutter_auto_probe_light_before - current_light_scale) * 100.0)), fps_delta]
				if fps_delta < minimum_gain:
					SurfaceLightObject.set_adaptive_active_light_scale(clutter_auto_probe_light_before)
					clutter_auto_light_reduction_ineffective = true
					clutter_auto_light_effect = "no gain; light range restored"
			elif clutter_auto_probe_kind == "draw_up":
				if clutter_auto_fps_average < float(target_fps) * 0.92:
					clutter_mgr.set_adaptive_quality(clutter_auto_probe_draw_before, clutter_mgr.adaptive_density_scale)
					clutter_auto_draw_quality_ceiling = clutter_auto_probe_draw_before
					clutter_auto_draw_effect = "quality increase costs FPS; backed off"
				else:
					clutter_auto_draw_effect = "range increase: %+.1f FPS" % fps_delta
			elif clutter_auto_probe_kind == "light_up":
				if clutter_auto_fps_average < float(target_fps) * 0.92:
					SurfaceLightObject.set_adaptive_active_light_scale(clutter_auto_probe_light_before)
					clutter_auto_light_quality_ceiling = clutter_auto_probe_light_before
					clutter_auto_light_effect = "quality increase costs FPS; backed off"
				else:
					clutter_auto_light_effect = "range increase: %+.1f FPS" % fps_delta
			clutter_auto_probe_kind = ""
			clutter_auto_probe_samples = 0

	if clutter_auto_fps_average < float(target_fps) * 0.92:
		clutter_auto_low_samples += 1
		clutter_auto_good_samples = 0
		if clutter_auto_low_samples >= 2 and clutter_auto_probe_kind.is_empty():
			var draw_scale = clutter_mgr.adaptive_draw_distance_scale
			var density_scale = clutter_mgr.adaptive_density_scale
			var probe_kind = ""
			if draw_scale > 0.75 and not clutter_auto_draw_reduction_ineffective:
				draw_scale = maxf(0.75, draw_scale - 0.10)
				probe_kind = "draw_down"
			elif density_scale > 0.5 and not clutter_auto_density_reduction_ineffective:
				density_scale = maxf(0.5, density_scale - 0.10)
				probe_kind = "density_down"
			elif weather_system and weather_system.is_precip_active and weather_system.rain_sheet_layer_count > 0 and weather_system.adaptive_precipitation_scale > 0.5 and not clutter_auto_precipitation_reduction_ineffective:
				probe_kind = "precipitation_down"
			elif SurfaceLightObject.global_active_light_distance > 0.0 and SurfaceLightObject.adaptive_active_light_scale > 0.5 and not clutter_auto_light_reduction_ineffective and not get_tree().get_nodes_in_group("surface_light_objects").is_empty():
				probe_kind = "light_down"
			if not probe_kind.is_empty():
				clutter_auto_probe_kind = probe_kind
				clutter_auto_probe_samples = 3
				clutter_auto_probe_fps_before = clutter_auto_fps_average
				clutter_auto_probe_draw_before = clutter_mgr.adaptive_draw_distance_scale
				clutter_auto_probe_density_before = clutter_mgr.adaptive_density_scale
				clutter_auto_probe_precipitation_before = weather_system.adaptive_precipitation_scale if weather_system else 1.0
				clutter_auto_probe_light_before = SurfaceLightObject.adaptive_active_light_scale
				if probe_kind == "precipitation_down" and weather_system:
					weather_system.set_adaptive_precipitation_scale(maxf(0.5, clutter_auto_probe_precipitation_before - 0.10))
				elif probe_kind == "light_down":
					SurfaceLightObject.set_adaptive_active_light_scale(maxf(0.5, clutter_auto_probe_light_before - 0.10))
				else:
					clutter_mgr.set_adaptive_quality(draw_scale, density_scale)
			clutter_auto_low_samples = 0
	elif clutter_auto_fps_average >= float(target_fps) * 0.98:
		clutter_auto_low_samples = 0
		clutter_auto_good_samples += 1
		if clutter_auto_good_samples >= 5 and clutter_auto_probe_kind.is_empty():
			var draw_scale = clutter_mgr.adaptive_draw_distance_scale
			var density_scale = clutter_mgr.adaptive_density_scale
			if weather_system and weather_system.adaptive_precipitation_scale < 1.0:
				weather_system.set_adaptive_precipitation_scale(minf(1.0, weather_system.adaptive_precipitation_scale + 0.05))
			elif SurfaceLightObject.adaptive_active_light_scale < 1.0:
				SurfaceLightObject.set_adaptive_active_light_scale(minf(1.0, SurfaceLightObject.adaptive_active_light_scale + 0.05))
			elif density_scale < 1.0:
				density_scale = minf(1.0, density_scale + 0.05)
			elif draw_scale < 1.0:
				draw_scale = minf(1.0, draw_scale + 0.05)
			else:
				var max_draw_scale = minf(1.5, 1000.0 / maxf(clutter_mgr.view_radius, 1.0))
				if draw_scale < minf(max_draw_scale, clutter_auto_draw_quality_ceiling):
					draw_scale = minf(minf(max_draw_scale, clutter_auto_draw_quality_ceiling), draw_scale + 0.05)
					clutter_auto_probe_kind = "draw_up"
					clutter_auto_probe_samples = 3
					clutter_auto_probe_fps_before = clutter_auto_fps_average
					clutter_auto_probe_draw_before = clutter_mgr.adaptive_draw_distance_scale
					clutter_auto_probe_density_before = clutter_mgr.adaptive_density_scale
				elif SurfaceLightObject.global_active_light_distance > 0.0 and SurfaceLightObject.adaptive_active_light_scale < minf(minf(1.5, 8000.0 / SurfaceLightObject.global_active_light_distance), clutter_auto_light_quality_ceiling):
					var old_light_scale = SurfaceLightObject.adaptive_active_light_scale
					var max_light_scale = minf(minf(1.5, 8000.0 / SurfaceLightObject.global_active_light_distance), clutter_auto_light_quality_ceiling)
					SurfaceLightObject.set_adaptive_active_light_scale(minf(max_light_scale, old_light_scale + 0.05))
					clutter_auto_probe_kind = "light_up"
					clutter_auto_probe_samples = 3
					clutter_auto_probe_fps_before = clutter_auto_fps_average
					clutter_auto_probe_light_before = old_light_scale
			clutter_mgr.set_adaptive_quality(draw_scale, density_scale)
			clutter_auto_good_samples = 0
	else:
		clutter_auto_low_samples = 0
		clutter_auto_good_samples = 0

	if perf_clutter_auto_label:
		var effective_radius = clutter_mgr._effective_draw_distance()
		perf_clutter_auto_label.text = "Auto-tune target: %d FPS | Current: %.0f FPS\nClutter: %.0f m | Distance: %.0f%%\nDensity: %.0f%% | Rain: %.0f%% | Lights: %.0f%%\nFPS effect:\nDistance: %s | Density: %s\nRain: %s | Lights: %s\nRender scale: 100%% | Camera range: 40 km" % [
			target_fps,
			clutter_auto_fps_average,
			effective_radius,
			clutter_mgr.adaptive_draw_distance_scale * 100.0,
			clutter_mgr.adaptive_density_scale * 100.0,
			(weather_system.adaptive_precipitation_scale if weather_system else 1.0) * 100.0,
			SurfaceLightObject.adaptive_active_light_scale * 100.0,
			clutter_auto_draw_effect,
			clutter_auto_density_effect,
			clutter_auto_precipitation_effect,
			clutter_auto_light_effect
		]

func _on_perf_near_clouds_toggle() -> void:
	if perf_near_clouds_btn:
		perf_near_clouds_btn.release_focus()
	if weather_system and weather_system.near_cloud_mesh_instance:
		weather_system.near_cloud_mesh_instance.visible = not weather_system.near_cloud_mesh_instance.visible
		_update_toggle_button(perf_near_clouds_btn, "Near Clouds", weather_system.near_cloud_mesh_instance.visible)
		log_event("Performance Setting -> Near Clouds Layer: %s" % ("ON" if weather_system.near_cloud_mesh_instance.visible else "OFF"), "#ddaaff")

func _on_perf_far_clouds_toggle() -> void:
	if perf_far_clouds_btn:
		perf_far_clouds_btn.release_focus()
	if weather_system and weather_system.far_cloud_mesh_instance:
		weather_system.far_cloud_mesh_instance.visible = not weather_system.far_cloud_mesh_instance.visible
		_update_toggle_button(perf_far_clouds_btn, "Far Clouds", weather_system.far_cloud_mesh_instance.visible)
		log_event("Performance Setting -> Far Clouds Layer: %s" % ("ON" if weather_system.far_cloud_mesh_instance.visible else "OFF"), "#ddaaff")

func _on_perf_water_mesh_toggle() -> void:
	if perf_water_mesh_btn:
		perf_water_mesh_btn.release_focus()
	var cylinder_world = _get_cylinder_world()
	if cylinder_world and cylinder_world.water_mesh_instance:
		cylinder_world.water_mesh_instance.visible = not cylinder_world.water_mesh_instance.visible
		_update_toggle_button(perf_water_mesh_btn, "Water Mesh", cylinder_world.water_mesh_instance.visible)
		log_event("Performance Setting -> Cylindrical Water Mesh: %s" % ("ON" if cylinder_world.water_mesh_instance.visible else "OFF"), "#ddaaff")

func _on_perf_glow_toggle() -> void:
	if perf_glow_btn:
		perf_glow_btn.release_focus()
	var env = _get_world_environment()
	if env and env.environment:
		env.environment.glow_enabled = not env.environment.glow_enabled
		_update_toggle_button(perf_glow_btn, "HDR Glow", env.environment.glow_enabled)
		log_event("Performance Setting -> HDR Bloom Glow: %s" % ("ON" if env.environment.glow_enabled else "OFF"), "#ddaaff")

func _on_perf_fog_toggle() -> void:
	if perf_fog_btn:
		perf_fog_btn.release_focus()
	var env = _get_world_environment()
	if env and env.environment:
		env.environment.fog_enabled = not env.environment.fog_enabled
		_update_toggle_button(perf_fog_btn, "Depth Fog", env.environment.fog_enabled)
		log_event("Performance Setting -> Volumetric Depth Fog: %s" % ("ON" if env.environment.fog_enabled else "OFF"), "#ddaaff")

func _update_toggle_button(btn: Button, label_name: String, state: bool) -> void:
	if btn:
		btn.text = "%s: %s" % [label_name, "ON" if state else "OFF"]
		btn.modulate = Color(1.0, 1.0, 1.0) if state else Color(0.7, 0.7, 0.7)

func _on_perf_preset_selected(idx: int) -> void:
	if perf_preset_option and perf_preset_option.selected != idx:
		perf_preset_option.select(idx)
	match idx:
		0: # Ultra Performance
			_apply_perf_preset("Ultra Performance", 40000.0, 1.0, 2, 600.0, 200.0, 60, true, false, true, false, false)
		1: # Balanced Mobile
			_apply_perf_preset("Balanced Mobile", 40000.0, 1.0, 4, 1500.0, 350.0, 60, true, true, true, false, true)
		2: # High Quality
			_apply_perf_preset("High Quality", 40000.0, 1.0, 6, 3500.0, 500.0, 0, true, true, true, true, true)
		3: # Cinematic
			_apply_perf_preset("Cinematic", 40000.0, 1.0, 8, 8000.0, 800.0, 0, true, true, true, true, true)

func _apply_perf_preset(preset_name: String, cull_dist: float, scale_3d: float, rain_layers: int, light_dist: float, clutter_dist: float, fps_limit: int, near_clouds: bool, far_clouds: bool, water: bool, glow: bool, fog: bool) -> void:
	# Device measurements show the render scale and camera clip distance are not
	# useful performance levers here, so keep both at their highest visual quality.
	cull_dist = 40000.0
	scale_3d = 1.0
	if player and player.camera:
		player.camera.far = cull_dist
	if perf_culling_slider:
		perf_culling_slider.set_value_no_signal(cull_dist)
	_update_culling_label(cull_dist)

	if get_viewport():
		get_viewport().scaling_3d_scale = scale_3d
	if perf_scale_slider:
		perf_scale_slider.set_value_no_signal(scale_3d)
	_update_perf_scale_label(scale_3d)

	if weather_system:
		weather_system.rain_sheet_layer_count = rain_layers
	if perf_rain_layers_option:
		var opt_idx = 2
		match rain_layers:
			0: opt_idx = 0
			2: opt_idx = 1
			4: opt_idx = 2
			6: opt_idx = 3
			8: opt_idx = 4
			_: opt_idx = 2
		perf_rain_layers_option.select(opt_idx)

	SurfaceLightObject.global_active_light_distance = light_dist
	if perf_light_dist_slider:
		perf_light_dist_slider.set_value_no_signal(light_dist)
	_update_light_dist_label(light_dist)

	var clutter_mgr = get_tree().get_first_node_in_group("clutter_manager") as ClutterManager if is_inside_tree() else null
	if clutter_mgr:
		if clutter_dist <= 0.0:
			clutter_mgr.enabled = false
		else:
			clutter_mgr.enabled = true
			clutter_mgr.view_radius = clutter_dist
	if perf_clutter_dist_slider:
		perf_clutter_dist_slider.set_value_no_signal(clutter_dist)
	_update_clutter_dist_label(clutter_dist)

	Engine.max_fps = fps_limit
	_reset_clutter_auto_measurements()
	if perf_fps_limit_option:
		var opt_idx = 0
		match fps_limit:
			30: opt_idx = 1
			45: opt_idx = 2
			60: opt_idx = 3
			90: opt_idx = 4
			120: opt_idx = 5
			_: opt_idx = 0
		perf_fps_limit_option.select(opt_idx)

	if weather_system and weather_system.near_cloud_mesh_instance:
		weather_system.near_cloud_mesh_instance.visible = near_clouds
	_update_toggle_button(perf_near_clouds_btn, "Near Clouds", near_clouds)

	if weather_system and weather_system.far_cloud_mesh_instance:
		weather_system.far_cloud_mesh_instance.visible = far_clouds
	_update_toggle_button(perf_far_clouds_btn, "Far Clouds", far_clouds)

	var cylinder_world = _get_cylinder_world()
	if cylinder_world and cylinder_world.water_mesh_instance:
		cylinder_world.water_mesh_instance.visible = water
	_update_toggle_button(perf_water_mesh_btn, "Water Mesh", water)

	var env = _get_world_environment()
	if env and env.environment:
		env.environment.glow_enabled = glow
		env.environment.fog_enabled = fog
	_update_toggle_button(perf_glow_btn, "HDR Glow", glow)
	_update_toggle_button(perf_fog_btn, "Depth Fog", fog)

	log_event("Performance Preset Applied -> '%s' (Cull: %.0fm, 3DScale: %.2f, Rain: %d, Clutter: %.0fm, MaxFPS: %s)" % [
		preset_name, cull_dist, scale_3d, rain_layers, clutter_dist, "Unlimited" if fps_limit == 0 else ("%d FPS" % fps_limit)
	], "#ff55ff")

# -----------------------------------------------------------------------------
# Looking At / Target Inspector UI & Processing
# -----------------------------------------------------------------------------

func _setup_looking_at_ui() -> void:
	crosshair_node = get_node_or_null("Crosshair") as Control
	if not crosshair_node:
		crosshair_node = find_child("Crosshair", true, false) as Control
	if crosshair_node:
		crosshair_node.visible = (telemetry_panel != null and telemetry_panel.visible)

	if not looking_at_terrain_label:
		looking_at_terrain_label = find_child("TerrainTypeLabel", true, false) as Label
	if not looking_at_object_label:
		looking_at_object_label = find_child("ObjectLabel", true, false) as Label
	if not looking_at_coords_label:
		looking_at_coords_label = find_child("CoordsLabel", true, false) as Label

	looking_at_panel = telemetry_panel

func _on_toggle_looking_at_pressed() -> void:
	toggle_looking_at()

func toggle_looking_at() -> void:
	_on_toggle_telemetry_pressed()

func set_looking_at_enabled(enabled: bool) -> void:
	looking_at_enabled = enabled
	if telemetry_panel:
		telemetry_panel.visible = enabled
		if enabled:
			telemetry_panel.reset_size()
	if crosshair_node:
		crosshair_node.visible = enabled
	if toggle_looking_at_btn:
		toggle_looking_at_btn.text = "👁️ Target Inspector (Looking At): %s" % ("ON" if enabled else "OFF")
	if toggle_looking_at_sys_btn:
		toggle_looking_at_sys_btn.text = "👁️ Target Inspector (Looking At): %s" % ("ON" if enabled else "OFF")
	if enabled:
		_update_looking_at_inspection()
	log_event("HUD -> Target Inspector (Looking At) %s" % ("Enabled" if enabled else "Disabled"), "#55ffaa" if enabled else "#ffaa55")

func _update_looking_at_inspection() -> void:
	if not looking_at_enabled:
		return

	var cam = player.camera if (player and player.camera) else get_viewport().get_camera_3d()
	if not cam:
		return

	var ray_origin = cam.global_position
	var ray_dir = -cam.global_transform.basis.z.normalized()

	var hit_found: bool = false
	var hit_pos: Vector3 = Vector3.ZERO
	var hit_distance: float = 0.0
	var detected_object_name: String = "Open Habitat Space"
	var detected_object_type: String = "None"
	var detected_terrain_name: String = "Open Space"
	var hit_theta: float = 0.0
	var hit_z: float = 0.0
	var hit_elevation: float = 0.0
	var is_water: bool = false
	var is_end_cap: bool = false

	# 1. Direct Physics Raycast for spawned objects
	var space_state = (player.get_world_3d().direct_space_state if (player and player.get_world_3d()) else null)
	if space_state:
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 30000.0)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		if player:
			query.exclude = [player.get_rid()]
		var result = space_state.intersect_ray(query)
		if not result.is_empty():
			hit_found = true
			hit_pos = result.position
			hit_distance = ray_origin.distance_to(hit_pos)
			var collider = result.collider
			if collider:
				var node: Node = collider as Node
				while node and node != get_tree().root:
					if node is SurfaceLightObject:
						match node.object_type:
							SurfaceLightObject.ObjectType.CAMPFIRE:
								detected_object_name = "Campfire [Active Surface Light]"
								detected_object_type = "Campfire"
							SurfaceLightObject.ObjectType.LAMP_POST:
								detected_object_name = "Habitat Lamp Post / Lighting Column"
								detected_object_type = "Lamp Post"
							SurfaceLightObject.ObjectType.BEACON_LANTERN:
								detected_object_name = "Spaceport Beacon Lantern"
								detected_object_type = "Beacon Lantern"
						break
					elif node.name.contains("Campfire"):
						detected_object_name = "Campfire [Active Surface Light]"
						detected_object_type = "Campfire"
						break
					elif node.name.contains("Beacon"):
						detected_object_name = "Spaceport Beacon Lantern"
						detected_object_type = "Beacon Lantern"
						break
					elif node.name.contains("Lamp"):
						detected_object_name = "Habitat Lamp Post"
						detected_object_type = "Lamp Post"
						break
					node = node.get_parent()

	# 2. Check if aiming towards Central Axis Light Bar
	var ray_xy = Vector2(ray_origin.x, ray_origin.y)
	var dir_xy = Vector2(ray_dir.x, ray_dir.y)
	if dir_xy.length_squared() > 0.0001:
		var t_axis = -ray_xy.dot(dir_xy) / dir_xy.length_squared()
		if t_axis > 0.0:
			var p_closest = ray_origin + ray_dir * t_axis
			var closest_r = Vector2(p_closest.x, p_closest.y).length()
			var cyl_len_ref = player.cylinder_length if player else 18000.0
			if closest_r < 60.0 and absf(p_closest.z) <= (cyl_len_ref * 0.5 + 500.0):
				if not hit_found or t_axis < hit_distance:
					hit_found = true
					hit_pos = p_closest
					hit_distance = t_axis
					detected_object_name = "Central Axis Light Bar [Daylight Emitter]"
					detected_object_type = "Axis Light Bar"
					detected_terrain_name = "None (Core Atmosphere)"

	# 3. Proximity check to SurfaceLightObjects
	var light_objects = get_tree().get_nodes_in_group("surface_light_objects")
	for obj in light_objects:
		if obj is Node3D:
			var obj_pos = (obj as Node3D).global_position
			var to_obj = obj_pos - ray_origin
			var proj = to_obj.dot(ray_dir)
			if proj > 0.5 and (not hit_found or proj <= hit_distance + 5.0):
				var closest_pt = ray_origin + ray_dir * proj
				var dist_to_ray = closest_pt.distance_to(obj_pos)
				if dist_to_ray < 4.5:
					hit_found = true
					hit_pos = obj_pos
					hit_distance = proj
					if obj is SurfaceLightObject:
						match obj.object_type:
							SurfaceLightObject.ObjectType.CAMPFIRE:
								detected_object_name = "Campfire [Active Surface Light]"
								detected_object_type = "Campfire"
							SurfaceLightObject.ObjectType.LAMP_POST:
								detected_object_name = "Habitat Lamp Post / Lighting Column"
								detected_object_type = "Lamp Post"
							SurfaceLightObject.ObjectType.BEACON_LANTERN:
								detected_object_name = "Spaceport Beacon Lantern"
								detected_object_type = "Beacon Lantern"
					break

	# 4. Analytical Cylinder & End Cap Intersection for Terrain
	var cyl_world = get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator if is_inside_tree() else null
	var cyl_radius = cyl_world.radius if cyl_world else (player.cylinder_radius if player else 4000.0)
	var cyl_len = cyl_world.cylinder_length if cyl_world else (player.cylinder_length if player else 18000.0)
	var water_level = cyl_world.water_level if cyl_world else 20.0

	var a = dir_xy.length_squared()
	var b_coeff = 2.0 * ray_xy.dot(dir_xy)
	var c_coeff = ray_xy.length_squared() - cyl_radius * cyl_radius
	var disc = b_coeff * b_coeff - 4.0 * a * c_coeff

	if not hit_found and disc >= 0.0 and a > 0.00001:
		var t1 = (-b_coeff - sqrt(disc)) / (2.0 * a)
		var t2 = (-b_coeff + sqrt(disc)) / (2.0 * a)
		var t_hit = t2 if t2 > 0.1 else t1
		if t_hit > 0.1:
			hit_pos = ray_origin + ray_dir * t_hit
			hit_distance = t_hit
			hit_found = true

	if hit_found and detected_terrain_name != "None (Core Atmosphere)":
		hit_theta = atan2(hit_pos.y, hit_pos.x)
		if hit_theta < 0.0:
			hit_theta += TAU
		hit_z = hit_pos.z

		var half_len = cyl_len * 0.5
		if absf(hit_z) > half_len:
			is_end_cap = true
			var is_north = hit_z > 0.0
			if detected_object_type == "None":
				detected_object_name = "North End Cap Dome Bulkhead (z = +%.0f m)" % hit_z if is_north else "South End Cap Dome Bulkhead (z = %.0f m)" % hit_z
			detected_terrain_name = "Structural Bulkhead / End Cap Armor"
			hit_elevation = 100.0
		else:
			if cyl_world:
				var t_id = cyl_world.get_terrain_type_at(hit_theta, hit_z)
				hit_elevation = cyl_world.get_elevation_at(hit_theta, hit_z)
				is_water = hit_elevation < water_level

				detected_terrain_name = str(cyl_world.terrain_manager.get_biome(hit_theta, hit_z, cyl_world.cylinder_length).get("name", "Unknown biome"))

				if is_water and detected_object_type == "None":
					var depth = maxf(water_level - hit_elevation, 0.0)
					detected_object_name = "Water Basin Surface (Depth: %.1f m)" % depth
			elif detected_terrain_name == "Open Space":
				detected_terrain_name = "Inner Cylinder Surface"

	if detected_object_type == "None" and not is_water and not is_end_cap and detected_terrain_name != "None (Core Atmosphere)":
		detected_object_name = "Open Terrain Surface"

	last_looking_at_data = {
		"terrain_type": detected_terrain_name,
		"object_name": detected_object_name,
		"elevation": hit_elevation,
		"distance": hit_distance,
		"theta_deg": rad_to_deg(hit_theta),
		"pos_z": hit_z,
		"is_water": is_water,
		"is_end_cap": is_end_cap
	}

	_render_looking_at_ui(detected_terrain_name, detected_object_name, hit_elevation, hit_distance, rad_to_deg(hit_theta), hit_z, is_water, is_end_cap)

func _render_looking_at_ui(terrain_name: String, object_name: String, elev: float, dist: float, theta_deg: float, z: float, is_water: bool, is_end_cap: bool) -> void:
	if not looking_at_panel or not looking_at_panel.visible:
		return

	if looking_at_terrain_label:
		if terrain_name.begins_with("None"):
			looking_at_terrain_label.text = "Terrain: %s" % terrain_name
			looking_at_terrain_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		elif is_end_cap:
			looking_at_terrain_label.text = "Terrain: %s" % terrain_name
			looking_at_terrain_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
		elif is_water:
			looking_at_terrain_label.text = "Terrain: %s (Seabed: %.1f m)" % [terrain_name, elev]
			looking_at_terrain_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
		else:
			looking_at_terrain_label.text = "Terrain: %s (Elev: %.1f m)" % [terrain_name, elev]
			looking_at_terrain_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.45))

	if looking_at_object_label:
		looking_at_object_label.text = "Object:  %s" % object_name
		if object_name.contains("Campfire"):
			looking_at_object_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.25))
		elif object_name.contains("Beacon") or object_name.contains("Light Bar"):
			looking_at_object_label.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
		elif object_name.contains("Water"):
			looking_at_object_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		else:
			looking_at_object_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

	if looking_at_coords_label:
		if dist >= 1000.0:
			looking_at_coords_label.text = "Distance: %.2f km | Target: θ: %5.1f° | Z: %5.1f m" % [dist / 1000.0, theta_deg, z]
		else:
			looking_at_coords_label.text = "Distance: %5.1f m | Target: θ: %5.1f° | Z: %5.1f m" % [dist, theta_deg, z]
