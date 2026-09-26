class_name HUD
extends CanvasLayer

const UIScaleManager = preload("res://scripts/ui_scale_manager.gd")
const CylinderParticleEmitter = preload("res://scripts/cylinder_particle_emitter.gd")

@export var player: PlayerController
@export var light_bar: AxisLightBar
@export var weather_system: WeatherSystem
@export var particle_emitter: CylinderParticleEmitter

# Root Container for Adaptive Scaling
@onready var ui_root: Control = $UIRoot
@onready var control_panel: PanelContainer = $UIRoot/ControlPanel
@onready var tab_container: TabContainer = get_node_or_null("UIRoot/ControlPanel/TabContainer")
@onready var toggle_controls_btn: Button = $UIRoot/ToggleControlsButton
@onready var touch_controls: MobileTouchControls = $UIRoot/TouchControls

# UI Node References (under UIRoot)
@onready var telemetry_label: Label = $UIRoot/TelemetryPanel/VBoxContainer/TelemetryLabel
@onready var mode_badge: Label = $UIRoot/TelemetryPanel/VBoxContainer/ModeBadge
@onready var horizon_status_label: Label = $UIRoot/TelemetryPanel/VBoxContainer/HorizonStatusLabel
@onready var artificial_horizon: Control = get_node_or_null("UIRoot/HorizonContainer/VBoxContainer/ArtificialHorizon")
@onready var horizon_angle_label: Label = get_node_or_null("UIRoot/HorizonContainer/VBoxContainer/HorizonAngleLabel")

var solar_badge_label: Label = null
var weather_badge_label: Label = null
var fps_label: Label = null
var system_fps_label: Label = null
var fps_update_timer: float = 0.0

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
var wobble_test_btn: Button = null
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

# Tab 4: System & Scale UI Controls
var scale_slider: HSlider = null
var scale_val: Label = null
var reset_scale_btn: Button = null
var deploy_campfire_btn: Button = null
var deploy_lamp_btn: Button = null

var current_ui_scale: float = 1.0
var is_scale_auto: bool = true
var auto_scale_info: Dictionary = {}

var underwater_overlay: ColorRect = null

func _ready() -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
	if not light_bar:
		light_bar = get_tree().get_first_node_in_group("light_bar")
	if not weather_system:
		weather_system = get_tree().get_first_node_in_group("weather_system")
	if not particle_emitter:
		particle_emitter = get_tree().get_first_node_in_group("particle_emitter")

	_setup_underwater_overlay()

	if player:
		player.telemetry_updated.connect(_on_telemetry_updated)
	if weather_system:
		weather_system.weather_updated.connect(_on_weather_updated)

	_setup_ui_scaling()
	_setup_control_panel()

	var telem_vbox = get_node_or_null("UIRoot/TelemetryPanel/VBoxContainer")
	if telem_vbox:
		var title_node = telem_vbox.get_node_or_null("TitleLabel")
		var header_hbox = HBoxContainer.new()
		header_hbox.name = "HeaderHBox"
		header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		telem_vbox.add_child(header_hbox)
		telem_vbox.move_child(header_hbox, 0)

		if title_node:
			title_node.reparent(header_hbox)
			title_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		fps_label = Label.new()
		fps_label.name = "FPSLabel"
		fps_label.add_theme_font_size_override("font_size", 12)
		fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fps_label.text = "-- FPS"
		fps_label.modulate = Color(0.3, 1.0, 0.4)
		header_hbox.add_child(fps_label)

		solar_badge_label = Label.new()
		solar_badge_label.name = "SolarBadgeLabel"
		solar_badge_label.add_theme_font_size_override("font_size", 12)
		solar_badge_label.text = "SOLAR: --:--:-- [--]"
		telem_vbox.add_child(solar_badge_label)
		telem_vbox.move_child(solar_badge_label, 3)

		weather_badge_label = Label.new()
		weather_badge_label.name = "WeatherBadgeLabel"
		weather_badge_label.add_theme_font_size_override("font_size", 11)
		weather_badge_label.text = "WEATHER: Initializing atmospheric thermodynamics..."
		telem_vbox.add_child(weather_badge_label)
		telem_vbox.move_child(weather_badge_label, 4)

	if toggle_controls_btn and not toggle_controls_btn.pressed.is_connected(_on_toggle_controls_pressed):
		toggle_controls_btn.focus_mode = Control.FOCUS_NONE
		toggle_controls_btn.pressed.connect(_on_toggle_controls_pressed)

	if wobble_test_btn and not wobble_test_btn.pressed.is_connected(_on_wobble_test_pressed):
		wobble_test_btn.focus_mode = Control.FOCUS_NONE
		wobble_test_btn.pressed.connect(_on_wobble_test_pressed)
	if reset_spawn_btn and not reset_spawn_btn.pressed.is_connected(_on_reset_spawn_pressed):
		reset_spawn_btn.focus_mode = Control.FOCUS_NONE
		reset_spawn_btn.pressed.connect(_on_reset_spawn_pressed)

	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _process(delta: float) -> void:
	_update_solar_ui()
	_update_fps_display(delta)

