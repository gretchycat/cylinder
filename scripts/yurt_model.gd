@tool
extends Node3D

const WALL_RADIUS: float = 3.8
const WALL_HEIGHT: float = 2.2
const WALL_THICKNESS: float = 0.16
const DOOR_ANGLE: float = PI * 0.5
const DOOR_HALF_ANGLE: float = 0.36
const WALL_SEGMENTS: int = 24
const ROOF_RINGS: int = 8

var _built: bool = false

func _init() -> void:
	# Build during instantiation so the object palette's mesh-only preview can
	# inspect the procedural geometry before the scene enters a SceneTree.
	_build_yurt()

func _ready() -> void:
	if not get_node_or_null("YurtGeometry"):
		_build_yurt()

func _build_yurt() -> void:
	if _built or get_node_or_null("YurtGeometry"):
		return
	_built = true
	var geometry := Node3D.new()
	geometry.name = "YurtGeometry"
	add_child(geometry)
	var fabric := _make_material("res://assets/maps/default/models/objects/yurt_fabric.png", Color(0.92, 0.82, 0.66))
	var dark_wood := _make_material("", Color(0.24, 0.12, 0.055))
	var floor_mat := _make_material("", Color(0.25, 0.18, 0.10))
	var rug_mat := _make_material("res://assets/maps/default/models/objects/yurt_rug.png", Color.WHITE)
	var metal := _make_material("", Color(0.12, 0.13, 0.14))
	var ceramic := _make_material("", Color(0.62, 0.66, 0.62))

	# Low circular floor, patterned rug, and a roof dome with a central crown.
	_add_cylinder(geometry, "Floor", 3.65, 0.10, 0.0, floor_mat, 32)
	_add_cylinder(geometry, "InteriorRug", 2.45, 0.035, 0.075, rug_mat, 32)
	_add_dome(geometry, "CanvasRoof", fabric)
	for segment: int in WALL_SEGMENTS:
		var angle := (float(segment) + 0.5) * TAU / float(WALL_SEGMENTS)
		if abs(_angle_delta(angle, DOOR_ANGLE)) < DOOR_HALF_ANGLE:
			continue
		var a0 := float(segment) * TAU / float(WALL_SEGMENTS)
		var a1 := float(segment + 1) * TAU / float(WALL_SEGMENTS)
		_add_wall_panel(geometry, "CanvasWall_%02d" % segment, a0, a1, fabric)

	# Timber doorway and a simple raised threshold. The opening is deliberately
	# free of a blocking wall or collision shape.
	_add_box(geometry, "DoorPostLeft", Vector3(0.22, 2.45, 0.22), Vector3(-1.15, 1.225, 3.63), 0.0, dark_wood)
	_add_box(geometry, "DoorPostRight", Vector3(0.22, 2.45, 0.22), Vector3(1.15, 1.225, 3.63), 0.0, dark_wood)
	_add_box(geometry, "DoorLintel", Vector3(2.5, 0.22, 0.22), Vector3(0.0, 2.35, 3.63), 0.0, dark_wood)
	_add_box(geometry, "DoorThreshold", Vector3(2.3, 0.10, 0.55), Vector3(0.0, 0.05, 3.70), 0.0, dark_wood)
	_add_cylinder(geometry, "CrownRing", 0.48, 0.18, 4.42, dark_wood, 16)

	# Normal living amenities: low beds/benches, a central table, stove and pot.
	_add_box(geometry, "BedLeft", Vector3(1.7, 0.32, 0.72), Vector3(-2.0, 0.25, -0.65), 0.0, dark_wood)
	_add_box(geometry, "BedRight", Vector3(1.7, 0.32, 0.72), Vector3(2.0, 0.25, -0.65), 0.0, dark_wood)
	_add_box(geometry, "BedBlanketLeft", Vector3(1.5, 0.08, 0.60), Vector3(-2.0, 0.46, -0.65), 0.0, rug_mat)
	_add_box(geometry, "BedBlanketRight", Vector3(1.5, 0.08, 0.60), Vector3(2.0, 0.46, -0.65), 0.0, rug_mat)
	_add_cylinder(geometry, "Table", 0.58, 0.16, 0.65, dark_wood, 16, Vector3(0.0, 0.82, -0.25))
	_add_cylinder(geometry, "Stove", 0.42, 0.65, 0.38, metal, 16, Vector3(0.0, 0.33, -2.55))
	_add_cylinder(geometry, "StovePipe", 0.12, 2.25, 0.0, metal, 12, Vector3(0.0, 1.72, -2.55))
	_add_cylinder(geometry, "WaterBasin", 0.34, 0.18, 0.78, ceramic, 16, Vector3(1.05, 0.91, 1.05))

	_build_collisions()
	set_meta("enterable", true)
	set_meta("collision_profile", "yurt_walls_doorway_open")

func _build_collisions() -> void:
	var body := StaticBody3D.new()
	body.name = "SolidCollision"
	add_child(body)
	for segment: int in WALL_SEGMENTS:
		var angle := (float(segment) + 0.5) * TAU / float(WALL_SEGMENTS)
		if abs(_angle_delta(angle, DOOR_ANGLE)) < DOOR_HALF_ANGLE:
			continue
		var panel_width := 2.0 * WALL_RADIUS * sin(PI / float(WALL_SEGMENTS)) * 1.06
		_add_collision_box(body, "WallCollision_%02d" % segment, Vector3(panel_width, WALL_HEIGHT, WALL_THICKNESS),
			Vector3(cos(angle) * WALL_RADIUS, WALL_HEIGHT * 0.5, sin(angle) * WALL_RADIUS), angle + PI * 0.5)
	_add_collision_box(body, "DoorPostCollisionLeft", Vector3(0.22, 2.45, 0.22), Vector3(-1.15, 1.225, 3.63), 0.0)
	_add_collision_box(body, "DoorPostCollisionRight", Vector3(0.22, 2.45, 0.22), Vector3(1.15, 1.225, 3.63), 0.0)
	_add_collision_box(body, "DoorLintelCollision", Vector3(2.5, 0.22, 0.22), Vector3(0.0, 2.35, 3.63), 0.0)

