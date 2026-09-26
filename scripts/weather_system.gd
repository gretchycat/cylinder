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
var wind_velocity: Vector2 = Vector2.ZERO # (theta_rad_s, z_m_s)

var cloud_mesh_instance: MeshInstance3D = null
var cloud_material: ShaderMaterial = null

func _ready() -> void:
	add_to_group("weather_system")
	_recalculate_coriolis_vectors()
	_recalculate_thermodynamics()
	_build_cloud_mesh()
	_sync_with_scene_lighting()

func _process(delta: float) -> void:
	_update_dynamic_wind(delta)
	_update_shader_parameters()
	_emit_weather_telemetry()

func _recalculate_coriolis_vectors() -> void:
	# Rotational velocity for 1G / 9.5 m/s² at R = 4000m: Omega = sqrt(a / R)
	coriolis_omega_rad_s = sqrt(base_gravity / maxf(cylinder_radius, 1.0))
	var spin_sign = float(spin_direction)

	# Thermal updrafts from ground and end cap HVAC flow:
	# Rising air (vr < 0 towards axis) deflects in spin direction: a_theta = -2 * Omega * vr
	# Inflowing air from end caps (vz towards center) deflects into helical swirl
	var estimated_updraft_speed = 0.65 # m/s
	var coriolis_accel_theta = 2.0 * coriolis_omega_rad_s * estimated_updraft_speed * spin_sign

	coriolis_deflection_rate = coriolis_accel_theta
	# Wind velocity in shader space: (angular flow speed in radians/s, axial drift speed in z)
	wind_velocity = Vector2(0.008 * spin_sign, 0.002)

func _recalculate_thermodynamics() -> void:
	# Atmospheric physics inside closed cylinder:
	# Saturation vapor pressure (Tetens equation) at ground temperature
	var avg_ground_temp = (endcap_air_temperature_c * 0.45) + (water_pipe_temperature_c * 0.55)
	var es_hpa = 6.1078 * exp((17.27 * avg_ground_temp) / (avg_ground_temp + 237.3))
	var sat_vapor_density_gm3 = (216.7 * es_hpa) / (avg_ground_temp + 273.15) # Max g/m³ at saturation

	# Relative Humidity = (actual humidity density / saturation density) * 100
	relative_humidity_pct = clampf((humidity_density_gm3 / maxf(sat_vapor_density_gm3, 1.0)) * 100.0, 5.0, 100.0)

	# Dew point estimation (Magnus approximation)
	var a = 17.27
	var b = 237.7
	var alpha_val = ((a * avg_ground_temp) / (b + avg_ground_temp)) + log(relative_humidity_pct / 100.0)
	dew_point_c = (b * alpha_val) / (a - alpha_val)

	# Lifting Condensation Level (LCL): height where clouds form
	# Cloud base altitude z_cloud ≈ 125 * (T_ground - T_dew)
	var calculated_lcl = clampf(125.0 * (avg_ground_temp - dew_point_c), 950.0, 1550.0)
	cloud_altitude_m = calculated_lcl

	# Determine weather state from humidity density & relative humidity
	if relative_humidity_pct < 45.0:
		current_weather = WeatherType.CLEAR
		cloud_coverage = 0.15
	elif relative_humidity_pct < 65.0:
		current_weather = WeatherType.FAIR_CUMULUS
		cloud_coverage = 0.45
	elif relative_humidity_pct < 85.0:
		current_weather = WeatherType.SCATTERED_CLOUDS
		cloud_coverage = 0.70
	elif relative_humidity_pct < 95.0:
		current_weather = WeatherType.OVERCAST
		cloud_coverage = 0.88
	else:
		current_weather = WeatherType.RAIN_MIST
		cloud_coverage = 0.98

func _build_cloud_mesh() -> void:
	if cloud_mesh_instance and is_instance_valid(cloud_mesh_instance):
		cloud_mesh_instance.queue_free()

	cloud_mesh_instance = MeshInstance3D.new()
	cloud_mesh_instance.name = "CylinderCloudLayer"
	add_child(cloud_mesh_instance)

	# Load dedicated cloud shader
	var shader = load("res://assets/shaders/cylinder_clouds.gdshader") as Shader
	if shader:
		cloud_material = ShaderMaterial.new()
		cloud_material.shader = shader
		cloud_mesh_instance.material_override = cloud_material

	_generate_cloud_geometry()
	_update_shader_parameters()

