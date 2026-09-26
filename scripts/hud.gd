class_name HUD
extends CanvasLayer

const UIScaleManager = preload("res://scripts/ui_scale_manager.gd")

@export var player: PlayerController
@export var light_bar: AxisLightBar
@export var weather_system: WeatherSystem

# Root Container for Adaptive Scaling
@onready var ui_root: Control = $UIRoot

# UI Node References (under UIRoot)
@onready var telemetry_label: Label = $UIRoot/TelemetryPanel/VBoxContainer/TelemetryLabel
@onready var mode_badge: Label = $UIRoot/TelemetryPanel/VBoxContainer/ModeBadge
@onready var horizon_status_label: Label = $UIRoot/TelemetryPanel/VBoxContainer/HorizonStatusLabel
@onready var artificial_horizon: Control = get_node_or_null("UIRoot/HorizonContainer/VBoxContainer/ArtificialHorizon")
@onready var horizon_angle_label: Label = get_node_or_null("UIRoot/HorizonContainer/VBoxContainer/HorizonAngleLabel")

@onready var light_preset_option: OptionButton = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/HBoxPreset/OptionButton
@onready var light_intensity_slider: HSlider = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/HBoxIntensity/HSlider
@onready var light_intensity_val: Label = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/HBoxIntensity/HBox/ValLabel
@onready var fog_slider: HSlider = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/HBoxFog/HSlider
@onready var fog_val: Label = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/HBoxFog/HBox/ValLabel
@onready var gravity_slider: HSlider = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/HBoxGravity/HSlider
@onready var gravity_val: Label = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/HBoxGravity/HBox/ValLabel
@onready var toggle_controls_btn: Button = $UIRoot/ToggleControlsButton
@onready var control_panel: PanelContainer = $UIRoot/ControlPanel
@onready var touch_controls: MobileTouchControls = $UIRoot/TouchControls

@onready var wobble_test_btn: Button = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/WobbleTestButton
@onready var reset_spawn_btn: Button = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/ResetSpawnButton
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

# Atmospheric Weather & HVAC UI Controls
var weather_badge_label: Label = null
var spin_direction_btn: Button = null
var humidity_slider: HSlider = null
var humidity_val: Label = null
var cloud_cover_slider: HSlider = null
var cloud_cover_val: Label = null
var cloud_thickness_slider: HSlider = null
var cloud_thickness_val: Label = null
var precipitation_slider: HSlider = null
var precipitation_val: Label = null
var dust_slider: HSlider = null
var dust_val: Label = null
var hvac_air_slider: HSlider = null
var hvac_air_val: Label = null
var water_pipe_slider: HSlider = null
var water_pipe_val: Label = null
var cloud_status_label: Label = null

