class_name WeatherSystem
extends Node3D

const CylinderParticleEmitter = preload("res://scripts/cylinder_particle_emitter.gd")

signal weather_updated(data: Dictionary)

enum SpinDirection {
	COUNTER_CLOCKWISE = 1, # +Z angular momentum
	CLOCKWISE = -1         # -Z angular momentum
}

enum WeatherType {
	CLEAR = 0,
	FAIR_CUMULUS = 1,
	SCATTERED_CLOUDS = 2,
	OVERCAST = 3,
	RAIN_MIST = 4
}

@export_category("Cylinder Dimensions (8 km dia x 18 km length)")
@export var cylinder_radius: float = 4000.0
@export var cylinder_length: float = 18000.0

@export_category("Weather Trajectory & Autonomous Cycling")
@export var auto_weather_cycle_enabled: bool = true
@export var tie_to_in_game_clock: bool = true
@export var trajectory_speed_scale: float = 1.0

@export_category("Atmospheric Thermodynamics & Heating")
@export var endcap_air_temperature_c: float = 22.5: # Heated in cylinder walls, piped through end caps
	set(val):
		endcap_air_temperature_c = val
		_recalculate_thermodynamics()

@export var water_pipe_temperature_c: float = 24.0: # Heated via submerged water pipes
	set(val):
		water_pipe_temperature_c = val
		_recalculate_thermodynamics()

@export var ambient_pressure_kpa: float = 101.3 # Standard 1 atm at ground level

@export_category("Humidity & Cloud Layer (1.0 to 1.5 km up)")
@export var humidity_density_gm3: float = 14.5: # Grams of water vapor per cubic meter (g/m³)
	set(val):
		humidity_density_gm3 = clampf(val, 2.0, 30.0)
		_recalculate_thermodynamics()

@export var cloud_altitude_m: float = 1250.0: # 1.0 to 1.5 km up from ground level
	set(val):
		cloud_altitude_m = clampf(val, 800.0, 2000.0)
		_update_cloud_mesh_radius()

@export var cloud_coverage: float = 0.55: # 0.0 (Clear) to 1.0 (Full Overcast)
	set(val):
		cloud_coverage = clampf(val, 0.0, 1.0)
		_update_shader_parameters()

@export var cloud_thickness_m: float = 250.0: # Vertical deck thickness (50m to 800m)
	set(val):
		cloud_thickness_m = clampf(val, 50.0, 800.0)
		_update_cloud_mesh_radius()

@export_category("Precipitation & Dust / Particulates")
@export var precipitation_rate_mmh: float = 0.0: # 0.0 to 50.0 mm/hr
	set(val):
		precipitation_rate_mmh = clampf(val, 0.0, 50.0)
		_update_precipitation_emitter()

@export var dust_density: float = 0.20: # 0.0 (Pristine) to 1.0 (Dense Hazy Dust)
	set(val):
		dust_density = clampf(val, 0.0, 1.0)
		_update_dust_emitter()
		_update_shader_parameters()

@export_category("Coriolis Dynamics & Spin Direction")
@export var spin_direction: SpinDirection = SpinDirection.COUNTER_CLOCKWISE:
	set(val):
		spin_direction = val
		_recalculate_coriolis_vectors()

@export var base_gravity: float = 9.5: # Centrifugal ground gravity m/s²
	set(val):
		base_gravity = maxf(val, 0.1)
		_recalculate_coriolis_vectors()

var current_weather: WeatherType = WeatherType.FAIR_CUMULUS
var relative_humidity_pct: float = 68.0
var dew_point_c: float = 15.2
var coriolis_omega_rad_s: float = 0.0487 # sqrt(g/R)
var coriolis_deflection_rate: float = 0.0
var coriolis_rain_tilt_deg: float = 0.0
var wind_velocity: Vector2 = Vector2.ZERO # (theta_rad_s, z_m_s)

# Cloud Deck Coriolis Rotation & Axial Translation Accumulators
var cloud_deck_rotation_theta: float = 0.0 # Radians
var cloud_deck_translation_z: float = 0.0  # Meters
var cloud_deck_accumulated_spin: float = 0.0
var cloud_deck_accumulated_drift: float = 0.0
var cloud_deck_angular_velocity: float = 0.0 # rad/s
var cloud_deck_axial_velocity: float = 0.0 # m/s

# Weather Trajectory & Transition Queue State
var is_transitioning: bool = false
var current_trajectory_index: int = 0
var trajectory_timer: float = 0.0
var trajectory_duration: float = 45.0
var trajectory_start_state: Dictionary = {}
var trajectory_target_state: Dictionary = {}
var trajectory_queue: Array[Dictionary] = []
var custom_target_counter: int = 1
var last_in_game_time_hours: float = -1.0

# 24-Hour Diurnal Weather Anchors (Synchronized with Earth Day/Night Time of Day)
var diurnal_weather_anchors: Array[Dictionary] = [
	{
		"hour": 6.0,
		"name": "Fair Cumulus Morning",
		"cloud_coverage": 0.35,
		"cloud_thickness_m": 200.0,
		"precipitation_rate_mmh": 0.0,
		"humidity_density_gm3": 12.0,
		"dust_density": 0.12,
		"endcap_air_temperature_c": 21.5,
		"water_pipe_temperature_c": 23.0
	},
	{
		"hour": 10.0,
		"name": "Building Cumulus Deck",
		"cloud_coverage": 0.62,
		"cloud_thickness_m": 360.0,
		"precipitation_rate_mmh": 0.0,
		"humidity_density_gm3": 16.5,
		"dust_density": 0.18,
		"endcap_air_temperature_c": 23.0,
		"water_pipe_temperature_c": 24.5
	},
	{
		"hour": 13.0,
		"name": "Overcast Coriolis Squall",
		"cloud_coverage": 0.88,
		"cloud_thickness_m": 520.0,
		"precipitation_rate_mmh": 10.5,
		"humidity_density_gm3": 21.5,
		"dust_density": 0.14,
		"endcap_air_temperature_c": 19.5,
		"water_pipe_temperature_c": 22.5
	},
	{
		"hour": 15.5,
		"name": "Atmospheric Downpour",
		"cloud_coverage": 0.98,
		"cloud_thickness_m": 680.0,
		"precipitation_rate_mmh": 28.0,
		"humidity_density_gm3": 26.0,
		"dust_density": 0.06,
		"endcap_air_temperature_c": 18.0,
		"water_pipe_temperature_c": 21.0
	},
	{
		"hour": 17.5,
		"name": "Post-Storm Clearing",
		"cloud_coverage": 0.38,
		"cloud_thickness_m": 210.0,
		"precipitation_rate_mmh": 0.0,
		"humidity_density_gm3": 12.5,
		"dust_density": 0.08,
		"endcap_air_temperature_c": 20.5,
		"water_pipe_temperature_c": 22.5
	},
	{
		"hour": 19.5,
		"name": "Hazy Golden Afternoon",
		"cloud_coverage": 0.18,
		"cloud_thickness_m": 130.0,
		"precipitation_rate_mmh": 0.0,
		"humidity_density_gm3": 8.5,
		"dust_density": 0.35,
		"endcap_air_temperature_c": 25.0,
		"water_pipe_temperature_c": 26.0
	},
	{
		"hour": 22.0,
		"name": "Clear Sky & Axis View",
		"cloud_coverage": 0.05,
		"cloud_thickness_m": 80.0,
		"precipitation_rate_mmh": 0.0,
		"humidity_density_gm3": 5.0,
		"dust_density": 0.15,
		"endcap_air_temperature_c": 22.0,
		"water_pipe_temperature_c": 23.5
	}
]

