@tool
class_name SurfaceLightObject
extends Node3D

enum ObjectType {
	CAMPFIRE,
	LAMP_POST,
	BEACON_LANTERN,
	BRIDGE,
	BONFIRE,
	HOUSE,
	TREE,
	FOREST,
	WINDMILL
}

enum TreeVariant {
	OAK,
	PINE,
	BIRCH,
	WILLOW,
	CHERRY_BLOSSOM,
	DEAD_TREE
}

const MapConfigClass = preload("res://scripts/map_config.gd")
const MapAssetLoaderClass = preload("res://scripts/map_asset_loader.gd")
const MapRuntimeClass = preload("res://scripts/map_runtime.gd")

@export var object_type: ObjectType = ObjectType.CAMPFIRE:
	set(val):
		object_type = val
		if is_inside_tree():
			rebuild_object()

@export var tree_variant: TreeVariant = TreeVariant.OAK:
	set(val):
		tree_variant = val
		if is_inside_tree() and object_type == ObjectType.TREE:
			rebuild_object()

var asset_id: String = ""
var instance_id: String = ""
var tint: Color = Color.WHITE

@export_file var model_scene_path: String = ""

@export var light_color: Color = Color(1.0, 0.58, 0.22):
	set(val):
		light_color = val
		if omni_light:
			omni_light.light_color = light_color

@export var light_energy: float = 5.5:
	set(val):
		light_energy = max(val, 0.0)
		base_energy = light_energy * light_color.a
		if omni_light:
			omni_light.light_energy = light_energy * light_color.a

@export var light_range: float = 55.0:
	set(val):
		light_range = max(val, 1.0)
		if omni_light:
			omni_light.omni_range = light_range

@export var enable_flicker: bool = true

var omni_light: OmniLight3D = null
var flame_nodes: Array[Node3D] = []
var flame_mats: Array[StandardMaterial3D] = []
var rotor_hub_node: Node3D = null
var base_energy: float = 5.5
var flicker_time: float = 0.0
var rng_offset: float = 0.0

func _ready() -> void:
	add_to_group("surface_light_objects")
	rng_offset = randf_range(0.0, 100.0)
	flicker_time = rng_offset
	rebuild_object()

func _update_process_state() -> void:
	set_physics_process(false)
	var needs_proc = (rotor_hub_node != null and is_instance_valid(rotor_hub_node)) or (enable_flicker and omni_light != null and is_near_camera)
	set_process(needs_proc)

func _get_model_instance() -> Node3D:
	var scene_path = model_scene_path
	if scene_path.is_empty():
		var reference_objects = get_tree().get_first_node_in_group("reference_objects") if is_inside_tree() else null
		if reference_objects and reference_objects.has_method("_get_model_path"):
			scene_path = reference_objects.call("_get_model_path", object_type, int(tree_variant))
		else:
			var map_config = MapConfigClass.load_map_config("default")
			scene_path = MapConfigClass.get_object_model_path(map_config, int(object_type), int(tree_variant))
	if scene_path.is_empty():
		return null
	return MapAssetLoaderClass.instantiate_model(scene_path)

func rebuild_object() -> void:
	for child in get_children():
		child.queue_free()

	flame_nodes.clear()
	flame_mats.clear()
	omni_light = null

	var instance: Node3D = null
	instance = _get_model_instance()

	if not instance:
		return

	add_child(instance)
	_apply_map_shader_parameters(instance)
	_setup_instance_bindings(instance)
	if not omni_light and light_energy > 0:
		omni_light = OmniLight3D.new()
		instance.add_child(omni_light)
		base_energy = light_energy * light_color.a
	apply_appearance(instance)
	_update_process_state()

