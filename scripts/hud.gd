class_name HUD
extends CanvasLayer

const UIScaleManager = preload("res://scripts/ui_scale_manager.gd")

@export var player: PlayerController
@export var light_bar: AxisLightBar

# Root Container for Adaptive Scaling
@onready var ui_root: Control = $UIRoot

# UI Node References (under UIRoot)
@onready var telemetry_label: Label = $UIRoot/TelemetryPanel/VBoxContainer/TelemetryLabel
@onready var mode_badge: Label = $UIRoot/TelemetryPanel/VBoxContainer/ModeBadge
@onready var horizon_status_label: Label = $UIRoot/TelemetryPanel/VBoxContainer/HorizonStatusLabel
@onready var artificial_horizon: Control = get_node_or_null("UIRoot/HorizonContainer/VBoxContainer/ArtificialHorizon")
@onready var horizon_angle_label: Label = get_node_or_null("UIRoot/HorizonContainer/VBoxContainer/HorizonAngleLabel")

@onready var light_preset_option: OptionButton = $UIRoot/ControlPanel/VBoxContainer/HBoxPreset/OptionButton
@onready var light_intensity_slider: HSlider = $UIRoot/ControlPanel/VBoxContainer/HBoxIntensity/HSlider
@onready var light_intensity_val: Label = $UIRoot/ControlPanel/VBoxContainer/HBoxIntensity/HBox/ValLabel
@onready var fog_slider: HSlider = $UIRoot/ControlPanel/VBoxContainer/HBoxFog/HSlider
@onready var fog_val: Label = $UIRoot/ControlPanel/VBoxContainer/HBoxFog/HBox/ValLabel
@onready var gravity_slider: HSlider = $UIRoot/ControlPanel/VBoxContainer/HBoxGravity/HSlider
@onready var gravity_val: Label = $UIRoot/ControlPanel/VBoxContainer/HBoxGravity/HBox/ValLabel
@onready var toggle_controls_btn: Button = $UIRoot/ToggleControlsButton
@onready var control_panel: PanelContainer = $UIRoot/ControlPanel
@onready var touch_controls: MobileTouchControls = $UIRoot/TouchControls

@onready var wobble_test_btn: Button = $UIRoot/ControlPanel/VBoxContainer/WobbleTestButton
@onready var reset_spawn_btn: Button = $UIRoot/ControlPanel/VBoxContainer/ResetSpawnButton
var south_cap_btn: Button = null
var north_cap_btn: Button = null
var deploy_campfire_btn: Button = null
var deploy_lamp_btn: Button = null

# Solar Cycle Day/Night UI Controls
var solar_badge_label: Label = null
var solar_time_slider: HSlider = null
var solar_time_val: Label = null
var sync_real_time_btn: Button = null
var latitude_slider: HSlider = null
var latitude_val: Label = null
var solar_status_label: Label = null

# UI Scaling Controls
@onready var scale_slider: HSlider = $UIRoot/ControlPanel/VBoxContainer/HBoxScale/HSlider
@onready var scale_val: Label = $UIRoot/ControlPanel/VBoxContainer/HBoxScale/HBox/ValLabel
@onready var reset_scale_btn: Button = $UIRoot/ControlPanel/VBoxContainer/HBoxScale/ResetScaleButton

var current_ui_scale: float = 1.0
var is_scale_auto: bool = true
var auto_scale_info: Dictionary = {}

var underwater_overlay: ColorRect = null