func _setup_underwater_overlay() -> void:
	underwater_overlay = ColorRect.new()
	underwater_overlay.name = "UnderwaterScreenTint"
	underwater_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	underwater_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater_overlay.color = Color(0.04, 0.32, 0.55, 0.38)
	underwater_overlay.visible = false
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
	current_ui_scale = clampf(target_scale, 0.5, 2.75)
	is_scale_auto = auto_mode

	if ui_root:
		ui_root.scale = Vector2(current_ui_scale, current_ui_scale)
		# Size the logical root to viewport/scale so scaled content fills the screen
		var vp_size = get_viewport().get_visible_rect().size
		ui_root.size = vp_size / current_ui_scale

	if touch_controls:
		touch_controls.ui_scale = current_ui_scale

	_update_scale_slider_ui()
	UIScaleManager.save_user_scale(current_ui_scale, is_scale_auto)

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

func _create_slider_row(parent: VBoxContainer, label_text: String, min_val: float, max_val: float, step_val: float, init_val: float, callback: Callable) -> Array:
	var box = VBoxContainer.new()
	var header = HBoxContainer.new()

	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	header.add_child(lbl)

	var vlbl = Label.new()
	vlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		tab_container.set_tab_title(0, "☁️ Weather")
		tab_container.set_tab_title(1, "☀️ Lighting")
		tab_container.set_tab_title(2, "⏳ Time")
		tab_container.set_tab_title(3, "🌐 Physics")
		tab_container.set_tab_title(4, "⚙️ System")

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

	var vbox_system = get_node_or_null("UIRoot/ControlPanel/TabContainer/System/VBoxSystem") as VBoxContainer
	if vbox_system:
		_setup_system_tab(vbox_system)

	_update_solar_ui()

func _setup_weather_tab(vbox: VBoxContainer) -> void:
	# 1. Active Trajectory & Queue Readout
	trajectory_status_label = Label.new()
	trajectory_status_label.name = "TrajectoryStatusLabel"
	trajectory_status_label.add_theme_font_size_override("font_size", 11)
	trajectory_status_label.text = "Forecast: Initializing Trajectory..."
	trajectory_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	
	var hbox_preset_row = HBoxContainer.new()
	queue_box.add_child(hbox_preset_row)

	preset_queue_option = OptionButton.new()
	preset_queue_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_queue_option.focus_mode = Control.FOCUS_NONE
	preset_queue_option.add_item("Fair Cumulus Morning", 0)
	preset_queue_option.add_item("Building Cumulus Deck", 1)
	preset_queue_option.add_item("Overcast Coriolis Squall", 2)
	preset_queue_option.add_item("Atmospheric Downpour", 3)
	preset_queue_option.add_item("Post-Storm Clearing", 4)
	preset_queue_option.add_item("Hazy Golden Afternoon", 5)
	preset_queue_option.add_item("Clear Sky & Axis View", 6)
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

	var hbox_actions = HBoxContainer.new()
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

	var hbox_q_mgmt = HBoxContainer.new()
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
	var r_time = _create_slider_row(vbox, "In-Game Time of Day:", 0.0, 24.0, 0.02, cur_time, _on_solar_time_slider_changed)
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

	wobble_test_btn = Button.new()
	wobble_test_btn.text = "Perturb Horizon Roll (+25°)"
	wobble_test_btn.focus_mode = Control.FOCUS_NONE
	wobble_test_btn.add_theme_font_size_override("font_size", 12)
	wobble_test_btn.pressed.connect(_on_wobble_test_pressed)
	vbox.add_child(wobble_test_btn)

	reset_spawn_btn = Button.new()
	reset_spawn_btn.text = "Reset to Spawn"
	reset_spawn_btn.focus_mode = Control.FOCUS_NONE
	reset_spawn_btn.add_theme_font_size_override("font_size", 12)
	reset_spawn_btn.pressed.connect(_on_reset_spawn_pressed)
	vbox.add_child(reset_spawn_btn)

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

	var hbox_pro_ret = HBoxContainer.new()
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

	var hbox_traj = HBoxContainer.new()
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

