class_name WeatherSystem
extends Node3D

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

var far_cloud_mesh_instance: MeshInstance3D = null
var near_cloud_mesh_instance: MeshInstance3D = null
var far_cloud_material: ShaderMaterial = null
var near_cloud_material: ShaderMaterial = null

# Localized Emitters tracking player position
var rain_particles: CPUParticles3D = null
var dust_particles: CPUParticles3D = null
var target_player: Node3D = null

func _ready() -> void:
	add_to_group("weather_system")
	_recalculate_coriolis_vectors()
	_recalculate_thermodynamics()
	_build_cloud_mesh()
	_setup_weather_emitters()
	_sync_with_scene_lighting()

func _process(delta: float) -> void:
	_update_dynamic_wind(delta)
	_update_shader_parameters()
	_update_particle_positions()
	_emit_weather_telemetry()

func _recalculate_coriolis_vectors() -> void:
	coriolis_omega_rad_s = sqrt(base_gravity / maxf(cylinder_radius, 1.0))
	var spin_sign = float(spin_direction)

	# Thermal updrafts from ground and end cap HVAC flow:
	var estimated_updraft_speed = 0.65 # m/s
	var coriolis_accel_theta = 2.0 * coriolis_omega_rad_s * estimated_updraft_speed * spin_sign

	coriolis_deflection_rate = coriolis_accel_theta
	wind_velocity = Vector2(0.008 * spin_sign, 0.002)

	# Precipitation Coriolis Tilt:
	# Rain drops falling outward away from axis (v_r > 0) accelerate retrograde:
	# a_coriolis_tangent = -2 * Omega * v_r * spin_sign
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

	# Determine weather state from humidity density & relative humidity
	if relative_humidity_pct < 45.0:
		current_weather = WeatherType.CLEAR
		if is_equal_approx(precipitation_rate_mmh, 0.0):
			cloud_coverage = 0.15
	elif relative_humidity_pct < 65.0:
		current_weather = WeatherType.FAIR_CUMULUS
		if is_equal_approx(precipitation_rate_mmh, 0.0):
			cloud_coverage = 0.45
	elif relative_humidity_pct < 85.0:
		current_weather = WeatherType.SCATTERED_CLOUDS
		if is_equal_approx(precipitation_rate_mmh, 0.0):
			cloud_coverage = 0.70
	elif relative_humidity_pct < 95.0:
		current_weather = WeatherType.OVERCAST
		if is_equal_approx(precipitation_rate_mmh, 0.0):
			cloud_coverage = 0.88
	else:
		current_weather = WeatherType.RAIN_MIST
		if is_equal_approx(precipitation_rate_mmh, 0.0):
			cloud_coverage = 0.98
			precipitation_rate_mmh = 12.0

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

	# Single continuous cylindrical shell geometry at cloud altitude
	var cloud_r = cylinder_radius - cloud_altitude_m
	var cloud_len = cylinder_length * 0.96
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

func _setup_weather_emitters() -> void:
	# 1. Coriolis-Deflected Precipitation Emitter (CPUParticles3D for robust performance)
	if not rain_particles:
		rain_particles = CPUParticles3D.new()
		rain_particles.name = "CoriolisRainParticles"
		rain_particles.amount = 800
		rain_particles.lifetime = 1.6
		rain_particles.preprocess = 0.5
		rain_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		rain_particles.emission_box_extents = Vector3(35.0, 35.0, 35.0)

		# Rain streak material
		var rain_mat = StandardMaterial3D.new()
		rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rain_mat.albedo_color = Color(0.75, 0.88, 1.0, 0.55)
		rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		rain_mat.render_priority = 10
		rain_particles.material_override = rain_mat

		var quad_mesh = QuadMesh.new()
		quad_mesh.size = Vector2(0.04, 0.75) # Elongated rain streak
		rain_particles.draw_pass_1 = quad_mesh
		add_child(rain_particles)

	# 2. Atmospheric Dust Motes & Sunbeam Particulate Emitter
	if not dust_particles:
		dust_particles = CPUParticles3D.new()
		dust_particles.name = "AtmosphericDustParticles"
		dust_particles.amount = 300
		dust_particles.lifetime = 6.0
		dust_particles.preprocess = 1.0
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
		dust_mat.albedo_color = Color(0.95, 0.90, 0.78, 0.4)
		dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		dust_mat.render_priority = 10
		dust_particles.material_override = dust_mat

		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.03
		sphere_mesh.height = 0.06
		dust_particles.draw_pass_1 = sphere_mesh
		add_child(dust_particles)

	_update_precipitation_emitter()
	_update_dust_emitter()

func _update_precipitation_emitter() -> void:
	if not rain_particles:
		return

	if precipitation_rate_mmh <= 0.05:
		rain_particles.emitting = false
		return

	rain_particles.emitting = true
	var intensity_norm = clampf(precipitation_rate_mmh / 40.0, 0.05, 1.0)
	rain_particles.amount = int(lerpf(150.0, 1500.0, intensity_norm))

	# Update rain fall speed and retrograde Coriolis drift
	var spin_sign = float(spin_direction)
	var fall_speed = lerpf(10.0, 22.0, intensity_norm)
	var coriolis_drift = -2.0 * coriolis_omega_rad_s * fall_speed * spin_sign

	rain_particles.initial_velocity_min = fall_speed * 0.9
	rain_particles.initial_velocity_max = fall_speed * 1.1

func _update_dust_emitter() -> void:
	if not dust_particles:
		return

	if dust_density <= 0.02:
		dust_particles.emitting = false
		return

	dust_particles.emitting = true
	dust_particles.amount = int(lerpf(50.0, 600.0, dust_density))
	var dust_mat = dust_particles.material_override as StandardMaterial3D
	if dust_mat:
		dust_mat.albedo_color = Color(0.95, 0.90, 0.78, clampf(dust_density * 0.5, 0.1, 0.7))

func _update_particle_positions() -> void:
	if not target_player or not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as Node3D
		if not target_player:
			return

	var p_pos = target_player.global_position
	# Center emitters around player
	if rain_particles and rain_particles.emitting:
		rain_particles.global_position = p_pos

		# In cylindrical geometry, "Down" points radially outward: normalize(x, y, 0)
		var r_vec = Vector2(p_pos.x, p_pos.y)
		var r_dir = r_vec.normalized() if r_vec.length_squared() > 1.0 else Vector2(0, -1)
		var down_3d = Vector3(r_dir.x, r_dir.y, 0.0)

		# Tangent vector in habitat: (-y, x, 0)
		var tangent_3d = Vector3(-r_dir.y, r_dir.x, 0.0)
		var spin_sign = float(spin_direction)

		# Rain particle gravity vector combines outward centrifugal gravity and retrograde Coriolis tilt
		var gravity_mag = base_gravity * 2.5
		var coriolis_mag = 2.0 * coriolis_omega_rad_s * 15.0 * spin_sign * 2.5
		rain_particles.gravity = (down_3d * gravity_mag) - (tangent_3d * coriolis_mag)

	if dust_particles and dust_particles.emitting:
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
		"coriolis_rain_tilt_deg": coriolis_rain_tilt_deg
	}

func _emit_weather_telemetry() -> void:
	weather_updated.emit(get_telemetry())
