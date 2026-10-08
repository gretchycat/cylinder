class_name MapObjectFactory
extends RefCounted
const Config = preload("res://scripts/map_config.gd")
const ObjectClass = preload("res://scripts/surface_light_object.gd")

static func create(doc: Dictionary, record: Dictionary, world: Node = null) -> Node3D:
	var definition: Dictionary = doc.objects.model_catalog[record.asset]
	var theta: float = record.get("theta", 0)
	var z: float = record.get("z", 0)
	if record.has("transform") and (not record.has("theta") or not record.has("z")):
		var t_arr: Array = record.transform
		if t_arr.size() >= 12:
			theta = atan2(float(t_arr[10]), float(t_arr[9]))
			z = float(t_arr[11])
	var point = world.get_surface_mesh_point_and_normal(theta, z) if world and world.has_method("get_surface_mesh_point_and_normal") else {}
	var elev: float = point.get("elevation", record.get("elevation", 0))

	var ground_offset: float = record.get("ground_offset_m", Config.get_object_ground_offset(definition, record.asset))
	var align_norm: bool = record.get("align_to_normal", Config.get_object_align_to_normal(definition, record.asset))
	var yaw: float = record.get("yaw_rad", 0.0)
	var pitch: float = record.get("pitch_rad", 0.0)
	var roll: float = record.get("roll_rad", 0.0)

	var inst = ObjectClass.create_on_cylinder(
		int(definition.behavior_type), theta, z, doc.geometry.cylinder_radius_m, elev,
		Config.color(record.get("light_color", definition.light_color)), record.get("light_range_m", definition.light_range_m),
		yaw, point.get("normal", Vector3.ZERO), point.get("position", Vector3.ZERO),
		int(definition.variant), Config.resolve_map_asset_path(doc, definition.scene_path), Vector3.ZERO,
		ground_offset, align_norm, pitch, roll
	)
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
		if t.size() >= 12:
			var saved_basis = Basis(Vector3(t[0],t[1],t[2]),Vector3(t[3],t[4],t[5]),Vector3(t[6],t[7],t[8]))
			var saved_pos = Vector3(t[9],t[10],t[11])
			if point.has("position") and point.position != Vector3.ZERO:
				saved_pos = point.position
				if ground_offset != 0.0:
					var up = point.normal if align_norm else Vector3(-point.position.x, -point.position.y, 0.0).normalized()
					saved_pos += up * ground_offset
			inst.transform = Transform3D(saved_basis, saved_pos)
	return inst
