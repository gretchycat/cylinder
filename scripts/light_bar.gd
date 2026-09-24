@tool
class_name AxisLightBar
extends Node3D

enum LightingPreset {
	UNIFORM,
	GRADIENT,
	DAY_NIGHT_WAVE,
	NEON_AURORA,
	WARM_SUNSET
}

@export_category("Dimensions")
@export var bar_length: float = 300.0:
	set(val):
		bar_length = max(val, 10.0)
		if is_inside_tree():
			rebuild_light_bar()

@export var cylinder_radius: float = 80.0:
	set(val):
		cylinder_radius = max(val, 5.0)
		if is_inside_tree():
			_update_light_ranges()

@export var num_segments: int = 12:
	set(val):
		num_segments = clampi(val, 2, 32)
		if is_inside_tree():
			rebuild_light_bar()

@export var bar_radius: float = 1.2:
	set(val):
		bar_radius = max(val, 0.1)
		if is_inside_tree():
			rebuild_light_bar()

@export_category("Lighting Control")
@export var preset: LightingPreset = LightingPreset.GRADIENT:
	set(val):
		preset = val
		_apply_current_preset()

@export var global_intensity_multiplier: float = 1.8:
	set(val):
		global_intensity_multiplier = max(val, 0.0)
		_refresh_all_segments()

@export var start_color: Color = Color(1.0, 0.85, 0.65) # Warm dawn/sunrise
@export var end_color: Color = Color(0.45, 0.7, 1.0)     # Cool daylight/dusk
@export var start_intensity: float = 2.0
@export var end_intensity: float = 1.2

@export var wave_speed: float = 0.5
@export var enable_shadows: bool = false:
	set(val):
		enable_shadows = val
		_update_shadows()

# Internal segment data
var segment_colors: Array[Color] = []
var segment_intensities: Array[float] = []

var segment_nodes: Array[MeshInstance3D] = []
var light_nodes: Array[OmniLight3D] = []
var truss_node: MeshInstance3D

var wave_time: float = 0.0

func _ready() -> void:
	rebuild_light_bar()

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
	spine_mesh.height = bar_length * 1.02
	spine_mesh.radial_segments = 16

	var spine_mat = StandardMaterial3D.new()
	spine_mat.albedo_color = Color(0.12, 0.13, 0.16)
	spine_mat.metallic = 0.85
	spine_mat.roughness = 0.25

	truss_node = MeshInstance3D.new()
	truss_node.name = "CentralTruss"
	truss_node.mesh = spine_mesh
	truss_node.material_override = spine_mat
	# Godot CylinderMesh is aligned along Y axis by default; rotate 90 deg around X to align with Z axis
	truss_node.rotation_degrees = Vector3(90, 0, 0)
	add_child(truss_node)

	# 2. Build Light Segments along Z axis
	var segment_length = bar_length / float(num_segments)
	var half_len = bar_length * 0.5

	for i in range(num_segments):
		# Z center for segment i
		var z_pos = -half_len + (float(i) + 0.5) * segment_length

		# Glowing tube segment
		var tube_mesh = CylinderMesh.new()
		tube_mesh.top_radius = bar_radius
		tube_mesh.bottom_radius = bar_radius
		tube_mesh.height = segment_length * 0.92 # Small gap between segments for visual modularity
		tube_mesh.radial_segments = 24

		var seg_mat = StandardMaterial3D.new()
		seg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		seg_mat.albedo_color = Color.WHITE
		seg_mat.emission_enabled = true
		seg_mat.emission = Color.WHITE
		seg_mat.emission_energy_multiplier = 2.0

		var seg_mesh_inst = MeshInstance3D.new()
		seg_mesh_inst.name = "SegmentMesh_%d" % i
		seg_mesh_inst.mesh = tube_mesh
		seg_mesh_inst.material_override = seg_mat
		seg_mesh_inst.rotation_degrees = Vector3(90, 0, 0)
		seg_mesh_inst.position = Vector3(0, 0, z_pos)
		add_child(seg_mesh_inst)
		segment_nodes.append(seg_mesh_inst)

		# OmniLight3D emitter at this segment
		var light = OmniLight3D.new()
		light.name = "SegmentLight_%d" % i
		light.position = Vector3(0, 0, z_pos)
		light.omni_range = cylinder_radius * 1.55
		light.omni_attenuation = 1.1
		light.shadow_enabled = enable_shadows
		add_child(light)
		light_nodes.append(light)

		# Initial values
		segment_colors.append(Color.WHITE)
		segment_intensities.append(1.0)

	_apply_current_preset()