var weather_trajectories: Array[Dictionary] = diurnal_weather_anchors

var far_cloud_mesh_instance: MeshInstance3D = null
var near_cloud_mesh_instance: MeshInstance3D = null
var far_cloud_material: ShaderMaterial = null
var near_cloud_material: ShaderMaterial = null

# Localized Emitters tracking player position
var rain_particles: CPUParticles3D = null
var dust_particles: CPUParticles3D = null
var target_player: Node3D = null

# Pre-rendered Textured Rain Sheets
var rain_sheets_root: Node3D = null
var rain_sheets_mesh_instance: MeshInstance3D = null
var rain_sheet_material: ShaderMaterial = null
var rain_texture_cache: Dictionary = {}
var current_rendered_density_tier: int = -1

func _ready() -> void:
	add_to_group("weather_system")
	_recalculate_coriolis_vectors()
	_recalculate_thermodynamics()
	_build_cloud_mesh()
	_build_rain_sheets()
	_setup_weather_emitters()
	_sync_with_scene_lighting()
	_init_weather_trajectory()

func _process(delta: float) -> void:
	var light_bar = get_tree().get_first_node_in_group("light_bar") as AxisLightBar if is_inside_tree() else null
	var current_clock_hours = light_bar.time_of_day_hours if light_bar else 12.0

	var effective_dt = delta * trajectory_speed_scale

	if tie_to_in_game_clock and light_bar:
		if last_in_game_time_hours >= 0.0:
			var dh = current_clock_hours - last_in_game_time_hours
			if dh < -12.0:
				dh += 24.0
			elif dh > 12.0:
				dh -= 24.0
			
			var clock_dt = dh * 3600.0 * trajectory_speed_scale
			if absf(dh) > 0.00005:
				effective_dt = clock_dt
		last_in_game_time_hours = current_clock_hours

	_update_weather_trajectory(effective_dt, current_clock_hours)
	_update_dynamic_wind(delta)
	_update_cloud_deck_coriolis_motion(delta, current_clock_hours)
	_update_shader_parameters()
	_update_particle_positions()
	_emit_weather_telemetry()

func _init_weather_trajectory() -> void:
	var light_bar = get_tree().get_first_node_in_group("light_bar") as AxisLightBar if is_inside_tree() else null
	var h = light_bar.time_of_day_hours if light_bar else 12.0
	_apply_diurnal_weather_at_hour(h)

func _get_diurnal_weather_at_hour(h: float) -> Dictionary:
	var hour_norm = fposmod(h, 24.0)
	var n = diurnal_weather_anchors.size()
	if n == 0:
		return {}

	# Find segment on the 24-hour ring
	var prev_anchor = diurnal_weather_anchors[n - 1]
	var next_anchor = diurnal_weather_anchors[0]
	var total_span = 0.0
	var elapsed = 0.0

	if hour_norm >= diurnal_weather_anchors[n - 1]["hour"] or hour_norm < diurnal_weather_anchors[0]["hour"]:
		prev_anchor = diurnal_weather_anchors[n - 1]
		next_anchor = diurnal_weather_anchors[0]
		total_span = (next_anchor["hour"] + 24.0) - prev_anchor["hour"]
		elapsed = (hour_norm - prev_anchor["hour"]) if hour_norm >= prev_anchor["hour"] else (hour_norm + 24.0 - prev_anchor["hour"])
	else:
		for i in range(n - 1):
			var a = diurnal_weather_anchors[i]
			var b = diurnal_weather_anchors[i + 1]
			if hour_norm >= a["hour"] and hour_norm < b["hour"]:
				prev_anchor = a
				next_anchor = b
				total_span = b["hour"] - a["hour"]
				elapsed = hour_norm - a["hour"]
				break

	var t = clampf(elapsed / maxf(total_span, 0.01), 0.0, 1.0)
	var s = 0.5 - 0.5 * cos(t * PI)

	return {
		"name": next_anchor["name"] if s > 0.6 else prev_anchor["name"],
		"cloud_coverage": lerpf(float(prev_anchor["cloud_coverage"]), float(next_anchor["cloud_coverage"]), s),
		"cloud_thickness_m": lerpf(float(prev_anchor["cloud_thickness_m"]), float(next_anchor["cloud_thickness_m"]), s),
		"precipitation_rate_mmh": lerpf(float(prev_anchor["precipitation_rate_mmh"]), float(next_anchor["precipitation_rate_mmh"]), s),
		"humidity_density_gm3": lerpf(float(prev_anchor["humidity_density_gm3"]), float(next_anchor["humidity_density_gm3"]), s),
		"dust_density": lerpf(float(prev_anchor["dust_density"]), float(next_anchor["dust_density"]), s),
		"endcap_air_temperature_c": lerpf(float(prev_anchor["endcap_air_temperature_c"]), float(next_anchor["endcap_air_temperature_c"]), s),
		"water_pipe_temperature_c": lerpf(float(prev_anchor["water_pipe_temperature_c"]), float(next_anchor["water_pipe_temperature_c"]), s)
	}

