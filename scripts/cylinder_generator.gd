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

@export_category("Terrain & Elevation (PNG Heightmap & RPG Tilemap)")
@export var elevation_variance: float = 100.0: # 0 to 100 m elevation range
	set(val):
		elevation_variance = max(val, 0.0)
		if terrain_manager:
			terrain_manager.elevation_variance = elevation_variance
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var water_level: float = 20.0: # 20 m from elevation 0
	set(val):
		water_level = max(val, 0.0)
		if terrain_manager:
			terrain_manager.water_level = water_level
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export_file("*.png") var elevation_map_path: String = "res://assets/maps/elevation_map.png":
	set(val):
		elevation_map_path = val
		if terrain_manager and is_inside_tree():
			terrain_manager.load_elevation_from_png(elevation_map_path)
			generate_cylinder()

@export_file("*.png") var terrain_map_path: String = "res://assets/maps/terrain_map.png":
	set(val):
		terrain_map_path = val
		if terrain_manager and is_inside_tree():
			terrain_manager.load_terrain_from_png(terrain_map_path)
			generate_cylinder()

@export var surface_material: Material
@export var water_material: Material

var terrain_manager: TerrainManagerClass

var mesh_instance: MeshInstance3D
var water_mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var collision_shape: CollisionShape3D

func _ready() -> void:
	add_to_group("cylinder_world")
	if not terrain_manager:
		_initialize_terrain_manager()
	generate_cylinder()

func _initialize_terrain_manager() -> void:
	terrain_manager = TerrainManagerClass.new(512, 256, elevation_variance, water_level)
	if FileAccess.file_exists(elevation_map_path) or FileAccess.file_exists(ProjectSettings.globalize_path(elevation_map_path)):
		terrain_manager.load_elevation_from_png(elevation_map_path)
	if FileAccess.file_exists(terrain_map_path) or FileAccess.file_exists(ProjectSettings.globalize_path(terrain_map_path)):
		terrain_manager.load_terrain_from_png(terrain_map_path)

func get_elevation_at(theta: float, z: float) -> float:
	if not terrain_manager:
		_initialize_terrain_manager()
	return terrain_manager.get_elevation(theta, z, cylinder_length)

func get_terrain_type_at(theta: float, z: float) -> int:
	if not terrain_manager:
		_initialize_terrain_manager()
	return terrain_manager.get_terrain_type(theta, z, cylinder_length)

func get_surface_radius_at(theta: float, z: float) -> float:
	return radius - get_elevation_at(theta, z)

