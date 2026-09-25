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
@onready var gravity_slider: HSlider = $UIRoot/ControlPanel/VBoxContainer/HBoxGravity/HSlider
@onready var gravity_val: Label = $UIRoot/ControlPanel/VBoxContainer/HBoxGravity/HBox/ValLabel
@onready var toggle_controls_btn: Button = $UIRoot/ToggleControlsButton
@onready var control_panel: PanelContainer = $UIRoot/ControlPanel
@onready var touch_controls: MobileTouchControls = $UIRoot/TouchControls

@onready var wobble_test_btn: Button = $UIRoot/ControlPanel/VBoxContainer/WobbleTestButton
@onready var reset_spawn_btn: Button = $UIRoot/ControlPanel/VBoxContainer/ResetSpawnButton

# UI Scaling Controls
@onready var scale_slider: HSlider = $UIRoot/ControlPanel/VBoxContainer/HBoxScale/HSlider
@onready var scale_val: Label = $UIRoot/ControlPanel/VBoxContainer/HBoxScale/HBox/ValLabel
@onready var reset_scale_btn: Button = $UIRoot/ControlPanel/VBoxContainer/HBoxScale/ResetScaleButton

var current_ui_scale: float = 1.0
var is_scale_auto: bool = true
var auto_scale_info: Dictionary = {}

func _ready() -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
	if not light_bar:
		light_bar = get_tree().get_first_node_in_group("light_bar")

	if player:
		player.telemetry_updated.connect(_on_telemetry_updated)

	_setup_ui_scaling()
	_setup_control_panel()

	if toggle_controls_btn:
		toggle_controls_btn.pressed.connect(_on_toggle_controls_pressed)

	if wobble_test_btn:
		wobble_test_btn.pressed.connect(_on_wobble_test_pressed)
	if reset_spawn_btn:
		reset_spawn_btn.pressed.connect(_on_reset_spawn_pressed)

	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _setup_ui_scaling() -> void:
	auto_scale_info = UIScaleManager.calculate_intelligent_scale()
	var saved_pref = UIScaleManager.load_user_scale()

	if saved_pref.get("has_saved", false) and not saved_pref.get("is_auto", true):
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
	current_ui_scale = clampf(target_scale, 0.75, 2.75)
	is_scale_auto = auto_mode

	if ui_root:
		ui_root.scale = Vector2(current_ui_scale, current_ui_scale)
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

func _setup_control_panel() -> void:
	if light_preset_option:
		light_preset_option.clear()
		light_preset_option.add_item("Gradient (Sunrise/Twilight)", 0)
		light_preset_option.add_item("Day/Night Wave (Animated)", 1)
		light_preset_option.add_item("Neon Aurora (Animated)", 2)
		light_preset_option.add_item("Warm Sunset", 3)
		light_preset_option.add_item("Uniform Daylight", 4)
		light_preset_option.item_selected.connect(_on_light_preset_selected)

	if light_intensity_slider:
		light_intensity_slider.min_value = 0.0
		light_intensity_slider.max_value = 5.0
		light_intensity_slider.step = 0.1
		light_intensity_slider.value = light_bar.global_intensity_multiplier if light_bar else 1.8
		light_intensity_slider.value_changed.connect(_on_light_intensity_changed)
		if light_intensity_val:
			light_intensity_val.text = "%.1fx" % light_intensity_slider.value

	if gravity_slider:
		gravity_slider.min_value = 0.0
		gravity_slider.max_value = 25.0
		gravity_slider.step = 0.5
		gravity_slider.value = player.base_gravity if player else 12.0
		gravity_slider.value_changed.connect(_on_gravity_changed)
		if gravity_val:
			gravity_val.text = "%.1f m/s²" % gravity_slider.value

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
			light_bar.preset = AxisLightBar.LightingPreset.GRADIENT
		1:
			light_bar.preset = AxisLightBar.LightingPreset.DAY_NIGHT_WAVE
		2:
			light_bar.preset = AxisLightBar.LightingPreset.NEON_AURORA
		3:
			light_bar.preset = AxisLightBar.LightingPreset.WARM_SUNSET
		4:
			light_bar.preset = AxisLightBar.LightingPreset.UNIFORM

func _on_light_intensity_changed(value: float) -> void:
	if light_bar:
		light_bar.global_intensity_multiplier = value
	if light_intensity_val:
		light_intensity_val.text = "%.1fx" % value

func _on_gravity_changed(value: float) -> void:
	if player:
		player.base_gravity = value
	if gravity_val:
		gravity_val.text = "%.1f m/s²" % value

func _on_toggle_controls_pressed() -> void:
	if control_panel:
		control_panel.visible = not control_panel.visible

func _on_wobble_test_pressed() -> void:
	if player:
		player.wobble_impulse(25.0)

func _on_reset_spawn_pressed() -> void:
	if player:
		player.reset_to_spawn()