func _setup_system_tab(vbox: VBoxContainer) -> void:
	var r_scale = _create_slider_row(vbox, "UI Scaling Factor:", 0.75, 2.75, 0.05, current_ui_scale, _on_scale_slider_changed)
	scale_slider = r_scale[0]
	scale_val = r_scale[1]
	_update_scale_slider_ui()

	reset_scale_btn = Button.new()
	reset_scale_btn.text = "Reset to Auto-Calculated Scale"
	reset_scale_btn.focus_mode = Control.FOCUS_NONE
	reset_scale_btn.add_theme_font_size_override("font_size", 10)
	reset_scale_btn.pressed.connect(_on_reset_scale_pressed)
	vbox.add_child(reset_scale_btn)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	deploy_campfire_btn = Button.new()
	deploy_campfire_btn.text = "Deploy Campfire at Feet (C)"
	deploy_campfire_btn.focus_mode = Control.FOCUS_NONE
	deploy_campfire_btn.add_theme_font_size_override("font_size", 11)
	deploy_campfire_btn.pressed.connect(_on_deploy_campfire_pressed)
	vbox.add_child(deploy_campfire_btn)

	deploy_lamp_btn = Button.new()
	deploy_lamp_btn.text = "Deploy Lamp Post at Feet (L)"
	deploy_lamp_btn.focus_mode = Control.FOCUS_NONE
	deploy_lamp_btn.add_theme_font_size_override("font_size", 11)
	deploy_lamp_btn.pressed.connect(_on_deploy_lamp_pressed)
	vbox.add_child(deploy_lamp_btn)

	var stats_sep = HSeparator.new()
	vbox.add_child(stats_sep)

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
		if fps >= 55:
			fps_label.modulate = Color(0.3, 1.0, 0.4)
		elif fps >= 30:
			fps_label.modulate = Color(1.0, 0.85, 0.2)
		else:
			fps_label.modulate = Color(1.0, 0.35, 0.3)

	if system_fps_label and is_instance_valid(system_fps_label) and system_fps_label.is_visible_in_tree():
		var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
		var process_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		system_fps_label.text = "Engine: %d FPS | Frame: %.1f ms (Proc: %.1f ms | Phys: %.1f ms)\nDraw Calls: %d | Objects: %d | VRAM: %.1f MB" % [
			fps, frame_ms, process_ms, physics_ms, int(draw_calls), int(objects), vram_mb
		]

func _on_telemetry_updated(data: Dictionary) -> void:
	var is_flying: bool = data.get("is_flying", false)
	var locomotion_state: String = data.get("locomotion_state", "IDLE")
	var grav_ms2: float = data.get("gravity_ms2", 0.0)
	var grav_g: float = data.get("gravity_g", 0.0)
	var grav_ratio: float = data.get("gravity_ratio", 0.0)
	var dist_axis: float = data.get("dist_from_axis", 0.0)
	var dist_surface: float = data.get("dist_to_surface", 0.0)
	var speed: float = data.get("speed", 0.0)
	var pos_z: float = data.get("pos_z", 0.0)
	var ring_deg: float = data.get("ring_angle_deg", 0.0)
	var wobble_deg: float = data.get("wobble_deg", 0.0)
	var correction_rate: float = data.get("wobble_correction_rate", 16.0)
	var pitch_deg: float = data.get("pitch_deg", 0.0)

	var is_in_water: bool = data.get("is_in_water", false)
	var is_camera_underwater: bool = data.get("is_camera_underwater", is_in_water)

	if underwater_overlay:
		underwater_overlay.visible = is_camera_underwater

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

	if artificial_horizon:
		artificial_horizon.roll_deg = wobble_deg
		artificial_horizon.pitch_deg = pitch_deg
		artificial_horizon.gravity_ratio = grav_ratio
		artificial_horizon.correction_rate = correction_rate
		artificial_horizon.locomotion_state = locomotion_state

	if horizon_angle_label:
		horizon_angle_label.text = "ROLL: %+.1f°\nRATE: %.1f/s" % [wobble_deg, correction_rate]