func _generate_cloud_geometry() -> void:
	if not cloud_mesh_instance:
		return

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Cloud cylinder dimensions: radius = cylinder_radius - cloud_altitude_m (e.g. 4000 - 1250 = 2750m)
	var cloud_r = cylinder_radius - cloud_altitude_m
	var cloud_len = cylinder_length * 0.96 # Span 17.2 km across the cylinder
	var half_len = cloud_len * 0.5

	var radial_segs = 64
	var length_segs = 32
	var d_theta = TAU / float(radial_segs)
	var d_z = cloud_len / float(length_segs)

	for j in range(length_segs + 1):
		var z = -half_len + float(j) * d_z
		for i in range(radial_segs + 1):
			var theta = float(i) * d_theta
			var cos_t = cos(theta)
			var sin_t = sin(theta)

			var pos = Vector3(cloud_r * cos_t, cloud_r * sin_t, z)
			var normal = Vector3(-cos_t, -sin_t, 0.0)

			st.set_normal(normal)
			st.set_uv(Vector2(float(i) / float(radial_segs), float(j) / float(length_segs)))
			st.add_vertex(pos)

	var stride = radial_segs + 1
	for j in range(length_segs):
		for i in range(radial_segs):
			var i00 = j * stride + i
			var i10 = j * stride + (i + 1)
			var i01 = (j + 1) * stride + i
			var i11 = (j + 1) * stride + (i + 1)

			# Inward and outward visibility
			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i01)

			st.add_index(i10)
			st.add_index(i11)
			st.add_index(i01)

	st.generate_tangents()
	var mesh = st.commit()
	cloud_mesh_instance.mesh = mesh

func _update_cloud_mesh_radius() -> void:
	_generate_cloud_geometry()
	_update_shader_parameters()

func _update_dynamic_wind(delta: float) -> void:
	# Subtle dynamic fluctuation in Coriolis thermal wind field
	var spin_sign = float(spin_direction)
	var time_val = Time.get_ticks_msec() * 0.001
	var wind_fluct = sin(time_val * 0.2) * 0.001
	wind_velocity.x = (0.006 + wind_fluct) * spin_sign

func _update_shader_parameters() -> void:
	if not cloud_material:
		return

	cloud_material.set_shader_parameter("cylinder_radius", cylinder_radius)
	cloud_material.set_shader_parameter("cylinder_length", cylinder_length)
	cloud_material.set_shader_parameter("cloud_altitude", cloud_altitude_m)
	cloud_material.set_shader_parameter("humidity_density", humidity_density_gm3)
	cloud_material.set_shader_parameter("cloud_coverage", cloud_coverage)
	cloud_material.set_shader_parameter("coriolis_spin_direction", float(spin_direction))
	cloud_material.set_shader_parameter("wind_velocity", wind_velocity)

	# Axial light synchronization
	var light_bar = get_tree().get_first_node_in_group("light_bar") as AxisLightBar if is_inside_tree() else null
	if light_bar and light_bar.lut_texture:
		cloud_material.set_shader_parameter("axial_light_lut", light_bar.lut_texture)
		cloud_material.set_shader_parameter("axial_light_enabled", 1.0)
		cloud_material.set_shader_parameter("global_light_intensity", light_bar.global_intensity_multiplier)

func _sync_with_scene_lighting() -> void:
	_update_shader_parameters()

func set_spin_direction(is_ccw: bool) -> void:
	spin_direction = SpinDirection.COUNTER_CLOCKWISE if is_ccw else SpinDirection.CLOCKWISE
	_recalculate_coriolis_vectors()
	_update_shader_parameters()

func get_weather_state_name() -> String:
	match current_weather:
		WeatherType.CLEAR: return "Clear Sky"
		WeatherType.FAIR_CUMULUS: return "Fair Cumulus"
		WeatherType.SCATTERED_CLOUDS: return "Scattered Clouds"
		WeatherType.OVERCAST: return "Overcast"
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
		"cloud_radius_m": cylinder_radius - cloud_altitude_m,
		"cloud_coverage_pct": int(round(cloud_coverage * 100.0)),
		"spin_direction_name": spin_name,
		"coriolis_omega_rpm": (coriolis_omega_rad_s * 60.0) / TAU,
		"coriolis_deflection_deg_s": rad_to_deg(coriolis_deflection_rate)
	}

func _emit_weather_telemetry() -> void:
	weather_updated.emit(get_telemetry())
