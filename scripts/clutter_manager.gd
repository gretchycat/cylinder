@tool
class_name ClutterManager
extends Node3D

const CLUTTER_SHADER: Shader = preload("res://assets/shaders/ground_clutter.gdshader")
const TerrainManagerClass = preload("res://scripts/terrain_manager.gd")

@export var enabled: bool = true:
	set(val):
		enabled = val
		if not enabled:
			_clear_all_chunks()

@export var view_radius: float = 500.0:
	set(val):
		view_radius = clampf(val, 50.0, 1000.0)
		_update_material_world_parameters()

@export var fade_distance: float = 120.0:
	set(val):
		fade_distance = clampf(val, 10.0, 400.0)
		_update_material_world_parameters()

@export var chunk_size: float = 40.0:
	set(val):
		chunk_size = clampf(val, 15.0, 100.0)

@export var density_multiplier: float = 1.0:
	set(val):
		density_multiplier = clampf(val, 0.1, 3.0)

var cylinder_world: CylinderGenerator = null
var active_chunks: Dictionary = {} # Vector2i -> Node3D (Chunk root)
var last_cam_grid: Vector2i = Vector2i(-99999, -99999)
var last_update_pos: Vector3 = Vector3(99999, 99999, 99999)
var update_timer: float = 0.0

# Shared materials & meshes
var grass_mat: ShaderMaterial = null
var flower_mat: ShaderMaterial = null
var stone_mat: ShaderMaterial = null
var crop_mat: ShaderMaterial = null
var shrub_mat: ShaderMaterial = null

var grass_mesh: ArrayMesh = null
var flower_mesh: ArrayMesh = null
var stone_mesh: ArrayMesh = null
var crop_mesh: ArrayMesh = null
var shrub_mesh: ArrayMesh = null

const FLOWER_COLORS: Array[Color] = [
	Color(0.95, 0.22, 0.18, 0.9), # Poppy Red
	Color(0.98, 0.85, 0.15, 0.9), # Buttercup Yellow
	Color(0.35, 0.55, 0.95, 0.9), # Cornflower Blue
	Color(0.72, 0.38, 0.92, 0.9), # Lavender / Lupine Purple
	Color(0.96, 0.96, 0.92, 0.85), # Daisy White
	Color(0.98, 0.52, 0.25, 0.9), # Orange Blossom
]

func _ready() -> void:
	_init_resources()
	_find_cylinder_world()
	_update_material_world_parameters()

func _find_cylinder_world() -> void:
	if not cylinder_world:
		cylinder_world = get_tree().get_first_node_in_group("cylinder_world") as CylinderGenerator
	if not cylinder_world and get_parent() is CylinderGenerator:
		cylinder_world = get_parent() as CylinderGenerator
	if cylinder_world:
		_update_material_world_parameters()

func _update_material_world_parameters() -> void:
	var r = cylinder_world.radius if cylinder_world else 4000.0
	var w_lvl = cylinder_world.water_level if cylinder_world else 20.0
	var air_col = cylinder_world.air_color if cylinder_world else Color(0.52, 0.72, 0.88, 1.0)
	var air_d = cylinder_world.air_density if cylinder_world else 1.25
	for mat in [grass_mat, flower_mat, stone_mat, crop_mat, shrub_mat]:
		if mat:
			mat.set_shader_parameter("cylinder_radius", r)
			mat.set_shader_parameter("water_level", w_lvl)
			mat.set_shader_parameter("air_color", air_col)
			mat.set_shader_parameter("air_density", air_d)
			mat.set_shader_parameter("max_distance", view_radius)
			mat.set_shader_parameter("fade_distance", fade_distance)

