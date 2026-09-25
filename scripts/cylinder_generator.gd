@tool
class_name CylinderGenerator
extends Node3D

const TerrainManagerClass = preload("res://scripts/terrain_manager.gd")

@export_category("Cylinder Dimensions (8 km x 8 km)")
@export var radius: float = 4000.0: # 8 km diameter = 4 km radius
	set(val):
		radius = max(val, 10.0)
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var cylinder_length: float = 8000.0: # 8 km length
	set(val):
		cylinder_length = max(val, 20.0)
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export_category("Mesh Tessellation")
@export var radial_segments: int = 144:
	set(val):
		radial_segments = clampi(val, 16, 256)
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var length_segments: int = 80:
	set(val):
		length_segments = clampi(val, 4, 160)
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var include_end_caps: bool = true:
	set(val):
		include_end_caps = val
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export_category("Terrain & Elevation")
@export var elevation_variance: float = 10.0: # 10 m default variance
	set(val):
		elevation_variance = max(val, 0.0)
		if terrain_manager:
			terrain_manager.elevation_variance = elevation_variance
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var water_level: float = 4.0: # 4 m from elevation 0
	set(val):
		water_level = max(val, 0.0)
		if terrain_manager:
			terrain_manager.water_level = water_level
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var surface_material: Material
@export var water_material: Material

var terrain_manager: TerrainManagerClass

var mesh_instance: MeshInstance3D
var water_mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var collision_shape: CollisionShape3D

func _ready() -> void:
	if not terrain_manager:
		terrain_manager = TerrainManagerClass.new(144, 80, elevation_variance, water_level)
	generate_cylinder()

func get_elevation_at(theta: float, z: float) -> float:
	if not terrain_manager:
		terrain_manager = TerrainManagerClass.new(144, 80, elevation_variance, water_level)
	return terrain_manager.get_elevation(theta, z, cylinder_length)

func get_terrain_type_at(theta: float, z: float) -> int:
	if not terrain_manager:
		terrain_manager = TerrainManagerClass.new(144, 80, elevation_variance, water_level)
	return terrain_manager.get_terrain_type(theta, z, cylinder_length)

func get_surface_radius_at(theta: float, z: float) -> float:
	return radius - get_elevation_at(theta, z)

func generate_cylinder() -> void:
	if not terrain_manager:
		terrain_manager = TerrainManagerClass.new(radial_segments, length_segments, elevation_variance, water_level)

	# Ensure child nodes exist
	if not mesh_instance:
		mesh_instance = get_node_or_null("MeshInstance3D")
		if not mesh_instance:
			mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "MeshInstance3D"
			add_child(mesh_instance)
			if Engine.is_editor_hint():
				mesh_instance.owner = get_tree().edited_scene_root

	if not water_mesh_instance:
		water_mesh_instance = get_node_or_null("WaterMeshInstance3D")
		if not water_mesh_instance:
			water_mesh_instance = MeshInstance3D.new()
			water_mesh_instance.name = "WaterMeshInstance3D"
			add_child(water_mesh_instance)
			if Engine.is_editor_hint():
				water_mesh_instance.owner = get_tree().edited_scene_root

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

	# Load terrain and water materials
	if surface_material == null:
		surface_material = _create_terrain_material()
	if water_material == null:
		water_material = _create_water_material()

	_build_terrain_mesh()
	_build_water_mesh()

func _create_terrain_material() -> ShaderMaterial:
	var shader = load("res://assets/shaders/cylinder_terrain.gdshader")
	if not shader:
		return null
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tex_sand", load("res://assets/textures/terrain/sand.png"))
	mat.set_shader_parameter("tex_dirt", load("res://assets/textures/terrain/dirt.png"))
	mat.set_shader_parameter("tex_grass", load("res://assets/textures/terrain/grass.png"))
	mat.set_shader_parameter("tex_concrete", load("res://assets/textures/terrain/concrete.png"))
	mat.set_shader_parameter("tex_road", load("res://assets/textures/terrain/road.png"))
	mat.set_shader_parameter("tex_sand_to_grass", load("res://assets/textures/terrain/sand_to_grass.png"))
	mat.set_shader_parameter("tex_dirt_to_grass", load("res://assets/textures/terrain/dirt_to_grass.png"))
	mat.set_shader_parameter("tex_road_edge", load("res://assets/textures/terrain/road_edge.png"))
	mat.set_shader_parameter("cylinder_radius", radius)
	mat.set_shader_parameter("water_level", water_level)
	mat.set_shader_parameter("max_elevation", elevation_variance)
	return mat

func _create_water_material() -> ShaderMaterial:
	var shader = load("res://assets/shaders/cylinder_water.gdshader")
	if not shader:
		return null
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("cylinder_radius", radius - water_level)
	return mat

