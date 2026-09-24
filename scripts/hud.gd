class_name HUD
extends CanvasLayer

@export var player: PlayerController
@export var light_bar: AxisLightBar

# UI Node References
@onready var telemetry_label: Label = $TelemetryPanel/VBoxContainer/TelemetryLabel
@onready var mode_badge: Label = $TelemetryPanel/VBoxContainer/ModeBadge
@onready var horizon_status_label: Label = $TelemetryPanel/VBoxContainer/HorizonStatusLabel
@onready var artificial_horizon: Control = get_node_or_null("HorizonContainer/VBoxContainer/ArtificialHorizon")
@onready var horizon_angle_label: Label = get_node_or_null("HorizonContainer/VBoxContainer/HorizonAngleLabel")

@onready var light_preset_option: OptionButton = $ControlPanel/VBoxContainer/HBoxPreset/OptionButton
@onready var light_intensity_slider: HSlider = $ControlPanel/VBoxContainer/HBoxIntensity/HSlider
@onready var light_intensity_val: Label = $ControlPanel/VBoxContainer/HBoxIntensity/HBox/ValLabel
@onready var gravity_slider: HSlider = $ControlPanel/VBoxContainer/HBoxGravity/HSlider
@onready var gravity_val: Label = $ControlPanel/VBoxContainer/HBoxGravity/HBox/ValLabel
@onready var toggle_controls_btn: Button = $ToggleControlsButton
@onready var control_panel: PanelContainer = $ControlPanel
@onready var touch_controls: MobileTouchControls = $TouchControls

@onready var wobble_test_btn: Button = $ControlPanel/VBoxContainer/WobbleTestButton
@onready var reset_spawn_btn: Button = $ControlPanel/VBoxContainer/ResetSpawnButton

func _ready() -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
	if not light_bar:
		light_bar = get_tree().get_first_node_in_group("light_bar")

	if player:
		player.telemetry_updated.connect(_on_telemetry_updated)

	_setup_control_panel()

	if toggle_controls_btn:
		toggle_controls_btn.pressed.connect(_on_toggle_controls_pressed)

	if wobble_test_btn:
		wobble_test_btn.pressed.connect(_on_wobble_test_pressed)
	if reset_spawn_btn:
		reset_spawn_btn.pressed.connect(_on_reset_spawn_pressed)

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

	if telemetry_label:
		var text = ""
		text += "CENTRIFUGAL GRAVITY: %4.2f G  (%4.1f m/s²)\n" % [grav_g, grav_ms2]
		text += "AXIS DISTANCE:       %5.1f m / %4.1f m\n" % [dist_axis, player.cylinder_radius if player else 80.0]
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
		horizon_angle_label.text = "HORIZON ROLL: %+.1f°\nRIGHTING RATE: %.1f/s" % [wobble_deg, correction_rate]

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