func _init_resources() -> void:
	if grass_mesh != null:
		return

	# Materials
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = CLUTTER_SHADER
	grass_mat.set_shader_parameter("base_color", Color(0.24, 0.52, 0.16, 1.0))
	grass_mat.set_shader_parameter("tip_color", Color(0.48, 0.78, 0.25, 1.0))
	grass_mat.set_shader_parameter("wind_speed", 2.2)
	grass_mat.set_shader_parameter("wind_strength", 0.24)
	grass_mat.set_shader_parameter("max_distance", view_radius)
	grass_mat.set_shader_parameter("fade_distance", fade_distance)

	flower_mat = ShaderMaterial.new()
	flower_mat.shader = CLUTTER_SHADER
	flower_mat.set_shader_parameter("base_color", Color(0.22, 0.50, 0.18, 1.0))
	flower_mat.set_shader_parameter("tip_color", Color(0.95, 0.30, 0.20, 1.0))
	flower_mat.set_shader_parameter("is_flower", true)
	flower_mat.set_shader_parameter("wind_speed", 2.6)
	flower_mat.set_shader_parameter("wind_strength", 0.18)
	flower_mat.set_shader_parameter("max_distance", view_radius)
	flower_mat.set_shader_parameter("fade_distance", fade_distance)

	stone_mat = ShaderMaterial.new()
	stone_mat.shader = CLUTTER_SHADER
	stone_mat.set_shader_parameter("base_color", Color(0.42, 0.44, 0.46, 1.0))
	stone_mat.set_shader_parameter("tip_color", Color(0.55, 0.56, 0.58, 1.0))
	stone_mat.set_shader_parameter("roughness", 0.94)
	stone_mat.set_shader_parameter("is_stone", true)
	stone_mat.set_shader_parameter("max_distance", view_radius)
	stone_mat.set_shader_parameter("fade_distance", fade_distance)

	crop_mat = ShaderMaterial.new()
	crop_mat.shader = CLUTTER_SHADER
	crop_mat.set_shader_parameter("base_color", Color(0.65, 0.52, 0.22, 1.0))
	crop_mat.set_shader_parameter("tip_color", Color(0.88, 0.74, 0.32, 1.0))
	crop_mat.set_shader_parameter("wind_speed", 1.8)
	crop_mat.set_shader_parameter("wind_strength", 0.28)
	crop_mat.set_shader_parameter("max_distance", view_radius)
	crop_mat.set_shader_parameter("fade_distance", fade_distance)

	shrub_mat = ShaderMaterial.new()
	shrub_mat.shader = CLUTTER_SHADER
	shrub_mat.set_shader_parameter("base_color", Color(0.18, 0.42, 0.14, 1.0))
	shrub_mat.set_shader_parameter("tip_color", Color(0.32, 0.62, 0.22, 1.0))
	shrub_mat.set_shader_parameter("wind_speed", 1.6)
	shrub_mat.set_shader_parameter("wind_strength", 0.14)
	shrub_mat.set_shader_parameter("max_distance", view_radius)
	shrub_mat.set_shader_parameter("fade_distance", fade_distance)

	_update_material_world_parameters()

	# Build procedural meshes
	grass_mesh = _build_grass_mesh(0.55, 0.85)
	flower_mesh = _build_flower_mesh(0.45, 0.80)
	stone_mesh = _build_stone_mesh(0.40, 0.25)
	crop_mesh = _build_crop_mesh(0.50, 1.15)
	shrub_mesh = _build_shrub_mesh(1.10, 0.95)

## Procedural Grass Clump (3 intersecting vertical quads at 0, 60, 120 deg)
func _build_grass_mesh(width_m: float, height_m: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w = width_m * 0.5
	var angles = [0.0, PI / 3.0, 2.0 * PI / 3.0]
	var root_y = -0.04

	for ang in angles:
		var cos_a = cos(ang)
		var sin_a = sin(ang)
		var p_left = Vector3(-half_w * cos_a, root_y, -half_w * sin_a)
		var p_right = Vector3(half_w * cos_a, root_y, half_w * sin_a)
		var p_top_left = Vector3(-half_w * 0.65 * cos_a, height_m, -half_w * 0.65 * sin_a)
		var p_top_right = Vector3(half_w * 0.65 * cos_a, height_m, half_w * 0.65 * sin_a)
		var norm = Vector3(-sin_a, 0.0, cos_a)

		# Quad (2 triangles, double-sided)
		st.set_normal(norm)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p_left)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p_right)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p_top_left)

		st.set_uv(Vector2(1, 0)); st.add_vertex(p_right)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p_top_right)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p_top_left)

	st.generate_tangents()
	return st.commit()

