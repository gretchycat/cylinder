class_name WeatherSystem
extends Node3D

const CylinderParticleEmitter = preload("res://scripts/cylinder_particle_emitter.gd")
const ClimateSystem = preload("res://scripts/climate_system.gd")

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
	RAIN_MIST = 4,
	SNOW_FLURRIES = 5
}

@export_category("Cylinder Dimensions (8 km dia x 18 km length)")
@export var cylinder_radius: float = 4000.0
@export var cylinder_length: float = 18000.0

@export_category("Climate & Yearly Cycles")
@export var latitude_deg: float = 40.0: # Earth latitude (-90° South to +90° North)
	set(val):
		latitude_deg = clampf(val, -90.0, 90.0)
		_recalculate_climate_profile()

@export var yearly_precipitation_mm: float = 950.0: # 50mm (Hyper-Arid) to 4000mm (Tropical Rainforest)
	set(val):
		yearly_precipitation_mm = clampf(val, 50.0, 4000.0)
		_recalculate_climate_profile()

@export var day_of_year: int = 172: # Day 1 to 365 (Yearly seasonal progression)
	set(val):
		day_of_year = clampi(val, 1, 366)
		_recalculate_climate_profile()

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

# Active Thermodynamic & Climate State
var current_weather: WeatherType = WeatherType.FAIR_CUMULUS
var relative_humidity_pct: float = 68.0
var dew_point_c: float = 15.2
var coriolis_omega_rad_s: float = 0.0487 # sqrt(g/R)
var coriolis_deflection_rate: float = 0.0
var coriolis_rain_tilt_deg: float = 0.0
var wind_velocity: Vector2 = Vector2.ZERO # (theta_rad_s, z_m_s)

# Climate System State
var current_temperature_c: float = 22.0
var is_snow_mode: bool = false
var current_climate_name: String = "Temperate Mixed Forest"
var current_season_name: String = "Summer"
var climate_profile: Dictionary = {}

# Cloud Deck Coriolis Rotation & Axial Translation Accumulators
var cloud_deck_rotation_theta: float = 0.0 # Radians
var cloud_deck_translation_z: float = 0.0  # Meters
var cloud_deck_accumulated_spin: float = 0.0
var cloud_deck_accumulated_drift: float = 0.0
var cloud_deck_angular_velocity: float = 0.0 # rad/s
var cloud_deck_axial_velocity: float = 0.0 # m/s

# 1-Deep Weather State Queue Architecture
var previous_weather_state: Dictionary = {}
var current_weather_state: Dictionary = {}
var next_queued_weather_state: Dictionary = {} # 1-deep pre-calculated queue
var manual_queue: Array[Dictionary] = [] # Runtime game queue
var transition_timer: float = 0.0
var transition_duration: float = 35.0
var last_in_game_time_hours: float = -1.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Cloud Rendering Meshes & Materials
var far_cloud_mesh_instance: MeshInstance3D = null
var near_cloud_mesh_instance: MeshInstance3D = null
var far_cloud_material: ShaderMaterial = null
var near_cloud_material: ShaderMaterial = null

# Localized Emitters tracking player position
var dust_particles: CPUParticles3D = null
var target_player: Node3D = null

# Pre-rendered Textured Rain / Snow Sheets
var rain_sheets_root: Node3D = null
var rain_sheets_mesh_instance: MeshInstance3D = null
var rain_sheet_material: ShaderMaterial = null
var rain_texture_cache: Dictionary = {}
var snow_texture_cache: Dictionary = {}
var current_rendered_density_tier: int = -1
var current_rendered_snow_state: bool = false

func _ready() -> void:
	add_to_group("weather_system")
	rng.randomize()
	_sync_with_light_bar_time()
	_recalculate_coriolis_vectors()
	_recalculate_climate_profile()
	_build_cloud_mesh()
	_build_rain_sheets()
	_setup_weather_emitters()
	_sync_with_scene_lighting()
	_init_weather_state_queue()