# UI Scaling Controls
@onready var scale_slider: HSlider = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/HBoxScale/HSlider
@onready var scale_val: Label = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/HBoxScale/HBox/ValLabel
@onready var reset_scale_btn: Button = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer/HBoxScale/ResetScaleButton

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

	_setup_underwater_overlay()

	if player:
		player.telemetry_updated.connect(_on_telemetry_updated)
	if weather_system:
		weather_system.weather_updated.connect(_on_weather_updated)

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

		weather_badge_label = Label.new()
		weather_badge_label.name = "WeatherBadgeLabel"
		weather_badge_label.add_theme_font_size_override("font_size", 11)
		weather_badge_label.text = "WEATHER: Initializing atmospheric thermodynamics..."
		telem_vbox.add_child(weather_badge_label)
		telem_vbox.move_child(weather_badge_label, 4)

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
		gravity_slider.value = player.base_gravity if player else 9.5
		gravity_slider.value_changed.connect(_on_gravity_changed)
		if gravity_val:
			gravity_val.text = "-%.1f m/s²" % gravity_slider.value

	var btn_vbox = $UIRoot/ControlPanel/ScrollContainer/VBoxContainer
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

		# 3. Atmospheric Weather & HVAC Thermal Controls
		var weather_sep = HSeparator.new()
		btn_vbox.add_child(weather_sep)
		btn_vbox.move_child(weather_sep, 6)

		var weather_header = Label.new()
		weather_header.name = "WeatherHeader"
		weather_header.text = "ATMOSPHERIC WEATHER & HVAC"
		weather_header.add_theme_font_size_override("font_size", 12)
		weather_header.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
		btn_vbox.add_child(weather_header)
		btn_vbox.move_child(weather_header, 7)

		spin_direction_btn = Button.new()
		spin_direction_btn.name = "SpinDirectionButton"
		var is_ccw_init = (weather_system.spin_direction == WeatherSystem.SpinDirection.COUNTER_CLOCKWISE) if weather_system else true
		spin_direction_btn.text = "Cylinder Spin: %s" % ("Counter-Clockwise (CCW)" if is_ccw_init else "Clockwise (CW)")
		spin_direction_btn.focus_mode = Control.FOCUS_NONE
		spin_direction_btn.add_theme_font_size_override("font_size", 11)
		spin_direction_btn.pressed.connect(_on_spin_direction_toggle_pressed)
		btn_vbox.add_child(spin_direction_btn)
		btn_vbox.move_child(spin_direction_btn, 8)

		# 1. Humidity Density Slider (g/m³)
		var hum_box = VBoxContainer.new()
		hum_box.name = "HBoxHumidity"
		var hum_header = HBoxContainer.new()
		var hum_label = Label.new()
		hum_label.text = "Humidity Density:"
		hum_label.add_theme_font_size_override("font_size", 11)
		hum_header.add_child(hum_label)

		humidity_val = Label.new()
		humidity_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		humidity_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		humidity_val.add_theme_font_size_override("font_size", 11)
		var cur_hum = weather_system.humidity_density_gm3 if weather_system else 14.5
		humidity_val.text = "%.1f g/m³" % cur_hum
		hum_header.add_child(humidity_val)
		hum_box.add_child(hum_header)

		humidity_slider = HSlider.new()
		humidity_slider.name = "HumiditySlider"
		humidity_slider.focus_mode = Control.FOCUS_NONE
		humidity_slider.min_value = 2.0
		humidity_slider.max_value = 30.0
		humidity_slider.step = 0.5
		humidity_slider.value = cur_hum
		humidity_slider.value_changed.connect(_on_humidity_slider_changed)
		hum_box.add_child(humidity_slider)
		btn_vbox.add_child(hum_box)
		btn_vbox.move_child(hum_box, 9)

		# 2. Cloud Coverage Slider (%)
		var cover_box = VBoxContainer.new()
		cover_box.name = "HBoxCloudCover"
		var cover_header = HBoxContainer.new()
		var cover_label = Label.new()
		cover_label.text = "Cloud Cover (Overcast):"
		cover_label.add_theme_font_size_override("font_size", 11)
		cover_header.add_child(cover_label)

		cloud_cover_val = Label.new()
		cloud_cover_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cloud_cover_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cloud_cover_val.add_theme_font_size_override("font_size", 11)
		var cur_cov = weather_system.cloud_coverage if weather_system else 0.55
		cloud_cover_val.text = "%d%%" % int(round(cur_cov * 100.0))
		cover_header.add_child(cloud_cover_val)
		cover_box.add_child(cover_header)

		cloud_cover_slider = HSlider.new()
		cloud_cover_slider.name = "CloudCoverSlider"
		cloud_cover_slider.focus_mode = Control.FOCUS_NONE
		cloud_cover_slider.min_value = 0.0
		cloud_cover_slider.max_value = 1.0
		cloud_cover_slider.step = 0.01
		cloud_cover_slider.value = cur_cov
		cloud_cover_slider.value_changed.connect(_on_cloud_cover_slider_changed)
		cover_box.add_child(cloud_cover_slider)
		btn_vbox.add_child(cover_box)
		btn_vbox.move_child(cover_box, 10)

		# 3. Cloud Deck Thickness Slider (m)
		var thick_box = VBoxContainer.new()
		thick_box.name = "HBoxCloudThickness"
		var thick_header = HBoxContainer.new()
		var thick_label = Label.new()
		thick_label.text = "Cloud Deck Thickness:"
		thick_label.add_theme_font_size_override("font_size", 11)
		thick_header.add_child(thick_label)

		cloud_thickness_val = Label.new()
		cloud_thickness_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cloud_thickness_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cloud_thickness_val.add_theme_font_size_override("font_size", 11)
		var cur_thick = weather_system.cloud_thickness_m if weather_system else 250.0
		cloud_thickness_val.text = "%.0f m" % cur_thick
		thick_header.add_child(cloud_thickness_val)
		thick_box.add_child(thick_header)

		cloud_thickness_slider = HSlider.new()
		cloud_thickness_slider.name = "CloudThicknessSlider"
		cloud_thickness_slider.focus_mode = Control.FOCUS_NONE
		cloud_thickness_slider.min_value = 50.0
		cloud_thickness_slider.max_value = 800.0
		cloud_thickness_slider.step = 10.0
		cloud_thickness_slider.value = cur_thick
		cloud_thickness_slider.value_changed.connect(_on_cloud_thickness_slider_changed)
		thick_box.add_child(cloud_thickness_slider)
		btn_vbox.add_child(thick_box)
		btn_vbox.move_child(thick_box, 11)

		# 4. Precipitation Rate Slider (mm/hr)
		var precip_box = VBoxContainer.new()
		precip_box.name = "HBoxPrecipitation"
		var precip_header = HBoxContainer.new()
		var precip_label = Label.new()
		precip_label.text = "Precipitation (Rain/Mist):"
		precip_label.add_theme_font_size_override("font_size", 11)
		precip_header.add_child(precip_label)

		precipitation_val = Label.new()
		precipitation_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		precipitation_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		precipitation_val.add_theme_font_size_override("font_size", 11)
		var cur_precip = weather_system.precipitation_rate_mmh if weather_system else 0.0
		precipitation_val.text = "%.1f mm/hr" % cur_precip if cur_precip > 0.0 else "0.0 mm/hr [None]"
		precip_header.add_child(precipitation_val)
		precip_box.add_child(precip_header)

		precipitation_slider = HSlider.new()
		precipitation_slider.name = "PrecipitationSlider"
		precipitation_slider.focus_mode = Control.FOCUS_NONE
		precipitation_slider.min_value = 0.0
		precipitation_slider.max_value = 50.0
		precipitation_slider.step = 0.5
		precipitation_slider.value = cur_precip
		precipitation_slider.value_changed.connect(_on_precipitation_slider_changed)
		precip_box.add_child(precipitation_slider)
		btn_vbox.add_child(precip_box)
		btn_vbox.move_child(precip_box, 12)

		# 5. Atmospheric Dust & Particulate Slider (%)
		var dust_box = VBoxContainer.new()
		dust_box.name = "HBoxDust"
		var dust_header = HBoxContainer.new()
		var dust_label = Label.new()
		dust_label.text = "Atmospheric Dust & Haze:"
		dust_label.add_theme_font_size_override("font_size", 11)
		dust_header.add_child(dust_label)

		dust_val = Label.new()
		dust_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dust_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dust_val.add_theme_font_size_override("font_size", 11)
		var cur_dust = weather_system.dust_density if weather_system else 0.20
		dust_val.text = "%d%%" % int(round(cur_dust * 100.0))
		dust_header.add_child(dust_val)
		dust_box.add_child(dust_header)

		dust_slider = HSlider.new()
		dust_slider.name = "DustSlider"
		dust_slider.focus_mode = Control.FOCUS_NONE
		dust_slider.min_value = 0.0
		dust_slider.max_value = 1.0
		dust_slider.step = 0.01
		dust_slider.value = cur_dust
		dust_slider.value_changed.connect(_on_dust_slider_changed)
		dust_box.add_child(dust_slider)
		btn_vbox.add_child(dust_box)
		btn_vbox.move_child(dust_box, 13)

		# 6. HVAC End-Cap Air Temp Slider
		var hvac_box = VBoxContainer.new()
		hvac_box.name = "HBoxHVACAir"
		var hvac_header = HBoxContainer.new()
		var hvac_label = Label.new()
		hvac_label.text = "HVAC End-Cap Air Temp:"
		hvac_label.add_theme_font_size_override("font_size", 11)
		hvac_header.add_child(hvac_label)

		hvac_air_val = Label.new()
		hvac_air_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hvac_air_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hvac_air_val.add_theme_font_size_override("font_size", 11)
		var cur_hvac = weather_system.endcap_air_temperature_c if weather_system else 22.5
		hvac_air_val.text = "%.1f °C" % cur_hvac
		hvac_header.add_child(hvac_air_val)
		hvac_box.add_child(hvac_header)

		hvac_air_slider = HSlider.new()
		hvac_air_slider.name = "HVACAirSlider"
		hvac_air_slider.focus_mode = Control.FOCUS_NONE
		hvac_air_slider.min_value = 10.0
		hvac_air_slider.max_value = 40.0
		hvac_air_slider.step = 0.5
		hvac_air_slider.value = cur_hvac
		hvac_air_slider.value_changed.connect(_on_hvac_air_slider_changed)
		hvac_box.add_child(hvac_air_slider)
		btn_vbox.add_child(hvac_box)
		btn_vbox.move_child(hvac_box, 14)

		# 7. Water Heating Pipe Temp Slider
		var water_box = VBoxContainer.new()
		water_box.name = "HBoxWaterPipe"
		var water_header = HBoxContainer.new()
		var water_label = Label.new()
		water_label.text = "Water Heating Pipe Temp:"
		water_label.add_theme_font_size_override("font_size", 11)
		water_header.add_child(water_label)

		water_pipe_val = Label.new()
		water_pipe_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		water_pipe_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		water_pipe_val.add_theme_font_size_override("font_size", 11)
		var cur_water = weather_system.water_pipe_temperature_c if weather_system else 24.0
		water_pipe_val.text = "%.1f °C" % cur_water
		water_header.add_child(water_pipe_val)
		water_box.add_child(water_header)

		water_pipe_slider = HSlider.new()
		water_pipe_slider.name = "WaterPipeSlider"
		water_pipe_slider.focus_mode = Control.FOCUS_NONE
		water_pipe_slider.min_value = 10.0
		water_pipe_slider.max_value = 40.0
		water_pipe_slider.step = 0.5
		water_pipe_slider.value = cur_water
		water_pipe_slider.value_changed.connect(_on_water_pipe_slider_changed)
		water_box.add_child(water_pipe_slider)
		btn_vbox.add_child(water_box)
		btn_vbox.move_child(water_box, 15)

		cloud_status_label = Label.new()
		cloud_status_label.name = "CloudStatusLabel"
		cloud_status_label.add_theme_font_size_override("font_size", 10)
		cloud_status_label.text = "Cloud Base: 1.25 km | RH: 68%"
		cloud_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn_vbox.add_child(cloud_status_label)
		btn_vbox.move_child(cloud_status_label, 16)

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
	if weather_system:
		weather_system.base_gravity = value
	if gravity_val:
		gravity_val.text = "-%.1f m/s²" % value

