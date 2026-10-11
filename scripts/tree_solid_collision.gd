@tool
extends StaticBody3D

const MapAssetLoaderClass = preload("res://scripts/map_asset_loader.gd")

## Builds lightweight collision from the imported tree's bark/trunk/branch
## material surfaces. Foliage surfaces are intentionally ignored.

const SOLID_MATERIAL_TOKENS: PackedStringArray = ["trunk", "bark", "branch", "stem", "wood"]
static var solid_shape_cache: Dictionary = {}

func _ready() -> void:
	call_deferred("_rebuild_collision")

func _rebuild_collision() -> void:
	for child: Node in get_children():
		if child is CollisionShape3D:
			child.queue_free()

	var model_root: Node = get_parent()
	if not model_root:
		return
	var mesh_nodes: Array[Dictionary] = []
	# SolidTreeCollision is a child of model_root. Start at the model's
	# descendants so the root transform is inherited exactly once by both the
	# visible meshes and this collision body.
	for child: Node in model_root.get_children():
		if child != self:
			_collect_mesh_nodes(child, Transform3D.IDENTITY, mesh_nodes)
	var found_solid_surface: bool = false
	for entry: Dictionary in mesh_nodes:
		var mesh_instance: MeshInstance3D = entry.mesh
		var local_transform: Transform3D = entry.transform
		if not mesh_instance.mesh:
			continue
		for surface_index: int in mesh_instance.mesh.get_surface_count():
			var material: Material = mesh_instance.mesh.surface_get_material(surface_index)
			if not _is_solid_material(material):
				continue
			var shape: ConvexPolygonShape3D = _get_cached_convex_shape(mesh_instance.mesh, surface_index)
			if shape:
				_add_convex_surface(local_transform, shape)
				found_solid_surface = true

	# Keep custom or unusually named tree assets solid at the trunk as well.
	# This fallback is deliberately narrow so it cannot turn foliage into a wall.
	if not found_solid_surface:
		for entry: Dictionary in mesh_nodes:
			var mesh_instance: MeshInstance3D = entry.mesh
			if mesh_instance.mesh:
				var bounds: AABB = mesh_instance.mesh.get_aabb()
				bounds.size.x = minf(bounds.size.x, maxf(bounds.size.y * 0.18, 0.08))
				bounds.size.z = minf(bounds.size.z, maxf(bounds.size.y * 0.18, 0.08))
				_add_cylinder(mesh_instance, entry.transform, bounds, null)
				break

func _collect_mesh_nodes(node: Node, parent_transform: Transform3D, output: Array[Dictionary]) -> void:
	if node == self or node is CollisionShape3D or node.is_in_group("collision_debug_hull"):
		return
	if node is MeshInstance3D and not (node as MeshInstance3D).visible:
		return
	var local_transform: Transform3D = parent_transform
	if node is Node3D:
		local_transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		output.append({"mesh": node as MeshInstance3D, "transform": local_transform})
	for child: Node in node.get_children():
		_collect_mesh_nodes(child, local_transform, output)

func _is_solid_material(material: Material) -> bool:
	if not material:
		return false
	var material_name: String = material.resource_name.to_lower()
	if material_name.contains("leaf") or material_name.contains("foliage"):
		return false
	if material_name.begins_with("island_tree") and not material_name.contains("branch"):
		return true
	for token: String in SOLID_MATERIAL_TOKENS:
		if material_name.contains(token):
			return true
	return false

func _get_cached_convex_shape(mesh: Mesh, surface_index: int) -> ConvexPolygonShape3D:
	var key: String = "%d:%d" % [mesh.get_instance_id(), surface_index]
	if solid_shape_cache.has(key):
		return solid_shape_cache[key] as ConvexPolygonShape3D
	var arrays: Array = mesh.surface_get_arrays(surface_index)
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return null
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if vertices.size() < 4:
		return null
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	if shape:
		solid_shape_cache[key] = shape
	return shape

func _add_convex_surface(local_transform: Transform3D, shape: ConvexPolygonShape3D) -> void:
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	# The points come directly from the visible bark/branch surface, so the
	# collider follows the imported trunk transform instead of an enclosing box.
	# Include every ancestor transform. This is important for fallen/angled
	# trees whose imported mesh is nested below an additional rotated node.
	collider.transform = local_transform
	add_child(collider)
	MapAssetLoaderClass._attach_collision_debug_mesh(collider)

func _add_cylinder(mesh_instance: MeshInstance3D, local_transform: Transform3D, surface_aabb: AABB, material: Material) -> void:
	var dimensions: Vector3 = surface_aabb.size
	var axis: Vector3 = Vector3.UP
	var height: float = dimensions.y
	var radius: float = maxf(dimensions.x, dimensions.z) * 0.5
	# Main trunks are vertical. For branch-only surfaces, use their longest
	# dimension to make the simplified solid follow the branch mass direction.
	if material and not material.resource_name.to_lower().contains("trunk") and not material.resource_name.to_lower().contains("bark"):
		if dimensions.x > height and dimensions.x >= dimensions.z:
			axis = Vector3.RIGHT
			height = dimensions.x
			radius = maxf(dimensions.y, dimensions.z) * 0.5
		elif dimensions.z > height:
			axis = Vector3.FORWARD
			height = dimensions.z
			radius = maxf(dimensions.x, dimensions.y) * 0.5
	radius = maxf(radius, 0.025)
	height = maxf(height, 0.05)

	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	var axis_basis: Basis = Basis(Quaternion(Vector3.UP, axis))
	collider.transform = local_transform * Transform3D(axis_basis, surface_aabb.get_center())
	add_child(collider)
	MapAssetLoaderClass._attach_collision_debug_mesh(collider)
