@tool
extends StaticBody3D

## Builds lightweight collision from the imported tree's bark/trunk/branch
## material surfaces. Foliage surfaces are intentionally ignored.

const SOLID_MATERIAL_TOKENS: PackedStringArray = ["trunk", "bark", "branch", "stem", "wood"]

func _ready() -> void:
	call_deferred("_rebuild_collision")

func _rebuild_collision() -> void:
	for child: Node in get_children():
		if child is CollisionShape3D:
			child.queue_free()

	var model_root: Node = get_parent()
	if not model_root:
		return
	var mesh_nodes: Array[MeshInstance3D] = []
	if model_root is MeshInstance3D:
		mesh_nodes.append(model_root as MeshInstance3D)
	for node: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		mesh_nodes.append(node as MeshInstance3D)
	var found_solid_surface: bool = false
	for mesh_instance: MeshInstance3D in mesh_nodes:
		if not mesh_instance.mesh:
			continue
		for surface_index: int in mesh_instance.mesh.get_surface_count():
			var material: Material = mesh_instance.mesh.surface_get_material(surface_index)
			if not _is_solid_material(material):
				continue
			var vertices: PackedVector3Array = _surface_vertices(mesh_instance.mesh, surface_index)
			if vertices.size() < 4:
				continue
			_add_convex_surface(mesh_instance, model_root, vertices)
			found_solid_surface = true

	# Keep custom or unusually named tree assets solid at the trunk as well.
	# This fallback is deliberately narrow so it cannot turn foliage into a wall.
	if not found_solid_surface:
		for mesh_instance: MeshInstance3D in mesh_nodes:
			if mesh_instance.mesh:
				var bounds: AABB = mesh_instance.mesh.get_aabb()
				bounds.size.x = minf(bounds.size.x, maxf(bounds.size.y * 0.18, 0.08))
				bounds.size.z = minf(bounds.size.z, maxf(bounds.size.y * 0.18, 0.08))
				_add_cylinder(mesh_instance, model_root, bounds, null)
				break

func _is_solid_material(material: Material) -> bool:
	if not material:
		return false
	var material_name: String = material.resource_name.to_lower()
	for token: String in SOLID_MATERIAL_TOKENS:
		if material_name.contains(token):
			return true
	return false

func _surface_vertices(mesh: Mesh, surface_index: int) -> PackedVector3Array:
	var source: PackedVector3Array = mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
	if source.size() <= 256:
		return source
	# The physics engine computes the convex hull, so a bounded sample keeps
	# imported branch meshes inexpensive without changing their overall shape.
	var vertices: PackedVector3Array = PackedVector3Array()
	var step: int = maxi(source.size() / 256, 1)
	for index: int in range(0, source.size(), step):
		vertices.append(source[index])
	return vertices

func _add_convex_surface(mesh_instance: MeshInstance3D, model_root: Node, vertices: PackedVector3Array) -> void:
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	shape.points = vertices
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	# The points come directly from the visible bark/branch surface, so the
	# collider follows the imported trunk transform instead of an enclosing box.
	# Include every ancestor transform. This is important for fallen/angled
	# trees whose imported mesh is nested below an additional rotated node.
	var root_transform: Transform3D = (model_root as Node3D).global_transform
	collider.transform = root_transform.affine_inverse() * mesh_instance.global_transform
	add_child(collider)

func _add_cylinder(mesh_instance: MeshInstance3D, model_root: Node, surface_aabb: AABB, material: Material) -> void:
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
	var root_transform: Transform3D = (model_root as Node3D).global_transform
	collider.transform = root_transform.affine_inverse() * mesh_instance.global_transform * Transform3D(axis_basis, surface_aabb.get_center())
	add_child(collider)
