@tool
class_name SurfaceLightObject
extends Node3D

enum ObjectType {
	CAMPFIRE,
	LAMP_POST,
	BEACON_LANTERN
}

@export var object_type: ObjectType = ObjectType.CAMPFIRE:
	set(val):
		object_type = val
		if is_inside_tree():
			rebuild_object()

@export var light_color: Color = Color(1.0, 0.58, 0.22):
	set(val):
		light_color = val
		if omni_light:
			omni_light.light_color = light_color

@export var light_energy: float = 5.5:
	set(val):
		light_energy = max(val, 0.0)
		base_energy = light_energy
		if omni_light:
			omni_light.light_energy = light_energy

@export var light_range: float = 55.0:
	set(val):
		light_range = max(val, 1.0)
		if omni_light:
			omni_light.omni_range = light_range

@export var enable_flicker: bool = true

var omni_light: OmniLight3D = null
var flame_nodes: Array[Node3D] = []
var flame_mats: Array[StandardMaterial3D] = []
var base_energy: float = 5.5
var flicker_time: float = 0.0
var rng_offset: float = 0.0

func _ready() -> void:
	rng_offset = randf_range(0.0, 100.0)
	flicker_time = rng_offset
	rebuild_object()

func rebuild_object() -> void:
	for child in get_children():
		child.queue_free()

	flame_nodes.clear()
	flame_mats.clear()

	match object_type:
		ObjectType.CAMPFIRE:
			_build_campfire()
		ObjectType.LAMP_POST:
			_build_lamp_post()
		ObjectType.BEACON_LANTERN:
			_build_beacon_lantern()

func _build_campfire() -> void:
	base_energy = light_energy if light_energy > 0.0 else 5.5
	if light_color == Color(1.0, 0.92, 0.78):
		light_color = Color(1.0, 0.55, 0.18) # Warm firelight

	# 1. Circular Stone Fire Ring (volcanic basalt stones)
	var num_stones = 10
	var ring_radius = 1.3
	var stone_mat = StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.20, 0.21, 0.24)
	stone_mat.roughness = 0.92

	var stone_parent = Node3D.new()
	stone_parent.name = "StoneRing"
	add_child(stone_parent)

	for i in range(num_stones):
		var ang = float(i) * (TAU / float(num_stones))
		var stone_mesh = SphereMesh.new()
		stone_mesh.radius = 0.28 + randf_range(-0.04, 0.04)
		stone_mesh.height = 0.38
		var stone_inst = MeshInstance3D.new()
		stone_inst.mesh = stone_mesh
		stone_inst.material_override = stone_mat
		stone_inst.position = Vector3(cos(ang) * ring_radius, 0.14, sin(ang) * ring_radius)
		stone_inst.scale = Vector3(1.1, 0.8, 1.2)
		stone_parent.add_child(stone_inst)

	# 2. Glowing Coal / Ash Bed
	var coal_mat = StandardMaterial3D.new()
	coal_mat.albedo_color = Color(0.12, 0.06, 0.04)
	coal_mat.roughness = 0.95
	coal_mat.emission_enabled = true
	coal_mat.emission = Color(1.0, 0.25, 0.04)
	coal_mat.emission_energy_multiplier = 2.4

	var coal_mesh = CylinderMesh.new()
	coal_mesh.top_radius = 0.95
	coal_mesh.bottom_radius = 1.05
	coal_mesh.height = 0.18
	var coal_inst = MeshInstance3D.new()
	coal_inst.name = "Coals"
	coal_inst.mesh = coal_mesh
	coal_inst.material_override = coal_mat
	coal_inst.position = Vector3(0.0, 0.08, 0.0)
	add_child(coal_inst)
	flame_mats.append(coal_mat)

	# 3. Firewood Logs
	var log_mat = StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.32, 0.20, 0.12)
	log_mat.roughness = 0.88

	var log_parent = Node3D.new()
	log_parent.name = "Logs"
	add_child(log_parent)

	var num_logs = 4
	for i in range(num_logs):
		var ang = float(i) * (TAU / float(num_logs)) + 0.35
		var log_mesh = CylinderMesh.new()
		log_mesh.top_radius = 0.10
		log_mesh.bottom_radius = 0.13
		log_mesh.height = 1.25
		var log_inst = MeshInstance3D.new()
		log_inst.mesh = log_mesh
		log_inst.material_override = log_mat
		log_inst.position = Vector3(cos(ang) * 0.45, 0.35, sin(ang) * 0.45)
		log_inst.rotation_degrees = Vector3(rad_to_deg(sin(ang) * 0.45), rad_to_deg(ang), rad_to_deg(-cos(ang) * 0.45))
		log_parent.add_child(log_inst)

	# 4. Stylized Animated Flames (Core + Outer Flame)
	var flame_mat = StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.85, 0.25)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.55, 0.12)
	flame_mat.emission_energy_multiplier = 4.5
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var flame_mesh = CylinderMesh.new()
	flame_mesh.top_radius = 0.02
	flame_mesh.bottom_radius = 0.45
	flame_mesh.height = 1.35
	var flame_inst = MeshInstance3D.new()
	flame_inst.name = "FlameCore"
	flame_inst.mesh = flame_mesh
	flame_inst.material_override = flame_mat
	flame_inst.position = Vector3(0.0, 0.72, 0.0)
	add_child(flame_inst)
	flame_nodes.append(flame_inst)
	flame_mats.append(flame_mat)

	var outer_flame_mat = StandardMaterial3D.new()
	outer_flame_mat.albedo_color = Color(1.0, 0.40, 0.05)
	outer_flame_mat.emission_enabled = true
	outer_flame_mat.emission = Color(1.0, 0.30, 0.02)
	outer_flame_mat.emission_energy_multiplier = 3.2
	outer_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var outer_flame_mesh = CylinderMesh.new()
	outer_flame_mesh.top_radius = 0.04
	outer_flame_mesh.bottom_radius = 0.65
	outer_flame_mesh.height = 1.10
	var outer_flame_inst = MeshInstance3D.new()
	outer_flame_inst.name = "FlameOuter"
	outer_flame_inst.mesh = outer_flame_mesh
	outer_flame_inst.material_override = outer_flame_mat
	outer_flame_inst.position = Vector3(0.0, 0.58, 0.0)
	outer_flame_inst.rotation_degrees.y = 45.0
	add_child(outer_flame_inst)
	flame_nodes.append(outer_flame_inst)
	flame_mats.append(outer_flame_mat)

	# 5. Real-Time Light Source (OmniLight3D)
	omni_light = OmniLight3D.new()
	omni_light.name = "CampfireLight"
	omni_light.position = Vector3(0.0, 0.85, 0.0)
	omni_light.light_color = light_color
	omni_light.light_energy = base_energy
	omni_light.omni_range = light_range
	omni_light.omni_attenuation = 0.85
	add_child(omni_light)