func _on_weather_updated(data: Dictionary) -> void:
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

		weather_badge_label.text = "WEATHER: [%s] | Hum: %.1f g/m³ (RH: %d%%)%s\nCLOUDS: Deck @ %.2f km AGL (Thick: %.0fm) | Dust: %d%%" % [
			w_state.to_upper(), density_gm3, int(round(rh)), precip_str, cloud_km, cloud_th, dust_pct
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
	if weather_system:
		weather_system.humidity_density_gm3 = val
	if humidity_val:
		humidity_val.text = "%.1f g/m³" % val

func _on_cloud_cover_slider_changed(val: float) -> void:
	if weather_system:
		weather_system.cloud_coverage = val
	if cloud_cover_val:
		cloud_cover_val.text = "%d%%" % int(round(val * 100.0))

func _on_cloud_thickness_slider_changed(val: float) -> void:
	if weather_system:
		weather_system.cloud_thickness_m = val
	if cloud_thickness_val:
		cloud_thickness_val.text = "%.0f m" % val

func _on_precipitation_slider_changed(val: float) -> void:
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
	if weather_system:
		weather_system.dust_density = val
	if dust_val:
		dust_val.text = "%d%%" % int(round(val * 100.0))

func _on_hvac_air_slider_changed(val: float) -> void:
	if weather_system:
		weather_system.endcap_air_temperature_c = val
	if hvac_air_val:
		hvac_air_val.text = "%.1f °C" % val

func _on_water_pipe_slider_changed(val: float) -> void:
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
