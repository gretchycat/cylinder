@tool
class_name CylinderGenerator
extends Node3D

@export var radius: float = 80.0:
	set(val):
		radius = max(val, 5.0)
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var cylinder_length: float = 300.0:
	set(val):
		cylinder_length = max(val, 10.0)
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var radial_segments: int = 96:
	set(val):
		radial_segments = clampi(val, 16, 256)
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var length_segments: int = 40:
	set(val):
		length_segments = clampi(val, 2, 128)
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var include_end_caps: bool = true:
	set(val):
		include_end_caps = val
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var surface_material: Material

var mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var collision_shape: CollisionShape3D

func _ready() -> void:
	generate_cylinder()

func generate_cylinder() -> void:
	# Ensure child nodes exist
	if not mesh_instance:
		mesh_instance = get_node_or_null("MeshInstance3D")
		if not mesh_instance:
			mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "MeshInstance3D"
			add_child(mesh_instance)
			if Engine.is_editor_hint():
				mesh_instance.owner = get_tree().edited_scene_root

	if not static_body:
		static_body = get_node_or_null("StaticBody3D")
		if not static_body:
			static_body = StaticBody3D.new()
			static_body.name = "StaticBody3D"
			add_child(static_body)
			if Engine.is_editor_hint():
				static_body.owner = get_tree().edited_scene_root

	if not collision_shape:
		collision_shape = static_body.get_node_or_null("CollisionShape3D")
		if not collision_shape:
			collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape3D"
			static_body.add_child(collision_shape)
			if Engine.is_editor_hint():
				collision_shape.owner = get_tree().edited_scene_root

	# Load default surface material if none assigned
	if surface_material == null:
		var shader = load("res://assets/shaders/cylinder_surface.gdshader")
		if shader:
			var mat = ShaderMaterial.new()
			mat.shader = shader
			surface_material = mat
		else:
			var standard_mat = StandardMaterial3D.new()
			standard_mat.albedo_color = Color(0.48, 0.50, 0.53)
			standard_mat.roughness = 0.7
			surface_material = standard_mat

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(surface_material)

	var half_len = cylinder_length * 0.5
	var d_theta = TAU / float(radial_segments)
	var d_z = cylinder_length / float(length_segments)

	# --- Generate Cylinder Tube (Inward Facing) ---
	for j in range(length_segments + 1):
		var z = -half_len + float(j) * d_z
		var v_coord = float(j) / float(length_segments)

		for i in range(radial_segments + 1):
			var theta = float(i) * d_theta
			var u_coord = float(i) / float(radial_segments)

			var cos_t = cos(theta)
			var sin_t = sin(theta)

			var pos = Vector3(radius * cos_t, radius * sin_t, z)
			# Normal points towards axis (0, 0, z)
			var normal = Vector3(-cos_t, -sin_t, 0.0)

			st.set_normal(normal)
			st.set_uv(Vector2(u_coord, v_coord))
			st.add_vertex(pos)

	var stride = radial_segments + 1
	for j in range(length_segments):
		for i in range(radial_segments):
			var i00 = j * stride + i
			var i10 = j * stride + (i + 1)
			var i01 = (j + 1) * stride + i
			var i11 = (j + 1) * stride + (i + 1)

			# Inward facing triangles (CCW when viewed from cylinder axis)
			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i01)

			st.add_index(i10)
			st.add_index(i11)
			st.add_index(i01)

	# --- Generate End Caps (if enabled) ---
	if include_end_caps:
		var cap_divisions = radial_segments

		# Cap 1: z = -half_len (inward normal is +Z)
		var base_vert_idx_cap1 = st.get_vertex_count() if st.has_method("get_vertex_count") else -1
		# Center vertex
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(Vector3(0, 0, -half_len))
		var center_idx1 = stride * (length_segments + 1)

		for i in range(cap_divisions + 1):
			var theta = float(i) * d_theta
			var cos_t = cos(theta)
			var sin_t = sin(theta)
			var pos = Vector3(radius * cos_t, radius * sin_t, -half_len)
			st.set_normal(Vector3(0, 0, 1))
			st.set_uv(Vector2(0.5 + 0.5 * cos_t, 0.5 + 0.5 * sin_t))
			st.add_vertex(pos)

		for i in range(cap_divisions):
			var p_curr = center_idx1 + 1 + i
			var p_next = center_idx1 + 1 + (i + 1)
			st.add_index(center_idx1)
			st.add_index(p_curr)
			st.add_index(p_next)

		# Cap 2: z = +half_len (inward normal is -Z)
		var center_idx2 = center_idx1 + 1 + (cap_divisions + 1)
		st.set_normal(Vector3(0, 0, -1))
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(Vector3(0, 0, half_len))

		for i in range(cap_divisions + 1):
			var theta = float(i) * d_theta
			var cos_t = cos(theta)
			var sin_t = sin(theta)
			var pos = Vector3(radius * cos_t, radius * sin_t, half_len)
			st.set_normal(Vector3(0, 0, -1))
			st.set_uv(Vector2(0.5 + 0.5 * cos_t, 0.5 + 0.5 * sin_t))
			st.add_vertex(pos)

		for i in range(cap_divisions):
			var p_curr = center_idx2 + 1 + i
			var p_next = center_idx2 + 1 + (i + 1)
			st.add_index(center_idx2)
			st.add_index(p_next)
			st.add_index(p_curr)

	st.generate_tangents()
	var mesh = st.commit()
	mesh_instance.mesh = mesh

	# Generate concave trimesh collision for accurate inner-surface physics
	var shape = mesh.create_trimesh_shape()
	shape.backface_collision = true
	collision_shape.shape = shape
