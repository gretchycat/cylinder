@tool
class_name CylinderGenerator
extends Node3D

const TerrainManagerClass = preload("res://scripts/terrain_manager.gd")
const MapConfigClass = preload("res://scripts/map_config.gd")
const MapAssetLoaderClass = preload("res://scripts/map_asset_loader.gd")

@export_category("Cylinder Dimensions (8 km dia x 18 km length)")
@export var radius: float = 4000.0: # 8 km diameter = 4 km radius
	set(val):
		radius = val
		if is_inside_tree() and Engine.is_editor_hint() and not _is_initializing_terrain:
			generate_cylinder()

@export var cylinder_length: float = 18000.0: # 18 km length
	set(val):
		cylinder_length = val
		if is_inside_tree() and Engine.is_editor_hint() and not _is_initializing_terrain:
			generate_cylinder()

@export_category("Mesh Tessellation")
@export var radial_segments: int = 144:
	set(val):
		radial_segments = clampi(val, 16, 256)
		if is_inside_tree() and Engine.is_editor_hint() and not _is_initializing_terrain:
			generate_cylinder()

@export var length_segments: int = 180: # 180 segments along 18 km = 100m per segment
	set(val):
		length_segments = clampi(val, 4, 360)
		if is_inside_tree() and Engine.is_editor_hint() and not _is_initializing_terrain:
			generate_cylinder()

@export var include_end_caps: bool = true:
	set(val):
		include_end_caps = val
		if is_inside_tree() and Engine.is_editor_hint() and not _is_initializing_terrain:
			generate_cylinder()

@export var end_cap_rings: int = 32: # Concentric structural rings on each hemispherical end cap
	set(val):
		end_cap_rings = clampi(val, 8, 64)
		if is_inside_tree() and Engine.is_editor_hint() and not _is_initializing_terrain:
			generate_cylinder()

@export var end_cap_dish_depth: float = 4000.0: # Hemispherical dome radius depth (4 km)
	set(val):
		end_cap_dish_depth = max(val, 0.0)
		if is_inside_tree() and Engine.is_editor_hint() and not _is_initializing_terrain:
			generate_cylinder()

@export_category("Terrain & Elevation Maps")
@export var elevation_variance: float = 100.0: # 0 to 100 m elevation range
	set(val):
		elevation_variance = max(val, 0.0)
		if terrain_manager:
			terrain_manager.elevation_variance = elevation_variance
		if is_inside_tree() and Engine.is_editor_hint() and not _is_initializing_terrain:
			generate_cylinder()

@export var water_level: float = 20.0: # 20 m from elevation 0
	set(val):
		water_level = max(val, 0.0)
		if terrain_manager:
			terrain_manager.water_level = water_level
		if is_inside_tree() and Engine.is_editor_hint() and not _is_initializing_terrain:
			generate_cylinder()

var elevation_map_path: String = "":
	set(val):
		elevation_map_path = val
		if terrain_manager and is_inside_tree() and not _is_initializing_terrain:
			terrain_manager.load_elevation(elevation_map_path)
			generate_cylinder()

var terrain_map_path: String = "":
	set(val):
		terrain_map_path = val
		if terrain_manager and is_inside_tree() and not _is_initializing_terrain:
			terrain_manager.load_terrain(terrain_map_path)
			generate_cylinder()

@export var map_package: String = "res://assets/maps/default":
	set(val):
		if map_package == val:
			return
		map_package = val
		if is_inside_tree() and not _is_initializing_terrain:
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
var active_map_config: Dictionary = {}
var map_load_error: String = ""

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
	else:
		generate_cylinder()
	var light_bar = get_tree().get_first_node_in_group("light_bar")
	if light_bar and light_bar.has_method("_apply_lut_to_materials"):
		light_bar._apply_lut_to_materials()

func _initialize_terrain_manager() -> void:
	load_map_package(MapConfigClass.active_map() if not Engine.is_editor_hint() else map_package)

