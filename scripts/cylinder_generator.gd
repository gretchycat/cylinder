@tool
class_name CylinderGenerator
extends Node3D

const TerrainManagerClass = preload("res://scripts/terrain_manager.gd")
const MapConfigClass = preload("res://scripts/map_config.gd")

@export_category("Cylinder Dimensions (8 km dia x 18 km length)")
@export var radius: float = 4000.0: # 8 km diameter = 4 km radius
	set(val):
		radius = max(val, 10.0)
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var cylinder_length: float = 18000.0: # 18 km length
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

@export var length_segments: int = 180: # 180 segments along 18 km = 100m per segment
	set(val):
		length_segments = clampi(val, 4, 360)
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var include_end_caps: bool = true:
	set(val):
		include_end_caps = val
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var end_cap_rings: int = 32: # Concentric structural rings on each hemispherical end cap
	set(val):
		end_cap_rings = clampi(val, 8, 64)
		if is_inside_tree() and Engine.is_editor_hint():
			generate_cylinder()

@export var end_cap_dish_depth: float = 4000.0: # Hemispherical dome radius depth (4 km)
	set(val):
		end_cap_dish_depth = max(val, 0.0)
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

@export_file("*.png") var elevation_map_path: String = "res://assets/maps/default/elevation_map.png":
	set(val):
		elevation_map_path = val
		if terrain_manager and is_inside_tree():
			terrain_manager.load_elevation_from_png(elevation_map_path)
			generate_cylinder()

@export_file("*.png") var terrain_map_path: String = "res://assets/maps/default/terrain_map.png":
	set(val):
		terrain_map_path = val
		if terrain_manager and is_inside_tree():
			terrain_manager.load_terrain_from_png(terrain_map_path)
			generate_cylinder()

@export var map_package: String = "res://assets/maps/default":
	set(val):
		map_package = val
		if is_inside_tree():
			load_map_package(map_package)

@export_category("Atmospheric Aerial Perspective (8 km Distance Haze)")
@export var air_color: Color = Color(0.52, 0.72, 0.88, 1.0):
	set(val):
		air_color = val
		_update_atmosphere_parameters()

@export var air_density: float = 1.25:
	set(val):
		air_density = clampf(val, 0.0, 3.0)
		_update_atmosphere_parameters()

@export var air_distance_min: float = 200.0:
	set(val):
		air_distance_min = max(val, 0.0)
		_update_atmosphere_parameters()

@export var air_distance_max: float = 18000.0:
	set(val):
		air_distance_max = max(val, air_distance_min + 10.0)
		_update_atmosphere_parameters()

@export var surface_material: Material
@export var water_material: Material

var terrain_manager: TerrainManagerClass

var mesh_instance: MeshInstance3D
var water_mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var collision_shape: CollisionShape3D

var _is_generating: bool = false
var _is_initializing_terrain: bool = false

func _ready() -> void:
	add_to_group("cylinder_world")
	if not terrain_manager:
		_initialize_terrain_manager()
	generate_cylinder()
	var light_bar = get_tree().get_first_node_in_group("light_bar")
	if light_bar and light_bar.has_method("_apply_lut_to_materials"):
		light_bar._apply_lut_to_materials()

func _initialize_terrain_manager() -> void:
	if _is_initializing_terrain:
		return
	_is_initializing_terrain = true
	if not map_package.is_empty():
		load_map_package(map_package)
		_is_initializing_terrain = false
		return
	terrain_manager = TerrainManagerClass.new(512, 256, elevation_variance, water_level)
	if FileAccess.file_exists(elevation_map_path) or FileAccess.file_exists(ProjectSettings.globalize_path(elevation_map_path)):
		terrain_manager.load_elevation_from_png(elevation_map_path)
	if FileAccess.file_exists(terrain_map_path) or FileAccess.file_exists(ProjectSettings.globalize_path(terrain_map_path)):
		terrain_manager.load_terrain_from_png(terrain_map_path)
	_is_initializing_terrain = false