## Procedural Wildflower Clump (Stem + Petal Blossom Quad)
func _build_flower_mesh(width_m: float, height_m: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w = width_m * 0.5
	var root_y = -0.04

	# 2 crossing stem cards
	for ang in [0.0, PI * 0.5]:
		var cos_a = cos(ang)
		var sin_a = sin(ang)
		var p0 = Vector3(-half_w * 0.4 * cos_a, root_y, -half_w * 0.4 * sin_a)
		var p1 = Vector3(half_w * 0.4 * cos_a, root_y, half_w * 0.4 * sin_a)
		var p2 = Vector3(-half_w * 0.3 * cos_a, height_m, -half_w * 0.3 * sin_a)
		var p3 = Vector3(half_w * 0.3 * cos_a, height_m, half_w * 0.3 * sin_a)
		var norm = Vector3(-sin_a, 0.0, cos_a)

		st.set_normal(norm)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p1)
		st.set_uv(Vector2(0, 0.8)); st.add_vertex(p2)

		st.set_uv(Vector2(1, 0)); st.add_vertex(p1)
		st.set_uv(Vector2(1, 0.8)); st.add_vertex(p3)
		st.set_uv(Vector2(0, 0.8)); st.add_vertex(p2)

	# Blossom head horizontal diamond quad
	var b_radius = width_m * 0.45
	var b_y = height_m * 0.98
	var b0 = Vector3(-b_radius, b_y, 0.0)
	var b1 = Vector3(0.0, b_y, -b_radius)
	var b2 = Vector3(b_radius, b_y, 0.0)
	var b3 = Vector3(0.0, b_y, b_radius)
	var up = Vector3.UP

	st.set_normal(up)
	st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(b0)
	st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(b1)
	st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(b2)

	st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(b0)
	st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(b2)
	st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(b3)

	st.generate_tangents()
	return st.commit()

## Procedural Low-Poly Stone / Pebble (with base sunken for natural ground embedding)
func _build_stone_mesh(radius: float, height: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var num_pts = 6
	var pts: Array[Vector3] = []
	var top = Vector3(0.0, height * 0.75, 0.0)
	var bottom = Vector3(0.0, -height * 0.25, 0.0)

	for i in range(num_pts):
		var ang = float(i) * TAU / float(num_pts)
		# Deform radius slightly for irregular natural rock look
		var r = radius * (0.8 + 0.35 * sin(float(i * 3)))
		pts.append(Vector3(cos(ang) * r, height * 0.20, sin(ang) * r))

	for i in range(num_pts):
		var i_next = (i + 1) % num_pts
		# Upper cone
		var n_up = (top - pts[i]).cross(pts[i_next] - pts[i]).normalized()
		st.set_normal(n_up); st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(top)
		st.set_normal(n_up); st.set_uv(Vector2(0.0, 0.5)); st.add_vertex(pts[i])
		st.set_normal(n_up); st.set_uv(Vector2(1.0, 0.5)); st.add_vertex(pts[i_next])

		# Lower skirt
		var n_dn = (pts[i_next] - pts[i]).cross(bottom - pts[i]).normalized()
		st.set_normal(n_dn); st.set_uv(Vector2(0.0, 0.5)); st.add_vertex(pts[i])
		st.set_normal(n_dn); st.set_uv(Vector2(0.5, 0.0)); st.add_vertex(bottom)
		st.set_normal(n_dn); st.set_uv(Vector2(1.0, 0.5)); st.add_vertex(pts[i_next])

	st.generate_tangents()
	return st.commit()

## Procedural Crop / Wheat Stalk Clump
func _build_crop_mesh(width_m: float, height_m: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w = width_m * 0.5
	var root_y = -0.04

	for ang in [0.0, PI * 0.5]:
		var cos_a = cos(ang)
		var sin_a = sin(ang)
		var p0 = Vector3(-half_w * 0.3 * cos_a, root_y, -half_w * 0.3 * sin_a)
		var p1 = Vector3(half_w * 0.3 * cos_a, root_y, half_w * 0.3 * sin_a)
		var p2 = Vector3(-half_w * cos_a, height_m, -half_w * sin_a)
		var p3 = Vector3(half_w * cos_a, height_m, half_w * sin_a)
		var norm = Vector3(-sin_a, 0.0, cos_a)

		st.set_normal(norm)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p1)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p2)

		st.set_uv(Vector2(1, 0)); st.add_vertex(p1)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p3)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p2)

	st.generate_tangents()
	return st.commit()