func _apply_diurnal_weather_at_hour(h: float) -> void:
	var state = _get_diurnal_weather_at_hour(h)
	if state.is_empty():
		return
	cloud_coverage = float(state["cloud_coverage"])
	cloud_thickness_m = float(state["cloud_thickness_m"])
	precipitation_rate_mmh = float(state["precipitation_rate_mmh"])
	humidity_density_gm3 = float(state["humidity_density_gm3"])
	dust_density = float(state["dust_density"])
	endcap_air_temperature_c = float(state["endcap_air_temperature_c"])
	water_pipe_temperature_c = float(state["water_pipe_temperature_c"])

func _begin_transition_to(target: Dictionary) -> void:
	trajectory_target_state = target.duplicate()
	trajectory_duration = maxf(float(target.get("duration", 45.0)), 1.0)
	trajectory_timer = 0.0
	trajectory_start_state = {
		"cloud_coverage": cloud_coverage,
		"cloud_thickness_m": cloud_thickness_m,
		"precipitation_rate_mmh": precipitation_rate_mmh,
		"humidity_density_gm3": humidity_density_gm3,
		"dust_density": dust_density,
		"endcap_air_temperature_c": endcap_air_temperature_c,
		"water_pipe_temperature_c": water_pipe_temperature_c
	}
	is_transitioning = true

func start_trajectory(index: int) -> void:
	if weather_trajectories.is_empty():
		return
	current_trajectory_index = index % weather_trajectories.size()
	_begin_transition_to(weather_trajectories[current_trajectory_index])

func enqueue_weather_target(target: Dictionary) -> void:
	trajectory_queue.append(target.duplicate())
	if not is_transitioning:
		var next = trajectory_queue.pop_front()
		_begin_transition_to(next)

func enqueue_preset_by_index(index: int, custom_duration: float = -1.0) -> void:
	if weather_trajectories.is_empty():
		return
	var idx = index % weather_trajectories.size()
	var preset = weather_trajectories[idx].duplicate()
	if custom_duration > 0.0:
		preset["duration"] = custom_duration
	enqueue_weather_target(preset)

func enqueue_custom_target(target_params: Dictionary, duration: float = 30.0, custom_name: String = "") -> void:
	var item_name = custom_name
	if item_name.is_empty():
		item_name = "Custom Transition #%d" % custom_target_counter
		custom_target_counter += 1

	var target = {
		"name": item_name,
		"duration": maxf(duration, 1.0),
		"cloud_coverage": clampf(target_params.get("cloud_coverage", cloud_coverage), 0.0, 1.0),
		"cloud_thickness_m": clampf(target_params.get("cloud_thickness_m", cloud_thickness_m), 50.0, 800.0),
		"precipitation_rate_mmh": clampf(target_params.get("precipitation_rate_mmh", precipitation_rate_mmh), 0.0, 50.0),
		"humidity_density_gm3": clampf(target_params.get("humidity_density_gm3", humidity_density_gm3), 2.0, 30.0),
		"dust_density": clampf(target_params.get("dust_density", dust_density), 0.0, 1.0),
		"endcap_air_temperature_c": clampf(target_params.get("endcap_air_temperature_c", endcap_air_temperature_c), 10.0, 40.0),
		"water_pipe_temperature_c": clampf(target_params.get("water_pipe_temperature_c", water_pipe_temperature_c), 10.0, 40.0)
	}
	enqueue_weather_target(target)

func skip_current_trajectory() -> void:
	if not trajectory_queue.is_empty():
		var next = trajectory_queue.pop_front()
		_begin_transition_to(next)
	elif auto_weather_cycle_enabled:
		advance_to_next_trajectory()
	else:
		if not trajectory_target_state.is_empty():
			cloud_coverage = float(trajectory_target_state.get("cloud_coverage", cloud_coverage))
			cloud_thickness_m = float(trajectory_target_state.get("cloud_thickness_m", cloud_thickness_m))
			precipitation_rate_mmh = float(trajectory_target_state.get("precipitation_rate_mmh", precipitation_rate_mmh))
			humidity_density_gm3 = float(trajectory_target_state.get("humidity_density_gm3", humidity_density_gm3))
			dust_density = float(trajectory_target_state.get("dust_density", dust_density))
			endcap_air_temperature_c = float(trajectory_target_state.get("endcap_air_temperature_c", endcap_air_temperature_c))
			water_pipe_temperature_c = float(trajectory_target_state.get("water_pipe_temperature_c", water_pipe_temperature_c))
		is_transitioning = false

func clear_weather_queue() -> void:
	trajectory_queue.clear()

func advance_to_next_trajectory() -> void:
	if weather_trajectories.is_empty():
		return
	var next_idx = (current_trajectory_index + 1) % weather_trajectories.size()
	start_trajectory(next_idx)

func set_auto_weather_cycle(enabled: bool) -> void:
	auto_weather_cycle_enabled = enabled
	if auto_weather_cycle_enabled and not is_transitioning:
		if not trajectory_queue.is_empty():
			var next = trajectory_queue.pop_front()
			_begin_transition_to(next)
		else:
			start_trajectory(current_trajectory_index)

func set_tie_to_in_game_clock(enabled: bool) -> void:
	tie_to_in_game_clock = enabled
	last_in_game_time_hours = -1.0

func get_current_trajectory_name() -> String:
	if not trajectory_queue.is_empty() or is_transitioning:
		if not trajectory_target_state.is_empty():
			return String(trajectory_target_state.get("name", "Custom Target"))
	var light_bar = get_tree().get_first_node_in_group("light_bar") as AxisLightBar if is_inside_tree() else null
	var h = light_bar.time_of_day_hours if light_bar else 12.0
	var state = _get_diurnal_weather_at_hour(h)
	return String(state.get("name", "Diurnal Cycle"))

func get_current_trajectory_progress() -> float:
	if is_transitioning:
		return clampf(trajectory_timer / maxf(trajectory_duration, 0.1), 0.0, 1.0)
	var light_bar = get_tree().get_first_node_in_group("light_bar") as AxisLightBar if is_inside_tree() else null
	var h = light_bar.time_of_day_hours if light_bar else 12.0
	return fposmod(h / 24.0, 1.0)