func _sync_with_light_bar_time() -> void:
	var light_bar = get_tree().get_first_node_in_group("light_bar") as AxisLightBar if is_inside_tree() else null
	if light_bar:
		latitude_deg = light_bar.earth_latitude_deg
		if light_bar.day_of_year > 0:
			day_of_year = light_bar.day_of_year
		else:
			var now = Time.get_date_dict_from_system()
			day_of_year = ClimateSystem.SolarCycleSimulator.get_day_of_year(now.year, now.month, now.day)

func _recalculate_climate_profile() -> void:
	var light_bar = get_tree().get_first_node_in_group("light_bar") as AxisLightBar if is_inside_tree() else null
	var time_h = light_bar.time_of_day_hours if light_bar else 12.0

	climate_profile = ClimateSystem.get_climate_weather_profile(latitude_deg, yearly_precipitation_mm, day_of_year, time_h)
	current_climate_name = String(climate_profile.get("climate_name", "Temperate Mixed Forest"))
	current_season_name = String(climate_profile.get("season_name", "Summer"))
	current_temperature_c = float(climate_profile.get("temperature_c", 22.0))
	is_snow_mode = bool(climate_profile.get("is_snow_mode", false))

	# If queue is empty, generate next queued state
	if next_queued_weather_state.is_empty():
		next_queued_weather_state = ClimateSystem.generate_weather_state(climate_profile, rng)

func _init_weather_state_queue() -> void:
	current_weather_state = ClimateSystem.generate_weather_state(climate_profile, rng)
	previous_weather_state = current_weather_state.duplicate()
	next_queued_weather_state = ClimateSystem.generate_weather_state(climate_profile, rng)
	transition_timer = 0.0
	transition_duration = float(current_weather_state.get("duration", 35.0))
	_apply_state_values(current_weather_state)

func _process(delta: float) -> void:
	var light_bar = get_tree().get_first_node_in_group("light_bar") as AxisLightBar if is_inside_tree() else null
	var current_clock_hours = light_bar.time_of_day_hours if light_bar else 12.0

	# Keep latitude and day of year synchronized with light bar if modified
	if light_bar:
		if not is_equal_approx(latitude_deg, light_bar.earth_latitude_deg):
			latitude_deg = light_bar.earth_latitude_deg
		if light_bar.day_of_year > 0 and light_bar.day_of_year != day_of_year:
			day_of_year = light_bar.day_of_year

	# Weather state progression timescale: smooth delta progression scaled gracefully
	var time_mult = 1.0
	if light_bar and not light_bar.use_real_time and light_bar.time_scale > 1.0:
		time_mult = clampf(sqrt(light_bar.time_scale), 1.0, 3.5)
	var effective_dt = delta * time_mult * trajectory_speed_scale

	_update_weather_queue_progression(effective_dt, current_clock_hours)
	_update_dynamic_wind(delta)
	_update_cloud_deck_coriolis_motion(delta)
	_update_shader_parameters()
	_update_precipitation_emitter()
	_update_dust_emitter()
	_update_particle_positions()
	_emit_weather_telemetry()

