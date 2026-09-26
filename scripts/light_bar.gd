@tool
class_name AxisLightBar
extends Node3D

const SolarCycleSimulator = preload("res://scripts/solar_cycle_simulator.gd")

enum LightingPreset {
	UNIFORM,
	GRADIENT,
	DAY_NIGHT_WAVE,
	NEON_AURORA,
	WARM_SUNSET,
	SOLAR_CYCLE
}

@export_category("Dimensions (18 km Scale)")
@export var bar_length: float = 18000.0:
	set(val):
		bar_length = max(val, 10.0)
		if is_inside_tree():
			rebuild_light_bar()

@export var cylinder_radius: float = 4000.0:
	set(val):
		cylinder_radius = max(val, 5.0)
		if is_inside_tree():
			_update_light_ranges()

@export var num_segments: int = 36:
	set(val):
		num_segments = clampi(val, 2, 64)
		if is_inside_tree():
			rebuild_light_bar()

@export var bar_radius: float = 35.0:
	set(val):
		bar_radius = max(val, 0.5)
		if is_inside_tree():
			rebuild_light_bar()

@export_category("Solar Day/Night Cycle (Earth Latitude)")
@export var use_real_time: bool = true:
	set(val):
		if use_real_time == val:
			return
		use_real_time = val
		if use_real_time and is_inside_tree():
			sync_to_system_clock()

@export var time_scale: float = 1.0: # Progression multiplier for manual time (1.0 = real-time, 60.0 = 1 min/sec)
	set(val):
		time_scale = maxf(val, 0.0)

@export var earth_latitude_deg: float = 40.0:
	set(val):
		earth_latitude_deg = clampf(val, -90.0, 90.0)
		if is_inside_tree():
			_apply_current_preset()

@export var time_of_day_hours: float = 12.0:
	set(val):
		var new_val = fposmod(val, 24.0)
		if is_equal_approx(time_of_day_hours, new_val):
			return
		time_of_day_hours = new_val
		if is_inside_tree():
			_apply_current_preset()

@export var day_of_year: int = 0: # 0 = auto from system date
	set(val):
		if day_of_year == val:
			return
		day_of_year = clampi(val, 0, 366)
		if is_inside_tree():
			_apply_current_preset()

@export var solar_span_hours: float = 1.5:
	set(val):
		solar_span_hours = maxf(val, 0.0)
		if is_inside_tree():
			_apply_current_preset()

@export var gradient_follows_solar_cycle: bool = true:
	set(val):
		gradient_follows_solar_cycle = val
		if is_inside_tree():
			_apply_current_preset()

@export var uniform_follows_solar_cycle: bool = false:
	set(val):
		uniform_follows_solar_cycle = val
		if is_inside_tree():
			_apply_current_preset()

@export_category("Lighting Control - Max On Full Illumination")
@export var preset: LightingPreset = LightingPreset.GRADIENT:
	set(val):
		if preset != val:
			use_custom_extent = false
		preset = val
		_apply_current_preset()

@export var global_intensity_multiplier: float = 3.5:
	set(val):
		global_intensity_multiplier = max(val, 0.0)
		_refresh_all_segments()
		if is_inside_tree():
			_sync_fog_and_atmosphere()

@export var start_color: Color = Color(1.0, 0.98, 0.95) # Clean daylight
@export var end_color: Color = Color(0.96, 0.98, 1.0)
@export var start_intensity: float = 3.5
@export var end_intensity: float = 3.5

@export var wave_speed: float = 0.5
@export var enable_shadows: bool = false:
	set(val):
		enable_shadows = val
		_update_shadows()

# Internal segment data
var segment_colors: Array[Color] = []
var segment_intensities: Array[float] = []
var use_custom_extent: bool = false

var segment_nodes: Array[MeshInstance3D] = []
var light_nodes: Array[OmniLight3D] = []
var truss_node: MeshInstance3D

var sun_lights: Array[DirectionalLight3D] = []
var world_environment: WorldEnvironment = null

var lut_image: Image = null
var lut_texture: ImageTexture = null

var wave_time: float = 0.0
var current_avg_color: Color = Color(1.0, 0.98, 0.95)
var current_avg_intensity: float = 3.5
var last_cam_z: float = -99999.0
var solar_info: Dictionary = {}

