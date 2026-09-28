@tool
class_name ReferenceObjects
extends Node3D

@export_category("Cylinder Dimensions (8 km dia x 18 km length)")
@export var cylinder_radius: float = 4000.0
@export var cylinder_length: float = 18000.0
@export var object_map_path: String = "res://assets/maps/default/object_map.json"

func _ready() -> void:
	add_to_group("reference_objects")
	# Avoid spawning duplicate objects when running in tool mode repeatedly
	for child in get_children():
		child.queue_free()

	spawn_all_markers()

func _get_terrain_elevation(theta: float, z: float) -> float:
	var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
	if not cyl_world:
		cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null
	if cyl_world and cyl_world.has_method("get_elevation_at"):
		return cyl_world.get_elevation_at(theta, z)
	return 0.0

func spawn_all_markers() -> void:
	var spawned_from_json = _load_and_spawn_from_json()
	if not spawned_from_json:
		_spawn_default_campfires()
		_spawn_default_beacon_lanterns()

func _load_and_spawn_from_json() -> bool:
	var target_path = object_map_path
	if not FileAccess.file_exists(target_path):
		if FileAccess.file_exists("res://assets/maps/object_map.json"):
			target_path = "res://assets/maps/object_map.json"
		else:
			return false

	var f = FileAccess.open(target_path, FileAccess.READ)
	if not f:
		return false

	var json_str = f.get_as_text()
	f.close()

	var json_inst = JSON.new()
	var err = json_inst.parse(json_str)
	if err != OK:
		push_warning("ReferenceObjects: Failed to parse object_map.json: %s" % json_inst.get_error_message())
		return false

	var data = json_inst.data
	if not (data is Dictionary) or not data.has("objects"):
		return false

	var objects_arr = data["objects"] as Array
	if objects_arr.is_empty():
		return false

	for obj in objects_arr:
		if not (obj is Dictionary):
			continue
		var obj_type_int: int = int(obj.get("object_type", 0))
		var obj_type: SurfaceLightObject.ObjectType = SurfaceLightObject.ObjectType.CAMPFIRE
		if obj_type_int == 1:
			obj_type = SurfaceLightObject.ObjectType.LAMP_POST
		elif obj_type_int == 2:
			obj_type = SurfaceLightObject.ObjectType.BEACON_LANTERN
		elif obj_type_int == 3:
			obj_type = SurfaceLightObject.ObjectType.BRIDGE
		elif obj_type_int == 4:
			obj_type = SurfaceLightObject.ObjectType.BONFIRE
		elif obj_type_int == 5:
			obj_type = SurfaceLightObject.ObjectType.HOUSE
		elif obj_type_int == 6:
			obj_type = SurfaceLightObject.ObjectType.TREE
		elif obj_type_int == 7:
			obj_type = SurfaceLightObject.ObjectType.WINDMILL

		var theta: float = float(obj.get("theta", 0.0))
		var z: float = float(obj.get("z", 0.0))
		var elev: float = float(obj.get("elevation", _get_terrain_elevation(theta, z)))
		var actual_elev = _get_terrain_elevation(theta, z)
		if actual_elev > 0.0:
			elev = actual_elev

		var col_arr = obj.get("light_color", [1.0, 0.58, 0.20])
		var col = Color(col_arr[0], col_arr[1], col_arr[2]) if col_arr.size() >= 3 else Color.WHITE
		var light_range: float = float(obj.get("light_range", 45.0))
		var light_energy: float = float(obj.get("light_energy", 5.5))
		var yaw_angle: float = float(obj.get("yaw_rad", 0.0))

		var custom_pos = Vector3.ZERO
		var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
		if not cyl_world:
			cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null
		if cyl_world and cyl_world.has_method("get_surface_mesh_point_and_normal"):
			var pt_info = cyl_world.get_surface_mesh_point_and_normal(theta, z)
			if not pt_info.is_empty():
				custom_pos = pt_info.get("position", Vector3.ZERO)
				elev = pt_info.get("elevation", elev)

		var inst = SurfaceLightObject.create_on_cylinder(
			obj_type,
			theta,
			z,
			cylinder_radius,
			elev,
			col,
			light_range,
			yaw_angle,
			Vector3.ZERO,
			custom_pos
		)
		inst.light_energy = light_energy
		inst.name = str(obj.get("name", "SurfaceLightObject"))
		add_child(inst)

	return true