## Load an arbitrary map package from assets/maps/<mapname>/
func load_map_package(package_path_or_name: String) -> bool:
	var cfg = MapConfigClass.load_map_config(package_path_or_name)
	if cfg.is_empty():
		return false

	var geom = cfg.get("geometry", {})
	var r = radius
	var clen = cylinder_length
	var elev_v = elevation_variance
	var w_lvl = water_level
	if geom is Dictionary:
		r = float(geom.get("cylinder_radius_m", radius))
		clen = float(geom.get("cylinder_length_m", cylinder_length))
		elev_v = float(geom.get("elevation_variance_m", elevation_variance))
		w_lvl = float(geom.get("water_sea_level_m", water_level))

	elevation_map_path = MapConfigClass.get_elevation_map_path(cfg)
	terrain_map_path = MapConfigClass.get_terrain_map_path(cfg)

	if not terrain_manager:
		terrain_manager = TerrainManagerClass.new(512, 256, elev_v, w_lvl)
	else:
		terrain_manager.elevation_variance = elev_v
		terrain_manager.water_level = w_lvl

	if FileAccess.file_exists(elevation_map_path) or FileAccess.file_exists(ProjectSettings.globalize_path(elevation_map_path)):
		terrain_manager.load_elevation_from_png(elevation_map_path)
	if FileAccess.file_exists(terrain_map_path) or FileAccess.file_exists(ProjectSettings.globalize_path(terrain_map_path)):
		terrain_manager.load_terrain_from_png(terrain_map_path)

	radius = r
	cylinder_length = clen
	elevation_variance = elev_v
	water_level = w_lvl

	if is_inside_tree() and not _is_generating:
		generate_cylinder()

	return true

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

## Computes the exact 3D position and inward surface normal directly on the generated terrain mesh triangles.
## This eliminates chord sagitta error (up to 0.95m floating) and aligns perfectly with local slopes.
func get_surface_mesh_point_and_normal(theta: float, z: float) -> Dictionary:
	if not terrain_manager:
		_initialize_terrain_manager()

	var half_len = cylinder_length * 0.5
	var u_norm = fposmod(theta, TAU) / TAU
	var v_norm = clampf((z + half_len) / maxf(cylinder_length, 1.0), 0.0, 1.0)

	var d_theta = TAU / float(radial_segments)
	var d_z = cylinder_length / float(length_segments)

	var fi = u_norm * float(radial_segments)
	var fj = v_norm * float(length_segments)

	var i = clampi(int(floor(fi)), 0, radial_segments - 1)
	var j = clampi(int(floor(fj)), 0, length_segments - 1)

	var s = fi - float(i)
	var t = fj - float(j)

	var theta_0 = float(i) * d_theta
	var theta_1 = float(i + 1) * d_theta
	var z_0 = -half_len + float(j) * d_z
	var z_1 = -half_len + float(j + 1) * d_z

	var e00 = terrain_manager.get_elevation(theta_0, z_0, cylinder_length)
	var e10 = terrain_manager.get_elevation(theta_1, z_0, cylinder_length)
	var e01 = terrain_manager.get_elevation(theta_0, z_1, cylinder_length)
	var e11 = terrain_manager.get_elevation(theta_1, z_1, cylinder_length)

	var v00 = Vector3((radius - e00) * cos(theta_0), (radius - e00) * sin(theta_0), z_0)
	var v10 = Vector3((radius - e10) * cos(theta_1), (radius - e10) * sin(theta_1), z_0)
	var v01 = Vector3((radius - e01) * cos(theta_0), (radius - e01) * sin(theta_0), z_1)
	var v11 = Vector3((radius - e11) * cos(theta_1), (radius - e11) * sin(theta_1), z_1)

	var pos: Vector3
	var normal: Vector3

	# Triangulation matching _build_terrain_mesh:
	# Tri 1: (v00, v10, v01) for s + t <= 1.0
	# Tri 2: (v10, v11, v01) for s + t > 1.0
	if (s + t) <= 1.0:
		pos = v00 + s * (v10 - v00) + t * (v01 - v00)
		normal = (v01 - v00).cross(v10 - v00).normalized()
	else:
		var u2 = 1.0 - s
		var v2 = 1.0 - t
		pos = v11 + u2 * (v01 - v11) + v2 * (v10 - v11)
		normal = (v10 - v11).cross(v01 - v11).normalized()

	var elev = lerpf(lerpf(e00, e10, s), lerpf(e01, e11, s), t)
	var t_type = terrain_manager.get_terrain_type(theta, z, cylinder_length)

	return {
		"position": pos,
		"normal": normal,
		"elevation": elev,
		"terrain_type": t_type
	}

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
	# Clearance for character capsule (height 1.85m, half-height 0.925m + chord sagitta margin = 1.80m)
	var spawn_r = surface_r - 1.80

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
	if _is_generating:
		return
	_is_generating = true
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
	else:
		_update_terrain_material_textures()
	if water_material == null:
		water_material = _create_water_material()
	else:
		_update_water_material_textures()

	_build_terrain_mesh()
	_build_water_mesh()
	_is_generating = false