## Procedural Low-Poly Shrub Bush
func _build_shrub_mesh(width_m: float, height_m: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w = width_m * 0.5
	var angles = [0.0, PI * 0.333, PI * 0.666]
	var root_y = -0.04

	for ang in angles:
		var cos_a = cos(ang)
		var sin_a = sin(ang)
		var p0 = Vector3(-half_w * cos_a, root_y, -half_w * sin_a)
		var p1 = Vector3(half_w * cos_a, root_y, half_w * sin_a)
		var p2 = Vector3(-half_w * 0.8 * cos_a, height_m, -half_w * 0.8 * sin_a)
		var p3 = Vector3(half_w * 0.8 * cos_a, height_m, half_w * 0.8 * sin_a)
		var norm = Vector3(-sin_a, 0.0, cos_a)

		st.set_normal(norm)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p1)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p2)

		st.set_uv(Vector2(1, 0)); st.add_vertex(p1)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p3)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p2)

	st.generate_tangents()
	return st.commit()

func _process(delta: float) -> void:
	if not enabled:
		return

	update_timer += delta
	if update_timer < 0.20:
		return
	update_timer = 0.0

	_find_cylinder_world()
	if not cylinder_world:
		return

	var cam_pos = _get_active_camera_position()
	if cam_pos.distance_squared_to(last_update_pos) < 16.0: # Only update if camera moved > 4m
		return

	last_update_pos = cam_pos
	_update_active_chunks(cam_pos)

func _get_active_camera_position() -> Vector3:
	var vp = get_viewport()
	if vp:
		var cam = vp.get_camera_3d()
		if cam:
			return cam.global_position
	# Fallback: check player node
	var player = get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	if player:
		return player.global_position
	return Vector3(0.0, -3940.0, 0.0)

## Calculate cylinder coordinates (theta, z) from 3D world position
func _world_to_cylindrical(pos: Vector3) -> Vector2:
	var theta = atan2(pos.y, pos.x) # [-PI, PI]
	var z = pos.z                   # [-9000, 9000]
	return Vector2(theta, z)

## Update chunks around camera
func _update_active_chunks(cam_pos: Vector3) -> void:
	var cyl_r = cylinder_world.radius if cylinder_world else 4000.0
	var cyl_len = cylinder_world.cylinder_length if cylinder_world else 18000.0
	var circ = TAU * cyl_r

	var cyl_coords = _world_to_cylindrical(cam_pos)
	var cam_theta = cyl_coords.x
	var cam_z = cyl_coords.y

	# Circumferential coordinate in meters [0, circ]
	var cam_u_m = fposmod(cam_theta + PI, TAU) * cyl_r
	var cam_z_m = cam_z + cyl_len * 0.5 # [0, cyl_len]

	var center_chunk_x = int(floor(cam_u_m / chunk_size))
	var center_chunk_z = int(floor(cam_z_m / chunk_size))
	var num_chunks_x = int(ceil(circ / chunk_size))
	var num_chunks_z = int(ceil(cyl_len / chunk_size))

	var chunk_radius = int(ceil(view_radius / chunk_size))
	var needed_chunks: Dictionary = {}

	for dz in range(-chunk_radius, chunk_radius + 1):
		var cz = center_chunk_z + dz
		if cz < 0 or cz >= num_chunks_z:
			continue

		for dx in range(-chunk_radius, chunk_radius + 1):
			# Wrap circumferential chunks seamlessly around cylinder
			var cx = posmod(center_chunk_x + dx, num_chunks_x)
			var key = Vector2i(cx, cz)
			needed_chunks[key] = true

			if not active_chunks.has(key):
				var chunk_node = _build_chunk(cx, cz, num_chunks_x, cyl_r, cyl_len)
				if chunk_node:
					add_child(chunk_node)
					active_chunks[key] = chunk_node

	# Cull out-of-range chunks
	var to_remove: Array[Vector2i] = []
	for key in active_chunks.keys():
		if not needed_chunks.has(key):
			to_remove.append(key)

	for key in to_remove:
		var node = active_chunks[key]
		if is_instance_valid(node):
			node.queue_free()
		active_chunks.erase(key)