## Find a spawn location guaranteed to be on terrain above sea level.
## If preferred (theta, z) is already above sea level (water_level + min_clearance), it is used.
## Otherwise, the terrain grid is searched for the nearest dry land above sea level.
func find_safe_spawn_point(preferred_theta: float = -PI * 0.5, preferred_z: float = 0.0, min_clearance: float = 2.0) -> Dictionary:
	if not terrain_manager:
		_initialize_terrain_manager()

	var required_elevation = water_level + maxf(min_clearance, 0.5)

	# 1. Test preferred location first
	var pref_elev = get_elevation_at(preferred_theta, preferred_z)
	var pref_type = get_terrain_type_at(preferred_theta, preferred_z)
	if pref_elev >= required_elevation and pref_type != TerrainManagerClass.TerrainType.WATER:
		return _build_spawn_info(preferred_theta, preferred_z, pref_elev, pref_type)

	# 2. Search grid for nearest terrain cell above sea level
	var grid_u = terrain_manager.grid_u
	var grid_v = terrain_manager.grid_v
	var elev_data = terrain_manager.elevation_data
	var terr_data = terrain_manager.terrain_data

	if elev_data.is_empty():
		return _build_spawn_info(preferred_theta, preferred_z, water_level + 5.0, TerrainManagerClass.TerrainType.GRASS)

	var target_u = fposmod(preferred_theta, TAU) / TAU
	var target_v = clampf((preferred_z + cylinder_length * 0.5) / maxf(cylinder_length, 1.0), 0.0, 1.0)
	var cx = int(target_u * float(grid_u)) % grid_u
	var cy = clampi(int(target_v * float(grid_v - 1)), 0, grid_v - 1)

	var best_x: int = -1
	var best_y: int = -1
	var best_dist_sq: float = INF
	var best_elev: float = 0.0
	var best_type: int = TerrainManagerClass.TerrainType.GRASS

	var max_ring = maxi(grid_u, grid_v)
	var found_in_ring = false

	for r in range(1, max_ring):
		# Top and bottom edges of search box
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var x = (cx + dx) % grid_u
				if x < 0: x += grid_u
				var y = cy + dy
				if y >= 0 and y < grid_v:
					var idx = y * grid_u + x
					var e = elev_data[idx]
					var t = terr_data[idx] if idx < terr_data.size() else 3
					if e >= required_elevation and t != TerrainManagerClass.TerrainType.WATER:
						var dz = (float(y - cy) / float(grid_v - 1)) * cylinder_length
						var du = absf(float(x - cx) / float(grid_u))
						if du > 0.5: du = 1.0 - du
						var dx_m = du * (TAU * radius)
						var dist_sq = dz * dz + dx_m * dx_m
						if dist_sq < best_dist_sq:
							best_dist_sq = dist_sq
							best_x = x
							best_y = y
							best_elev = e
							best_type = t
						found_in_ring = true

		# Left and right edges of search box
		for dy in range(-r + 1, r):
			for dx in [-r, r]:
				var x = (cx + dx) % grid_u
				if x < 0: x += grid_u
				var y = cy + dy
				if y >= 0 and y < grid_v:
					var idx = y * grid_u + x
					var e = elev_data[idx]
					var t = terr_data[idx] if idx < terr_data.size() else 3
					if e >= required_elevation and t != TerrainManagerClass.TerrainType.WATER:
						var dz = (float(y - cy) / float(grid_v - 1)) * cylinder_length
						var du = absf(float(x - cx) / float(grid_u))
						if du > 0.5: du = 1.0 - du
						var dx_m = du * (TAU * radius)
						var dist_sq = dz * dz + dx_m * dx_m
						if dist_sq < best_dist_sq:
							best_dist_sq = dist_sq
							best_x = x
							best_y = y
							best_elev = e
							best_type = t
						found_in_ring = true

		if found_in_ring:
			break

	if best_x >= 0 and best_y >= 0:
		var u_best = float(best_x) / float(grid_u)
		var v_best = float(best_y) / float(grid_v - 1)
		var theta_best = u_best * TAU
		var z_best = (v_best - 0.5) * cylinder_length
		var final_elev = get_elevation_at(theta_best, z_best)
		return _build_spawn_info(theta_best, z_best, final_elev, best_type)

	# Global fallback: scan all cells for highest point
	var highest_elev = -1.0
	var highest_idx = 0
	for i in range(elev_data.size()):
		if elev_data[i] > highest_elev:
			highest_elev = elev_data[i]
			highest_idx = i

	var fall_x = highest_idx % grid_u
	var fall_y = highest_idx / grid_u
	var fall_theta = (float(fall_x) / float(grid_u)) * TAU
	var fall_z = (float(fall_y) / float(grid_v - 1) - 0.5) * cylinder_length
	return _build_spawn_info(fall_theta, fall_z, highest_elev, TerrainManagerClass.TerrainType.GRASS)

func _build_spawn_info(theta: float, z: float, elev: float, terrain_type: int) -> Dictionary:
	var surface_r = radius - elev
	# Clearance for character capsule (height 1.8m, half-height 0.9m + small margin 0.05m)
	var spawn_r = surface_r - 0.95

	var pos = Vector3(spawn_r * cos(theta), spawn_r * sin(theta), z)

	# Local coordinate frame:
	# Inward local Up towards axis:
	var up = Vector3(-cos(theta), -sin(theta), 0.0)
	# Looking down -Z along cylinder axis:
	var back = Vector3(0.0, 0.0, 1.0)
	var right = up.cross(back).normalized()
	var basis = Basis(right, up, back).orthonormalized()

	return {
		"position": pos,
		"basis": basis,
		"theta": theta,
		"z": z,
		"elevation": elev,
		"terrain_type": terrain_type,
		"surface_radius": surface_r,
		"is_above_sea_level": elev > water_level,
		"clearance_above_sea": elev - water_level
	}

func generate_cylinder() -> void:
	if not terrain_manager:
		_initialize_terrain_manager()

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