func get_current_trajectory_time_remaining() -> float:
	if is_transitioning:
		return maxf(0.0, trajectory_duration - trajectory_timer)
	return 0.0

func get_queue_items_summary() -> Array[String]:
	var summaries: Array[String] = []
	for i in range(trajectory_queue.size()):
		var item = trajectory_queue[i]
		var item_name = item.get("name", "Target")
		var dur = int(round(float(item.get("duration", 30.0))))
		summaries.append("%d. %s (%ds)" % [i + 1, item_name, dur])
	return summaries

func _update_weather_trajectory(effective_dt: float, current_clock_hours: float) -> void:
	# 1. If user has items in the queue or is executing an active transition, process transition
	if is_transitioning and not trajectory_start_state.is_empty() and not trajectory_target_state.is_empty():
		var remaining_dt = effective_dt
		while is_transitioning and remaining_dt > 0.0 and (trajectory_timer + remaining_dt) >= trajectory_duration:
			var step_left = trajectory_duration - trajectory_timer
			remaining_dt -= step_left
			trajectory_timer = trajectory_duration

			# Snap to target values
			cloud_coverage = float(trajectory_target_state.get("cloud_coverage", cloud_coverage))
			cloud_thickness_m = float(trajectory_target_state.get("cloud_thickness_m", cloud_thickness_m))
			precipitation_rate_mmh = float(trajectory_target_state.get("precipitation_rate_mmh", precipitation_rate_mmh))
			humidity_density_gm3 = float(trajectory_target_state.get("humidity_density_gm3", humidity_density_gm3))
			dust_density = float(trajectory_target_state.get("dust_density", dust_density))
			endcap_air_temperature_c = float(trajectory_target_state.get("endcap_air_temperature_c", endcap_air_temperature_c))
			water_pipe_temperature_c = float(trajectory_target_state.get("water_pipe_temperature_c", water_pipe_temperature_c))

			if not trajectory_queue.is_empty():
				var next = trajectory_queue.pop_front()
				_begin_transition_to(next)
			else:
				is_transitioning = false
				break

		if is_transitioning:
			trajectory_timer += maxf(0.0, remaining_dt)
			var t = clampf(trajectory_timer / maxf(trajectory_duration, 0.1), 0.0, 1.0)
			var s = 0.5 - 0.5 * cos(t * PI)

			cloud_coverage = lerpf(float(trajectory_start_state.get("cloud_coverage", cloud_coverage)), float(trajectory_target_state.get("cloud_coverage", cloud_coverage)), s)
			cloud_thickness_m = lerpf(float(trajectory_start_state.get("cloud_thickness_m", cloud_thickness_m)), float(trajectory_target_state.get("cloud_thickness_m", cloud_thickness_m)), s)
			precipitation_rate_mmh = lerpf(float(trajectory_start_state.get("precipitation_rate_mmh", precipitation_rate_mmh)), float(trajectory_target_state.get("precipitation_rate_mmh", precipitation_rate_mmh)), s)
			humidity_density_gm3 = lerpf(float(trajectory_start_state.get("humidity_density_gm3", humidity_density_gm3)), float(trajectory_target_state.get("humidity_density_gm3", humidity_density_gm3)), s)
			dust_density = lerpf(float(trajectory_start_state.get("dust_density", dust_density)), float(trajectory_target_state.get("dust_density", dust_density)), s)
			endcap_air_temperature_c = lerpf(float(trajectory_start_state.get("endcap_air_temperature_c", endcap_air_temperature_c)), float(trajectory_target_state.get("endcap_air_temperature_c", endcap_air_temperature_c)), s)
			water_pipe_temperature_c = lerpf(float(trajectory_start_state.get("water_pipe_temperature_c", water_pipe_temperature_c)), float(trajectory_target_state.get("water_pipe_temperature_c", water_pipe_temperature_c)), s)

	# 2. If queue is empty and auto cycle is enabled: follow diurnal in-game clock directly
	elif auto_weather_cycle_enabled:
		if not trajectory_queue.is_empty():
			var next = trajectory_queue.pop_front()
			_begin_transition_to(next)
		elif tie_to_in_game_clock:
			_apply_diurnal_weather_at_hour(current_clock_hours)

func _update_cloud_deck_coriolis_motion(delta: float, current_clock_hours: float) -> void:
	var spin_sign = float(spin_direction)
	var thickness_factor = clampf(cloud_thickness_m / 350.0, 0.7, 1.5)
	cloud_deck_angular_velocity = (0.012 + 0.004 * thickness_factor) * spin_sign * (coriolis_omega_rad_s / 0.0487)
	cloud_deck_axial_velocity = 2.2 + sin(Time.get_ticks_msec() * 0.00015) * 0.8

	# Accumulate micro turbulence
	cloud_deck_accumulated_spin += cloud_deck_angular_velocity * delta
	cloud_deck_accumulated_drift += cloud_deck_axial_velocity * delta

	# Directly tie cloud deck azimuth to in-game clock time of day
	if tie_to_in_game_clock:
		# 24 hours = 2 full rotations of cloud deck across habitat sky
		var diurnal_theta = (current_clock_hours / 24.0) * TAU * spin_sign * 2.0
		var diurnal_z = sin((current_clock_hours / 24.0) * TAU) * 1400.0 + (current_clock_hours / 24.0) * 3200.0

		cloud_deck_rotation_theta = fposmod(diurnal_theta + cloud_deck_accumulated_spin, TAU)
		var half_len = cylinder_length * 0.5
		cloud_deck_translation_z = fposmod(diurnal_z + cloud_deck_accumulated_drift + half_len, cylinder_length) - half_len
	else:
		cloud_deck_rotation_theta = fposmod(cloud_deck_rotation_theta + cloud_deck_angular_velocity * delta, TAU)
		var half_len = cylinder_length * 0.5
		cloud_deck_translation_z = fposmod(cloud_deck_translation_z + cloud_deck_axial_velocity * delta + half_len, cylinder_length) - half_len