func _apply_map_shader_parameters(root: Node) -> void:
	var map_doc: Dictionary = MapRuntimeClass.document(self)
	if map_doc.is_empty():
		return
	var meshes: Array[Node] = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mesh := node as MeshInstance3D
		if mesh.material_override is ShaderMaterial:
			var override := (mesh.material_override as ShaderMaterial).duplicate(true) as ShaderMaterial
			MapRuntimeClass.shader_parameters(override, map_doc)
			mesh.material_override = override
		if not mesh.mesh:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			if source is ShaderMaterial:
				var material := (source as ShaderMaterial).duplicate(true) as ShaderMaterial
				MapRuntimeClass.shader_parameters(material, map_doc)
				mesh.set_surface_override_material(surface, material)

func _setup_instance_bindings(instance: Node3D) -> void:
	# Helper to find nodes by name at any depth in the instance hierarchy.
	# Needed because .glb model nodes are nested under "Model/" while
	# Godot-specific nodes (lights, particles) are direct children.
	var _find = func(node_name: String) -> Node:
		var found = instance.get_node_or_null(node_name)
		if found:
			return found
		return instance.find_child(node_name, true, false)

	match object_type:
		ObjectType.CAMPFIRE:

			omni_light = _find.call("CampfireLight") as OmniLight3D
			var coals = _find.call("Coals") as MeshInstance3D
			var flame_core = _find.call("FlameCore") as MeshInstance3D
			var flame_outer = _find.call("FlameOuter") as MeshInstance3D
			var flame_card0 = _find.call("FlameCard0") as MeshInstance3D
			var flame_card1 = _find.call("FlameCard1") as MeshInstance3D
			var flame_card2 = _find.call("FlameCard2") as MeshInstance3D
			var flame_card3 = _find.call("FlameCard3") as MeshInstance3D

			if flame_core:
				flame_nodes.append(flame_core)
			if flame_outer:
				flame_nodes.append(flame_outer)
			if flame_card0:
				flame_nodes.append(flame_card0)
			if flame_card1:
				flame_nodes.append(flame_card1)
			if flame_card2:
				flame_nodes.append(flame_card2)
			if flame_card3:
				flame_nodes.append(flame_card3)

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
			if flame_mats.is_empty():
				var m = StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.emission_enabled = true
				m.emission = light_color
				flame_mats.append(m)

		ObjectType.BONFIRE:

			omni_light = _find.call("BonfireLight") as OmniLight3D
			var coals = _find.call("Coals") as MeshInstance3D
			var flame_core = _find.call("FlameCore") as MeshInstance3D
			var flame_outer = _find.call("FlameOuter") as MeshInstance3D
			var flame_card0 = _find.call("FlameCard0") as MeshInstance3D
			var flame_card1 = _find.call("FlameCard1") as MeshInstance3D
			var flame_card2 = _find.call("FlameCard2") as MeshInstance3D
			var flame_card3 = _find.call("FlameCard3") as MeshInstance3D

			if flame_core:
				flame_nodes.append(flame_core)
			if flame_outer:
				flame_nodes.append(flame_outer)
			if flame_card0:
				flame_nodes.append(flame_card0)
			if flame_card1:
				flame_nodes.append(flame_card1)
			if flame_card2:
				flame_nodes.append(flame_card2)
			if flame_card3:
				flame_nodes.append(flame_card3)

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
			if flame_mats.is_empty():
				var m = StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.emission_enabled = true
				m.emission = light_color
				flame_mats.append(m)

		ObjectType.LAMP_POST:

			omni_light = _find.call("LampLight") as OmniLight3D
			var lantern_head = _find.call("LanternHead") as MeshInstance3D
			if lantern_head and lantern_head.mesh and lantern_head.mesh.material:
				var m = lantern_head.mesh.material.duplicate() as StandardMaterial3D
				lantern_head.material_override = m
				flame_mats.append(m)

		ObjectType.BEACON_LANTERN:

			omni_light = _find.call("BeaconLight") as OmniLight3D
			var beacon = _find.call("Beacon") as MeshInstance3D
			if beacon and beacon.mesh and beacon.mesh.material:
				var m = beacon.mesh.material.duplicate() as StandardMaterial3D
				beacon.material_override = m
				flame_mats.append(m)

		ObjectType.HOUSE:
			omni_light = _find.call("WindowLight") as OmniLight3D

		ObjectType.WINDMILL:
			omni_light = _find.call("LanternLight") as OmniLight3D
			rotor_hub_node = _find.call("RotorHub") as Node3D

		ObjectType.TREE:
			enable_flicker = false

	if omni_light:
		base_energy = light_energy * light_color.a
		omni_light.light_energy = base_energy
		omni_light.light_color = light_color
		if light_range > 0.0:
			omni_light.omni_range = light_range