func _update_weather_queue_progression(effective_dt: float, current_clock_hours: float) -> void:
	if not auto_weather_cycle_enabled and manual_queue.is_empty():
		return

	transition_timer += maxf(0.0, effective_dt)

	# When current transition finishes, advance states
	while transition_timer >= transition_duration:
		transition_timer -= transition_duration
		previous_weather_state = current_weather_state.duplicate()

		# 1. Pop from manual queue if available
		if not manual_queue.is_empty():
			current_weather_state = manual_queue.pop_front()
		# 2. Advance to the 1-deep pre-calculated climate queue state
		elif not next_queued_weather_state.is_empty():
			current_weather_state = next_queued_weather_state
			# Pre-calculate the new next queued state from the climate descriptor
			_recalculate_climate_profile()
			next_queued_weather_state = ClimateSystem.generate_weather_state(climate_profile, rng)
		else:
			_recalculate_climate_profile()
			current_weather_state = ClimateSystem.generate_weather_state(climate_profile, rng)
			next_queued_weather_state = ClimateSystem.generate_weather_state(climate_profile, rng)

		transition_duration = maxf(float(current_weather_state.get("duration", 35.0)), 5.0)

	# Smooth Hermite S-Curve Interpolation between previous state and current state
	var t = clampf(transition_timer / maxf(transition_duration, 0.1), 0.0, 1.0)
	var s = 0.5 - 0.5 * cos(t * PI)

	var p_cov = float(previous_weather_state.get("cloud_coverage", cloud_coverage))
	var c_cov = float(current_weather_state.get("cloud_coverage", cloud_coverage))
	cloud_coverage = lerpf(p_cov, c_cov, s)

	var p_thick = float(previous_weather_state.get("cloud_thickness_m", cloud_thickness_m))
	var c_thick = float(current_weather_state.get("cloud_thickness_m", cloud_thickness_m))
	cloud_thickness_m = lerpf(p_thick, c_thick, s)

	var p_precip = float(previous_weather_state.get("precipitation_rate_mmh", precipitation_rate_mmh))
	var c_precip = float(current_weather_state.get("precipitation_rate_mmh", precipitation_rate_mmh))
	precipitation_rate_mmh = lerpf(p_precip, c_precip, s)

	var p_hum = float(previous_weather_state.get("humidity_density_gm3", humidity_density_gm3))
	var c_hum = float(current_weather_state.get("humidity_density_gm3", humidity_density_gm3))
	humidity_density_gm3 = lerpf(p_hum, c_hum, s)

	var p_dust = float(previous_weather_state.get("dust_density", dust_density))
	var c_dust = float(current_weather_state.get("dust_density", dust_density))
	dust_density = lerpf(p_dust, c_dust, s)

	var p_ec = float(previous_weather_state.get("endcap_air_temperature_c", endcap_air_temperature_c))
	var c_ec = float(current_weather_state.get("endcap_air_temperature_c", endcap_air_temperature_c))
	endcap_air_temperature_c = lerpf(p_ec, c_ec, s)

	var p_wp = float(previous_weather_state.get("water_pipe_temperature_c", water_pipe_temperature_c))
	var c_wp = float(current_weather_state.get("water_pipe_temperature_c", water_pipe_temperature_c))
	water_pipe_temperature_c = lerpf(p_wp, c_wp, s)

	# Update snow mode determination: below 4°C
	_recalculate_thermodynamics()
	is_snow_mode = (current_temperature_c <= 4.0)

func _apply_state_values(state: Dictionary) -> void:
	cloud_coverage = float(state.get("cloud_coverage", cloud_coverage))
	cloud_thickness_m = float(state.get("cloud_thickness_m", cloud_thickness_m))
	precipitation_rate_mmh = float(state.get("precipitation_rate_mmh", precipitation_rate_mmh))
	humidity_density_gm3 = float(state.get("humidity_density_gm3", humidity_density_gm3))
	dust_density = float(state.get("dust_density", dust_density))
	endcap_air_temperature_c = float(state.get("endcap_air_temperature_c", endcap_air_temperature_c))
	water_pipe_temperature_c = float(state.get("water_pipe_temperature_c", water_pipe_temperature_c))
	_recalculate_thermodynamics()

# Push custom weather state onto the queue during gameplay or debugging
func push_weather_state(state: Dictionary, immediate: bool = false) -> void:
	var formatted_state = state.duplicate()
	if not formatted_state.has("name"):
		formatted_state["name"] = "Pushed Weather Event"
	if not formatted_state.has("duration"):
		formatted_state["duration"] = 35.0

	if immediate:
		previous_weather_state = formatted_state.duplicate()
		current_weather_state = formatted_state
		transition_timer = 0.0
		transition_duration = float(formatted_state.get("duration", 35.0))
		_apply_state_values(formatted_state)
		_update_precipitation_emitter()
		_update_dust_emitter()
		_update_particle_positions()
	else:
		manual_queue.append(formatted_state)