func _recalculate_coriolis_vectors() -> void:
	coriolis_omega_rad_s = sqrt(base_gravity / maxf(cylinder_radius, 1.0))
	var spin_sign = float(spin_direction)

	var estimated_updraft_speed = 0.65 # m/s
	var coriolis_accel_theta = 2.0 * coriolis_omega_rad_s * estimated_updraft_speed * spin_sign

	coriolis_deflection_rate = coriolis_accel_theta
	wind_velocity = Vector2(0.008 * spin_sign, 0.002)

	var rain_fall_speed = 14.0 # m/s terminal velocity
	var coriolis_rain_v_tangent = -2.0 * coriolis_omega_rad_s * rain_fall_speed * spin_sign
	coriolis_rain_tilt_deg = rad_to_deg(atan2(coriolis_rain_v_tangent, rain_fall_speed))

	_update_precipitation_emitter()

func _recalculate_thermodynamics() -> void:
	var avg_ground_temp = (endcap_air_temperature_c * 0.45) + (water_pipe_temperature_c * 0.55)
	var es_hpa = 6.1078 * exp((17.27 * avg_ground_temp) / (avg_ground_temp + 237.3))
	var sat_vapor_density_gm3 = (216.7 * es_hpa) / (avg_ground_temp + 273.15)

	relative_humidity_pct = clampf((humidity_density_gm3 / maxf(sat_vapor_density_gm3, 1.0)) * 100.0, 5.0, 100.0)

	var a = 17.27
	var b = 237.7
	var alpha_val = ((a * avg_ground_temp) / (b + avg_ground_temp)) + log(relative_humidity_pct / 100.0)
	dew_point_c = (b * alpha_val) / (a - alpha_val)

	var calculated_lcl = clampf(125.0 * (avg_ground_temp - dew_point_c), 950.0, 1550.0)
	cloud_altitude_m = calculated_lcl

	if relative_humidity_pct < 45.0:
		current_weather = WeatherType.CLEAR
	elif relative_humidity_pct < 65.0:
		current_weather = WeatherType.FAIR_CUMULUS
	elif relative_humidity_pct < 85.0:
		current_weather = WeatherType.SCATTERED_CLOUDS
	elif relative_humidity_pct < 95.0:
		current_weather = WeatherType.OVERCAST
	else:
		current_weather = WeatherType.RAIN_MIST

func _build_cloud_mesh() -> void:
	if far_cloud_mesh_instance and is_instance_valid(far_cloud_mesh_instance):
		far_cloud_mesh_instance.queue_free()
	if near_cloud_mesh_instance and is_instance_valid(near_cloud_mesh_instance):
		near_cloud_mesh_instance.queue_free()

	far_cloud_mesh_instance = MeshInstance3D.new()
	far_cloud_mesh_instance.name = "FarCloudLayer"
	add_child(far_cloud_mesh_instance)

	near_cloud_mesh_instance = MeshInstance3D.new()
	near_cloud_mesh_instance.name = "NearCloudLayer"
	add_child(near_cloud_mesh_instance)

	var far_shader = load("res://assets/shaders/cylinder_clouds_far.gdshader") as Shader
	if far_shader:
		far_cloud_material = ShaderMaterial.new()
		far_cloud_material.shader = far_shader
		far_cloud_material.render_priority = 4 # Far clouds render over far water/terrain (P0), behind near clouds (P5)
		far_cloud_mesh_instance.material_override = far_cloud_material

	var near_shader = load("res://assets/shaders/cylinder_clouds.gdshader") as Shader
	if near_shader:
		near_cloud_material = ShaderMaterial.new()
		near_cloud_material.shader = near_shader
		near_cloud_material.render_priority = 5 # Near clouds render over far clouds (P4) and central axis light bar
		near_cloud_mesh_instance.material_override = near_cloud_material

	_generate_cloud_geometry()
	_update_shader_parameters()

func _generate_cloud_geometry() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cloud_r = cylinder_radius - cloud_altitude_m
	var cloud_len = cylinder_length
	var half_len = cloud_len * 0.5

	var radial_segs = 96
	var length_segs = 48
	var d_theta = TAU / float(radial_segs)
	var d_z = cloud_len / float(length_segs)

	for j in range(length_segs + 1):
		var z = -half_len + float(j) * d_z
		var v_coord = float(j) / float(length_segs)

		for i in range(radial_segs + 1):
			var theta = float(i) * d_theta
			var u_coord = float(i) / float(radial_segs)

			var cos_t = cos(theta)
			var sin_t = sin(theta)

			var pos = Vector3(cloud_r * cos_t, cloud_r * sin_t, z)
			var normal = Vector3(-cos_t, -sin_t, 0.0)

			st.set_normal(normal)
			st.set_uv(Vector2(u_coord, v_coord))
			st.add_vertex(pos)

	var stride = radial_segs + 1
	for j in range(length_segs):
		for i in range(radial_segs):
			var i00 = j * stride + i
			var i10 = j * stride + (i + 1)
			var i01 = (j + 1) * stride + i
			var i11 = (j + 1) * stride + (i + 1)

			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i01)

			st.add_index(i10)
			st.add_index(i11)
			st.add_index(i01)

	st.generate_tangents()
	var mesh = st.commit()

	if far_cloud_mesh_instance and is_instance_valid(far_cloud_mesh_instance):
		far_cloud_mesh_instance.mesh = mesh
	if near_cloud_mesh_instance and is_instance_valid(near_cloud_mesh_instance):
		near_cloud_mesh_instance.mesh = mesh

func _update_cloud_mesh_radius() -> void:
	_generate_cloud_geometry()
	_update_shader_parameters()