func apply_appearance(instance: Node = null) -> void:
	if instance == null:
		instance = self
	var meshes = instance.find_children("*", "MeshInstance3D", true, false)
	if instance is MeshInstance3D:
		meshes.append(instance)
	for node in meshes:
		var mesh_instance = node as MeshInstance3D
		if not mesh_instance.mesh:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source = mesh_instance.get_active_material(surface)
			if source == null or source is BaseMaterial3D:
				var material = source.duplicate() as BaseMaterial3D if source else StandardMaterial3D.new()
				material.albedo_color *= tint
				if material.emission_enabled:
					material.emission *= light_color
					material.emission_energy_multiplier *= light_color.a
				if tint.a < 1:
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mesh_instance.set_surface_override_material(surface, material)
		if mesh_instance.material_override is BaseMaterial3D:
			mesh_instance.material_override = null
	for light in instance.find_children("*", "Light3D", true, false):
		light.light_color = light_color
		light.light_energy = light_energy * light_color.a
		if light is OmniLight3D:
			light.omni_range = light_range


static var global_active_light_distance: float = 3500.0
static var adaptive_active_light_scale: float = 1.0

static func set_adaptive_active_light_scale(scale: float) -> void:
	adaptive_active_light_scale = clampf(scale, 0.5, 1.5)

static func get_effective_active_light_distance() -> float:
	if global_active_light_distance <= 0.0:
		return 0.0
	return minf(global_active_light_distance * adaptive_active_light_scale, 8000.0)

var is_near_camera: bool = true

func set_surface_light_active(light: OmniLight3D, active: bool) -> void:
	light.visible = active
	is_near_camera = active
	_update_process_state()