## Stage layers before changing active state. A malformed layer preserves the world.
func load_map_package(package_path_or_name: String) -> bool:
	var cfg = MapConfigClass.load_map_config(package_path_or_name)
	if cfg.is_empty():
		map_load_error = MapConfigClass.last_error
		push_error(map_load_error)
		return false
	if cfg.map_directory != MapConfigClass.active_map_assets_validated_directory:
		var asset_error = MapConfigClass.validate_assets(cfg)
		if not asset_error.is_empty():
			map_load_error = asset_error
			push_error(map_load_error)
			return false
	var staged = MapConfigClass.take_active_map_terrain(cfg.map_directory) as TerrainManagerClass
	if not staged:
		staged = TerrainManagerClass.new()
		staged.configure(cfg)
		if not staged.load_layers(MapConfigClass.get_elevation_map_path(cfg), MapConfigClass.get_terrain_map_path(cfg)):
			map_load_error = staged.last_error
			push_error(map_load_error)
			return false
	map_load_error = ""
	_is_initializing_terrain = true
	map_package = package_path_or_name
	active_map_config = cfg
	terrain_manager = staged
	radius = cfg.geometry.cylinder_radius_m
	cylinder_length = cfg.geometry.cylinder_length_m
	elevation_variance = cfg.geometry.elevation_variance_m
	water_level = cfg.geometry.water_sea_level_m
	elevation_map_path = MapConfigClass.get_elevation_map_path(cfg)
	terrain_map_path = MapConfigClass.get_terrain_map_path(cfg)
	radial_segments = int(cfg.rendering.radial_segments)
	length_segments = int(cfg.rendering.length_segments)
	end_cap_rings = int(cfg.rendering.end_cap_rings)
	end_cap_dish_depth = cfg.rendering.end_cap_dish_depth_m
	include_end_caps = cfg.rendering.include_end_caps
	air_color = MapConfigClass.color(cfg.environment.air_color)
	air_density = cfg.environment.air_density
	air_distance_min = cfg.environment.air_distance_min
	air_distance_max = cfg.environment.air_distance_max
	_is_initializing_terrain = false
	if is_inside_tree() and not _is_generating:
		apply_environment()
		for group in active_map_config.simulation:
			var node = get_tree().get_first_node_in_group(group)
			if node:
				preload("res://scripts/map_runtime.gd").configure_node(node, group, active_map_config)
				if node.has_method("map_changed"):
					node.map_changed()
		generate_cylinder()
	return true

func apply_environment() -> void:
	var env_node = get_parent().get_node_or_null("WorldEnvironment")
	if env_node and env_node.environment:
		var env = env_node.environment
		var values: Dictionary = active_map_config.environment
		env.background_color = MapConfigClass.color(values.sky_color)
		env.ambient_light_color = MapConfigClass.color(values.ambient_color)
		env.ambient_light_energy = values.ambient_energy
		env.fog_light_color = MapConfigClass.color(values.air_color)
		env.fog_depth_begin = values.air_distance_min
		env.fog_depth_end = values.air_distance_max

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
	if pref_elev >= required_elevation:
		return _build_spawn_info(preferred_theta, preferred_z, pref_elev, pref_type)

	# 2. Search grid for nearest terrain cell above sea level
	var grid_u = terrain_manager.grid_u
	var grid_v = terrain_manager.grid_v
	var elev_data = terrain_manager.elevation_data
	var terr_data = terrain_manager.terrain_data

	if elev_data.is_empty():
		return _build_spawn_info(preferred_theta, preferred_z, water_level + 5.0, -1)

	var target_u = fposmod(preferred_theta, TAU) / TAU
	var target_v = clampf((preferred_z + cylinder_length * 0.5) / maxf(cylinder_length, 1.0), 0.0, 1.0)
	var cx = int(target_u * float(grid_u)) % grid_u
	var cy = clampi(int(target_v * float(grid_v - 1)), 0, grid_v - 1)

	var best_x: int = -1
	var best_y: int = -1
	var best_dist_sq: float = INF
	var best_elev: float = 0.0
	var best_type: int = -1

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
					var t = terrain_manager.get_terrain_type(float(x) / grid_u * TAU, (float(y) / (grid_v - 1) - 0.5) * cylinder_length, cylinder_length)
					if e >= required_elevation:
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
					var t = terrain_manager.get_terrain_type(float(x) / grid_u * TAU, (float(y) / (grid_v - 1) - 0.5) * cylinder_length, cylinder_length)
					if e >= required_elevation:
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
	return _build_spawn_info(fall_theta, fall_z, highest_elev, -1)

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
	return MapAssetLoaderClass.load_texture(path)