func _build_rain_sheets() -> void:
	if rain_sheets_root and is_instance_valid(rain_sheets_root):
		rain_sheets_root.queue_free()

	rain_sheets_root = Node3D.new()
	rain_sheets_root.name = "RainSheetsRoot"
	add_child(rain_sheets_root)

	rain_sheets_mesh_instance = MeshInstance3D.new()
	rain_sheets_mesh_instance.name = "RainSheetsMesh"
	rain_sheets_root.add_child(rain_sheets_mesh_instance)

	var shader = load("res://assets/shaders/cylinder_rain_sheet.gdshader") as Shader
	if shader:
		rain_sheet_material = ShaderMaterial.new()
		rain_sheet_material.shader = shader
		rain_sheet_material.render_priority = 8
		rain_sheets_mesh_instance.material_override = rain_sheet_material

	# Generate multi-layered curtain cage mesh around player for seamless volumetric depth
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Concentric layers with varied radii, heights, and UV scales: [radius, num_planes, height, width, uv_sx, uv_sy]
	var layers = [
		[0.9, 4, 10.0, 2.8, 0.8, 0.6],  # Close foreground right in front of view
		[1.8, 5, 12.0, 4.2, 1.2, 0.8],  # Immediate near field
		[3.2, 6, 16.0, 7.0, 1.8, 1.0],  # Close radius
		[6.5, 6, 22.0, 12.0, 2.5, 1.4], # Mid-inner
		[12.5, 8, 28.0, 18.0, 3.2, 1.8],# Mid-outer
		[21.0, 8, 36.0, 24.0, 4.0, 2.2],# Far
		[34.0, 10, 48.0, 32.0, 5.0, 2.6]# Horizon perimeter
	]

	var rng = RandomNumberGenerator.new()
	rng.seed = 4242

	# 1. Concentric ring sheets
	for layer in layers:
		var rad: float = layer[0]
		var count: int = layer[1]
		var h: float = layer[2]
		var w: float = layer[3]
		var uv_sx: float = layer[4]
		var uv_sy: float = layer[5]

		var d_ang = TAU / float(count)
		var angle_offset = rng.randf_range(0.0, TAU)

		for i in range(count):
			var ang = float(i) * d_ang + angle_offset
			var cos_a = cos(ang)
			var sin_a = sin(ang)

			var center = Vector3(cos_a * rad, 0.0, sin_a * rad)
			var right_dir = Vector3(-sin_a, 0.0, cos_a)
			var up_dir = Vector3.UP

			var half_w = w * 0.5
			var half_h = h * 0.5

			var p0 = center - (right_dir * half_w) - (up_dir * half_h)
			var p1 = center + (right_dir * half_w) - (up_dir * half_h)
			var p2 = center + (right_dir * half_w) + (up_dir * half_h)
			var p3 = center - (right_dir * half_w) + (up_dir * half_h)

			var u_off = rng.randf()
			var v_off = rng.randf()

			var uv0 = Vector2(u_off, v_off + uv_sy)
			var uv1 = Vector2(u_off + uv_sx, v_off + uv_sy)
			var uv2 = Vector2(u_off + uv_sx, v_off)
			var uv3 = Vector2(u_off, v_off)

			var norm = Vector3(cos_a, 0.0, sin_a)

			# Triangle 1
			st.set_normal(norm)
			st.set_uv(uv0)
			st.add_vertex(p0)

			st.set_normal(norm)
			st.set_uv(uv1)
			st.add_vertex(p1)

			st.set_normal(norm)
			st.set_uv(uv2)
			st.add_vertex(p2)

			# Triangle 2
			st.set_normal(norm)
			st.set_uv(uv0)
			st.add_vertex(p0)

			st.set_normal(norm)
			st.set_uv(uv2)
			st.add_vertex(p2)

			st.set_normal(norm)
			st.set_uv(uv3)
			st.add_vertex(p3)

	# 2. Intersecting cross planes passing directly through the center (0, 0, 0)
	var cross_planes = [
		[Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), 10.0, 5.0, 1.4, 0.9],
		[Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), 10.0, 5.0, 1.4, 0.9],
		[Vector3(0.0, 0.0, 0.0), Vector3(0.707, 0.0, 0.707), 10.0, 5.0, 1.4, 0.9],
		[Vector3(0.0, 0.0, 0.0), Vector3(-0.707, 0.0, 0.707), 10.0, 5.0, 1.4, 0.9]
	]
	for cp in cross_planes:
		var center: Vector3 = cp[0]
		var right_dir: Vector3 = cp[1]
		var h: float = cp[2]
		var w: float = cp[3]
		var uv_sx: float = cp[4]
		var uv_sy: float = cp[5]
		var up_dir = Vector3.UP

		var half_w = w * 0.5
		var half_h = h * 0.5

		var p0 = center - (right_dir * half_w) - (up_dir * half_h)
		var p1 = center + (right_dir * half_w) - (up_dir * half_h)
		var p2 = center + (right_dir * half_w) + (up_dir * half_h)
		var p3 = center - (right_dir * half_w) + (up_dir * half_h)

		var u_off = rng.randf()
		var v_off = rng.randf()

		var uv0 = Vector2(u_off, v_off + uv_sy)
		var uv1 = Vector2(u_off + uv_sx, v_off + uv_sy)
		var uv2 = Vector2(u_off + uv_sx, v_off)
		var uv3 = Vector2(u_off, v_off)

		var norm = right_dir.cross(up_dir).normalized()

		st.set_normal(norm)
		st.set_uv(uv0)
		st.add_vertex(p0)

		st.set_normal(norm)
		st.set_uv(uv1)
		st.add_vertex(p1)

		st.set_normal(norm)
		st.set_uv(uv2)
		st.add_vertex(p2)

		st.set_normal(norm)
		st.set_uv(uv0)
		st.add_vertex(p0)

		st.set_normal(norm)
		st.set_uv(uv2)
		st.add_vertex(p2)

		st.set_normal(norm)
		st.set_uv(uv3)
		st.add_vertex(p3)

	var mesh = st.commit()
	rain_sheets_mesh_instance.mesh = mesh
	rain_sheets_root.visible = false

func _get_density_tier(precip_rate: float) -> int:
	if precip_rate <= 0.05:
		return 0
	elif precip_rate < 6.0:
		return 1 # Mist / Drizzle
	elif precip_rate < 15.0:
		return 2 # Light Rain
	elif precip_rate < 28.0:
		return 3 # Moderate Rain
	elif precip_rate < 42.0:
		return 4 # Heavy Rain
	else:
		return 5 # Torrential Downpour

func _get_or_render_rain_texture(density_tier: int) -> ImageTexture:
	if rain_texture_cache.has(density_tier):
		return rain_texture_cache[density_tier]

	var img_tex = _generate_rain_streak_texture(density_tier)
	rain_texture_cache[density_tier] = img_tex
	return img_tex