func _get_effective_day_of_year() -> int:
	if day_of_year > 0:
		return day_of_year
	var d_dict = Time.get_date_dict_from_system()
	return SolarCycleSimulator.get_day_of_year(d_dict["year"], d_dict["month"], d_dict["day"])

func _get_system_time_hours() -> float:
	var t_dict = Time.get_time_dict_from_system()
	return float(t_dict["hour"]) + float(t_dict["minute"]) / 60.0 + float(t_dict["second"]) / 3600.0

func _ready() -> void:
	add_to_group("light_bar")
	if use_real_time:
		time_of_day_hours = _get_system_time_hours()
	_find_global_lighting()
	rebuild_light_bar()
	_apply_lut_to_materials.call_deferred()
	_sync_fog_and_atmosphere.call_deferred()

func _find_global_lighting() -> void:
	if not is_inside_tree():
		return
	sun_lights.clear()
	var parent_node = get_parent()
	if parent_node:
		for child in parent_node.get_children():
			if child is DirectionalLight3D:
				sun_lights.append(child)
			elif child is WorldEnvironment:
				world_environment = child
	if not world_environment:
		world_environment = get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment

func rebuild_light_bar() -> void:
	# Clear existing children
	for child in get_children():
		child.queue_free()

	segment_nodes.clear()
	light_nodes.clear()
	segment_colors.clear()
	segment_intensities.clear()

	# 1. Build Central Truss Spine (Dark structural backbone)
	var spine_mesh = CylinderMesh.new()
	spine_mesh.top_radius = bar_radius * 0.45
	spine_mesh.bottom_radius = bar_radius * 0.45
	spine_mesh.height = bar_length + cylinder_radius * 2.0 - 80.0  # Reaches into end cap poles (±half_len ± cylinder_radius)
	spine_mesh.radial_segments = 24

	var spine_mat = StandardMaterial3D.new()
	spine_mat.albedo_color = Color(0.12, 0.13, 0.16)
	spine_mat.metallic = 0.85
	spine_mat.roughness = 0.25

	truss_node = MeshInstance3D.new()
	truss_node.name = "CentralTruss"
	truss_node.mesh = spine_mesh
	truss_node.material_override = spine_mat
	truss_node.rotation_degrees = Vector3(90, 0, 0)
	add_child(truss_node)

	# 2. Build Light Segments along Z axis
	var segment_length = bar_length / float(num_segments)
	var half_len = bar_length * 0.5

	for i in range(num_segments):
		var z_pos = -half_len + (float(i) + 0.5) * segment_length

		# Glowing tube segment
		var tube_mesh = CylinderMesh.new()
		tube_mesh.top_radius = bar_radius
		tube_mesh.bottom_radius = bar_radius
		tube_mesh.height = segment_length * 0.94
		tube_mesh.radial_segments = 32

		var seg_mat = StandardMaterial3D.new()
		seg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		seg_mat.albedo_color = Color.WHITE
		seg_mat.emission_enabled = true
		seg_mat.emission = Color.WHITE
		seg_mat.emission_energy_multiplier = 4.0

		var seg_mesh_inst = MeshInstance3D.new()
		seg_mesh_inst.name = "SegmentMesh_%d" % i
		seg_mesh_inst.mesh = tube_mesh
		seg_mesh_inst.material_override = seg_mat
		seg_mesh_inst.rotation_degrees = Vector3(90, 0, 0)
		seg_mesh_inst.position = Vector3(0, 0, z_pos)
		add_child(seg_mesh_inst)
		segment_nodes.append(seg_mesh_inst)

		# Initial values
		segment_colors.append(Color.WHITE)
		segment_intensities.append(1.0)

	# 2 broad axial omni lights (South and North halves) to illuminate the cylinder
	# while leaving room in Godot's light cluster budget for local surface lights (campfires, lamps)
	for k in range(2):
		var z_axial = -half_len * 0.5 if k == 0 else half_len * 0.5
		var light = OmniLight3D.new()
		light.name = "AxialLight_%s" % ("South" if k == 0 else "North")
		light.position = Vector3(0, 0, z_axial)
		light.omni_range = cylinder_radius * 2.5
		light.omni_attenuation = 1.0
		light.shadow_enabled = false
		add_child(light)
		light_nodes.append(light)

	_apply_current_preset()