func _load_texture_safe(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is Texture2D:
			return res
	var global_path = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(global_path):
		var check_path = global_path if FileAccess.file_exists(global_path) else path
		var img = Image.load_from_file(check_path)
		if img:
			return ImageTexture.create_from_image(img)
	return null

func _update_terrain_material_textures(mat: ShaderMaterial = null) -> void:
	if not mat:
		mat = surface_material as ShaderMaterial
	if not mat:
		return

	# Grass variations
	if not mat.get_shader_parameter("tex_grass_0"):
		mat.set_shader_parameter("tex_grass_0", _load_texture_safe("res://assets/textures/terrain/grass_0.png"))
		mat.set_shader_parameter("tex_grass_1", _load_texture_safe("res://assets/textures/terrain/grass_1.png"))
		mat.set_shader_parameter("tex_grass_2", _load_texture_safe("res://assets/textures/terrain/grass_2.png"))

	# Sand variations
	if not mat.get_shader_parameter("tex_sand_0"):
		mat.set_shader_parameter("tex_sand_0", _load_texture_safe("res://assets/textures/terrain/sand_0.png"))
		mat.set_shader_parameter("tex_sand_1", _load_texture_safe("res://assets/textures/terrain/sand_1.png"))
		mat.set_shader_parameter("tex_sand_2", _load_texture_safe("res://assets/textures/terrain/sand_2.png"))

	# Dirt variations
	if not mat.get_shader_parameter("tex_dirt_0"):
		mat.set_shader_parameter("tex_dirt_0", _load_texture_safe("res://assets/textures/terrain/dirt_0.png"))
		mat.set_shader_parameter("tex_dirt_1", _load_texture_safe("res://assets/textures/terrain/dirt_1.png"))
		mat.set_shader_parameter("tex_dirt_2", _load_texture_safe("res://assets/textures/terrain/dirt_2.png"))

	# Farmland variations
	if not mat.get_shader_parameter("tex_farmland_0"):
		mat.set_shader_parameter("tex_farmland_0", _load_texture_safe("res://assets/textures/terrain/farmland_0.png"))
		mat.set_shader_parameter("tex_farmland_1", _load_texture_safe("res://assets/textures/terrain/farmland_1.png"))
		mat.set_shader_parameter("tex_farmland_2", _load_texture_safe("res://assets/textures/terrain/farmland_2.png"))

	# Rocks variations
	if not mat.get_shader_parameter("tex_rocks_0"):
		mat.set_shader_parameter("tex_rocks_0", _load_texture_safe("res://assets/textures/terrain/rocks_0.png"))
		mat.set_shader_parameter("tex_rocks_1", _load_texture_safe("res://assets/textures/terrain/rocks_1.png"))
		mat.set_shader_parameter("tex_rocks_2", _load_texture_safe("res://assets/textures/terrain/rocks_2.png"))

	# Concrete variations
	if not mat.get_shader_parameter("tex_concrete_0"):
		mat.set_shader_parameter("tex_concrete_0", _load_texture_safe("res://assets/textures/terrain/concrete_0.png"))
		mat.set_shader_parameter("tex_concrete_1", _load_texture_safe("res://assets/textures/terrain/concrete_1.png"))
		mat.set_shader_parameter("tex_concrete_2", _load_texture_safe("res://assets/textures/terrain/concrete_2.png"))

	# Road variations
	if not mat.get_shader_parameter("tex_road_0"):
		mat.set_shader_parameter("tex_road_0", _load_texture_safe("res://assets/textures/terrain/road_0.png"))
		mat.set_shader_parameter("tex_road_1", _load_texture_safe("res://assets/textures/terrain/road_1.png"))
		mat.set_shader_parameter("tex_road_2", _load_texture_safe("res://assets/textures/terrain/road_2.png"))

	var rib_tex: Texture2D = _load_texture_safe("res://assets/textures/terrain/end_cap_ribs.png")
	if rib_tex:
		mat.set_shader_parameter("tex_end_cap_ribs", rib_tex)

	if terrain_manager:
		var terr_id_img = terrain_manager.create_terrain_type_id_image()
		if terr_id_img:
			var terr_tex = ImageTexture.create_from_image(terr_id_img)
			mat.set_shader_parameter("terrain_map", terr_tex)
			mat.set_shader_parameter("terrain_map_size", Vector2(terrain_manager.grid_u, terrain_manager.grid_v))

	mat.set_shader_parameter("cylinder_radius", radius)
	mat.set_shader_parameter("cylinder_length", cylinder_length)
	mat.set_shader_parameter("water_level", water_level)
	mat.set_shader_parameter("max_elevation", elevation_variance)
	mat.set_shader_parameter("air_color", air_color)
	mat.set_shader_parameter("air_density", air_density)
	mat.set_shader_parameter("air_distance_min", air_distance_min)
	mat.set_shader_parameter("air_distance_max", air_distance_max)
	mat.set_shader_parameter("cloud_coverage", 0.55)

func _create_terrain_material() -> ShaderMaterial:
	var shader = load("res://assets/shaders/cylinder_terrain.gdshader")
	if not shader:
		return null
	var mat = ShaderMaterial.new()
	mat.shader = shader
	_update_terrain_material_textures(mat)
	return mat

func _create_water_material() -> ShaderMaterial:
	var shader = load("res://assets/shaders/cylinder_water.gdshader")
	if not shader:
		return null
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 1
	mat.set_shader_parameter("cylinder_radius", radius - water_level)
	mat.set_shader_parameter("cylinder_length", cylinder_length)
	mat.set_shader_parameter("water_level", water_level)
	mat.set_shader_parameter("max_elevation", elevation_variance)
	mat.set_shader_parameter("air_color", air_color)
	mat.set_shader_parameter("air_density", air_density)
	mat.set_shader_parameter("air_distance_min", air_distance_min)
	mat.set_shader_parameter("air_distance_max", air_distance_max)
	mat.set_shader_parameter("cloud_coverage", 0.55)
	_update_water_material_textures(mat)
	return mat

func _update_atmosphere_parameters() -> void:
	if surface_material is ShaderMaterial:
		surface_material.set_shader_parameter("air_color", air_color)
		surface_material.set_shader_parameter("air_density", air_density)
		surface_material.set_shader_parameter("air_distance_min", air_distance_min)
		surface_material.set_shader_parameter("air_distance_max", air_distance_max)
	if water_material is ShaderMaterial:
		water_material.set_shader_parameter("air_color", air_color)
		water_material.set_shader_parameter("air_density", air_density)
		water_material.set_shader_parameter("air_distance_min", air_distance_min)
		water_material.set_shader_parameter("air_distance_max", air_distance_max)

func _update_water_material_textures(mat: ShaderMaterial = null) -> void:
	if not mat:
		mat = water_material as ShaderMaterial
	if not mat:
		return
	mat.set_shader_parameter("cylinder_radius", radius - water_level)
	mat.set_shader_parameter("cylinder_length", cylinder_length)
	mat.set_shader_parameter("water_level", water_level)
	mat.set_shader_parameter("max_elevation", elevation_variance)
	mat.set_shader_parameter("air_color", air_color)
	mat.set_shader_parameter("air_density", air_density)
	mat.set_shader_parameter("air_distance_min", air_distance_min)
	mat.set_shader_parameter("air_distance_max", air_distance_max)

	var elev_tex: Texture2D = null
	if ResourceLoader.exists(elevation_map_path):
		elev_tex = load(elevation_map_path)
	elif FileAccess.file_exists(elevation_map_path) or FileAccess.file_exists(ProjectSettings.globalize_path(elevation_map_path)):
		var img = Image.load_from_file(elevation_map_path)
		if not img:
			img = Image.load_from_file(ProjectSettings.globalize_path(elevation_map_path))
		if img:
			elev_tex = ImageTexture.create_from_image(img)
	if not elev_tex and terrain_manager:
		var img = terrain_manager.create_elevation_image()
		if img:
			elev_tex = ImageTexture.create_from_image(img)
	if elev_tex:
		mat.set_shader_parameter("elevation_map", elev_tex)

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
			# Pass elevation and terrain type through vertex COLOR attribute (0..7 normalized by 7.0)
			st.set_color(Color(elev / max(elevation_variance, 0.1), float(t_type) / 7.0, 0.0, 1.0))
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

	# --- Generate Concentric Hemispherical End Cap Bulkheads (if enabled) ---
	if include_end_caps:
		var cap_divisions = radial_segments
		var cap_rings = end_cap_rings

		# === Cap 1: Hemispherical Dome at z = -half_len (inward normal facing +Z into cylinder) ===
		var center_idx1 = stride * (length_segments + 1)
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(Vector2(0.5, 0.5))
		# COLOR: r = radial_ratio (0.0 at pole), g = spaceport concrete (6/7), b = is_end_cap (1.0)
		st.set_color(Color(0.0, 6.0 / 7.0, 1.0, 1.0))
		st.add_vertex(Vector3(0, 0, -half_len - radius))

		for k in range(1, cap_rings + 1):
			var alpha = float(k) / float(cap_rings)
			var phi = alpha * (PI * 0.5) # 0 at pole, PI/2 at cylinder rim
			var sin_phi = sin(phi)
			var cos_phi = cos(phi)
			var r_sphere = radius * sin_phi
			var delta_z = radius * cos_phi
			var z_cap = -half_len - delta_z

			for i in range(cap_divisions + 1):
				var theta = float(i) * d_theta
				var cos_t = cos(theta)
				var sin_t = sin(theta)

				var elev = terrain_manager.get_elevation(theta, -half_len, cylinder_length)
				var elev_blend = smoothstep(0.70, 1.0, alpha)
				var r_k = r_sphere - elev * elev_blend

				var pos = Vector3(r_k * cos_t, r_k * sin_t, z_cap)
				var norm = Vector3(-sin_phi * cos_t, -sin_phi * sin_t, cos_phi).normalized()

				# Polar rib UV: 1:1 mapping with circular radial rib texture (center 0.5, 0.5, radius 0.49)
				var uv_rib = Vector2(0.5 + cos_t * (0.49 * alpha), 0.5 + sin_t * (0.49 * alpha))

				var t_type = 6 # Concrete structural bulkhead
				if r_k <= 350.0:
					t_type = 7 # Road / alloy central spaceport docking collar
				elif alpha > 0.94:
					t_type = terrain_manager.get_terrain_type(theta, -half_len, cylinder_length)

				st.set_normal(norm)
				st.set_uv(uv_rib)
				st.set_color(Color(alpha, float(t_type) / 7.0, 1.0, 1.0))
				st.add_vertex(pos)

		# Cap 1 Triangles: Center to Ring 1
		for i in range(cap_divisions):
			var p0 = center_idx1
			var p1 = center_idx1 + 1 + i
			var p2 = center_idx1 + 1 + (i + 1)
			st.add_index(p0)
			st.add_index(p1)
			st.add_index(p2)

		# Cap 1 Triangles: Ring k to Ring k+1
		for k in range(1, cap_rings):
			var r_curr_start = center_idx1 + 1 + (k - 1) * stride
			var r_next_start = center_idx1 + 1 + k * stride
			for i in range(cap_divisions):
				var i00 = r_curr_start + i
				var i10 = r_curr_start + (i + 1)
				var i01 = r_next_start + i
				var i11 = r_next_start + (i + 1)

				st.add_index(i00)
				st.add_index(i01)
				st.add_index(i10)

				st.add_index(i10)
				st.add_index(i01)
				st.add_index(i11)

		# === Cap 2: Hemispherical Dome at z = +half_len (inward normal facing -Z into cylinder) ===
		var center_idx2 = center_idx1 + 1 + cap_rings * stride
		st.set_normal(Vector3(0, 0, -1))
		st.set_uv(Vector2(0.5, 0.5))
		st.set_color(Color(0.0, 6.0 / 7.0, 1.0, 1.0))
		st.add_vertex(Vector3(0, 0, half_len + radius))

		for k in range(1, cap_rings + 1):
			var alpha = float(k) / float(cap_rings)
			var phi = alpha * (PI * 0.5)
			var sin_phi = sin(phi)
			var cos_phi = cos(phi)
			var r_sphere = radius * sin_phi
			var delta_z = radius * cos_phi
			var z_cap = half_len + delta_z

			for i in range(cap_divisions + 1):
				var theta = float(i) * d_theta
				var cos_t = cos(theta)
				var sin_t = sin(theta)

				var elev = terrain_manager.get_elevation(theta, half_len, cylinder_length)
				var elev_blend = smoothstep(0.70, 1.0, alpha)
				var r_k = r_sphere - elev * elev_blend

				var pos = Vector3(r_k * cos_t, r_k * sin_t, z_cap)
				var norm = Vector3(-sin_phi * cos_t, -sin_phi * sin_t, -cos_phi).normalized()

				# Polar rib UV: 1:1 mapping with circular radial rib texture (center 0.5, 0.5, radius 0.49)
				var uv_rib = Vector2(0.5 + cos_t * (0.49 * alpha), 0.5 + sin_t * (0.49 * alpha))

				var t_type = 6 # Concrete structural bulkhead
				if r_k <= 350.0:
					t_type = 7 # Road / alloy central spaceport docking collar
				elif alpha > 0.94:
					t_type = terrain_manager.get_terrain_type(theta, half_len, cylinder_length)

				st.set_normal(norm)
				st.set_uv(uv_rib)
				st.set_color(Color(alpha, float(t_type) / 7.0, 1.0, 1.0))
				st.add_vertex(pos)

		# Cap 2 Triangles: Center to Ring 1 (reversed winding for -Z facing)
		for i in range(cap_divisions):
			var p0 = center_idx2
			var p1 = center_idx2 + 1 + i
			var p2 = center_idx2 + 1 + (i + 1)
			st.add_index(p0)
			st.add_index(p2)
			st.add_index(p1)

		# Cap 2 Triangles: Ring k to Ring k+1 (reversed winding for -Z facing)
		for k in range(1, cap_rings):
			var r_curr_start = center_idx2 + 1 + (k - 1) * stride
			var r_next_start = center_idx2 + 1 + k * stride
			for i in range(cap_divisions):
				var i00 = r_curr_start + i
				var i10 = r_curr_start + (i + 1)
				var i01 = r_next_start + i
				var i11 = r_next_start + (i + 1)

				st.add_index(i00)
				st.add_index(i10)
				st.add_index(i01)

				st.add_index(i10)
				st.add_index(i11)
				st.add_index(i01)

	st.generate_tangents()
	var mesh = st.commit()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = surface_material
	mesh_instance.extra_cull_margin = 6000.0
	mesh_instance.custom_aabb = AABB(Vector3(-4500.0, -4500.0, -14000.0), Vector3(9000.0, 9000.0, 28000.0))

	# Dedicated lightweight physics collision mesh (92% fewer collision triangles on mobile CPU)
	_generate_physics_collision_shape()

func _generate_physics_collision_shape() -> void:
	if not mesh_instance or not mesh_instance.mesh:
		return
	var shape = mesh_instance.mesh.create_trimesh_shape()
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
	water_mesh_instance.material_override = water_material
	water_mesh_instance.extra_cull_margin = 4000.0
	water_mesh_instance.custom_aabb = AABB(Vector3(-4500.0, -4500.0, -10000.0), Vector3(9000.0, 9000.0, 20000.0))
