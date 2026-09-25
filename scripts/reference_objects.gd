@tool
class_name ReferenceObjects
extends Node3D

@export_category("Cylinder Dimensions (8 km dia x 18 km length)")
@export var cylinder_radius: float = 4000.0
@export var cylinder_length: float = 18000.0

func _ready() -> void:
	add_to_group("reference_objects")
	# Avoid spawning duplicate objects when running in tool mode repeatedly
	for child in get_children():
		child.queue_free()

	spawn_all_markers()

func _get_terrain_elevation(theta: float, z: float) -> float:
	var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
	if cyl_world and cyl_world.has_method("get_elevation_at"):
		return cyl_world.get_elevation_at(theta, z)
	return 0.0

func spawn_all_markers() -> void:
	_spawn_campfires()
	_spawn_surface_lamps()

func _spawn_campfires() -> void:
	var spawn_theta = -PI * 0.5
	var spawn_z = 0.0

	var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
	if not cyl_world:
		cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null

	if cyl_world and cyl_world.has_method("find_safe_spawn_point"):
		var spawn_info = cyl_world.find_safe_spawn_point()
		spawn_theta = spawn_info["theta"]
		spawn_z = spawn_info["z"]

	# Key Campfire Locations across the cylinder
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
		var fire = SurfaceLightObject.create_on_cylinder(
			SurfaceLightObject.ObjectType.CAMPFIRE,
			theta,
			z,
			cylinder_radius,
			elev,
			Color(1.0, 0.58, 0.20),
			loc["range"]
		)
		fire.name = loc["name"]
		add_child(fire)

func _spawn_surface_lamps() -> void:
	var spawn_theta = -PI * 0.5
	var spawn_z = 0.0

	var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
	if not cyl_world:
		cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null

	if cyl_world and cyl_world.has_method("find_safe_spawn_point"):
		var spawn_info = cyl_world.find_safe_spawn_point()
		spawn_theta = spawn_info["theta"]
		spawn_z = spawn_info["z"]

	# 1. Walkway of Lamp Posts near Player Spawn
	var num_spawn_lamps = 6
	for i in range(num_spawn_lamps):
		var z_lamp = spawn_z - 8.0 - float(i) * 22.0
		# Left side lamp
		var theta_l = spawn_theta - 0.0035
		var elev_l = _get_terrain_elevation(theta_l, z_lamp)
		var lamp_l = SurfaceLightObject.create_on_cylinder(
			SurfaceLightObject.ObjectType.LAMP_POST,
			theta_l,
			z_lamp,
			cylinder_radius,
			elev_l,
			Color(1.0, 0.92, 0.78),
			35.0
		)
		lamp_l.name = "SpawnLamp_L_%d" % i
		add_child(lamp_l)

		# Right side lamp
		var theta_r = spawn_theta + 0.0035
		var elev_r = _get_terrain_elevation(theta_r, z_lamp)
		var lamp_r = SurfaceLightObject.create_on_cylinder(
			SurfaceLightObject.ObjectType.LAMP_POST,
			theta_r,
			z_lamp,
			cylinder_radius,
			elev_r,
			Color(1.0, 0.92, 0.78),
			35.0
		)
		lamp_r.name = "SpawnLamp_R_%d" % i
		add_child(lamp_r)

	# 2. Highway / Road Lamp Posts across the 18 km cylinder
	var road_z_positions = [-7500.0, -5000.0, -3000.0, -1200.0, 1200.0, 3000.0, 5000.0, 7500.0]
	for z_pos in road_z_positions:
		for offset_side in [-0.006, 0.006]:
			var th = spawn_theta + offset_side
			var el = _get_terrain_elevation(th, z_pos)
			var lamp = SurfaceLightObject.create_on_cylinder(
				SurfaceLightObject.ObjectType.LAMP_POST,
				th,
				z_pos,
				cylinder_radius,
				el,
				Color(1.0, 0.90, 0.75),
				38.0
			)
			lamp.name = "RoadLamp_Z%d_s%d" % [int(z_pos), 1 if offset_side > 0 else 0]
			add_child(lamp)

	# 3. Beacon Lanterns near Spaceport End Caps
	var beacon_z_caps = [-8550.0, 8550.0]
	for z_cap in beacon_z_caps:
		for k in range(4):
			var th = spawn_theta + float(k - 1.5) * 0.03
			var el = _get_terrain_elevation(th, z_cap)
			var beacon = SurfaceLightObject.create_on_cylinder(
				SurfaceLightObject.ObjectType.BEACON_LANTERN,
				th,
				z_cap,
				cylinder_radius,
				el,
				Color(0.20, 0.88, 1.0),
				40.0
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
	var obj = SurfaceLightObject.create_on_cylinder(type, theta, z, cylinder_radius, elev, custom_col, custom_range)
	add_child(obj)
	return obj