func _build_terrain_mesh() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(surface_material)

	var half_len = cylinder_length * 0.5
	var d_theta = TAU / float(radial_segments)
	var d_z = cylinder_length / float(length_segments)

	# --- Generate Cylinder Tube with Elevation Displacements ---
	for j in range(length_segments + 1):
		var z = -half_len + float(j) * d_z
		var v_coord = float(j) / float(length_segments)

		for i in range(radial_segments + 1):
			var theta = float(i) * d_theta
			var u_coord = float(i) / float(radial_segments)

			var cos_t = cos(theta)
			var sin_t = sin(theta)

			# Sample elevation from 2D RPG heightmap
			var elev = terrain_manager.get_elevation(theta, z, cylinder_length)
			var t_type = terrain_manager.get_terrain_type(theta, z, cylinder_length)

			# Inner surface radius is reduced by elevation inward
			var r_surface = radius - elev
			var pos = Vector3(r_surface * cos_t, r_surface * sin_t, z)

			# Approximate normal: points inward toward axis (-cos, -sin)
			var normal = Vector3(-cos_t, -sin_t, 0.0).normalized()

			st.set_normal(normal)
			st.set_uv(Vector2(u_coord, v_coord))
			# Pass elevation and terrain type through vertex COLOR attribute
			st.set_color(Color(elev / max(elevation_variance, 0.1), float(t_type) / 8.0, 0.0, 1.0))
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
		var center_idx1 = stride * (length_segments + 1)

		# Cap 1: z = -half_len (inward normal is +Z)
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(Vector2(0.5, 0.5))
		st.set_color(Color(0.5, 0.5, 0.5, 1.0))
		st.add_vertex(Vector3(0, 0, -half_len))

		for i in range(cap_divisions + 1):
			var theta = float(i) * d_theta
			var cos_t = cos(theta)
			var sin_t = sin(theta)
			var elev = terrain_manager.get_elevation(theta, -half_len, cylinder_length)
			var r_surface = radius - elev
			var pos = Vector3(r_surface * cos_t, r_surface * sin_t, -half_len)
			st.set_normal(Vector3(0, 0, 1))
			st.set_uv(Vector2(0.5 + 0.5 * cos_t, 0.5 + 0.5 * sin_t))
			st.set_color(Color(elev / max(elevation_variance, 0.1), 0.5, 0.0, 1.0))
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
		st.set_color(Color(0.5, 0.5, 0.5, 1.0))
		st.add_vertex(Vector3(0, 0, half_len))

		for i in range(cap_divisions + 1):
			var theta = float(i) * d_theta
			var cos_t = cos(theta)
			var sin_t = sin(theta)
			var elev = terrain_manager.get_elevation(theta, half_len, cylinder_length)
			var r_surface = radius - elev
			var pos = Vector3(r_surface * cos_t, r_surface * sin_t, half_len)
			st.set_normal(Vector3(0, 0, -1))
			st.set_uv(Vector2(0.5 + 0.5 * cos_t, 0.5 + 0.5 * sin_t))
			st.set_color(Color(elev / max(elevation_variance, 0.1), 0.5, 0.0, 1.0))
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

	# Concave trimesh physics collision
	var shape = mesh.create_trimesh_shape()
	shape.backface_collision = true
	collision_shape.shape = shape

func _build_water_mesh() -> void:
	# Build water surface mesh at constant radius (radius - water_level)
	var water_st = SurfaceTool.new()
	water_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	water_st.set_material(water_material)

	var water_r = radius - water_level # 3996.0 m
	var half_len = cylinder_length * 0.5
	var d_theta = TAU / float(radial_segments)
	var d_z = cylinder_length / float(length_segments)

	for j in range(length_segments + 1):
		var z = -half_len + float(j) * d_z
		var v_coord = float(j) / float(length_segments)

		for i in range(radial_segments + 1):
			var theta = float(i) * d_theta
			var u_coord = float(i) / float(radial_segments)
			var cos_t = cos(theta)
			var sin_t = sin(theta)

			var pos = Vector3(water_r * cos_t, water_r * sin_t, z)
			var normal = Vector3(-cos_t, -sin_t, 0.0)

			water_st.set_normal(normal)
			water_st.set_uv(Vector2(u_coord, v_coord))
			water_st.add_vertex(pos)

	var stride = radial_segments + 1
	for j in range(length_segments):
		for i in range(radial_segments):
			var i00 = j * stride + i
			var i10 = j * stride + (i + 1)
			var i01 = (j + 1) * stride + i
			var i11 = (j + 1) * stride + (i + 1)

			water_st.add_index(i00)
			water_st.add_index(i10)
			water_st.add_index(i01)

			water_st.add_index(i10)
			water_st.add_index(i11)
			water_st.add_index(i01)

	water_st.generate_tangents()
	var w_mesh = water_st.commit()
	water_mesh_instance.mesh = w_mesh