func _process(delta: float) -> void:
	if use_real_time:
		var cur_h = _get_system_time_hours()
		if absf(cur_h - time_of_day_hours) > 0.0001:
			time_of_day_hours = cur_h
			if (preset == LightingPreset.GRADIENT and gradient_follows_solar_cycle) or preset == LightingPreset.SOLAR_CYCLE or (preset == LightingPreset.UNIFORM and uniform_follows_solar_cycle):
				_apply_current_preset()
	elif time_scale > 0.0:
		var dh = (delta * time_scale) / 3600.0
		time_of_day_hours = fposmod(time_of_day_hours + dh, 24.0)
		if (preset == LightingPreset.GRADIENT and gradient_follows_solar_cycle) or preset == LightingPreset.SOLAR_CYCLE or (preset == LightingPreset.UNIFORM and uniform_follows_solar_cycle):
			_apply_current_preset()

	if preset == LightingPreset.DAY_NIGHT_WAVE or preset == LightingPreset.NEON_AURORA:
		wave_time += delta * wave_speed
		_update_animated_wave()
	elif preset == LightingPreset.GRADIENT or preset == LightingPreset.SOLAR_CYCLE:
		var cam_z = _get_camera_z()
		if absf(cam_z - last_cam_z) > 15.0:
			last_cam_z = cam_z
			_sync_fog_and_atmosphere()

func _apply_current_preset() -> void:
	if segment_colors.size() != num_segments:
		return

	match preset:
		LightingPreset.UNIFORM:
			if uniform_follows_solar_cycle:
				var p = SolarCycleSimulator.get_solar_lighting_at_time(
					earth_latitude_deg,
					_get_effective_day_of_year(),
					time_of_day_hours
				)
				solar_info = p
				for i in range(num_segments):
					segment_colors[i] = p["sun_color"]
					segment_intensities[i] = p["intensity"]
			else:
				for i in range(num_segments):
					segment_colors[i] = Color(1.0, 0.98, 0.95)
					segment_intensities[i] = 3.5

		LightingPreset.GRADIENT:
			if use_custom_extent:
				for i in range(num_segments):
					var t = float(i) / max(float(num_segments - 1), 1.0)
					segment_colors[i] = start_color.lerp(end_color, t)
					segment_intensities[i] = lerpf(start_intensity, end_intensity, t)
			elif gradient_follows_solar_cycle:
				var grad = SolarCycleSimulator.get_cylinder_axial_gradient(
					earth_latitude_deg,
					_get_effective_day_of_year(),
					time_of_day_hours,
					num_segments,
					solar_span_hours
				)
				segment_colors = grad["segment_colors"]
				segment_intensities = grad["segment_intensities"]
				solar_info = grad
			else:
				# Multi-stop Sunrise to Twilight gradient along the 18 km cylinder
				var col_dawn = Color(1.0, 0.52, 0.18)     # Dawn Golden Orange
				var col_morning = Color(1.0, 0.88, 0.65)  # Warm Morning Gold
				var col_noon = Color(0.98, 0.98, 1.0)     # Clean High Noon
				var col_dusk = Color(0.65, 0.35, 0.75)    # Evening Dusk Violet
				var col_night = Color(0.08, 0.16, 0.38)   # Deep Twilight Sapphire

				for i in range(num_segments):
					var t = float(i) / max(float(num_segments - 1), 1.0)
					var col: Color
					var intensity: float
					if t < 0.25:
						col = col_dawn.lerp(col_morning, t / 0.25)
						intensity = lerpf(2.5, 3.5, t / 0.25)
					elif t < 0.55:
						col = col_morning.lerp(col_noon, (t - 0.25) / 0.30)
						intensity = 3.5
					elif t < 0.80:
						col = col_noon.lerp(col_dusk, (t - 0.55) / 0.25)
						intensity = lerpf(3.5, 2.0, (t - 0.55) / 0.25)
					else:
						col = col_dusk.lerp(col_night, (t - 0.80) / 0.20)
						intensity = lerpf(2.0, 0.5, (t - 0.80) / 0.20)

					segment_colors[i] = col
					segment_intensities[i] = intensity

		LightingPreset.SOLAR_CYCLE:
			var grad = SolarCycleSimulator.get_cylinder_axial_gradient(
				earth_latitude_deg,
				_get_effective_day_of_year(),
				time_of_day_hours,
				num_segments,
				solar_span_hours
			)
			segment_colors = grad["segment_colors"]
			segment_intensities = grad["segment_intensities"]
			solar_info = grad

		LightingPreset.WARM_SUNSET:
			var sunset_amber = Color(1.0, 0.48, 0.15)
			var sunset_gold = Color(1.0, 0.85, 0.45)
			var sunset_crimson = Color(0.92, 0.25, 0.35)
			var sunset_twilight = Color(0.18, 0.28, 0.75)
			for i in range(num_segments):
				var t = float(i) / max(float(num_segments - 1), 1.0)
				var col: Color
				if t < 0.35:
					col = sunset_amber.lerp(sunset_gold, t / 0.35)
				elif t < 0.70:
					col = sunset_gold.lerp(sunset_crimson, (t - 0.35) / 0.35)
				else:
					col = sunset_crimson.lerp(sunset_twilight, (t - 0.70) / 0.30)
				segment_colors[i] = col
				segment_intensities[i] = lerpf(3.5, 1.8, t)

		LightingPreset.NEON_AURORA, LightingPreset.DAY_NIGHT_WAVE:
			_update_animated_wave()
			return

	_refresh_all_segments()