func _build_lamp_post() -> void:
	base_energy = light_energy if light_energy > 0.0 else 4.8
	light_color = Color(1.0, 0.92, 0.78) # Warm incandescent glow

	var metal_mat = StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.16, 0.18, 0.22)
	metal_mat.metallic = 0.85
	metal_mat.roughness = 0.35

	# 1. Base pedestal
	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = 0.32
	base_mesh.bottom_radius = 0.45
	base_mesh.height = 0.55
	var base_inst = MeshInstance3D.new()
	base_inst.name = "Pedestal"
	base_inst.mesh = base_mesh
	base_inst.material_override = metal_mat
	base_inst.position = Vector3(0.0, 0.27, 0.0)
	add_child(base_inst)

	# 2. Main vertical post
	var post_mesh = CylinderMesh.new()
	post_mesh.top_radius = 0.09
	post_mesh.bottom_radius = 0.14
	post_mesh.height = 4.2
	var post_inst = MeshInstance3D.new()
	post_inst.name = "Post"
	post_inst.mesh = post_mesh
	post_inst.material_override = metal_mat
	post_inst.position = Vector3(0.0, 2.45, 0.0)
	add_child(post_inst)

	# 3. Lantern Arm / Crossbar
	var arm_mesh = BoxMesh.new()
	arm_mesh.size = Vector3(0.12, 0.12, 0.95)
	var arm_inst = MeshInstance3D.new()
	arm_inst.name = "Arm"
	arm_inst.mesh = arm_mesh
	arm_inst.material_override = metal_mat
	arm_inst.position = Vector3(0.0, 4.45, 0.35)
	add_child(arm_inst)

	# 4. Glowing Lantern Housing
	var lantern_mat = StandardMaterial3D.new()
	lantern_mat.albedo_color = Color(1.0, 0.96, 0.85)
	lantern_mat.emission_enabled = true
	lantern_mat.emission = light_color
	lantern_mat.emission_energy_multiplier = 3.8

	var lantern_mesh = CylinderMesh.new()
	lantern_mesh.top_radius = 0.24
	lantern_mesh.bottom_radius = 0.18
	lantern_mesh.height = 0.55
	var lantern_inst = MeshInstance3D.new()
	lantern_inst.name = "LanternHead"
	lantern_inst.mesh = lantern_mesh
	lantern_inst.material_override = lantern_mat
	lantern_inst.position = Vector3(0.0, 4.25, 0.70)
	add_child(lantern_inst)
	flame_mats.append(lantern_mat)

	# Lantern Cap
	var cap_mesh = CylinderMesh.new()
	cap_mesh.top_radius = 0.06
	cap_mesh.bottom_radius = 0.34
	cap_mesh.height = 0.22
	var cap_inst = MeshInstance3D.new()
	cap_inst.mesh = cap_mesh
	cap_inst.material_override = metal_mat
	cap_inst.position = Vector3(0.0, 4.60, 0.70)
	add_child(cap_inst)

	# 5. Real-Time Light Source (OmniLight3D)
	omni_light = OmniLight3D.new()
	omni_light.name = "LampLight"
	omni_light.position = Vector3(0.0, 4.15, 0.70)
	omni_light.light_color = light_color
	omni_light.light_energy = base_energy
	omni_light.omni_range = light_range if light_range > 0.0 else 45.0
	omni_light.omni_attenuation = 0.85
	add_child(omni_light)

