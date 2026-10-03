class_name MapObjectFactory
extends RefCounted
const Config = preload("res://scripts/map_config.gd")
const ObjectClass = preload("res://scripts/surface_light_object.gd")

static func create(doc: Dictionary, record: Dictionary, world: Node = null) -> Node3D:
	var definition: Dictionary = doc.objects.model_catalog[record.asset]
	var theta: float = record.get("theta", 0)
	var z: float = record.get("z", 0)
	var point = world.get_surface_mesh_point_and_normal(theta, z) if world else {}
	var inst = ObjectClass.create_on_cylinder(int(definition.behavior_type), theta, z, doc.geometry.cylinder_radius_m, point.get("elevation", 0), Config.color(record.get("light_color", definition.light_color)), record.get("light_range_m", definition.light_range_m), record.get("yaw_rad", 0), point.get("normal", Vector3.ZERO), point.get("position", Vector3.ZERO), int(definition.variant), Config.resolve_map_asset_path(doc, definition.scene_path))
	inst.asset_id = record.asset
	inst.instance_id = record.get("id", "")
	inst.name = record.get("name", definition.name)
	inst.tint = Config.color(record.get("tint", definition.tint))
	inst.light_color = Config.color(record.get("light_color", definition.light_color))
	inst.light_energy = record.get("light_energy", definition.light_energy)
	inst.enable_flicker = record.get("flicker", definition.flicker)
	inst.scale *= float(record.get("scale", 1))
	if record.has("transform"):
		var t: Array = record.transform
		inst.transform = Transform3D(Basis(Vector3(t[0],t[1],t[2]),Vector3(t[3],t[4],t[5]),Vector3(t[6],t[7],t[8])),Vector3(t[9],t[10],t[11]))
	return inst