func _process(delta: float) -> void:
	if rotor_hub_node and is_instance_valid(rotor_hub_node):
		rotor_hub_node.rotate_object_local(Vector3.UP, delta * 0.7)

	if not omni_light:
		return

	if not enable_flicker or not is_near_camera:
		return

	flicker_time += delta

	match object_type:
		ObjectType.CAMPFIRE:
			var flick = sin(flicker_time * 16.7) * 0.26 + sin(flicker_time * 31.3) * 0.17 + sin(flicker_time * 7.9) * 0.11
			var energy = base_energy * (1.0 + flick * 0.35)
			omni_light.light_energy = max(energy, 0.2)

			var light_jitter_x = sin(flicker_time * 19.3) * 0.04
			var light_jitter_z = cos(flicker_time * 23.7) * 0.04
			omni_light.position = Vector3(light_jitter_x, 0.85 + flick * 0.03, light_jitter_z)

			for i in range(flame_nodes.size()):
				var f_node = flame_nodes[i]
				var phase = flicker_time * 14.0 + float(i) * 1.57
				var scale_y = 1.0 + sin(phase) * 0.12 + flick * 0.10
				var scale_xz = 1.0 - sin(phase) * 0.06 - flick * 0.05
				f_node.scale = Vector3(scale_xz, scale_y, scale_xz)

		ObjectType.BONFIRE:
			var flick = sin(flicker_time * 14.2) * 0.28 + sin(flicker_time * 27.5) * 0.18 + sin(flicker_time * 6.8) * 0.12
			var energy = base_energy * (1.0 + flick * 0.38)
			omni_light.light_energy = max(energy, 0.5)

			var light_jitter_x = sin(flicker_time * 16.1) * 0.08
			var light_jitter_z = cos(flicker_time * 20.4) * 0.08
			omni_light.position = Vector3(light_jitter_x, 2.0 + flick * 0.08, light_jitter_z)

			for i in range(flame_nodes.size()):
				var f_node = flame_nodes[i]
				var phase = flicker_time * 12.0 + float(i) * 1.57
				var scale_y = 1.0 + sin(phase) * 0.14 + flick * 0.12
				var scale_xz = 1.0 - sin(phase) * 0.07 - flick * 0.06
				f_node.scale = Vector3(scale_xz, scale_y, scale_xz)

		ObjectType.LAMP_POST:
			var hum = sin(flicker_time * 6.5) * 0.06
			omni_light.light_energy = base_energy * (1.0 + hum)

		ObjectType.BEACON_LANTERN:
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
	custom_range: float = -1.0,
	yaw_angle_rad: float = 0.0,
	custom_normal: Vector3 = Vector3.ZERO,
	custom_pos: Vector3 = Vector3.ZERO,
	tree_variant_idx: int = -1,
	model_path: String = "",
	player_facing_fwd: Vector3 = Vector3.ZERO,
	ground_offset_m: float = 0.0,
	should_align_to_normal: bool = false,
	pitch_angle_rad: float = 0.0,
	roll_angle_rad: float = 0.0
) -> SurfaceLightObject:
	var obj = SurfaceLightObject.new()
	obj.object_type = type
	obj.model_scene_path = model_path

	if type == ObjectType.TREE and tree_variant_idx >= 0 and tree_variant_idx < TreeVariant.size():
		obj.tree_variant = tree_variant_idx as TreeVariant

	if custom_color != Color.WHITE:
		obj.light_color = custom_color
	if custom_range > 0.0:
		obj.light_range = custom_range

	var pos = custom_pos
	if pos == Vector3.ZERO:
		var surface_r = cylinder_radius - elevation
		var d_theta = TAU / 144.0
		var phi = fposmod(theta, d_theta) - d_theta * 0.5
		var chord_r = surface_r * (cos(d_theta * 0.5) / maxf(cos(phi), 0.001))
		pos = Vector3(chord_r * cos(theta), chord_r * sin(theta), z)

	# Determine Up vector based on normal alignment preference
	var up := Vector3.UP
	if should_align_to_normal and custom_normal != Vector3.ZERO and not custom_normal.is_zero_approx():
		up = custom_normal.normalized()
	else:
		var r_xz := Vector2(pos.x, pos.y).length()
		if r_xz > 500.0:
			var cyl_up := Vector3(-pos.x, -pos.y, 0.0).normalized()
			if not cyl_up.is_zero_approx():
				up = cyl_up

	# Apply ground offset (sinking curved bases or lifting surface items)
	if ground_offset_m != 0.0:
		pos += up * ground_offset_m

	var fwd = -player_facing_fwd
	if fwd != Vector3.ZERO:
		fwd = (fwd - up * fwd.dot(up)).normalized()
	if fwd.is_zero_approx():
		fwd = Vector3(0.0, 0.0, 1.0)
		if absf(up.dot(fwd)) > 0.90:
			fwd = Vector3(-1.0, 0.0, 0.0)
		fwd = (fwd - up * fwd.dot(up)).normalized()

	var right = up.cross(-fwd).normalized()
	var adjusted_up = (-fwd).cross(right).normalized()
	var basis = Basis(right, adjusted_up, -fwd).orthonormalized()

	if not is_zero_approx(yaw_angle_rad):
		basis = basis.rotated(up, yaw_angle_rad)
	if not is_zero_approx(pitch_angle_rad):
		basis = basis.rotated(basis.x, pitch_angle_rad)
	if not is_zero_approx(roll_angle_rad):
		basis = basis.rotated(basis.z, roll_angle_rad)

	obj.position = pos
	obj.basis = basis
	return obj