func _generate_rain_streak_texture(density_tier: int) -> ImageTexture:
	var width = 256
	var height = 512
	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Density tiers: 0=None, 1=Mist, 2=Light, 3=Moderate, 4=Heavy, 5=Torrential
	var streak_counts = [0, 220, 550, 1100, 2100, 3600]
	var count = streak_counts[clamp(density_tier, 0, streak_counts.size() - 1)]

	var rng = RandomNumberGenerator.new()
	rng.seed = 9871 + density_tier * 4099

	# Dark blue 50% Alpha streaks with 1:3 aspect ratio (width 2px, height 6px)
	var streak_w = 2
	var streak_h = 6

	for i in range(count):
		var rx = rng.randi_range(0, width - 1)
		var ry = rng.randi_range(0, height - 1)
		var a_mod = rng.randf_range(0.85, 1.15)

		for dy in range(streak_h):
			var py = (ry + dy) % height
			# Vertical gradient profile with 1:3 aspect ratio
			var v_factor: float
			if dy == 0 or dy == streak_h - 1:
				v_factor = 0.35
			elif dy == 1 or dy == streak_h - 2:
				v_factor = 0.75
			else:
				v_factor = 1.0

			for dx in range(streak_w):
				var px = (rx + dx) % width
				var final_alpha = clampf(0.50 * v_factor * a_mod, 0.0, 1.0)
				# Dark blue streaks (50% alpha)
				var streak_color = Color(0.12, 0.28, 0.58, final_alpha)

				var existing = img.get_pixel(px, py)
				if existing.a > 0.0:
					var blended_a = clampf(existing.a + streak_color.a * (1.0 - existing.a), 0.0, 1.0)
					var blended_rgb = existing.blend(streak_color)
					blended_rgb.a = blended_a
					img.set_pixel(px, py, blended_rgb)
				else:
					img.set_pixel(px, py, streak_color)

	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _setup_weather_emitters() -> void:
	if not dust_particles:
		dust_particles = CPUParticles3D.new()
		dust_particles.name = "AtmosphericDustParticles"
		dust_particles.amount = 200
		dust_particles.lifetime = 6.0
		dust_particles.preprocess = 1.0
		dust_particles.local_coords = false
		dust_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		dust_particles.emission_sphere_radius = 25.0
		dust_particles.gravity = Vector3.ZERO
		dust_particles.initial_velocity_min = 0.1
		dust_particles.initial_velocity_max = 0.4
		dust_particles.angular_velocity_min = -15.0
		dust_particles.angular_velocity_max = 15.0

		var dust_mat = StandardMaterial3D.new()
		dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dust_mat.albedo_color = Color(0.95, 0.90, 0.78, 0.35)
		dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		dust_mat.render_priority = 10
		dust_particles.material_override = dust_mat

		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.03
		sphere_mesh.height = 0.06
		dust_particles.mesh = sphere_mesh
		add_child(dust_particles)

	_update_precipitation_emitter()
	_update_dust_emitter()

func _update_precipitation_emitter() -> void:
	# Ensure particle emitter doesn't spawn macro blobs
	var emitter = get_tree().get_first_node_in_group("particle_emitter") as CylinderParticleEmitter if is_inside_tree() else null
	if emitter:
		emitter.rain_stream_enabled = false

	if not rain_sheets_root or not rain_sheet_material:
		return

	if precipitation_rate_mmh <= 0.05:
		rain_sheets_root.visible = false
		return

	var tier = _get_density_tier(precipitation_rate_mmh)
	if tier != current_rendered_density_tier:
		current_rendered_density_tier = tier
		var tex = _get_or_render_rain_texture(tier)
		rain_sheet_material.set_shader_parameter("rain_texture", tex)

	var intensity_norm = clampf(precipitation_rate_mmh / 40.0, 0.05, 1.0)
	var fall_speed = lerpf(16.0, 32.0, intensity_norm)
	var spin_sign = float(spin_direction)
	var coriolis_drift = -2.0 * coriolis_omega_rad_s * fall_speed * spin_sign

	# Scroll UVs in fall direction and Coriolis tilt
	var uv_scroll_y = fall_speed * 0.16
	var uv_scroll_x = coriolis_drift * 0.10
	rain_sheet_material.set_shader_parameter("uv_scroll_speed", Vector2(uv_scroll_x, uv_scroll_y))

func _update_dust_emitter() -> void:
	if not dust_particles:
		return

	if dust_density <= 0.02:
		dust_particles.emitting = false
		return

	dust_particles.emitting = true
	dust_particles.amount = int(lerpf(40.0, 350.0, dust_density))
	var dust_mat = dust_particles.material_override as StandardMaterial3D
	if dust_mat:
		dust_mat.albedo_color = Color(0.95, 0.90, 0.78, clampf(dust_density * 0.45, 0.1, 0.6))

func _update_particle_positions() -> void:
	if not is_inside_tree():
		return
	if not target_player or not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as Node3D
		if not target_player:
			return
	if not target_player.is_inside_tree():
		return

	var p_pos = target_player.global_position
	var r_vec = Vector2(p_pos.x, p_pos.y)
	var player_radius = r_vec.length()
	var player_altitude = maxf(cylinder_radius - player_radius, 0.0)

	var r_dir = r_vec.normalized() if r_vec.length_squared() > 1.0 else Vector2(0, -1)
	var down_3d = Vector3(r_dir.x, r_dir.y, 0.0) # Radially outward toward floor
	var up_sky_3d = -down_3d                     # Radially inward toward axis / cloud base
	var tangent_3d = Vector3(-r_dir.y, r_dir.x, 0.0)
	var spin_sign = float(spin_direction)

	# Calculate cloud altitude factor:
	# Below cloud base (altitude < cloud_altitude_m - 80m): full rain (1.0)
	# Transition zone (cloud_altitude_m - 80m to cloud_altitude_m + 40m): smooth fade out
	# Above cloud deck (altitude >= cloud_altitude_m + 40m): no rain (0.0)
	var fade_start = cloud_altitude_m - 80.0
	var fade_end = cloud_altitude_m + 40.0
	var altitude_rain_factor = clampf(1.0 - (player_altitude - fade_start) / maxf(fade_end - fade_start, 1.0), 0.0, 1.0)

	if rain_sheets_root and rain_sheets_root.is_inside_tree():
		if precipitation_rate_mmh <= 0.05 or altitude_rain_factor <= 0.001:
			rain_sheets_root.visible = false
		else:
			rain_sheets_root.visible = true
			rain_sheets_root.global_position = p_pos
			var local_up = up_sky_3d
			var local_forward = Vector3(0, 0, 1)
			var local_right = tangent_3d * spin_sign

			var tilt_rad = deg_to_rad(coriolis_rain_tilt_deg)
			var basis_rain = Basis(local_right, local_up, local_forward)
			basis_rain = basis_rain.rotated(local_forward, tilt_rad)
			rain_sheets_root.global_basis = basis_rain

			if rain_sheet_material:
				var intensity_norm = clampf(precipitation_rate_mmh / 40.0, 0.05, 1.0)
				var base_alpha = lerpf(0.75, 1.25, intensity_norm)
				rain_sheet_material.set_shader_parameter("rain_alpha_multiplier", base_alpha * altitude_rain_factor)

	if dust_particles and dust_particles.is_inside_tree() and dust_particles.emitting:
		dust_particles.global_position = p_pos