## Build a spatial clutter chunk containing MultiMeshInstance3Ds
func _build_chunk(cx: int, cz: int, num_chunks_x: int, cyl_r: float, cyl_len: float) -> Node3D:
	if not cylinder_world or not cylinder_world.terrain_manager:
		return null

	var tm = cylinder_world.terrain_manager
	var chunk_root = Node3D.new()
	chunk_root.name = "ClutterChunk_%d_%d" % [cx, cz]

	# Chunk bounding box in cylinder coordinates
	var u0_m = float(cx) * chunk_size
	var z0_m = float(cz) * chunk_size - cyl_len * 0.5
	var circ = TAU * cyl_r

	# Deterministic pseudo-random seed per chunk
	var seed_val = int(cx * 73856093 ^ cz * 19349663)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val

	# Number of sample points per chunk
	var base_samples = int(48 * density_multiplier)
	
	# Instance buffers for each clutter category
	var grass_transforms: Array[Transform3D] = []
	var grass_colors: Array[Color] = []

	var flower_transforms: Array[Transform3D] = []
	var flower_colors: Array[Color] = []

	var stone_transforms: Array[Transform3D] = []
	var stone_colors: Array[Color] = []

	var crop_transforms: Array[Transform3D] = []
	var crop_colors: Array[Color] = []

	var shrub_transforms: Array[Transform3D] = []
	var shrub_colors: Array[Color] = []

	for s in range(base_samples):
		var offset_u = rng.randf() * chunk_size
		var offset_z = rng.randf() * chunk_size

		var u_m = u0_m + offset_u
		var z = z0_m + offset_z
		if z < -cyl_len * 0.5 or z > cyl_len * 0.5:
			continue

		var theta = (u_m / cyl_r) - PI
		var t_type = tm.get_terrain_type(theta, z, cyl_len)
		var elev = tm.get_elevation(theta, z, cyl_len)

		# Water level culling: don't spawn on submerged terrain or roads
		if elev < tm.water_level + 0.35:
			continue
		if t_type == TerrainManagerClass.TerrainType.WATER or t_type == TerrainManagerClass.TerrainType.ROAD or t_type == TerrainManagerClass.TerrainType.CONCRETE:
			continue

		# Query exact terrain mesh surface position and normal directly on triangle polygons
		var pos: Vector3
		var normal: Vector3
		var mesh_info: Dictionary = {}
		if cylinder_world and cylinder_world.has_method("get_surface_mesh_point_and_normal"):
			mesh_info = cylinder_world.get_surface_mesh_point_and_normal(theta, z)

		if not mesh_info.is_empty():
			pos = mesh_info["position"]
			normal = mesh_info["normal"]
			elev = mesh_info["elevation"]
		else:
			var surface_r = cyl_r - elev
			pos = Vector3(surface_r * cos(theta), surface_r * sin(theta), z)
			normal = Vector3(-cos(theta), -sin(theta), 0.0)

		# Local coordinate basis aligned with terrain slope normal:
		var up = normal
		var forward = Vector3(0.0, 0.0, -1.0)
		if absf(up.dot(forward)) > 0.90:
			forward = Vector3(1.0, 0.0, 0.0)
		var right = up.cross(forward).normalized()
		var forward_adj = right.cross(up).normalized()
		var base_basis = Basis(right, up, -forward_adj).orthonormalized()

		# Random yaw rotation around surface normal
		var yaw = rng.randf() * TAU
		var instance_basis = base_basis.rotated(up, yaw)

		# Scatter logic per terrain type
		match t_type:
			TerrainManagerClass.TerrainType.GRASS:
				var roll = rng.randf()
				if roll < 0.60: # 60% Grass tufts
					var scale_factor = rng.randf_range(0.75, 1.45)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					grass_transforms.append(tf)
					var green_tint = rng.randf_range(0.85, 1.15)
					grass_colors.append(Color(green_tint, green_tint, green_tint, 0.0))
				elif roll < 0.88: # 28% Wildflowers
					var scale_factor = rng.randf_range(0.80, 1.35)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					flower_transforms.append(tf)
					var col_idx = rng.randi() % FLOWER_COLORS.size()
					flower_colors.append(FLOWER_COLORS[col_idx])
				elif roll < 0.94: # 6% Shrubs
					var scale_factor = rng.randf_range(0.9, 1.6)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					shrub_transforms.append(tf)
					shrub_colors.append(Color(1, 1, 1, 0.0))
				else: # 6% Field pebbles
					var scale_factor = rng.randf_range(0.6, 1.3)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					stone_transforms.append(tf)
					stone_colors.append(Color(0.9, 0.9, 0.85, 0.0))

			TerrainManagerClass.TerrainType.ROCKS:
				var scale_factor = rng.randf_range(0.6, 2.2)
				var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
				stone_transforms.append(tf)
				var grey_var = rng.randf_range(0.7, 1.2)
				stone_colors.append(Color(grey_var, grey_var, grey_var, 0.0))

			TerrainManagerClass.TerrainType.FARMLAND:
				if rng.randf() < 0.75:
					var scale_factor = rng.randf_range(0.85, 1.4)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					crop_transforms.append(tf)
					crop_colors.append(Color(1, 1, 1, 0.0))
				else:
					var scale_factor = rng.randf_range(0.4, 0.9)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					stone_transforms.append(tf)
					stone_colors.append(Color(0.8, 0.75, 0.65, 0.0))

			TerrainManagerClass.TerrainType.DIRT:
				if rng.randf() < 0.60:
					var scale_factor = rng.randf_range(0.4, 1.1)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					stone_transforms.append(tf)
					stone_colors.append(Color(0.75, 0.68, 0.60, 0.0))
				else:
					var scale_factor = rng.randf_range(0.5, 0.9)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					grass_transforms.append(tf)
					grass_colors.append(Color(0.8, 0.8, 0.7, 0.0))

			TerrainManagerClass.TerrainType.SAND:
				if rng.randf() < 0.40:
					var scale_factor = rng.randf_range(0.35, 0.85)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					stone_transforms.append(tf)
					stone_colors.append(Color(0.9, 0.85, 0.75, 0.0))

	# Populate MultiMeshes
	_add_multimesh_to_chunk(chunk_root, "Grass", grass_mesh, grass_mat, grass_transforms, grass_colors)
	_add_multimesh_to_chunk(chunk_root, "Flowers", flower_mesh, flower_mat, flower_transforms, flower_colors)
	_add_multimesh_to_chunk(chunk_root, "Stones", stone_mesh, stone_mat, stone_transforms, stone_colors)
	_add_multimesh_to_chunk(chunk_root, "Crops", crop_mesh, crop_mat, crop_transforms, crop_colors)
	_add_multimesh_to_chunk(chunk_root, "Shrubs", shrub_mesh, shrub_mat, shrub_transforms, shrub_colors)

	return chunk_root

func _add_multimesh_to_chunk(
	parent: Node3D,
	item_name: String,
	mesh_res: Mesh,
	mat: Material,
	transforms: Array[Transform3D],
	colors: Array[Color]
) -> void:
	if transforms.is_empty() or not mesh_res:
		return

	var mmi = MultiMeshInstance3D.new()
	mmi.name = item_name + "MultiMesh"
	mmi.material_override = mat

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh_res
	mm.instance_count = transforms.size()

	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		if i < colors.size():
			mm.set_instance_color(i, colors[i])

	mmi.multimesh = mm
	parent.add_child(mmi)

func _clear_all_chunks() -> void:
	for node in active_chunks.values():
		if is_instance_valid(node):
			node.queue_free()
	active_chunks.clear()
	last_update_pos = Vector3(99999, 99999, 99999)