func _ready() -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
	if not light_bar:
		light_bar = get_tree().get_first_node_in_group("light_bar")

	_setup_underwater_overlay()

	if player:
		player.telemetry_updated.connect(_on_telemetry_updated)

	_setup_ui_scaling()
	_setup_control_panel()

	var telem_vbox = get_node_or_null("UIRoot/TelemetryPanel/VBoxContainer")
	if telem_vbox:
		solar_badge_label = Label.new()
		solar_badge_label.name = "SolarBadgeLabel"
		solar_badge_label.add_theme_font_size_override("font_size", 12)
		solar_badge_label.text = "SOLAR: --:--:-- [--]"
		telem_vbox.add_child(solar_badge_label)
		telem_vbox.move_child(solar_badge_label, 3)

	if toggle_controls_btn:
		toggle_controls_btn.focus_mode = Control.FOCUS_NONE
		toggle_controls_btn.pressed.connect(_on_toggle_controls_pressed)

	if wobble_test_btn:
		wobble_test_btn.focus_mode = Control.FOCUS_NONE
		wobble_test_btn.pressed.connect(_on_wobble_test_pressed)
	if reset_spawn_btn:
		reset_spawn_btn.focus_mode = Control.FOCUS_NONE
		reset_spawn_btn.pressed.connect(_on_reset_spawn_pressed)

	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _process(_delta: float) -> void:
	_update_solar_ui()

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
	# Continuous scale from 0.0 to 3.5
	# s=0.0 -> 0.0, s=1.0 -> 3.5
	var s_clamped = clampf(s, 0.0, 1.0)
	if s_clamped <= 0.001:
		return 0.0
	const MIN_INTENSITY: float = 0.001
	const MAX_INTENSITY: float = 3.5
	return MIN_INTENSITY * pow(MAX_INTENSITY / MIN_INTENSITY, s_clamped)

static func intensity_to_slider_pos(intensity: float) -> float:
	const MIN_INTENSITY: float = 0.001
	const MAX_INTENSITY: float = 3.5
	if intensity <= 0.0001:
		return 0.0
	return clampf(log(intensity / MIN_INTENSITY) / log(MAX_INTENSITY / MIN_INTENSITY), 0.0, 1.0)