func _update_animated_wave() -> void:
	for i in range(num_segments):
		var t = float(i) / float(num_segments)
		var phase = t * TAU * 1.5 - wave_time * TAU

		if preset == LightingPreset.DAY_NIGHT_WAVE:
			var wave_factor = (sin(phase) + 1.0) * 0.5
			var col_night = Color(0.322, 0.306, 0.613)
			var col_day = Color(1.0, 0.96, 0.90)
			var col = col_night.lerp(col_day, wave_factor)
			var intensity = lerpf(0.0, 4.0, wave_factor)
			segment_colors[i] = col
			segment_intensities[i] = intensity
		elif preset == LightingPreset.NEON_AURORA:
			var hue = fposmod(t + wave_time * 0.2, 1.0)
			var col = Color.from_hsv(hue, 0.85, 1.0)
			var intensity = 2.0 + 1.5 * sin(phase)
			segment_colors[i] = col
			segment_intensities[i] = intensity

	_refresh_all_segments()

func _refresh_all_segments() -> void:
	_find_global_lighting()

	var avg_col = Color.BLACK
	var avg_intensity = 0.0
	var count = min(segment_nodes.size(), num_segments)
	var intensity_norm = global_intensity_multiplier / 3.5

	for i in range(count):
		var col = segment_colors[i]
		var energy = segment_intensities[i] * intensity_norm

		# Update mesh emission
		var mesh_inst = segment_nodes[i]
		var mat = mesh_inst.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = col
			mat.emission = col
			mat.emission_energy_multiplier = energy * 1.5

		avg_col += col
		avg_intensity += segment_intensities[i]

	if count > 0:
		avg_col = Color(avg_col.r / float(count), avg_col.g / float(count), avg_col.b / float(count), 1.0)
		avg_intensity /= float(count)

	# Update 2 broad axial lights (South and North)
	if light_nodes.size() >= 2 and count > 0:
		var half_count = count / 2
		var south_col = Color.BLACK
		var south_inten = 0.0
		var north_col = Color.BLACK
		var north_inten = 0.0
		for i in range(half_count):
			south_col += segment_colors[i]
			south_inten += segment_intensities[i]
		for i in range(half_count, count):
			north_col += segment_colors[i]
			north_inten += segment_intensities[i]
		if half_count > 0:
			south_col = south_col / float(half_count)
			south_inten = south_inten / float(half_count)
		var north_count = count - half_count
		if north_count > 0:
			north_col = north_col / float(north_count)
			north_inten = north_inten / float(north_count)
		light_nodes[0].light_color = south_col
		light_nodes[0].light_energy = south_inten * intensity_norm * 1.5
		light_nodes[1].light_color = north_col
		light_nodes[1].light_energy = north_inten * intensity_norm * 1.5

	current_avg_color = avg_col
	current_avg_intensity = avg_intensity

	# Synchronize scene directional sun lights with intensity and preset color
	for sun in sun_lights:
		sun.light_color = avg_col
		sun.light_energy = 1.8 * intensity_norm

	# Synchronize scene ambient lighting with intensity and preset color
	if world_environment and world_environment.environment:
		var env = world_environment.environment
		env.ambient_light_color = avg_col
		env.ambient_light_energy = 1.0 * intensity_norm

	# Synchronize depth fog and material air tint with current light level and color
	_sync_fog_and_atmosphere()

	_update_axial_lut()

