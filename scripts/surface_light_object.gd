@tool
class_name SurfaceLightObject
extends Node3D

enum ObjectType {
	CAMPFIRE,
	LAMP_POST,
	BEACON_LANTERN
}

const CAMPFIRE_SCENE: PackedScene = preload("res://assets/objects/campfire.tscn")
const LAMP_POST_SCENE: PackedScene = preload("res://assets/objects/lamp_post.tscn")
const BEACON_SCENE: PackedScene = preload("res://assets/objects/beacon_lantern.tscn")

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
	omni_light = null

	var instance: Node3D = null
	match object_type:
		ObjectType.CAMPFIRE:
			if CAMPFIRE_SCENE:
				instance = CAMPFIRE_SCENE.instantiate()
		ObjectType.LAMP_POST:
			if LAMP_POST_SCENE:
				instance = LAMP_POST_SCENE.instantiate()
		ObjectType.BEACON_LANTERN:
			if BEACON_SCENE:
				instance = BEACON_SCENE.instantiate()

	if not instance:
		return

	add_child(instance)
	_setup_instance_bindings(instance)

func _setup_instance_bindings(instance: Node3D) -> void:
	match object_type:
		ObjectType.CAMPFIRE:
			if light_color == Color(1.0, 0.92, 0.78) or light_color == Color.WHITE:
				light_color = Color(1.0, 0.55, 0.18)

			omni_light = instance.get_node_or_null("CampfireLight") as OmniLight3D
			var coals = instance.get_node_or_null("Coals") as MeshInstance3D
			var flame_core = instance.get_node_or_null("FlameCore") as MeshInstance3D
			var flame_outer = instance.get_node_or_null("FlameOuter") as MeshInstance3D

			if flame_core:
				flame_nodes.append(flame_core)
			if flame_outer:
				flame_nodes.append(flame_outer)

			if coals and coals.mesh and coals.mesh.material:
				var m = coals.mesh.material.duplicate() as StandardMaterial3D
				coals.material_override = m
				flame_mats.append(m)
			if flame_core and flame_core.mesh and flame_core.mesh.material:
				var m = flame_core.mesh.material.duplicate() as StandardMaterial3D
				flame_core.material_override = m
				flame_mats.append(m)
			if flame_outer and flame_outer.mesh and flame_outer.mesh.material:
				var m = flame_outer.mesh.material.duplicate() as StandardMaterial3D
				flame_outer.material_override = m
				flame_mats.append(m)

		ObjectType.LAMP_POST:
			if light_color == Color(1.0, 0.58, 0.22) or light_color == Color.WHITE:
				light_color = Color(1.0, 0.92, 0.78)

			omni_light = instance.get_node_or_null("LampLight") as OmniLight3D
			var lantern_head = instance.get_node_or_null("LanternHead") as MeshInstance3D
			if lantern_head and lantern_head.mesh and lantern_head.mesh.material:
				var m = lantern_head.mesh.material.duplicate() as StandardMaterial3D
				lantern_head.material_override = m
				flame_mats.append(m)

		ObjectType.BEACON_LANTERN:
			if light_color == Color(1.0, 0.58, 0.22) or light_color == Color.WHITE:
				light_color = Color(0.20, 0.88, 1.0)

			omni_light = instance.get_node_or_null("BeaconLight") as OmniLight3D
			var beacon = instance.get_node_or_null("Beacon") as MeshInstance3D
			if beacon and beacon.mesh and beacon.mesh.material:
				var m = beacon.mesh.material.duplicate() as StandardMaterial3D
				beacon.material_override = m
				flame_mats.append(m)

	if omni_light:
		if light_energy > 0.0:
			base_energy = light_energy
		else:
			base_energy = omni_light.light_energy
		omni_light.light_energy = base_energy
		omni_light.light_color = light_color
		if light_range > 0.0:
			omni_light.omni_range = light_range

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
