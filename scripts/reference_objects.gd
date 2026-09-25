@tool
class_name ReferenceObjects
extends Node3D

@export_category("Cylinder Dimensions (8 km dia x 18 km length)")
@export var cylinder_radius: float = 4000.0
@export var cylinder_length: float = 18000.0
@export var num_scattered_balls: int = 50
@export var spawn_ring_markers: bool = true
@export var spawn_dynamic_balls: bool = true

func _ready() -> void:
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
	if spawn_ring_markers:
		_spawn_reference_rings()
	_spawn_landmark_spheres()
	_spawn_scattered_spheres()
	if spawn_dynamic_balls and not Engine.is_editor_hint():
		_spawn_interactive_physics_balls()

func _create_sphere_material(color: Color, roughness: float = 0.3, metallic: float = 0.2, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emission != Color.BLACK:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = 1.5
	return mat

func _spawn_reference_rings() -> void:
	# Rings of spheres along Z to mark distance and angle in the 18 km cylinder
	var z_positions = [-7000.0, -3500.0, 0.0, 3500.0, 7000.0]
	var ring_colors = [
		Color(0.95, 0.25, 0.25), # Red
		Color(0.25, 0.85, 0.35), # Green
		Color(0.25, 0.55, 0.95), # Blue
		Color(0.95, 0.85, 0.20), # Yellow/Gold
		Color(0.85, 0.35, 0.95), # Magenta
		Color(0.20, 0.90, 0.90), # Cyan
		Color(0.95, 0.55, 0.20), # Orange
		Color(0.95, 0.95, 0.95)  # White
	]

	var r_ball = 25.0
	var spawn_theta = -PI * 0.5
	var spawn_z = 0.0
	var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
	if cyl_world and cyl_world.has_method("find_safe_spawn_point"):
		var spawn_info = cyl_world.find_safe_spawn_point()
		spawn_theta = spawn_info["theta"]
		spawn_z = spawn_info["z"]

	for z in z_positions:
		for i in range(8):
			var theta = float(i) * (TAU / 8.0)
			# Keep player spawn area clear
			if absf(wrapf(theta - spawn_theta, -PI, PI)) < 0.25 and absf(z - spawn_z) < 75.0:
				continue
			var col = ring_colors[i]
			var elev = _get_terrain_elevation(theta, z)
			var dist = cylinder_radius - elev - r_ball
			var pos = Vector3(dist * cos(theta), dist * sin(theta), z)

			var body = StaticBody3D.new()
			body.name = "RingBall_Z%d_deg%d" % [int(z), int(rad_to_deg(theta))]
			body.position = pos

			var mesh_inst = MeshInstance3D.new()
			var sphere_mesh = SphereMesh.new()
			sphere_mesh.radius = r_ball
			sphere_mesh.height = r_ball * 2.0
			mesh_inst.mesh = sphere_mesh
			mesh_inst.material_override = _create_sphere_material(col, 0.25, 0.3, col * 0.25)
			body.add_child(mesh_inst)

			var col_shape = CollisionShape3D.new()
			var shape = SphereShape3D.new()
			shape.radius = r_ball
			col_shape.shape = shape
			body.add_child(col_shape)

			add_child(body)

func _spawn_landmark_spheres() -> void:
	# Major landmark beacons across the 18 km landscape
	var landmarks = [
		{"theta": 0.0, "z": -5000.0, "radius": 75.0, "color": Color(0.98, 0.3, 0.1), "name": "Alpha_Sphere"},
		{"theta": PI * 0.5, "z": 5000.0, "radius": 80.0, "color": Color(0.1, 0.7, 0.95), "name": "Beta_Sphere"},
		{"theta": PI, "z": -2500.0, "radius": 65.0, "color": Color(0.9, 0.8, 0.1), "name": "Gamma_Sphere"},
		{"theta": PI * 1.5, "z": 2500.0, "radius": 70.0, "color": Color(0.7, 0.2, 0.9), "name": "Delta_Sphere"},
		{"theta": 0.0, "z": -8700.0, "radius": 90.0, "color": Color(0.2, 0.9, 0.95), "name": "Aft_Spaceport_Beacon"},
		{"theta": PI, "z": 8700.0, "radius": 90.0, "color": Color(0.95, 0.85, 0.2), "name": "Forward_Spaceport_Beacon"},
	]

	for lm in landmarks:
		var r_ball: float = lm["radius"]
		var theta: float = lm["theta"]
		var z: float = lm["z"]
		var col: Color = lm["color"]

		var elev = _get_terrain_elevation(theta, z)
		var dist = cylinder_radius - elev - r_ball
		var pos = Vector3(dist * cos(theta), dist * sin(theta), z)

		var body = StaticBody3D.new()
		body.name = lm["name"]
		body.position = pos

		var mesh_inst = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = r_ball
		sphere_mesh.height = r_ball * 2.0
		mesh_inst.mesh = sphere_mesh
		mesh_inst.material_override = _create_sphere_material(col, 0.2, 0.6, col * 0.4)
		body.add_child(mesh_inst)

		var col_shape = CollisionShape3D.new()
		var shape = SphereShape3D.new()
		shape.radius = r_ball
		col_shape.shape = shape
		body.add_child(col_shape)

		add_child(body)

func _spawn_scattered_spheres() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 42

	var palette = [
		Color(0.85, 0.25, 0.25),
		Color(0.25, 0.75, 0.85),
		Color(0.95, 0.65, 0.15),
		Color(0.45, 0.85, 0.35),
		Color(0.75, 0.35, 0.85),
		Color(0.95, 0.95, 0.35),
		Color(0.20, 0.40, 0.85),
		Color(0.85, 0.85, 0.88),
		Color(0.25, 0.25, 0.28)
	]

	var half_len = (cylinder_length * 0.5) - 300.0

	for i in range(num_scattered_balls):
		var theta = rng.randf_range(0, TAU)
		var z = rng.randf_range(-half_len, half_len)
		var r_ball = rng.randf_range(15.0, 35.0)
		var col = palette[rng.randi() % palette.size()]

		var elev = _get_terrain_elevation(theta, z)
		var dist = cylinder_radius - elev - r_ball
		var pos = Vector3(dist * cos(theta), dist * sin(theta), z)

		var body = StaticBody3D.new()
		body.name = "ScatteredBall_%d" % i
		body.position = pos

		var mesh_inst = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = r_ball
		sphere_mesh.height = r_ball * 2.0
		mesh_inst.mesh = sphere_mesh
		mesh_inst.material_override = _create_sphere_material(col, rng.randf_range(0.2, 0.6), rng.randf_range(0.1, 0.8))
		body.add_child(mesh_inst)

		var col_shape = CollisionShape3D.new()
		var shape = SphereShape3D.new()
		shape.radius = r_ball
		col_shape.shape = shape
		body.add_child(col_shape)

		add_child(body)

func _spawn_interactive_physics_balls() -> void:
	var spawn_theta = -PI * 0.5
	var spawn_z = 0.0

	var cyl_world = get_parent().get_node_or_null("CylinderWorld") if get_parent() else null
	if not cyl_world:
		cyl_world = get_tree().get_first_node_in_group("cylinder_world") if is_inside_tree() else null

	if cyl_world and cyl_world.has_method("find_safe_spawn_point"):
		var spawn_info = cyl_world.find_safe_spawn_point()
		spawn_theta = spawn_info["theta"]
		spawn_z = spawn_info["z"]

	# Add physics balls safely ahead of spawn in -Z direction
	var spawn_z_start = spawn_z - 45.0
	for i in range(6):
		var r_ball = 3.0
		var theta = spawn_theta + float(i - 2.5) * 0.005
		var z = spawn_z_start + float(i) * 8.0
		var elev = _get_terrain_elevation(theta, z)
		var dist = cylinder_radius - elev - r_ball - 0.5
		var pos = Vector3(dist * cos(theta), dist * sin(theta), z)

		var rb = RigidBody3D.new()
		rb.name = "DynamicBall_%d" % i
		rb.position = pos
		rb.mass = 20.0
		rb.custom_integrator = true

		var script_code = load("res://scripts/cylinder_rigidbody.gd")
		if script_code:
			rb.set_script(script_code)
			rb.set("cylinder_radius", cylinder_radius)

		var mesh_inst = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = r_ball
		sphere_mesh.height = r_ball * 2.0
		mesh_inst.mesh = sphere_mesh
		var col = Color(1.0, 0.4, 0.1) if i % 2 == 0 else Color(0.1, 0.8, 1.0)
		mesh_inst.material_override = _create_sphere_material(col, 0.2, 0.5, col * 0.3)
		rb.add_child(mesh_inst)

		var col_shape = CollisionShape3D.new()
		var shape = SphereShape3D.new()
		shape.radius = r_ball
		col_shape.shape = shape
		rb.add_child(col_shape)

		add_child(rb)