func enqueue_custom_target(target_params: Dictionary, duration: float = 30.0, custom_name: String = "") -> void:
	var item_name = custom_name if not custom_name.is_empty() else "Custom Weather Target"
	var target = {
		"name": item_name,
		"duration": maxf(duration, 1.0),
		"cloud_coverage": clampf(target_params.get("cloud_coverage", cloud_coverage), 0.0, 1.0),
		"cloud_thickness_m": clampf(target_params.get("cloud_thickness_m", cloud_thickness_m), 50.0, 800.0),
		"precipitation_rate_mmh": clampf(target_params.get("precipitation_rate_mmh", precipitation_rate_mmh), 0.0, 50.0),
		"humidity_density_gm3": clampf(target_params.get("humidity_density_gm3", humidity_density_gm3), 2.0, 30.0),
		"dust_density": clampf(target_params.get("dust_density", dust_density), 0.0, 1.0),
		"endcap_air_temperature_c": clampf(target_params.get("endcap_air_temperature_c", endcap_air_temperature_c), -30.0, 45.0),
		"water_pipe_temperature_c": clampf(target_params.get("water_pipe_temperature_c", water_pipe_temperature_c), -20.0, 45.0)
	}
	push_weather_state(target, false)

func skip_current_trajectory() -> void:
	previous_weather_state = current_weather_state.duplicate()
	if not manual_queue.is_empty():
		current_weather_state = manual_queue.pop_front()
	elif not next_queued_weather_state.is_empty():
		current_weather_state = next_queued_weather_state
		_recalculate_climate_profile()
		next_queued_weather_state = ClimateSystem.generate_weather_state(climate_profile, rng)
	else:
		_recalculate_climate_profile()
		current_weather_state = ClimateSystem.generate_weather_state(climate_profile, rng)
		next_queued_weather_state = ClimateSystem.generate_weather_state(climate_profile, rng)

	transition_timer = 0.0
	transition_duration = float(current_weather_state.get("duration", 35.0))
	_apply_state_values(current_weather_state)

func clear_weather_queue() -> void:
	manual_queue.clear()

func apply_time_of_day_weather(hours: float) -> void:
	last_in_game_time_hours = hours
	_recalculate_climate_profile()
	_update_shader_parameters()
	_update_precipitation_emitter()
	_update_dust_emitter()
	_emit_weather_telemetry()

func set_auto_weather_cycle(enabled: bool) -> void:
	auto_weather_cycle_enabled = enabled

func set_tie_to_in_game_clock(enabled: bool) -> void:
	tie_to_in_game_clock = enabled
	last_in_game_time_hours = -1.0

func _recalculate_coriolis_vectors() -> void:
	coriolis_omega_rad_s = sqrt(base_gravity / maxf(cylinder_radius, 1.0))
	var spin_sign = float(spin_direction)

	var estimated_updraft_speed = 0.65 # m/s
	var coriolis_accel_theta = 2.0 * coriolis_omega_rad_s * estimated_updraft_speed * spin_sign

	coriolis_deflection_rate = coriolis_accel_theta
	wind_velocity = Vector2(0.008 * spin_sign, 0.002)

	var fall_speed = 6.0 if is_snow_mode else 14.0 # m/s terminal velocity
	var coriolis_rain_v_tangent = -2.0 * coriolis_omega_rad_s * fall_speed * spin_sign
	coriolis_rain_tilt_deg = rad_to_deg(atan2(coriolis_rain_v_tangent, fall_speed))

	_update_precipitation_emitter()