func _update_dynamic_wind(delta: float) -> void:
	var spin_sign = float(spin_direction)
	var time_val = Time.get_ticks_msec() * 0.001
	var wind_fluct = sin(time_val * 0.2) * 0.001
	wind_velocity.x = (0.006 + wind_fluct) * spin_sign

func _update_shader_parameters() -> void:
	var materials: Array[ShaderMaterial] = []
	if far_cloud_material:
		materials.append(far_cloud_material)
	if near_cloud_material:
		materials.append(near_cloud_material)

	if materials.is_empty():
		return

	var light_bar = get_tree().get_first_node_in_group("light_bar") as AxisLightBar if is_inside_tree() else null
	var lut_tex = light_bar.lut_texture if light_bar else null
	var light_int = light_bar.global_intensity_multiplier if light_bar else 3.5

	for mat in materials:
		mat.set_shader_parameter("cylinder_radius", cylinder_radius)
		mat.set_shader_parameter("cylinder_length", cylinder_length)
		mat.set_shader_parameter("cloud_altitude", cloud_altitude_m)
		mat.set_shader_parameter("cloud_thickness", cloud_thickness_m)
		mat.set_shader_parameter("humidity_density", humidity_density_gm3)
		mat.set_shader_parameter("cloud_coverage", cloud_coverage)
		mat.set_shader_parameter("dust_density", dust_density)
		mat.set_shader_parameter("coriolis_spin_direction", float(spin_direction))
		mat.set_shader_parameter("wind_velocity", wind_velocity)
		mat.set_shader_parameter("cloud_deck_offset", Vector2(cloud_deck_rotation_theta, cloud_deck_translation_z))

		if lut_tex:
			mat.set_shader_parameter("axial_light_lut", lut_tex)
			mat.set_shader_parameter("axial_light_enabled", 1.0)
			mat.set_shader_parameter("global_light_intensity", light_int)

	# Synchronize overcast cloud coverage to terrain, end caps, and water materials
	var cylinder_world = get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator if is_inside_tree() else null
	if cylinder_world:
		if cylinder_world.surface_material is ShaderMaterial:
			cylinder_world.surface_material.set_shader_parameter("cloud_coverage", cloud_coverage)
		if cylinder_world.water_material is ShaderMaterial:
			cylinder_world.water_material.set_shader_parameter("cloud_coverage", cloud_coverage)

func _sync_with_scene_lighting() -> void:
	_update_shader_parameters()

func set_spin_direction(is_ccw: bool) -> void:
	spin_direction = SpinDirection.COUNTER_CLOCKWISE if is_ccw else SpinDirection.CLOCKWISE
	_recalculate_coriolis_vectors()
	_update_shader_parameters()

func get_weather_state_name() -> String:
	if precipitation_rate_mmh > 0.5:
		if precipitation_rate_mmh < 8.0:
			return "Light Rain & Mist"
		elif precipitation_rate_mmh < 25.0:
			return "Moderate Rain"
		else:
			return "Heavy Atmospheric Downpour"
	match current_weather:
		WeatherType.CLEAR: return "Clear Sky"
		WeatherType.FAIR_CUMULUS: return "Fair Cumulus"
		WeatherType.SCATTERED_CLOUDS: return "Scattered Clouds"
		WeatherType.OVERCAST: return "Overcast Deck"
		WeatherType.RAIN_MIST: return "Atmospheric Rain & Mist"
	return "Fair Cumulus"

func get_telemetry() -> Dictionary:
	var spin_name = "Counter-Clockwise (CCW)" if spin_direction == SpinDirection.COUNTER_CLOCKWISE else "Clockwise (CW)"
	return {
		"weather_state": get_weather_state_name(),
		"is_transitioning": is_transitioning,
		"auto_cycle_enabled": auto_weather_cycle_enabled,
		"tie_to_in_game_clock": tie_to_in_game_clock,
		"trajectory_index": current_trajectory_index,
		"trajectory_name": get_current_trajectory_name(),
		"trajectory_progress": get_current_trajectory_progress(),
		"trajectory_time_remaining": get_current_trajectory_time_remaining(),
		"trajectory_duration": trajectory_duration,
		"queue_size": trajectory_queue.size(),
		"queue_items": get_queue_items_summary(),
		"humidity_density_gm3": humidity_density_gm3,
		"relative_humidity_pct": relative_humidity_pct,
		"dew_point_c": dew_point_c,
		"endcap_air_temp_c": endcap_air_temperature_c,
		"water_pipe_temp_c": water_pipe_temperature_c,
		"cloud_altitude_km": cloud_altitude_m / 1000.0,
		"cloud_thickness_m": cloud_thickness_m,
		"cloud_radius_m": cylinder_radius - cloud_altitude_m,
		"cloud_coverage_pct": int(round(cloud_coverage * 100.0)),
		"precipitation_rate_mmh": precipitation_rate_mmh,
		"dust_density_pct": int(round(dust_density * 100.0)),
		"spin_direction_name": spin_name,
		"coriolis_omega_rpm": (coriolis_omega_rad_s * 60.0) / TAU,
		"coriolis_deflection_deg_s": rad_to_deg(coriolis_deflection_rate),
		"coriolis_rain_tilt_deg": coriolis_rain_tilt_deg,
		"cloud_deck_rotation_deg": rad_to_deg(cloud_deck_rotation_theta),
		"cloud_deck_drift_z": cloud_deck_translation_z,
		"cloud_deck_omega_deg_s": rad_to_deg(cloud_deck_angular_velocity),
		"cloud_deck_vz_ms": cloud_deck_axial_velocity
	}

func _emit_weather_telemetry() -> void:
	weather_updated.emit(get_telemetry())
