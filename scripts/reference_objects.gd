@tool
class_name ReferenceObjects
extends Node3D

@export var cylinder_radius: float = 80.0
@export var cylinder_length: float = 300.0
@export var num_scattered_balls: int = 40
@export var spawn_ring_markers: bool = true
@export var spawn_dynamic_balls: bool = true

func _ready() -> void:
	# Avoid spawning duplicate objects when running in tool mode repeatedly
	for child in get_children():
		child.queue_free()

	spawn_all_markers()

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
		mat.emission_energy_multiplier = 1.0
	return mat

func _spawn_reference_rings() -> void:
	# Create rings of spheres along Z to mark distance and angle
	var z_positions = [-100.0, -50.0, 0.0, 50.0, 100.0]
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

	var r_ball = 1.6
	for z in z_positions:
		for i in range(8):
			if is_equal_approx(z, 0.0) and i == 6:
				continue # Keep player spawn area at z=0, deg 270 completely clear
			var theta = float(i) * (TAU / 8.0)
			var col = ring_colors[i]
			var dist = cylinder_radius - r_ball
			var pos = Vector3(dist * cos(theta), dist * sin(theta), z)

			var body = StaticBody3D.new()
			body.name = "RingBall_Z%d_deg%d" % [int(z), int(rad_to_deg(theta))]
			body.position = pos

			var mesh_inst = MeshInstance3D.new()
			var sphere_mesh = SphereMesh.new()
			sphere_mesh.radius = r_ball
			sphere_mesh.height = r_ball * 2.0
			mesh_inst.mesh = sphere_mesh
			mesh_inst.material_override = _create_sphere_material(col, 0.25, 0.3, col * 0.15)
			body.add_child(mesh_inst)

			var col_shape = CollisionShape3D.new()
			var shape = SphereShape3D.new()
			shape.radius = r_ball
			col_shape.shape = shape
			body.add_child(col_shape)

			add_child(body)

func _spawn_landmark_spheres() -> void:
	# Major landmark spheres - large navigation anchors
	var landmarks = [
		{"theta": 0.0, "z": -60.0, "radius": 4.5, "color": Color(0.98, 0.3, 0.1), "name": "Alpha_Sphere"},
		{"theta": PI * 0.5, "z": 60.0, "radius": 5.0, "color": Color(0.1, 0.7, 0.95), "name": "Beta_Sphere"},
		{"theta": PI, "z": -30.0, "radius": 4.0, "color": Color(0.9, 0.8, 0.1), "name": "Gamma_Sphere"},
		{"theta": PI * 1.5, "z": 30.0, "radius": 4.5, "color": Color(0.7, 0.2, 0.9), "name": "Delta_Sphere"},
	]

	for lm in landmarks:
		var r_ball: float = lm["radius"]
		var theta: float = lm["theta"]
		var z: float = lm["z"]
		var col: Color = lm["color"]

		var dist = cylinder_radius - r_ball
		var pos = Vector3(dist * cos(theta), dist * sin(theta), z)

		var body = StaticBody3D.new()
		body.name = lm["name"]
		body.position = pos

		var mesh_inst = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = r_ball
		sphere_mesh.height = r_ball * 2.0
		mesh_inst.mesh = sphere_mesh
		mesh_inst.material_override = _create_sphere_material(col, 0.2, 0.6, col * 0.3)
		body.add_child(mesh_inst)

		var col_shape = CollisionShape3D.new()
		var shape = SphereShape3D.new()
		shape.radius = r_ball
		col_shape.shape = shape
		body.add_child(col_shape)

		add_child(body)

func _spawn_scattered_spheres() -> void:
	# Pseudo-random but deterministic placement of scattered spheres
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
		Color(0.85, 0.85, 0.88), # Pearl
		Color(0.25, 0.25, 0.28)  # Obsidian
	]

	var half_len = (cylinder_length * 0.5) - 20.0

	for i in range(num_scattered_balls):
		var theta = rng.randf_range(0, TAU)
		var z = rng.randf_range(-half_len, half_len)
		var r_ball = rng.randf_range(0.8, 2.8)
		var col = palette[rng.randi() % palette.size()]

		var dist = cylinder_radius - r_ball
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
	# Add a cluster of dynamic physics balls safely ahead of spawn
	# Spawn near bottom (theta = -PI/2, i.e. x=0, y=-radius)
	var spawn_z_start = -45.0
	for i in range(6):
		var r_ball = 1.0
		var theta = -PI * 0.5 + float(i - 2.5) * 0.05
		var z = spawn_z_start + float(i) * 3.5
		var dist = cylinder_radius - r_ball - 0.5
		var pos = Vector3(dist * cos(theta), dist * sin(theta), z)

		var rb = RigidBody3D.new()
		rb.name = "DynamicBall_%d" % i
		rb.position = pos
		rb.mass = 5.0
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
		mesh_inst.material_override = _create_sphere_material(col, 0.2, 0.5, col * 0.2)
		rb.add_child(mesh_inst)

		var col_shape = CollisionShape3D.new()
		var shape = SphereShape3D.new()
		shape.radius = r_ball
		col_shape.shape = shape
		rb.add_child(col_shape)

		add_child(rb)