func _add_dome(parent: Node3D, node_name: String, material: StandardMaterial3D) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(material)
	for ring: int in ROOF_RINGS:
		var t0 := float(ring) / float(ROOF_RINGS)
		var t1 := float(ring + 1) / float(ROOF_RINGS)
		var y0 := WALL_HEIGHT + t0 * 2.25
		var y1 := WALL_HEIGHT + t1 * 2.25
		var r0 := WALL_RADIUS * (1.0 - t0) + 0.18 * t0
		var r1 := WALL_RADIUS * (1.0 - t1) + 0.18 * t1
		for segment: int in WALL_SEGMENTS:
			var a0 := float(segment) * TAU / float(WALL_SEGMENTS)
			var a1 := float(segment + 1) * TAU / float(WALL_SEGMENTS)
			_add_surface_quad(tool, Vector3(cos(a0) * r0, y0, sin(a0) * r0), Vector3(cos(a0) * r1, y1, sin(a0) * r1),
				Vector3(cos(a1) * r1, y1, sin(a1) * r1), Vector3(cos(a1) * r0, y0, sin(a1) * r0), a0 / TAU, t0, a1 / TAU, t1)
	tool.generate_normals()
	var mesh := tool.commit()
	if mesh:
		var instance := MeshInstance3D.new()
		instance.name = node_name
		instance.mesh = mesh
		parent.add_child(instance)

func _add_wall_panel(parent: Node3D, node_name: String, a0: float, a1: float, material: StandardMaterial3D) -> void:
	var inner_radius := WALL_RADIUS - WALL_THICKNESS * 0.5
	var outer_radius := WALL_RADIUS + WALL_THICKNESS * 0.5
	var bottom_inner := Vector3(cos(a0) * inner_radius, 0.0, sin(a0) * inner_radius)
	var bottom_outer := Vector3(cos(a0) * outer_radius, 0.0, sin(a0) * outer_radius)
	var next_bottom_inner := Vector3(cos(a1) * inner_radius, 0.0, sin(a1) * inner_radius)
	var next_bottom_outer := Vector3(cos(a1) * outer_radius, 0.0, sin(a1) * outer_radius)
	var lift := Vector3.UP * WALL_HEIGHT
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(material)
	# Outer and inner faces, followed by the two radial end faces and caps.
	_add_surface_quad(tool, bottom_outer, bottom_outer + lift, next_bottom_outer + lift, next_bottom_outer, 0.0, 1.0, 1.0, 0.0)
	_add_surface_quad(tool, bottom_inner, bottom_inner + lift, next_bottom_inner + lift, next_bottom_inner, 0.0, 1.0, 1.0, 0.0)
	_add_surface_quad(tool, bottom_inner, bottom_inner + lift, bottom_outer + lift, bottom_outer, 0.0, 1.0, 1.0, 0.0)
	_add_surface_quad(tool, next_bottom_outer, next_bottom_outer + lift, next_bottom_inner + lift, next_bottom_inner, 0.0, 1.0, 1.0, 0.0)
	_add_surface_quad(tool, bottom_inner + lift, next_bottom_inner + lift, next_bottom_outer + lift, bottom_outer + lift, 0.0, 1.0, 1.0, 0.0)
	tool.generate_normals()
	var mesh := tool.commit()
	if mesh:
		var instance := MeshInstance3D.new()
		instance.name = node_name
		instance.mesh = mesh
		parent.add_child(instance)

func _add_surface_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u0: float, v0: float, u1: float, v1: float) -> void:
	tool.set_uv(Vector2(u0, v0)); tool.add_vertex(a)
	tool.set_uv(Vector2(u1, v0)); tool.add_vertex(b)
	tool.set_uv(Vector2(u1, v1)); tool.add_vertex(c)
	tool.set_uv(Vector2(u0, v0)); tool.add_vertex(a)
	tool.set_uv(Vector2(u1, v1)); tool.add_vertex(c)
	tool.set_uv(Vector2(u0, v1)); tool.add_vertex(d)

func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, rotation_y: float, material: StandardMaterial3D) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = position
	instance.rotation.y = rotation_y
	parent.add_child(instance)

func _add_cylinder(parent: Node3D, node_name: String, radius: float, height: float, y: float, material: StandardMaterial3D, segments: int, position: Vector3 = Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.material = material
	instance.mesh = mesh
	instance.position = Vector3(position.x, position.y if position != Vector3.ZERO else y, position.z)
	parent.add_child(instance)

func _add_collision_box(parent: StaticBody3D, node_name: String, size: Vector3, position: Vector3, rotation_y: float) -> void:
	var collider := CollisionShape3D.new()
	collider.name = node_name
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = position
	collider.rotation.y = rotation_y
	parent.add_child(collider)

func _make_material(texture_path: String, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not texture_path.is_empty():
		var texture := load(texture_path) as Texture2D
		if texture:
			material.albedo_texture = texture
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material

func _angle_delta(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))