func _spawn_default_campfires() -> void:
	var spawn_theta = -PI * 0.5
	var spawn_z = 0.0

	var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
	if not cyl_world:
		cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null

	if cyl_world and cyl_world.has_method("find_safe_spawn_point"):
		var spawn_info = cyl_world.find_safe_spawn_point()
		spawn_theta = spawn_info["theta"]
		spawn_z = spawn_info["z"]

	var campfire_locs = [
		{"theta": spawn_theta, "z": spawn_z - 16.0, "name": "Spawn_Welcoming_Campfire", "range": 45.0},
		{"theta": spawn_theta + 0.22, "z": spawn_z - 180.0, "name": "Lakeside_Campfire", "range": 40.0},
		{"theta": spawn_theta - 0.18, "z": spawn_z + 240.0, "name": "Meadow_Campfire", "range": 40.0},
		{"theta": spawn_theta + 0.35, "z": -2500.0, "name": "South_Waystation_Campfire", "range": 45.0},
		{"theta": spawn_theta - 0.25, "z": 2500.0, "name": "North_Waystation_Campfire", "range": 45.0},
		{"theta": spawn_theta + 0.10, "z": -6500.0, "name": "South_Outpost_Campfire", "range": 50.0},
		{"theta": spawn_theta - 0.10, "z": 6500.0, "name": "North_Outpost_Campfire", "range": 50.0},
		{"theta": spawn_theta, "z": -8400.0, "name": "South_EndCap_Campfire", "range": 55.0},
		{"theta": spawn_theta, "z": 8400.0, "name": "North_EndCap_Campfire", "range": 55.0}
	]

	for loc in campfire_locs:
		var theta: float = loc["theta"]
		var z: float = loc["z"]
		var elev = _get_terrain_elevation(theta, z)
		var custom_pos = Vector3.ZERO
		if cyl_world and cyl_world.has_method("get_surface_mesh_point_and_normal"):
			var pt_info = cyl_world.get_surface_mesh_point_and_normal(theta, z)
			if not pt_info.is_empty():
				custom_pos = pt_info.get("position", Vector3.ZERO)
				elev = pt_info.get("elevation", elev)

		var fire = SurfaceLightObject.create_on_cylinder(
			SurfaceLightObject.ObjectType.CAMPFIRE,
			theta,
			z,
			cylinder_radius,
			elev,
			Color(1.0, 0.58, 0.20),
			loc["range"],
			0.0,
			Vector3.ZERO,
			custom_pos
		)
		fire.name = loc["name"]
		add_child(fire)

func _spawn_default_beacon_lanterns() -> void:
	var spawn_theta = -PI * 0.5
	var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
	if not cyl_world:
		cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null

	if cyl_world and cyl_world.has_method("find_safe_spawn_point"):
		var spawn_info = cyl_world.find_safe_spawn_point()
		spawn_theta = spawn_info["theta"]

	var beacon_z_caps = [-8550.0, 8550.0]
	for z_cap in beacon_z_caps:
		for k in range(4):
			var th = spawn_theta + float(k - 1.5) * 0.03
			var el = _get_terrain_elevation(th, z_cap)
			var custom_pos = Vector3.ZERO
			if cyl_world and cyl_world.has_method("get_surface_mesh_point_and_normal"):
				var pt_info = cyl_world.get_surface_mesh_point_and_normal(th, z_cap)
				if not pt_info.is_empty():
					custom_pos = pt_info.get("position", Vector3.ZERO)
					el = pt_info.get("elevation", el)

			var beacon = SurfaceLightObject.create_on_cylinder(
				SurfaceLightObject.ObjectType.BEACON_LANTERN,
				th,
				z_cap,
				cylinder_radius,
				el,
				Color(0.20, 0.88, 1.0),
				40.0,
				0.0,
				Vector3.ZERO,
				custom_pos
			)
			beacon.name = "EndCapBeacon_Z%d_%d" % [int(z_cap), k]
			add_child(beacon)

func spawn_light_emitter(
	type: SurfaceLightObject.ObjectType,
	theta: float,
	z: float,
	custom_col: Color = Color.WHITE,
	custom_range: float = -1.0
) -> SurfaceLightObject:
	var elev = _get_terrain_elevation(theta, z)
	var custom_pos = Vector3.ZERO
	var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
	if not cyl_world:
		cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null
	if cyl_world and cyl_world.has_method("get_surface_mesh_point_and_normal"):
		var pt_info = cyl_world.get_surface_mesh_point_and_normal(theta, z)
		if not pt_info.is_empty():
			custom_pos = pt_info.get("position", Vector3.ZERO)
			elev = pt_info.get("elevation", elev)

	var obj = SurfaceLightObject.create_on_cylinder(type, theta, z, cylinder_radius, elev, custom_col, custom_range, 0.0, Vector3.ZERO, custom_pos)
	add_child(obj)
	return obj
