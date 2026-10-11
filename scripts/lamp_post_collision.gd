extends Node3D

const MapAssetLoaderClass = preload("res://scripts/map_asset_loader.gd")

func _ready() -> void:
	if get_node_or_null("SolidCollision"):
		return
	var body := StaticBody3D.new()
	body.name = "SolidCollision"
	add_child(body)
	_add_cylinder(body, "PedestalHull", 0.45, 0.55, Vector3(0.0, 0.27, 0.0))
	_add_cylinder(body, "PostHull", 0.14, 4.2, Vector3(0.0, 2.45, 0.0))
	_add_box(body, "ArmHull", Vector3(0.12, 0.12, 0.95), Vector3(0.0, 4.45, 0.35))
	_add_cylinder(body, "LanternHull", 0.24, 0.55, Vector3(0.0, 4.25, 0.7))
	_add_cylinder(body, "CapHull", 0.34, 0.22, Vector3(0.0, 4.6, 0.7))

func _add_cylinder(body: StaticBody3D, shape_name: String, radius: float, height: float, center: Vector3) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collider := CollisionShape3D.new()
	collider.name = shape_name
	collider.shape = shape
	collider.position = center
	body.add_child(collider)
	MapAssetLoaderClass._attach_collision_debug_mesh(collider)

func _add_box(body: StaticBody3D, shape_name: String, dimensions: Vector3, center: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collider := CollisionShape3D.new()
	collider.name = shape_name
	collider.shape = shape
	collider.position = center
	body.add_child(collider)
	MapAssetLoaderClass._attach_collision_debug_mesh(collider)