func _update_axial_lut() -> void:
	if num_segments <= 0 or segment_colors.size() < num_segments:
		return
	if not lut_image or lut_image.get_width() != num_segments:
		lut_image = Image.create(num_segments, 1, false, Image.FORMAT_RGBA8)
		lut_texture = null

	for i in range(num_segments):
		var c = segment_colors[i]
		var intensity_factor = clampf(segment_intensities[i] / 3.5, 0.0, 1.5)
		lut_image.set_pixel(i, 0, Color(c.r, c.g, c.b, intensity_factor))

	if not lut_texture:
		lut_texture = ImageTexture.create_from_image(lut_image)
	else:
		lut_texture.update(lut_image)

	_apply_lut_to_materials()

func _apply_lut_to_materials() -> void:
	if not is_inside_tree() or not lut_texture:
		return
	var cylinder_world = get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator
	if cylinder_world:
		if cylinder_world.surface_material is ShaderMaterial:
			cylinder_world.surface_material.set_shader_parameter("axial_light_lut", lut_texture)
			cylinder_world.surface_material.set_shader_parameter("cylinder_length", bar_length)
		if cylinder_world.water_material is ShaderMaterial:
			cylinder_world.water_material.set_shader_parameter("axial_light_lut", lut_texture)
			cylinder_world.water_material.set_shader_parameter("cylinder_length", bar_length)

func _get_camera_z() -> float:
	if not is_inside_tree():
		return 0.0
	var viewport = get_viewport()
	if viewport:
		var cam = viewport.get_camera_3d()
		if cam:
			return cam.global_position.z
	return 0.0

func get_light_at_z(z: float) -> Dictionary:
	if num_segments <= 0 or segment_colors.is_empty():
		return {"color": Color(1.0, 0.98, 0.95), "intensity": 3.5}
	var half_len = bar_length * 0.5
	var t = clampf((z + half_len) / bar_length, 0.0, 1.0)
	var seg_idx = t * float(num_segments - 1)
	var idx0 = clampi(int(floor(seg_idx)), 0, num_segments - 1)
	var idx1 = clampi(int(ceil(seg_idx)), 0, num_segments - 1)
	var frac = seg_idx - float(idx0)
	var col = segment_colors[idx0].lerp(segment_colors[idx1], frac)
	var inten = lerpf(segment_intensities[idx0], segment_intensities[idx1], frac)
	return {"color": col, "intensity": inten}

func get_effective_fog_properties() -> Dictionary:
	var intensity_norm = global_intensity_multiplier / 3.5

	var effective_light_col = current_avg_color
	var effective_intensity = current_avg_intensity

	if preset == LightingPreset.GRADIENT or preset == LightingPreset.SOLAR_CYCLE:
		var cam_z = _get_camera_z()
		var local_light = get_light_at_z(cam_z)
		effective_light_col = current_avg_color.lerp(local_light.color, 0.65)
		effective_intensity = lerpf(current_avg_intensity, local_light.intensity, 0.65)

	var local_norm = (effective_intensity / 3.5) * intensity_norm

	# Atmospheric Rayleigh scattered fog tint calculated from current light color
	# In nominal daylight (Color(1.0, 0.98, 0.95)), this yields exactly Color(0.52, 0.72, 0.88, 1.0)
	var light_r_ratio = clampf(effective_light_col.r / 1.00, 0.0, 3.0)
	var light_g_ratio = clampf(effective_light_col.g / 0.98, 0.0, 3.0)
	var light_b_ratio = clampf(effective_light_col.b / 0.95, 0.0, 3.0)

	var fog_col = Color(
		clampf(0.52 * light_r_ratio, 0.05, 1.0),
		clampf(0.72 * light_g_ratio, 0.05, 1.0),
		clampf(0.88 * light_b_ratio, 0.08, 1.0),
		1.0
	)
	var fog_energy = clampf(lerpf(0.35, 1.0, intensity_norm), 0.35, 1.0)

	return {
		"fog_color": fog_col,
		"fog_energy": fog_energy,
		"light_color": effective_light_col,
		"intensity_norm": intensity_norm
	}