func _build_beacon_lantern() -> void:
	base_energy = light_energy if light_energy > 0.0 else 4.2
	light_color = Color(0.20, 0.88, 1.0) # Active cyan spaceport marker

	var metal_mat = StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.18, 0.20, 0.24)
	metal_mat.metallic = 0.8
	metal_mat.roughness = 0.3

	var post_mesh = CylinderMesh.new()
	post_mesh.top_radius = 0.15
	post_mesh.bottom_radius = 0.25
	post_mesh.height = 2.2
	var post_inst = MeshInstance3D.new()
	post_inst.mesh = post_mesh
	post_inst.material_override = metal_mat
	post_inst.position = Vector3(0.0, 1.1, 0.0)
	add_child(post_inst)

	var beacon_mat = StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(0.3, 0.9, 1.0)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = light_color
	beacon_mat.emission_energy_multiplier = 4.0

	var beacon_mesh = SphereMesh.new()
	beacon_mesh.radius = 0.32
	beacon_mesh.height = 0.64
	var beacon_inst = MeshInstance3D.new()
	beacon_inst.mesh = beacon_mesh
	beacon_inst.material_override = beacon_mat
	beacon_inst.position = Vector3(0.0, 2.35, 0.0)
	add_child(beacon_inst)
	flame_mats.append(beacon_mat)

	omni_light = OmniLight3D.new()
	omni_light.name = "BeaconLight"
	omni_light.position = Vector3(0.0, 2.4, 0.0)
	omni_light.light_color = light_color
	omni_light.light_energy = base_energy
	omni_light.omni_range = light_range if light_range > 0.0 else 45.0
	omni_light.omni_attenuation = 0.90
	add_child(omni_light)

func _process(delta: float) -> void:
	if not enable_flicker or not omni_light:
		return

	flicker_time += delta

	match object_type:
		ObjectType.CAMPFIRE:
			# Multi-octave organic fire flickering
			var flick = sin(flicker_time * 16.7) * 0.26 + sin(flicker_time * 31.3) * 0.17 + sin(flicker_time * 7.9) * 0.11
			var energy = base_energy * (1.0 + flick * 0.35)
			omni_light.light_energy = max(energy, 0.2)

			# Modulate flame core emission & subtle scale breathing
			if flame_mats.size() > 0:
				for mat in flame_mats:
					mat.emission_energy_multiplier = 3.5 * (1.0 + flick * 0.30)
			if flame_nodes.size() > 0:
				var scale_y = 1.0 + flick * 0.14
				var scale_xz = 1.0 - flick * 0.07
				flame_nodes[0].scale = Vector3(scale_xz, scale_y, scale_xz)

		ObjectType.LAMP_POST:
			# Subtle warm electric/gas lantern breathing
			var hum = sin(flicker_time * 6.5) * 0.06
			omni_light.light_energy = base_energy * (1.0 + hum)

		ObjectType.BEACON_LANTERN:
			# Rhythmic navigation beacon pulsing
			var pulse = (sin(flicker_time * 3.5) + 1.0) * 0.5
			omni_light.light_energy = lerpf(base_energy * 0.4, base_energy * 1.35, pulse)
			if flame_mats.size() > 0:
				flame_mats[0].emission_energy_multiplier = lerpf(1.5, 5.0, pulse)

# Static factory to create and orient a surface light object anywhere on the curved cylinder floor
static func create_on_cylinder(
	type: ObjectType,
	theta: float,
	z: float,
	cylinder_radius: float,
	elevation: float = 0.0,
	custom_color: Color = Color.WHITE,
	custom_range: float = -1.0
) -> SurfaceLightObject:
	var obj = SurfaceLightObject.new()
	obj.object_type = type

	if custom_color != Color.WHITE:
		obj.light_color = custom_color
	if custom_range > 0.0:
		obj.light_range = custom_range

	var surface_r = cylinder_radius - elevation
	var pos = Vector3(surface_r * cos(theta), surface_r * sin(theta), z)

	# Local coordinate basis on the curved inner surface:
	# Y points inward towards the rotational axis (Local Up)
	# Z points down the cylinder axis (+Z)
	# X is the circumferential tangent
	var up = Vector3(-cos(theta), -sin(theta), 0.0)
	var forward = Vector3(0.0, 0.0, -1.0)
	var back = -forward
	var right = up.cross(back).normalized()
	var basis = Basis(right, up, back).orthonormalized()

	obj.position = pos
	obj.basis = basis
	return obj