func _on_light_preset_selected(index: int) -> void:
	if not light_bar:
		return
	match index:
		0:
			light_bar.preset = AxisLightBar.LightingPreset.UNIFORM
		1:
			light_bar.preset = AxisLightBar.LightingPreset.GRADIENT
			light_bar.gradient_follows_solar_cycle = true
		2:
			light_bar.preset = AxisLightBar.LightingPreset.DAY_NIGHT_WAVE
		3:
			light_bar.preset = AxisLightBar.LightingPreset.NEON_AURORA
		4:
			light_bar.preset = AxisLightBar.LightingPreset.WARM_SUNSET
		5:
			light_bar.preset = AxisLightBar.LightingPreset.SOLAR_CYCLE
	_update_solar_ui()

func _on_solar_time_slider_changed(value: float) -> void:
	if light_bar:
		light_bar.set_time_of_day(value, true)
	if weather_system and weather_system.tie_to_in_game_clock:
		weather_system.apply_time_of_day_weather(value)
	_update_solar_ui()

func _on_time_scale_slider_changed(value: float) -> void:
	if light_bar:
		light_bar.time_scale = value
	_update_time_scale_display(value)
	_update_solar_ui()

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
	_update_solar_ui()

func _on_latitude_slider_changed(value: float) -> void:
	if light_bar:
		light_bar.set_earth_latitude(value)
	_update_solar_ui()

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

	if solar_badge_label:
		solar_badge_label.text = "SOLAR: %02d:%02d:%02d [%s] | Elev: %+.1f° (%s)" % [
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

	if solar_time_val:
		solar_time_val.text = "%02d:%02d:%02d [%s]" % [hours, mins, secs, mode_tag]

	if solar_time_slider and (is_rt or t_scale > 0.0):
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

func _on_gravity_changed(value: float) -> void:
	if player:
		player.base_gravity = value
	if weather_system:
		weather_system.base_gravity = value
	if gravity_val:
		gravity_val.text = "-%.1f m/s²" % value

func _on_auto_cycle_toggle_pressed() -> void:
	if auto_cycle_btn:
		auto_cycle_btn.release_focus()
	if not weather_system:
		return
	weather_system.set_auto_weather_cycle(not weather_system.auto_weather_cycle_enabled)
	if auto_cycle_btn:
		auto_cycle_btn.text = "Auto-Loop: %s" % ("ON" if weather_system.auto_weather_cycle_enabled else "OFF")

func _on_add_preset_to_queue_pressed() -> void:
	if add_preset_to_queue_btn:
		add_preset_to_queue_btn.release_focus()
	if not weather_system or not preset_queue_option or not duration_queue_option:
		return
	var preset_idx = preset_queue_option.selected
	var dur = float(duration_queue_option.get_selected_id())
	weather_system.enqueue_preset_by_index(preset_idx, dur)

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

func _on_skip_trajectory_pressed() -> void:
	if skip_trajectory_btn:
		skip_trajectory_btn.release_focus()
	if weather_system:
		weather_system.skip_current_trajectory()

func _on_clear_queue_pressed() -> void:
	if clear_queue_btn:
		clear_queue_btn.release_focus()
	if weather_system:
		weather_system.clear_weather_queue()

func _on_clock_sync_toggle_pressed() -> void:
	if clock_sync_btn:
		clock_sync_btn.release_focus()
	if not weather_system:
		return
	weather_system.set_tie_to_in_game_clock(not weather_system.tie_to_in_game_clock)
	if clock_sync_btn:
		clock_sync_btn.text = "Clock: %s" % ("ON" if weather_system.tie_to_in_game_clock else "OFF")

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

	if trajectory_status_label:
		if is_trans:
			var clock_tag = "⏱️ Clock Tied" if is_clock else "⏱️ Real-Time"
			trajectory_status_label.text = "Active Target: %s [%d%% | %ds left] (%s)\nCloud Deck: Rot %.1f° | Drift Z: %+.0fm" % [
				traj_name, int(round(traj_prog * 100.0)), int(round(traj_rem)), clock_tag, cloud_rot_deg, cloud_z_drift
			]
		else:
			trajectory_status_label.text = "Active Weather: %s (Stationary)\nCloud Deck: Rot %.1f° | Drift Z: %+.0fm" % [
				data.get("weather_state", "Fair Cumulus"), cloud_rot_deg, cloud_z_drift
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

	if weather_badge_label:
		var w_state = data.get("weather_state", "Fair Cumulus")
		var rh = data.get("relative_humidity_pct", 68.0)
		var cloud_km = data.get("cloud_altitude_km", 1.25)
		var cloud_th = data.get("cloud_thickness_m", 250.0)
		var density_gm3 = data.get("humidity_density_gm3", 14.5)
		var precip = data.get("precipitation_rate_mmh", 0.0)
		var dust_pct = data.get("dust_density_pct", 20)

		var precip_str = ""
		if precip > 0.05:
			precip_str = " | Rain: %.1f mm/h (Tilt: %+.1f°)" % [precip, data.get("coriolis_rain_tilt_deg", 0.0)]

		var queue_tag = "[Queue: %d]" % q_size if q_size > 0 else ("[Auto-Loop]" if is_auto else "[Manual]")
		weather_badge_label.text = "WEATHER %s: [%s] | Hum: %.1f g/m³ (RH: %d%%)%s\nCLOUDS: Deck @ %.2f km AGL (Thick: %.0fm) | Rot: %.1f° | Dust: %d%%" % [
			queue_tag, traj_name if is_trans else w_state.to_upper(), density_gm3, int(round(rh)), precip_str, cloud_km, cloud_th, cloud_rot_deg, dust_pct
		]
		match w_state:
			"Clear Sky":
				weather_badge_label.modulate = Color(0.4, 0.9, 1.0)
			"Fair Cumulus":
				weather_badge_label.modulate = Color(0.5, 1.0, 0.7)
			"Scattered Clouds":
				weather_badge_label.modulate = Color(0.9, 0.9, 0.5)
			"Overcast Deck":
				weather_badge_label.modulate = Color(0.8, 0.8, 0.9)
			"Atmospheric Rain & Mist", "Light Rain & Mist", "Moderate Rain", "Heavy Atmospheric Downpour":
				weather_badge_label.modulate = Color(0.55, 0.75, 1.0)
			_:
				weather_badge_label.modulate = Color(0.7, 0.9, 0.8)

	if cloud_status_label:
		var dew = data.get("dew_point_c", 15.2)
		var hvac_t = data.get("endcap_air_temp_c", 22.5)
		var water_t = data.get("water_pipe_temp_c", 24.0)
		var precip = data.get("precipitation_rate_mmh", 0.0)
		cloud_status_label.text = "LCL Base: %.2f km | Dew: %.1f°C | Rain: %.1f mm/h\nHVAC Air: %.1f°C | Water Pipes: %.1f°C" % [
			data.get("cloud_altitude_km", 1.25), dew, precip, hvac_t, water_t
		]

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

func _on_humidity_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.humidity_density_gm3 = val
	if humidity_val:
		humidity_val.text = "%.1f g/m³" % val

func _on_cloud_cover_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.cloud_coverage = val
	if cloud_cover_val:
		cloud_cover_val.text = "%d%%" % int(round(val * 100.0))

func _on_cloud_thickness_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.cloud_thickness_m = val
	if cloud_thickness_val:
		cloud_thickness_val.text = "%.0f m" % val

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

func _on_dust_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.dust_density = val
	if dust_val:
		dust_val.text = "%d%%" % int(round(val * 100.0))

func _on_hvac_air_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.endcap_air_temperature_c = val
	if hvac_air_val:
		hvac_air_val.text = "%.1f °C" % val

func _on_water_pipe_slider_changed(val: float) -> void:
	_disable_auto_weather_for_manual_control()
	if weather_system:
		weather_system.water_pipe_temperature_c = val
	if water_pipe_val:
		water_pipe_val.text = "%.1f °C" % val


func _on_toggle_controls_pressed() -> void:
	if toggle_controls_btn:
		toggle_controls_btn.release_focus()
	if control_panel:
		control_panel.visible = not control_panel.visible

func _on_wobble_test_pressed() -> void:
	if wobble_test_btn:
		wobble_test_btn.release_focus()
	if player:
		player.wobble_impulse(25.0)

func _on_reset_spawn_pressed() -> void:
	if reset_spawn_btn:
		reset_spawn_btn.release_focus()
	if player:
		player.reset_to_spawn()

func _on_view_south_cap_pressed() -> void:
	if south_cap_btn:
		south_cap_btn.release_focus()
	if player and player.has_method("teleport_to_z"):
		player.teleport_to_z(-8500.0, true)

func _on_view_north_cap_pressed() -> void:
	if north_cap_btn:
		north_cap_btn.release_focus()
	if player and player.has_method("teleport_to_z"):
		player.teleport_to_z(8500.0, true)

func _on_deploy_campfire_pressed() -> void:
	if deploy_campfire_btn:
		deploy_campfire_btn.release_focus()
	if player and player.has_method("deploy_campfire"):
		player.deploy_campfire()

func _on_deploy_lamp_pressed() -> void:
	if deploy_lamp_btn:
		deploy_lamp_btn.release_focus()
	if player and player.has_method("deploy_lamp_post"):
		player.deploy_lamp_post()

func _on_launch_speed_changed(val: float) -> void:
	launch_speed = val
	if launch_speed_val:
		launch_speed_val.text = "%.0f m/s" % val

func _on_particle_drag_changed(val: float) -> void:
	if particle_emitter:
		particle_emitter.air_drag_coefficient = val

func _on_launch_up_pressed() -> void:
	if launch_up_btn:
		launch_up_btn.release_focus()
	if player:
		player.launch_vertical_particle(launch_speed)

func _on_launch_prograde_pressed() -> void:
	if launch_prograde_btn:
		launch_prograde_btn.release_focus()
	if particle_emitter and player:
		var spawn_pos = player.global_position + player.global_basis.y * 1.5
		particle_emitter.launch_relative_to_surface(spawn_pos, launch_speed, 5.0, 0.0, {
			"color": Color(0.2, 1.0, 0.4, 1.0),
			"size": 1.2
		})

func _on_launch_retrograde_pressed() -> void:
	if launch_retrograde_btn:
		launch_retrograde_btn.release_focus()
	if particle_emitter and player:
		var spawn_pos = player.global_position + player.global_basis.y * 1.5
		particle_emitter.launch_relative_to_surface(spawn_pos, -launch_speed, 5.0, 0.0, {
			"color": Color(1.0, 0.3, 0.7, 1.0),
			"size": 1.2
		})

func _on_launch_aimed_pressed() -> void:
	if launch_aimed_btn:
		launch_aimed_btn.release_focus()
	if player:
		player.launch_aimed_particle(launch_speed)

func _on_toggle_rain_stream_pressed() -> void:
	if toggle_rain_stream_btn:
		toggle_rain_stream_btn.release_focus()
	if particle_emitter:
		particle_emitter.rain_stream_enabled = not particle_emitter.rain_stream_enabled
		if toggle_rain_stream_btn:
			toggle_rain_stream_btn.text = "🌧️ Cloud Rain Stream: %s" % ("ON" if particle_emitter.rain_stream_enabled else "OFF")

func _on_toggle_trajectories_pressed() -> void:
	if toggle_trajectories_btn:
		toggle_trajectories_btn.release_focus()
	if particle_emitter:
		particle_emitter.show_trajectories = not particle_emitter.show_trajectories
		if toggle_trajectories_btn:
			toggle_trajectories_btn.text = "Trajectories: %s" % ("ON" if particle_emitter.show_trajectories else "OFF")

func _on_clear_trajectories_pressed() -> void:
	if clear_trajectories_btn:
		clear_trajectories_btn.release_focus()
	if particle_emitter:
		particle_emitter.clear_all()