func _process(delta: float) -> void:
	if preset == LightingPreset.DAY_NIGHT_WAVE or preset == LightingPreset.NEON_AURORA:
		wave_time += delta * wave_speed
		_update_animated_wave()

func _apply_current_preset() -> void:
	if segment_colors.size() != num_segments:
		return

	match preset:
		LightingPreset.UNIFORM:
			for i in range(num_segments):
				segment_colors[i] = start_color
				segment_intensities[i] = start_intensity

		LightingPreset.GRADIENT:
			for i in range(num_segments):
				var t = float(i) / max(float(num_segments - 1), 1.0)
				segment_colors[i] = start_color.lerp(end_color, t)
				segment_intensities[i] = lerpf(start_intensity, end_intensity, t)

		LightingPreset.WARM_SUNSET:
			var sunset_start = Color(1.0, 0.45, 0.15) # Intense amber/orange
			var sunset_mid = Color(1.0, 0.85, 0.5)   # Golden center
			var sunset_end = Color(0.2, 0.4, 0.9)    # Twilight deep blue
			for i in range(num_segments):
				var t = float(i) / max(float(num_segments - 1), 1.0)
				var col: Color
				if t < 0.5:
					col = sunset_start.lerp(sunset_mid, t * 2.0)
				else:
					col = sunset_mid.lerp(sunset_end, (t - 0.5) * 2.0)
				segment_colors[i] = col
				segment_intensities[i] = lerpf(2.2, 1.4, t)

		LightingPreset.NEON_AURORA, LightingPreset.DAY_NIGHT_WAVE:
			_update_animated_wave()
			return

	_refresh_all_segments()

func _update_animated_wave() -> void:
	for i in range(num_segments):
		var t = float(i) / float(num_segments)
		var phase = t * TAU * 1.5 - wave_time * TAU

		if preset == LightingPreset.DAY_NIGHT_WAVE:
			# Shifting wave of daylight down the cylinder
			var wave_factor = (sin(phase) + 1.0) * 0.5
			var col = start_color.lerp(end_color, wave_factor)
			var intensity = lerpf(0.5, 2.5, wave_factor)
			segment_colors[i] = col
			segment_intensities[i] = intensity
		elif preset == LightingPreset.NEON_AURORA:
			# Shifting neon spectrum
			var hue = fposmod(t + wave_time * 0.2, 1.0)
			var col = Color.from_hsv(hue, 0.8, 1.0)
			var intensity = 1.5 + 0.8 * sin(phase)
			segment_colors[i] = col
			segment_intensities[i] = intensity

	_refresh_all_segments()

func _refresh_all_segments() -> void:
	for i in range(min(segment_nodes.size(), num_segments)):
		var col = segment_colors[i]
		var energy = segment_intensities[i] * global_intensity_multiplier

		# Update mesh emission
		var mesh_inst = segment_nodes[i]
		var mat = mesh_inst.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = col
			mat.emission = col
			mat.emission_energy_multiplier = energy * 1.5

		# Update omni light
		if i < light_nodes.size():
			var light = light_nodes[i]
			light.light_color = col
			light.light_energy = energy

func _update_light_ranges() -> void:
	for light in light_nodes:
		light.omni_range = cylinder_radius * 1.55

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
	_apply_current_preset()