func _recalculate_thermodynamics() -> void:
	var avg_ground_temp = (endcap_air_temperature_c * 0.45) + (water_pipe_temperature_c * 0.55)
	current_temperature_c = avg_ground_temp
	is_snow_mode = (current_temperature_c <= 4.0)

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
		current_weather = WeatherType.SNOW_FLURRIES if is_snow_mode else WeatherType.RAIN_MIST

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
		far_cloud_material.render_priority = 4
		far_cloud_mesh_instance.material_override = far_cloud_material

	var near_shader = load("res://assets/shaders/cylinder_clouds.gdshader") as Shader
	if near_shader:
		near_cloud_material = ShaderMaterial.new()
		near_cloud_material.shader = near_shader
		near_cloud_material.render_priority = 5
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

	# Multi-layered hexagonal cylinder cage with circumference and opposite-vertex interior sheets
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rng_geom = RandomNumberGenerator.new()
	rng_geom.seed = 4242

	var hex_tiers = [
		[4.0, 16.0, 0.0],
		[12.0, 24.0, 20.0],
		[26.0, 36.0, 40.0],
		[46.0, 52.0, 10.0]
	]

	for tier in hex_tiers:
		var rad: float = tier[0]
		var h: float = tier[1]
		var angle_offset: float = deg_to_rad(tier[2])
		var y_bottom = -0.5

		var verts: Array[Vector3] = []
		for k in range(6):
			var ang = angle_offset + float(k) * (TAU / 6.0)
			verts.append(Vector3(cos(ang) * rad, 0.0, sin(ang) * rad))

		for k in range(6):
			var v_start = verts[k]
			var v_end = verts[(k + 1) % 6]
			_add_rain_quad(st, v_start, v_end, y_bottom, h, rng_geom)

		for k in range(3):
			var v_start = verts[k]
			var v_end = verts[k + 3]
			_add_rain_quad(st, v_start, v_end, y_bottom, h, rng_geom)

	var mesh = st.commit()
	rain_sheets_mesh_instance.mesh = mesh
	rain_sheets_root.visible = false

func _add_rain_quad(st: SurfaceTool, A: Vector3, B: Vector3, y_bottom: float, h: float, rng_geom: RandomNumberGenerator) -> void:
	var edge = B - A
	var w = edge.length()
	var edge_dir = edge.normalized() if w > 0.001 else Vector3.RIGHT
	var up_dir = Vector3.UP
	var norm = edge_dir.cross(up_dir).normalized()

	var y_top = y_bottom + h
	var p0 = A + Vector3(0.0, y_bottom, 0.0)
	var p1 = B + Vector3(0.0, y_bottom, 0.0)
	var p2 = B + Vector3(0.0, y_top, 0.0)
	var p3 = A + Vector3(0.0, y_top, 0.0)

	var u_off = rng_geom.randf()
	var u_span = maxf(w * 0.35, 0.8)

	var uv0 = Vector2(u_off, 0.0)
	var uv1 = Vector2(u_off + u_span, 0.0)
	var uv2 = Vector2(u_off + u_span, 1.0)
	var uv3 = Vector2(u_off, 1.0)

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

func _get_density_tier(precip_rate: float) -> int:
	if precip_rate <= 0.05:
		return 0
	elif precip_rate < 6.0:
		return 1
	elif precip_rate < 15.0:
		return 2
	elif precip_rate < 28.0:
		return 3
	elif precip_rate < 42.0:
		return 4
	else:
		return 5

func _get_or_render_rain_texture(density_tier: int, snow: bool) -> ImageTexture:
	if snow:
		if snow_texture_cache.has(density_tier):
			return snow_texture_cache[density_tier]
		var tex = _generate_snow_streak_texture(density_tier)
		snow_texture_cache[density_tier] = tex
		return tex
	else:
		if rain_texture_cache.has(density_tier):
			return rain_texture_cache[density_tier]
		var tex = _generate_rain_streak_texture(density_tier)
		rain_texture_cache[density_tier] = tex
		return tex

func _generate_rain_streak_texture(density_tier: int) -> ImageTexture:
	var width = 256
	var height = 512
	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var streak_counts = [0, 220, 550, 1100, 2100, 3600]
	var count = streak_counts[clamp(density_tier, 0, streak_counts.size() - 1)]

	var rng_tex = RandomNumberGenerator.new()
	rng_tex.seed = 9871 + density_tier * 4099
	var streak_w = 2
	var streak_h = 6

	for i in range(count):
		var rx = rng_tex.randi_range(0, width - 1)
		var ry = rng_tex.randi_range(0, height - 1)
		var a_mod = rng_tex.randf_range(0.85, 1.15)

		for dy in range(streak_h):
			var py = (ry + dy) % height
			var v_factor = 0.35 if (dy == 0 or dy == streak_h - 1) else (0.75 if (dy == 1 or dy == streak_h - 2) else 1.0)

			for dx in range(streak_w):
				var px = (rx + dx) % width
				var final_alpha = clampf(0.50 * v_factor * a_mod, 0.0, 1.0)
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