func _setup_control_panel() -> void:
	if light_preset_option:
		light_preset_option.focus_mode = Control.FOCUS_NONE
		light_preset_option.clear()
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

	if light_intensity_slider:
		light_intensity_slider.focus_mode = Control.FOCUS_NONE
		light_intensity_slider.min_value = 0.0
		light_intensity_slider.max_value = 1.0
		light_intensity_slider.step = 0.002
		var cur_intensity = light_bar.global_intensity_multiplier if light_bar else 3.5
		light_intensity_slider.value = intensity_to_slider_pos(cur_intensity)
		light_intensity_slider.value_changed.connect(_on_light_slider_changed)
		_update_intensity_display(cur_intensity)

	if fog_slider:
		fog_slider.focus_mode = Control.FOCUS_NONE
		fog_slider.min_value = 0.0
		fog_slider.max_value = 2.0
		fog_slider.step = 0.01
		var cylinder_world = get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator
		var cur_fog = cylinder_world.air_density if cylinder_world else 1.25
		fog_slider.value = cur_fog
		fog_slider.value_changed.connect(_on_fog_changed)
		if fog_val:
			fog_val.text = "%d%%" % int(round(cur_fog * 100.0))

	if gravity_slider:
		gravity_slider.focus_mode = Control.FOCUS_NONE
		gravity_slider.min_value = 0.0
		gravity_slider.max_value = 25.0
		gravity_slider.step = 0.5
		gravity_slider.value = player.base_gravity if player else 12.0
		gravity_slider.value_changed.connect(_on_gravity_changed)
		if gravity_val:
			gravity_val.text = "%.1f m/s²" % gravity_slider.value

	var btn_vbox = $UIRoot/ControlPanel/VBoxContainer
	if btn_vbox:
		# 1. Solar Time of Day Controls
		var time_box = VBoxContainer.new()
		time_box.name = "HBoxSolarTime"
		var time_header = HBoxContainer.new()
		var time_label = Label.new()
		time_label.text = "Time of Day:"
		time_label.add_theme_font_size_override("font_size", 11)
		time_header.add_child(time_label)

		solar_time_val = Label.new()
		solar_time_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		solar_time_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		solar_time_val.add_theme_font_size_override("font_size", 11)
		solar_time_val.text = "12:00 [Real-Time]"
		time_header.add_child(solar_time_val)
		time_box.add_child(time_header)

		solar_time_slider = HSlider.new()
		solar_time_slider.name = "SolarTimeSlider"
		solar_time_slider.focus_mode = Control.FOCUS_NONE
		solar_time_slider.min_value = 0.0
		solar_time_slider.max_value = 24.0
		solar_time_slider.step = 0.02
		solar_time_slider.value = light_bar.time_of_day_hours if light_bar else 12.0
		solar_time_slider.value_changed.connect(_on_solar_time_slider_changed)
		time_box.add_child(solar_time_slider)

		sync_real_time_btn = Button.new()
		sync_real_time_btn.name = "SyncRealTimeButton"
		sync_real_time_btn.text = "Sync to Real-Time Clock"
		sync_real_time_btn.focus_mode = Control.FOCUS_NONE
		sync_real_time_btn.add_theme_font_size_override("font_size", 10)
		sync_real_time_btn.pressed.connect(_on_sync_real_time_pressed)
		time_box.add_child(sync_real_time_btn)

		btn_vbox.add_child(time_box)
		btn_vbox.move_child(time_box, 4)

		# 2. Earth Latitude Controls
		var lat_box = VBoxContainer.new()
		lat_box.name = "HBoxLatitude"
		var lat_header = HBoxContainer.new()
		var lat_label = Label.new()
		lat_label.text = "Earth Latitude:"
		lat_label.add_theme_font_size_override("font_size", 11)
		lat_header.add_child(lat_label)

		latitude_val = Label.new()
		latitude_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		latitude_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		latitude_val.add_theme_font_size_override("font_size", 11)
		latitude_val.text = "+40.0° N (Temperate)"
		lat_header.add_child(latitude_val)
		lat_box.add_child(lat_header)

		latitude_slider = HSlider.new()
		latitude_slider.name = "LatitudeSlider"
		latitude_slider.focus_mode = Control.FOCUS_NONE
		latitude_slider.min_value = -90.0
		latitude_slider.max_value = 90.0
		latitude_slider.step = 1.0
		latitude_slider.value = light_bar.earth_latitude_deg if light_bar else 40.0
		latitude_slider.value_changed.connect(_on_latitude_slider_changed)
		lat_box.add_child(latitude_slider)

		solar_status_label = Label.new()
		solar_status_label.name = "SolarStatusLabel"
		solar_status_label.add_theme_font_size_override("font_size", 10)
		solar_status_label.text = "Solar Elev: +0.0°"
		solar_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lat_box.add_child(solar_status_label)

		btn_vbox.add_child(lat_box)
		btn_vbox.move_child(lat_box, 5)

		south_cap_btn = Button.new()
		south_cap_btn.name = "ViewSouthCapButton"
		south_cap_btn.text = "Inspect South End Cap (z = -8.5 km)"
		south_cap_btn.focus_mode = Control.FOCUS_NONE
		south_cap_btn.add_theme_font_size_override("font_size", 12)
		south_cap_btn.pressed.connect(_on_view_south_cap_pressed)
		btn_vbox.add_child(south_cap_btn)

		north_cap_btn = Button.new()
		north_cap_btn.name = "ViewNorthCapButton"
		north_cap_btn.text = "Inspect North End Cap (z = +8.5 km)"
		north_cap_btn.focus_mode = Control.FOCUS_NONE
		north_cap_btn.add_theme_font_size_override("font_size", 12)
		north_cap_btn.pressed.connect(_on_view_north_cap_pressed)
		btn_vbox.add_child(north_cap_btn)

		deploy_campfire_btn = Button.new()
		deploy_campfire_btn.name = "DeployCampfireButton"
		deploy_campfire_btn.text = "Deploy Campfire at Feet"
		deploy_campfire_btn.focus_mode = Control.FOCUS_NONE
		deploy_campfire_btn.add_theme_font_size_override("font_size", 12)
		deploy_campfire_btn.pressed.connect(_on_deploy_campfire_pressed)
		btn_vbox.add_child(deploy_campfire_btn)

		deploy_lamp_btn = Button.new()
		deploy_lamp_btn.name = "DeployLampButton"
		deploy_lamp_btn.text = "Deploy Lamp Post at Feet"
		deploy_lamp_btn.focus_mode = Control.FOCUS_NONE
		deploy_lamp_btn.add_theme_font_size_override("font_size", 12)
		deploy_lamp_btn.pressed.connect(_on_deploy_lamp_pressed)
		btn_vbox.add_child(deploy_lamp_btn)

	_update_solar_ui()

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
	_update_solar_ui()

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

	var total_sec = int(t_hours * 3600.0)
	var hours = (total_sec / 3600) % 24
	var mins = (total_sec / 60) % 60
	var secs = total_sec % 60
	var mode_tag = "Real-Time" if is_rt else "Manual"

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

	if is_rt and solar_time_slider:
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
	if gravity_val:
		gravity_val.text = "%.1f m/s²" % value

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
