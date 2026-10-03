class_name WorldEditor
extends Node

const REACH: float = 120.0
const Storage = preload("res://scripts/world_edit_storage.gd")
const Config = preload("res://scripts/map_config.gd")

var enabled := false
var player: PlayerController
var catalog: Array[Dictionary] = []
var selected_index := 0
var status := "Aim at a surface to place an object"

func _ready() -> void:
	reload_catalog()

func reload_catalog() -> void:
	catalog.clear()
	selected_index = 0
	var references = get_tree().get_first_node_in_group("reference_objects")
	var config: Dictionary = references.active_map_config if references else Config.load_map_config(Config.active_map())
	if config.is_empty():
		return
	for id in config.objects.model_catalog:
		var item: Dictionary = config.objects.model_catalog[id].duplicate(true)
		item["id"] = id
		item["path"] = Config.resolve_map_asset_path(config, item.scene_path)
		item["type"] = int(item.behavior_type)
		catalog.append(item)

func current_object() -> Dictionary:
	return catalog[selected_index] if not catalog.is_empty() else {}

func ray_hit() -> Dictionary:
	if not player or not player.camera:
		return {}
	var camera := player.camera
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * REACH)
	query.exclude = [player.get_rid()]
	query.hit_back_faces = true
	return player.get_world_3d().direct_space_state.intersect_ray(query)

func target_object(hit: Dictionary) -> SurfaceLightObject:
	if not player or not player.camera:
		return null
	var origin := player.camera.global_position
	var direction := -player.camera.global_basis.z
	var max_distance := REACH
	var nearest: SurfaceLightObject = null
	if not hit.is_empty():
		max_distance = origin.distance_to(hit.position) + 0.05
		var ancestor: Node = hit.collider
		while ancestor:
			if ancestor is SurfaceLightObject:
				nearest = ancestor
				break
			ancestor = ancestor.get_parent()
	# Decorative models such as campfires have no physics body. Pick their
	# visible mesh bounds too, while respecting the first solid obstruction.
	for object in get_tree().get_nodes_in_group("surface_light_objects"):
		if not object is SurfaceLightObject or object.is_queued_for_deletion():
			continue
		for node in object.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if not mesh.mesh or not mesh.is_visible_in_tree():
				continue
			var inverse := mesh.global_transform.affine_inverse()
			var local_hit: Variant = mesh.get_aabb().intersects_ray(inverse * origin, inverse.basis * direction)
			if local_hit == null:
				continue
			var world_hit: Vector3 = mesh.global_transform * local_hit
			var distance := (world_hit - origin).dot(direction)
			if distance >= 0.0 and distance < max_distance:
				max_distance = distance
				nearest = object
	return nearest

func place() -> SurfaceLightObject:
	if not enabled or catalog.is_empty():
		return null
	var hit := ray_hit()
	if hit.is_empty():
		status = "Aim at a surface within %d m" % int(REACH)
		return null
	var references = get_tree().get_first_node_in_group("reference_objects")
	if not references:
		status = "No object layer available"
		return null
	var normal: Vector3 = hit.normal
	if normal.is_zero_approx():
		status = "Aim at the outside of a surface"
		return null
	# Face the surface toward the viewer, including two-sided cap collisions.
	if normal.dot(player.camera.global_position - hit.position) < 0.0:
		normal = -normal
	var entry := current_object()
	var position: Vector3 = hit.position + normal * 0.03
	var object := SurfaceLightObject.create_on_cylinder(
		entry.type as SurfaceLightObject.ObjectType, atan2(position.y, position.x), position.z,
		references.active_map_config.geometry.cylinder_radius_m, 0.0, Config.color(entry.light_color), float(entry.light_range_m),
		0.0, normal, position, entry.variant, entry.path)
	object.asset_id = entry.id
	object.instance_id = "object_%d" % Time.get_ticks_usec()
	object.tint = Config.color(entry.tint)
	object.light_color = Config.color(entry.light_color)
	object.light_energy = float(entry.light_energy)
	var color: Array = entry.get("light_color", [])
	if color.size() >= 3:
		object.light_color = Config.color(color)
	object.enable_flicker = bool(entry.get("flicker", true))
	object.name = str(entry.get("name", "Object")).replace(" ", "")
	references.add_child(object)
	# The ray is in world space; object parents need not have an identity transform.
	object.global_transform = Transform3D(object.basis, position)
	status = "Placed %s · Unsaved" % entry.get("name", "object")
	return object

func remove() -> bool:
	if not enabled:
		return false
	var object := target_object(ray_hit())
	if not object:
		status = "Aim at an object within %d m to remove it" % int(REACH)
		return false
	status = "Removed %s · Unsaved" % object.name
	object.queue_free()
	return true

func save_edits() -> Error:
	if not enabled:
		return ERR_UNAVAILABLE
	var references = get_tree().get_first_node_in_group("reference_objects")
	if not references:
		status = "No object layer available"
		return ERR_UNAVAILABLE
	var error := Storage.save(references, "", player)
	if error == OK:
		var world = get_tree().get_first_node_in_group("cylinder_world")
		if world:
			world.load_map_package(references.active_map_config.map_directory)
		Config.activate(references.active_map_config.map_directory)
	status = "Saved — edits and default player location" if error == OK else "Could not save edits (%s)" % error_string(error)
	return error

func tint_target(appearance: Color, emission: Color) -> void:
	var object = target_object(ray_hit())
	if not object:
		status = "Aim at an object to tint it"
		return
	object.tint = appearance
	object.light_color = emission
	object.rebuild_object()
	status = "Tinted %s · Unsaved" % object.name