func _generate_snow_streak_texture(density_tier: int) -> ImageTexture:
	var width = 256
	var height = 512
	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var flake_counts = [0, 350, 850, 1600, 2900, 4800]
	var count = flake_counts[clamp(density_tier, 0, flake_counts.size() - 1)]

	var rng_tex = RandomNumberGenerator.new()
	rng_tex.seed = 13579 + density_tier * 3137

	for i in range(count):
		var rx = rng_tex.randi_range(0, width - 1)
		var ry = rng_tex.randi_range(0, height - 1)
		var size = rng_tex.randi_range(2, 4)
		var a_mod = rng_tex.randf_range(0.65, 0.95)

		for dy in range(size):
			var py = (ry + dy) % height
			for dx in range(size):
				var px = (rx + dx) % width
				var dist = Vector2(dx - size * 0.5, dy - size * 0.5).length()
				var falloff = clampf(1.0 - dist / (size * 0.6), 0.0, 1.0)
				var flake_color = Color(0.95, 0.97, 1.0, falloff * a_mod)

				var existing = img.get_pixel(px, py)
				if existing.a > 0.0:
					var blended_a = clampf(existing.a + flake_color.a * (1.0 - existing.a), 0.0, 1.0)
					var blended_rgb = existing.blend(flake_color)
					blended_rgb.a = blended_a
					img.set_pixel(px, py, blended_rgb)
				else:
					img.set_pixel(px, py, flake_color)

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
		dust_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		dust_particles.emission_box_extents = Vector3(25.0, 10.0, 25.0)
		dust_particles.gravity = Vector3.ZERO
		dust_particles.initial_velocity_min = 0.1
		dust_particles.initial_velocity_max = 0.4
		dust_particles.angular_velocity_min = -15.0
		dust_particles.angular_velocity_max = 15.0

		var dust_mat = StandardMaterial3D.new()
		dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dust_mat.albedo_color = Color(0.95, 0.90, 0.78, 0.25)
		dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		dust_mat.render_priority = 10
		dust_particles.material_override = dust_mat

		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.02
		sphere_mesh.height = 0.04
		dust_particles.mesh = sphere_mesh
		add_child(dust_particles)

	_update_precipitation_emitter()
	_update_dust_emitter()

func _update_precipitation_emitter() -> void:
	var emitter = get_tree().get_first_node_in_group("particle_emitter") as CylinderParticleEmitter if is_inside_tree() else null
	if emitter:
		emitter.rain_stream_enabled = false

	if not rain_sheets_root or not rain_sheet_material:
		return

	if precipitation_rate_mmh <= 0.05:
		rain_sheets_root.visible = false
		return

	var tier = _get_density_tier(precipitation_rate_mmh)
	if tier != current_rendered_density_tier or is_snow_mode != current_rendered_snow_state:
		current_rendered_density_tier = tier
		current_rendered_snow_state = is_snow_mode
		var tex = _get_or_render_rain_texture(tier, is_snow_mode)
		rain_sheet_material.set_shader_parameter("rain_texture", tex)

	var intensity_norm = clampf(precipitation_rate_mmh / 40.0, 0.05, 1.0)
	var fall_speed = lerpf(3.5, 7.0, intensity_norm) if is_snow_mode else lerpf(16.0, 32.0, intensity_norm)
	var spin_sign = float(spin_direction)
	var coriolis_drift = -2.0 * coriolis_omega_rad_s * fall_speed * spin_sign

	var uv_scroll_y = fall_speed * (0.04 if is_snow_mode else 0.16)
	var uv_scroll_x = coriolis_drift * (0.04 if is_snow_mode else 0.10)
	rain_sheet_material.set_shader_parameter("uv_scroll_speed", Vector2(uv_scroll_x, uv_scroll_y))
	rain_sheet_material.set_shader_parameter("rain_tint", Color(1.0, 1.0, 1.0, 1.0))

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
		var dust_col = Color(0.95, 0.98, 1.0) if is_snow_mode else Color(0.95, 0.90, 0.78)
		dust_mat.albedo_color = Color(dust_col.r, dust_col.g, dust_col.b, clampf(dust_density * 0.45, 0.1, 0.6))

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
	var down_3d = Vector3(r_dir.x, r_dir.y, 0.0)
	var up_sky_3d = -down_3d
	var tangent_3d = Vector3(-r_dir.y, r_dir.x, 0.0)
	var spin_sign = float(spin_direction)

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
		dust_particles.global_position = p_pos + up_sky_3d * 20.0