func _sync_fog_and_atmosphere() -> void:
	_find_global_lighting()
	var fog_props = get_effective_fog_properties()
	var fog_col = fog_props["fog_color"] as Color
	var fog_energy = fog_props["fog_energy"] as float
	var intensity_norm = fog_props["intensity_norm"] as float

	# Declare cylinder_world once here to avoid illegal forward references below
	var cylinder_world = get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator if is_inside_tree() else null

	if world_environment and world_environment.environment:
		var env = world_environment.environment
		env.fog_light_color = fog_col
		env.fog_light_energy = fog_energy
		env.fog_depth_curve = 1.1
		env.fog_depth_begin = 200.0
		# Update end‑cap emission based on scene brightness
		if cylinder_world and cylinder_world.surface_material is ShaderMaterial:
			cylinder_world.surface_material.set_shader_parameter("endcap_emission_factor", intensity_norm)

	if cylinder_world:
		cylinder_world.air_color = fog_col

func _update_light_ranges() -> void:
	for light in light_nodes:
		light.omni_range = cylinder_radius * 2.0

func _update_shadows() -> void:
	for light in light_nodes:
		light.shadow_enabled = enable_shadows

# Public API for setting individual segment properties
func set_segment(index: int, color: Color, intensity: float) -> void:
	if index >= 0 and index < num_segments:
		segment_colors[index] = color
		segment_intensities[index] = intensity
		_refresh_all_segments()

func set_all_segments(color: Color, intensity: float) -> void:
	for i in range(num_segments):
		segment_colors[i] = color
		segment_intensities[i] = intensity
	_refresh_all_segments()

func set_extent_gradient(col_a: Color, col_b: Color, intensity_a: float, intensity_b: float) -> void:
	start_color = col_a
	end_color = col_b
	start_intensity = intensity_a
	end_intensity = intensity_b
	preset = LightingPreset.GRADIENT
	use_custom_extent = true
	_apply_current_preset()

func set_time_of_day(hours: float, manual: bool = true) -> void:
	time_of_day_hours = fposmod(hours, 24.0)
	if manual:
		use_real_time = false
	_apply_current_preset()

func sync_to_system_clock() -> void:
	use_real_time = true
	var d_dict = Time.get_date_dict_from_system()
	day_of_year = SolarCycleSimulator.get_day_of_year(d_dict["year"], d_dict["month"], d_dict["day"])
	time_of_day_hours = _get_system_time_hours()
	_apply_current_preset()

func set_earth_latitude(lat_deg: float) -> void:
	earth_latitude_deg = clampf(lat_deg, -90.0, 90.0)
	_apply_current_preset()

func get_solar_status() -> Dictionary:
	var doy = _get_effective_day_of_year()
	var t = time_of_day_hours
	var elev = SolarCycleSimulator.calculate_solar_elevation(earth_latitude_deg, doy, t)
	var az = SolarCycleSimulator.calculate_solar_azimuth(earth_latitude_deg, doy, t)
	var lighting = SolarCycleSimulator.get_solar_lighting_at_time(earth_latitude_deg, doy, t)
	return {
		"time_hours": t,
		"latitude": earth_latitude_deg,
		"day_of_year": doy,
		"solar_elevation": elev,
		"solar_azimuth": az,
		"phase_name": lighting["phase_name"],
		"sun_color": lighting["sun_color"],
		"intensity": lighting["intensity"],
		"is_real_time": use_real_time,
		"time_scale": time_scale
	}