func _update_terrain_material_textures(mat: ShaderMaterial = null) -> void:
	if not mat:
		mat = surface_material as ShaderMaterial
	if not mat:
		return
	preload("res://scripts/map_runtime.gd").shader_parameters(mat, active_map_config)

	var images: Array[Image] = []
	var tints = Image.create(256, 1, false, Image.FORMAT_RGBA8)
	var parameters = Image.create(256, 1, false, Image.FORMAT_RGBAF)
	var resolution = int(active_map_config.rendering.biome_texture_resolution)
	for biome in active_map_config.biomes.values():
		var img = MapAssetLoaderClass.load_image(MapConfigClass.resolve_map_asset_path(active_map_config, biome.texture))
		if img == null:
			push_error("Missing biome texture: " + str(biome.texture))
			return
		img.convert(Image.FORMAT_RGBA8)
		img.resize(resolution, resolution, Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		var id = int(biome.raster_id)
		tints.set_pixel(id, 0, MapConfigClass.color(biome.tint))
		var is_blended: bool = bool(biome.get("blended", true))
		var is_rotated: bool = bool(biome.get("rotate", is_blended))
		var alpha_val: float = 0.0
		if is_blended:
			alpha_val = 1.0 if is_rotated else 0.5
		parameters.set_pixel(id, 0, Color(images.size(), biome.texture_size_m, biome.roughness, alpha_val))


		images.append(img)
	var textures = Texture2DArray.new()
	textures.create_from_images(images)
	mat.set_shader_parameter("biome_textures", textures)
	mat.set_shader_parameter("biome_tints", ImageTexture.create_from_image(tints))
	mat.set_shader_parameter("biome_parameters", ImageTexture.create_from_image(parameters))
	mat.set_shader_parameter("tex_end_cap_ribs", _load_texture_safe(MapConfigClass.resolve_map_asset_path(active_map_config, active_map_config.rendering.end_cap_texture)))
	mat.set_shader_parameter("end_cap_tint", MapConfigClass.color(active_map_config.rendering.end_cap_tint))
	mat.set_shader_parameter("terrain_map", ImageTexture.create_from_image(terrain_manager.create_terrain_type_id_image()))
	mat.set_shader_parameter("terrain_map_size", Vector2(terrain_manager.terrain_grid_u, terrain_manager.terrain_grid_v))
	mat.set_shader_parameter("biome_blend_width_m", active_map_config.rendering.biome_blend_width_m)
	mat.set_shader_parameter("deep_water_color", MapConfigClass.color(active_map_config.environment.water.deep_color))

	mat.set_shader_parameter("cylinder_radius", radius)
	mat.set_shader_parameter("cylinder_length", cylinder_length)
	mat.set_shader_parameter("water_level", water_level)
	mat.set_shader_parameter("max_elevation", elevation_variance)
	mat.set_shader_parameter("air_color", air_color)
	mat.set_shader_parameter("air_density", air_density)
	mat.set_shader_parameter("air_distance_min", air_distance_min)
	mat.set_shader_parameter("air_distance_max", air_distance_max)
	mat.set_shader_parameter("cloud_coverage", active_map_config.simulation.weather_system.cloud_coverage)

func _create_terrain_material() -> ShaderMaterial:
	var shader = load("res://assets/shaders/cylinder_terrain.gdshader")
	if not shader:
		return null
	var mat = ShaderMaterial.new()
	mat.shader = shader
	preload("res://scripts/map_runtime.gd").shader_parameters(mat, active_map_config)
	_update_terrain_material_textures(mat)
	return mat

func _create_water_material() -> ShaderMaterial:
	var shader = load("res://assets/shaders/cylinder_water.gdshader")
	if not shader:
		return null
	var mat = ShaderMaterial.new()
	mat.shader = shader
	preload("res://scripts/map_runtime.gd").shader_parameters(mat, active_map_config)
	mat.render_priority = 1
	preload("res://scripts/map_runtime.gd").shader_parameters(mat, active_map_config)
	mat.set_shader_parameter("cylinder_radius", radius - water_level)
	mat.set_shader_parameter("cylinder_length", cylinder_length)
	mat.set_shader_parameter("water_level", water_level)
	mat.set_shader_parameter("max_elevation", elevation_variance)
	mat.set_shader_parameter("air_color", air_color)
	mat.set_shader_parameter("air_density", air_density)
	mat.set_shader_parameter("air_distance_min", air_distance_min)
	mat.set_shader_parameter("air_distance_max", air_distance_max)
	mat.set_shader_parameter("cloud_coverage", active_map_config.simulation.weather_system.cloud_coverage)
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
	preload("res://scripts/map_runtime.gd").shader_parameters(mat, active_map_config)
	mat.set_shader_parameter("cylinder_radius", radius - water_level)
	mat.set_shader_parameter("cylinder_length", cylinder_length)
	mat.set_shader_parameter("water_level", water_level)
	mat.set_shader_parameter("max_elevation", elevation_variance)
	mat.set_shader_parameter("air_color", air_color)
	mat.set_shader_parameter("air_density", air_density)
	mat.set_shader_parameter("air_distance_min", air_distance_min)
	mat.set_shader_parameter("air_distance_max", air_distance_max)

	for key in active_map_config.environment.water:
		var value = active_map_config.environment.water[key]
		if value is Array:
			value = Vector3(value[0], value[1], value[2]) if value.size() == 3 else MapConfigClass.color(value)
		mat.set_shader_parameter(key, value)
	mat.set_shader_parameter("elevation_map", ImageTexture.create_from_image(terrain_manager.create_elevation_image()))
	mat.set_shader_parameter("elevation_map_size", Vector2(terrain_manager.elevation_grid_u, terrain_manager.elevation_grid_v))

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
			var du = TAU / terrain_manager.elevation_grid_u
			var sample_dz = cylinder_length / (terrain_manager.elevation_grid_v - 1)
			var h_s = (terrain_manager.get_elevation(theta + du, z, cylinder_length) - terrain_manager.get_elevation(theta - du, z, cylinder_length)) / (2 * du * r_surface)
			var z0 = maxf(z - sample_dz, -half_len)
			var z1 = minf(z + sample_dz, half_len)
			var h_z = (terrain_manager.get_elevation(theta, z1, cylinder_length) - terrain_manager.get_elevation(theta, z0, cylinder_length)) / (z1 - z0)
			var normal = Vector3(-cos_t + h_s * sin_t, -sin_t - h_s * cos_t, -h_z).normalized()

			st.set_normal(normal)
			st.set_uv(Vector2(u_coord, v_coord))
			# Pass elevation and terrain type through vertex COLOR attribute (0..7 normalized by 7.0)
			st.set_color(Color(elev / max(elevation_variance, 0.1), float(t_type) / 255.0, 0.0, 1.0))
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
				st.set_color(Color(alpha, float(t_type) / 255.0, 1.0, 1.0))
				st.add_vertex(pos)

		# Cap 1 Triangles: Clockwise from inside, matching the inward +Z normals.
		# With cull_disabled, back-facing triangles would flip those normals outward.
		# Center to Ring 1
		for i in range(cap_divisions):
			var p0 = center_idx1
			var p1 = center_idx1 + 1 + i
			var p2 = center_idx1 + 1 + (i + 1)
			st.add_index(p0)
			st.add_index(p2)
			st.add_index(p1)

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
				st.add_index(i10)
				st.add_index(i01)

				st.add_index(i10)
				st.add_index(i11)
				st.add_index(i01)

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
				st.set_color(Color(alpha, float(t_type) / 255.0, 1.0, 1.0))
				st.add_vertex(pos)

		# Cap 2 Triangles: Clockwise from inside, matching the inward -Z normals.
		for i in range(cap_divisions):
			var p0 = center_idx2
			var p1 = center_idx2 + 1 + i
			var p2 = center_idx2 + 1 + (i + 1)
			st.add_index(p0)
			st.add_index(p1)
			st.add_index(p2)

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
				st.add_index(i01)
				st.add_index(i10)

				st.add_index(i10)
				st.add_index(i01)
				st.add_index(i11)

	st.generate_tangents()
	var mesh = st.commit()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = surface_material
	mesh_instance.extra_cull_margin = 0.0
	mesh_instance.custom_aabb = AABB(Vector3(-radius, -radius, -cylinder_length * 0.5 - end_cap_dish_depth), Vector3(radius * 2, radius * 2, cylinder_length + 2 * end_cap_dish_depth))

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
	water_mesh_instance.extra_cull_margin = 0.0
	water_mesh_instance.custom_aabb = AABB(Vector3(-water_r, -water_r, -half_len), Vector3(water_r * 2, water_r * 2, cylinder_length))