func _update_dynamic_wind(delta: float) -> void:
	var spin_sign = float(spin_direction)
	var time_val = Time.get_ticks_msec() * 0.001
	var wind_fluct = sin(time_val * 0.2) * 0.001
	wind_velocity.x = (0.006 + wind_fluct) * spin_sign

func _update_cloud_deck_coriolis_motion(delta: float) -> void:
	var spin_sign = float(spin_direction)
	var thickness_factor = clampf(cloud_thickness_m / 350.0, 0.7, 1.5)
	cloud_deck_angular_velocity = (0.010 + 0.003 * thickness_factor) * spin_sign * (coriolis_omega_rad_s / 0.0487)
	cloud_deck_axial_velocity = 2.0 + sin(Time.get_ticks_msec() * 0.0001) * 0.5

	# Smooth, continuous monotonic accumulation without wrapping jumps or direction flipping
	cloud_deck_rotation_theta += cloud_deck_angular_velocity * delta
	cloud_deck_translation_z += cloud_deck_axial_velocity * delta

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
	if not current_weather_state.is_empty():
		return String(current_weather_state.get("name", "Active Weather"))
	if precipitation_rate_mmh > 0.5:
		if is_snow_mode:
			return "Active Snowfall & Drifts"
		return "Moderate Rain & Mist"
	return "Fair Cumulus Skies"

func get_current_trajectory_name() -> String:
	return get_weather_state_name()

func get_current_trajectory_progress() -> float:
	return clampf(transition_timer / maxf(transition_duration, 0.1), 0.0, 1.0)

func get_current_trajectory_time_remaining() -> float:
	return maxf(0.0, transition_duration - transition_timer)

func get_queue_items_summary() -> Array[String]:
	var summaries: Array[String] = []
	if not manual_queue.is_empty():
		for i in range(manual_queue.size()):
			var item = manual_queue[i]
			var iname = item.get("name", "Queued State")
			var dur = int(round(float(item.get("duration", 30.0))))
			summaries.append("Manual #%d: %s (%ds)" % [i + 1, iname, dur])
	elif not next_queued_weather_state.is_empty():
		var n_name = next_queued_weather_state.get("name", "Next Climate State")
		var dur = int(round(float(next_queued_weather_state.get("duration", 35.0))))
		summaries.append("Next: %s (%ds)" % [n_name, dur])
	return summaries

func get_telemetry() -> Dictionary:
	var spin_name = "Counter-Clockwise (CCW)" if spin_direction == SpinDirection.COUNTER_CLOCKWISE else "Clockwise (CW)"
	var is_transitioning_now = transition_timer < transition_duration
	return {
		"weather_state": get_weather_state_name(),
		"is_transitioning": is_transitioning_now,
		"auto_cycle_enabled": auto_weather_cycle_enabled,
		"tie_to_in_game_clock": tie_to_in_game_clock,
		"trajectory_name": get_weather_state_name(),
		"trajectory_progress": get_current_trajectory_progress(),
		"trajectory_time_remaining": get_current_trajectory_time_remaining(),
		"trajectory_duration": transition_duration,
		"queue_size": manual_queue.size() + (1 if not next_queued_weather_state.is_empty() else 0),
		"queue_items": get_queue_items_summary(),
		"climate_name": current_climate_name,
		"season_name": current_season_name,
		"surface_temperature_c": current_temperature_c,
		"is_snow_mode": is_snow_mode,
		"latitude_deg": latitude_deg,
		"yearly_precipitation_mm": yearly_precipitation_mm,
		"day_of_year": day_of_year,
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
