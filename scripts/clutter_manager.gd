@tool
class_name ClutterManager
extends Node3D

const CLUTTER_SHADER: Shader = preload("res://assets/shaders/ground_clutter.gdshader")
const TerrainManagerClass = preload("res://scripts/terrain_manager.gd")
const MapConfigClass = preload("res://scripts/map_config.gd")
const DebugConsoleClass = preload("res://scripts/debug_console.gd")

@export var enabled: bool = true:
	set(val):
		enabled = val
		if not enabled:
			_clear_all_chunks()

## Periodically prints low-overhead clutter and renderer measurements for profiling.
@export var performance_telemetry_enabled: bool = true
@export_range(1.0, 30.0, 1.0) var performance_telemetry_interval: float = 5.0

@export var view_radius: float = 500.0:
	set(val):
		view_radius = clampf(val, 50.0, 1000.0)
		_update_material_world_parameters()
		last_update_pos = Vector3(99999.0, 99999.0, 99999.0)

@export var fade_distance: float = 120.0:
	set(val):
		fade_distance = clampf(val, 10.0, 400.0)
		_update_material_world_parameters()

@export var chunk_size: float = 40.0:
	set(val):
		chunk_size = clampf(val, 15.0, 100.0)

@export var density_multiplier: float = 1.0:
	set(val):
		var next_value = clampf(val, 0.0, 3.0)
		var changed = not is_equal_approx(density_multiplier, next_value)
		density_multiplier = next_value
		if changed and is_inside_tree():
			_clear_all_chunks()

var grassland_density_multiplier: float = 1.0
var farmland_density_multiplier: float = 1.0
var adaptive_draw_distance_scale: float = 1.0
var adaptive_density_scale: float = 1.0

var cylinder_world: CylinderGenerator = null
var map_config: Dictionary = {}
var clutter_model_definitions: Dictionary = {}
var active_chunks: Dictionary = {} # Vector2i -> Node3D (Chunk root)
var last_cam_grid: Vector2i = Vector2i(-99999, -99999)
var last_update_pos: Vector3 = Vector3(99999, 99999, 99999)
var update_timer: float = 0.0

# Rolling console telemetry. Work counters reset after each report interval.
var _telemetry_elapsed: float = 0.0
var _telemetry_frame_count: int = 0
var _telemetry_frame_ms_total: float = 0.0
var _telemetry_frame_ms_max: float = 0.0
var _telemetry_chunk_builds: int = 0
var _telemetry_chunk_build_ms_total: float = 0.0
var _telemetry_chunk_build_ms_max: float = 0.0
var _telemetry_terrain_samples: int = 0
var _telemetry_surface_queries: int = 0

# Shared materials & meshes
var grass_mat: ShaderMaterial = null
var flower_mat: ShaderMaterial = null
var stone_mat: ShaderMaterial = null
var crop_mat: ShaderMaterial = null
var shrub_mat: ShaderMaterial = null
var mushroom_mat: ShaderMaterial = null
var grass_mesh: ArrayMesh = null
var flower_mesh: ArrayMesh = null
var stone_mesh: ArrayMesh = null
var crop_mesh: ArrayMesh = null
var shrub_mesh: ArrayMesh = null
var mushroom_mesh: ArrayMesh = null

const FLOWER_COLORS: Array[Color] = [
	Color(0.95, 0.22, 0.18, 0.9), # Poppy Red
	Color(0.98, 0.85, 0.15, 0.9), # Buttercup Yellow
	Color(0.35, 0.55, 0.95, 0.9), # Cornflower Blue
	Color(0.72, 0.38, 0.92, 0.9), # Lavender / Lupine Purple
	Color(0.96, 0.96, 0.92, 0.85), # Daisy White
	Color(0.98, 0.52, 0.25, 0.9), # Orange Blossom
]

func _ready() -> void:
	_find_cylinder_world()
	_load_map_clutter_config()
	_init_resources()
	_update_material_world_parameters()

func _load_map_clutter_config() -> void:
	var map_package = str(cylinder_world.map_package) if cylinder_world else "default"
	map_config = MapConfigClass.load_map_config(map_package)
	var clutter_config = MapConfigClass.get_clutter_config(map_config)
	clutter_model_definitions = clutter_config.get("models", {}) as Dictionary
	view_radius = float(clutter_config.get("view_radius_m", view_radius))
	chunk_size = float(clutter_config.get("chunk_size_m", chunk_size))
	density_multiplier = float(clutter_config.get("density_multiplier", density_multiplier))
	grassland_density_multiplier = clampf(float(clutter_config.get("grassland_density_multiplier", grassland_density_multiplier)), 1.0, 10.0)
	farmland_density_multiplier = clampf(float(clutter_config.get("farmland_density_multiplier", farmland_density_multiplier)), 1.0, 10.0)

func _load_clutter_model_mesh(model_id: String) -> Mesh:
	var scene_path = MapConfigClass.get_clutter_model_path(map_config, model_id)
	if scene_path.is_empty():
		push_warning("Map clutter model '%s' has no scene_path" % model_id)
		return null
	var resource = ResourceLoader.load(scene_path)
	if resource is Mesh:
		return resource
	if not resource is PackedScene:
		push_warning("Could not load map clutter model scene or mesh: %s" % scene_path)
		return null
	var model_instance = (resource as PackedScene).instantiate()
	var generated_mesh: Mesh = null
	if model_instance.has_method("build_mesh"):
		generated_mesh = model_instance.call("build_mesh") as Mesh
	if generated_mesh == null and model_instance is MeshInstance3D:
		generated_mesh = (model_instance as MeshInstance3D).mesh
	if generated_mesh == null:
		var mesh_nodes = model_instance.find_children("*", "MeshInstance3D", true, false)
		if not mesh_nodes.is_empty():
			generated_mesh = (mesh_nodes[0] as MeshInstance3D).mesh
	model_instance.free()
	if generated_mesh == null:
		push_warning("Map clutter model scene contains no mesh: %s" % scene_path)
	return generated_mesh

func _configure_map_material(mat: ShaderMaterial, model_id: String) -> void:
	var definition: Dictionary = clutter_model_definitions.get(model_id, {}) as Dictionary
	if definition.is_empty():
		return
	for color_key in ["base_color", "tip_color"]:
		var color_values = definition.get(color_key, []) as Array
		if color_values.size() >= 3:
			var color = Color(float(color_values[0]), float(color_values[1]), float(color_values[2]), float(color_values[3]) if color_values.size() > 3 else 1.0)
			mat.set_shader_parameter(color_key, color)
	for float_key in ["wind_speed", "wind_strength", "roughness"]:
		if definition.has(float_key):
			mat.set_shader_parameter(float_key, float(definition[float_key]))
	if definition.has("gradient_mode"):
		var gradient_modes := {"none": 0, "linear": 1, "radial": 2}
		var mode_name = str(definition["gradient_mode"]).to_lower()
		if gradient_modes.has(mode_name):
			mat.set_shader_parameter("gradient_mode", gradient_modes[mode_name])
	if definition.has("gradient_extent_m"):
		mat.set_shader_parameter("gradient_extent", maxf(float(definition["gradient_extent_m"]), 0.001))
	if definition.has("fade_distance_m"):
		mat.set_shader_parameter("fade_distance", float(definition["fade_distance_m"]))

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
	for mat in [grass_mat, flower_mat, stone_mat, crop_mat, shrub_mat, mushroom_mat]:
		if mat:
			mat.set_shader_parameter("cylinder_radius", r)
			mat.set_shader_parameter("water_level", w_lvl)
			mat.set_shader_parameter("air_color", air_col)
			mat.set_shader_parameter("air_density", air_d)
			mat.set_shader_parameter("max_distance", _effective_draw_distance())
			mat.set_shader_parameter("fade_distance", fade_distance)

func _init_resources() -> void:
	if grass_mesh != null:
		return

	# Materials
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = CLUTTER_SHADER
	grass_mat.set_shader_parameter("base_color", Color(0.24, 0.52, 0.16, 1.0))
	grass_mat.set_shader_parameter("tip_color", Color(0.48, 0.78, 0.25, 1.0))
	grass_mat.set_shader_parameter("gradient_mode", 1)
	grass_mat.set_shader_parameter("gradient_extent", 0.85)
	grass_mat.set_shader_parameter("wind_speed", 2.2)
	grass_mat.set_shader_parameter("wind_strength", 0.24)
	grass_mat.set_shader_parameter("max_distance", view_radius)
	grass_mat.set_shader_parameter("fade_distance", fade_distance)

	flower_mat = ShaderMaterial.new()
	flower_mat.shader = CLUTTER_SHADER
	flower_mat.set_shader_parameter("base_color", Color(0.22, 0.50, 0.18, 1.0))
	flower_mat.set_shader_parameter("tip_color", Color(0.95, 0.30, 0.20, 1.0))
	flower_mat.set_shader_parameter("is_flower", true)
	flower_mat.set_shader_parameter("gradient_mode", 1)
	flower_mat.set_shader_parameter("gradient_extent", 0.80)
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
	stone_mat.set_shader_parameter("gradient_mode", 2)
	stone_mat.set_shader_parameter("gradient_extent", 0.40)
	stone_mat.set_shader_parameter("max_distance", view_radius)
	stone_mat.set_shader_parameter("fade_distance", fade_distance)

	crop_mat = ShaderMaterial.new()
	crop_mat.shader = CLUTTER_SHADER
	crop_mat.set_shader_parameter("base_color", Color(0.65, 0.52, 0.22, 1.0))
	crop_mat.set_shader_parameter("tip_color", Color(0.88, 0.74, 0.32, 1.0))
	crop_mat.set_shader_parameter("gradient_mode", 1)
	crop_mat.set_shader_parameter("gradient_extent", 1.15)
	crop_mat.set_shader_parameter("wind_speed", 1.8)
	crop_mat.set_shader_parameter("wind_strength", 0.28)
	crop_mat.set_shader_parameter("max_distance", view_radius)
	crop_mat.set_shader_parameter("fade_distance", fade_distance)

	shrub_mat = ShaderMaterial.new()
	shrub_mat.shader = CLUTTER_SHADER
	shrub_mat.set_shader_parameter("base_color", Color(0.18, 0.42, 0.14, 1.0))
	shrub_mat.set_shader_parameter("tip_color", Color(0.32, 0.62, 0.22, 1.0))
	shrub_mat.set_shader_parameter("gradient_mode", 2)
	shrub_mat.set_shader_parameter("gradient_extent", 0.65)
	shrub_mat.set_shader_parameter("wind_speed", 1.6)
	shrub_mat.set_shader_parameter("wind_strength", 0.14)
	shrub_mat.set_shader_parameter("max_distance", view_radius)
	shrub_mat.set_shader_parameter("fade_distance", fade_distance)
	_configure_map_material(grass_mat, "grass_tuft")
	_configure_map_material(flower_mat, "wildflowers")
	_configure_map_material(stone_mat, "pebbles")
	_configure_map_material(crop_mat, "crops")
	_configure_map_material(shrub_mat, "shrubs")

	_update_material_world_parameters()

	# Build procedural meshes
	grass_mesh = _load_clutter_model_mesh("grass_tuft") as ArrayMesh
	flower_mesh = _load_clutter_model_mesh("wildflowers") as ArrayMesh
	stone_mesh = _load_clutter_model_mesh("pebbles") as ArrayMesh
	crop_mesh = _load_clutter_model_mesh("crops") as ArrayMesh
	shrub_mesh = _load_clutter_model_mesh("shrubs") as ArrayMesh

	mushroom_mat = ShaderMaterial.new()
	mushroom_mat.shader = CLUTTER_SHADER
	mushroom_mat.set_shader_parameter("base_color", Color(0.84, 0.76, 0.63, 1.0))
	mushroom_mat.set_shader_parameter("tip_color", Color(0.44, 0.27, 0.16, 1.0))
	mushroom_mat.set_shader_parameter("is_mushroom", true)
	mushroom_mat.set_shader_parameter("gradient_mode", 2)
	mushroom_mat.set_shader_parameter("gradient_extent", 0.115)
	mushroom_mat.set_shader_parameter("max_distance", view_radius)
	mushroom_mat.set_shader_parameter("fade_distance", fade_distance)
	_configure_map_material(mushroom_mat, "mushrooms")

	mushroom_mesh = _load_clutter_model_mesh("mushrooms") as ArrayMesh

func _get_model_instance_color(model_id: String, rng: RandomNumberGenerator, fallback: Color) -> Color:
	var definition: Dictionary = clutter_model_definitions.get(model_id, {}) as Dictionary
	var colors: Array = definition.get("instance_colors", []) as Array
	if colors.is_empty():
		return fallback
	var values = colors[rng.randi() % colors.size()] as Array
	if values.size() < 3:
		return fallback
	return Color(float(values[0]), float(values[1]), float(values[2]), float(values[3]) if values.size() > 3 else 1.0)

func _process(delta: float) -> void:
	_record_performance_telemetry(delta)
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

func _record_performance_telemetry(delta: float) -> void:
	if not performance_telemetry_enabled:
		return
	_telemetry_elapsed += delta
	_telemetry_frame_count += 1
	var frame_ms = delta * 1000.0
	_telemetry_frame_ms_total += frame_ms
	_telemetry_frame_ms_max = maxf(_telemetry_frame_ms_max, frame_ms)
	if _telemetry_elapsed < maxf(performance_telemetry_interval, 1.0):
		return
	var active_instances := 0
	for chunk in active_chunks.values():
		if is_instance_valid(chunk):
			active_instances += int(floor(float(chunk.get_meta("clutter_placed_instances", 0)) * adaptive_density_scale))
	var fps = float(_telemetry_frame_count) / maxf(_telemetry_elapsed, 0.001)
	var avg_frame_ms = _telemetry_frame_ms_total / maxf(float(_telemetry_frame_count), 1.0)
	var avg_build_ms = _telemetry_chunk_build_ms_total / maxf(float(_telemetry_chunk_builds), 1.0)
	var draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var video_mem_mb = float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0)
	var map_name = str(cylinder_world.map_package) if cylinder_world else "unknown"
	var report = "[ClutterPerf] map=%s avg_fps=%.1f avg_frame_ms=%.2f max_frame_ms=%.2f chunks=%d visible_instances~%d density=%.2f range=%.0fm draw_calls=%d primitives=%d video_mem=%.1fMB chunk_builds=%d build_avg_ms=%.2f build_max_ms=%.2f terrain_samples=%d surface_queries=%d" % [
		map_name, fps, avg_frame_ms, _telemetry_frame_ms_max, active_chunks.size(), active_instances,
		adaptive_density_scale, _effective_draw_distance(), draw_calls, primitives, video_mem_mb,
		_telemetry_chunk_builds, avg_build_ms, _telemetry_chunk_build_ms_max,
		_telemetry_terrain_samples, _telemetry_surface_queries
	]
	HUD.log_event(report, "#66ddff")
	DebugConsoleClass.log(report)
	_telemetry_elapsed = fposmod(_telemetry_elapsed, maxf(performance_telemetry_interval, 1.0))
	_telemetry_frame_count = 0
	_telemetry_frame_ms_total = 0.0
	_telemetry_frame_ms_max = 0.0
	_telemetry_chunk_builds = 0
	_telemetry_chunk_build_ms_total = 0.0
	_telemetry_chunk_build_ms_max = 0.0
	_telemetry_terrain_samples = 0
	_telemetry_surface_queries = 0

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

	var chunk_radius = int(ceil(_effective_draw_distance() / chunk_size))
	var clutter_radius = _effective_draw_distance() + 3.0
	var clutter_radius_squared = clutter_radius * clutter_radius
	var camera_chunk_offset_x = fposmod(cam_u_m, chunk_size)
	var camera_chunk_offset_z = fposmod(cam_z_m, chunk_size)
	var needed_chunks: Dictionary = {}

	for dz in range(-chunk_radius, chunk_radius + 1):
		var cz = center_chunk_z + dz
		if cz < 0 or cz >= num_chunks_z:
			continue

		for dx in range(-chunk_radius, chunk_radius + 1):
			# The previous square window built and rendered corner chunks whose
			# entire 40m footprint was beyond the radial shader cutoff. Keep only
			# chunks whose footprint can intersect the clutter visibility circle.
			var chunk_offset_x = float(dx) * chunk_size - camera_chunk_offset_x
			var chunk_offset_z = float(dz) * chunk_size - camera_chunk_offset_z
			var nearest_x = maxf(maxf(chunk_offset_x, -(chunk_offset_x + chunk_size)), 0.0)
			var nearest_z = maxf(maxf(chunk_offset_z, -(chunk_offset_z + chunk_size)), 0.0)
			if nearest_x * nearest_x + nearest_z * nearest_z > clutter_radius_squared:
				continue
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
	var build_started_usec = Time.get_ticks_usec()

	var tm = cylinder_world.terrain_manager
	var texture_cover_active := false
	if cylinder_world.surface_material is ShaderMaterial:
		texture_cover_active = bool((cylinder_world.surface_material as ShaderMaterial).get_shader_parameter("clutter_cover_enabled"))
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
	var targeted_density = maxf(grassland_density_multiplier, farmland_density_multiplier)
	var base_samples = int(120 * density_multiplier * targeted_density)
	
	# Instance buffers for each clutter category
	var grass_transforms: Array[Transform3D] = []
	var grass_colors: Array[Color] = []

	var flower_transforms: Array[Transform3D] = []
	var flower_colors: Array[Color] = []
	var flower_petal_angles: Array[Color] = []

	var stone_transforms: Array[Transform3D] = []
	var stone_colors: Array[Color] = []

	var crop_transforms: Array[Transform3D] = []
	var crop_colors: Array[Color] = []

	var shrub_transforms: Array[Transform3D] = []
	var shrub_colors: Array[Color] = []

	var mushroom_transforms: Array[Transform3D] = []
	var mushroom_colors: Array[Color] = []

	for s in range(base_samples):
		_telemetry_terrain_samples += 1
		var offset_u = rng.randf() * chunk_size
		var offset_z = rng.randf() * chunk_size

		var u_m = u0_m + offset_u
		var z = z0_m + offset_z
		if z < -cyl_len * 0.5 or z > cyl_len * 0.5:
			continue

		var theta = (u_m / cyl_r) - PI
		var t_type = tm.get_terrain_type(theta, z, cyl_len)
		var type_density = 1.0
		if t_type == TerrainManagerClass.TerrainType.GRASS:
			type_density = grassland_density_multiplier
		elif t_type == TerrainManagerClass.TerrainType.FARMLAND:
			type_density = farmland_density_multiplier
		if rng.randf() >= type_density / targeted_density:
			continue
		var elev = tm.get_elevation(theta, z, cyl_len)

		# Water level culling: don't spawn on submerged terrain or roads
		if elev < tm.water_level + 0.35:
			continue
		if t_type == TerrainManagerClass.TerrainType.WATER or t_type == TerrainManagerClass.TerrainType.ROAD or t_type == TerrainManagerClass.TerrainType.CONCRETE:
			continue

		# Decide whether this sample needs a unique model before doing the exact
		# terrain-triangle query. Cached cover replaces most small clutter.
		var scatter_roll := 0.0
		var needs_model := true
		match t_type:
			TerrainManagerClass.TerrainType.GRASS:
				scatter_roll = rng.randf()
				var secondary_end = 0.88 + 0.10 / maxf(grassland_density_multiplier, 1.0)
				needs_model = (scatter_roll < 0.28 or (scatter_roll >= 0.88 and scatter_roll < secondary_end)) if texture_cover_active else scatter_roll < secondary_end + 0.02 / maxf(grassland_density_multiplier, 1.0)
			TerrainManagerClass.TerrainType.ROCKS:
				scatter_roll = rng.randf()
				needs_model = scatter_roll < 0.25 if texture_cover_active else true
			TerrainManagerClass.TerrainType.FARMLAND:
				scatter_roll = rng.randf()
				needs_model = scatter_roll < 0.40 if texture_cover_active else true
			TerrainManagerClass.TerrainType.DIRT:
				scatter_roll = rng.randf()
				needs_model = scatter_roll < 0.20 or scatter_roll >= 0.98 if texture_cover_active else true
			TerrainManagerClass.TerrainType.SAND:
				scatter_roll = rng.randf()
				needs_model = scatter_roll < 0.15 if texture_cover_active else scatter_roll < 0.40
		if not needs_model:
			continue

		# Query exact terrain mesh surface position and normal directly on triangle polygons
		var pos: Vector3
		var normal: Vector3
		var mesh_info: Dictionary = {}
		if cylinder_world and cylinder_world.has_method("get_surface_mesh_point_and_normal"):
			_telemetry_surface_queries += 1
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
				var roll = scatter_roll
				var grass_density = maxf(grassland_density_multiplier, 1.0)
				# The atlas provides continuous cover; sparse meshes preserve clear,
				# recognizable blades and flowers without restoring the old mesh load.
				if texture_cover_active and roll < 0.28:
					var scale_factor = rng.randf_range(0.75, 1.45)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					grass_transforms.append(tf)
					grass_colors.append(Color(rng.randf_range(0.62, 1.32), rng.randf_range(0.72, 1.28), rng.randf_range(0.48, 1.38), 1.0))
				elif texture_cover_active and roll >= 0.88 and roll < 0.88 + 0.07 / grass_density:
					var scale_factor = rng.randf_range(0.80, 1.35)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					flower_transforms.append(tf)
					var col_idx = rng.randi() % FLOWER_COLORS.size()
					flower_colors.append(_get_model_instance_color("wildflowers", rng, FLOWER_COLORS[col_idx]))
					flower_petal_angles.append(Color(rng.randf() * TAU, 0.0, 0.0, 1.0))
				elif texture_cover_active and roll >= 0.88 + 0.07 / grass_density and roll < 0.88 + 0.10 / grass_density:
					var scale_factor = rng.randf_range(0.9, 1.6)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					shrub_transforms.append(tf)
					shrub_colors.append(Color(1, 1, 1, 1.0))
				elif not texture_cover_active and roll < 0.88:
					var scale_factor = rng.randf_range(0.75, 1.45)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					grass_transforms.append(tf)
					grass_colors.append(Color(rng.randf_range(0.62, 1.32), rng.randf_range(0.72, 1.28), rng.randf_range(0.48, 1.38), 1.0))
				elif not texture_cover_active and roll < 0.88 + 0.07 / grass_density:
					var scale_factor = rng.randf_range(0.80, 1.35)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					flower_transforms.append(tf)
					var col_idx = rng.randi() % FLOWER_COLORS.size()
					flower_colors.append(_get_model_instance_color("wildflowers", rng, FLOWER_COLORS[col_idx]))
					flower_petal_angles.append(Color(rng.randf() * TAU, 0.0, 0.0, 1.0))
				elif not texture_cover_active and roll < 0.88 + 0.10 / grass_density:
					var scale_factor = rng.randf_range(0.9, 1.6)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					shrub_transforms.append(tf)
					shrub_colors.append(Color(1, 1, 1, 1.0))
				elif not texture_cover_active and roll < 0.88 + 0.12 / grass_density:
					var scale_factor = rng.randf_range(0.6, 1.3)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					stone_transforms.append(tf)
					stone_colors.append(Color(0.9, 0.9, 0.85, 1.0))

			TerrainManagerClass.TerrainType.ROCKS:
				if not texture_cover_active or scatter_roll < 0.25:
					var scale_factor = rng.randf_range(0.6, 2.2)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					stone_transforms.append(tf)
					var grey_var = rng.randf_range(0.7, 1.2)
					stone_colors.append(Color(grey_var, grey_var, grey_var, 1.0))

			TerrainManagerClass.TerrainType.FARMLAND:
				var farmland_roll = scatter_roll
				# Keep occasional tall crop clumps for depth; the atlas fills the rows.
				if texture_cover_active and farmland_roll < 0.40:
					var scale_factor = rng.randf_range(0.85, 1.4)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					crop_transforms.append(tf)
					crop_colors.append(Color(1, 1, 1, 1.0))
				elif not texture_cover_active and farmland_roll < 0.75:
					var scale_factor = rng.randf_range(0.85, 1.4)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					crop_transforms.append(tf)
					crop_colors.append(Color(1, 1, 1, 1.0))
				elif not texture_cover_active:
					var scale_factor = rng.randf_range(0.4, 0.9)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					stone_transforms.append(tf)
					stone_colors.append(Color(0.8, 0.75, 0.65, 1.0))

			TerrainManagerClass.TerrainType.DIRT:
				if texture_cover_active and scatter_roll < 0.20:
					var scale_factor = rng.randf_range(0.4, 1.1)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					stone_transforms.append(tf)
					stone_colors.append(Color(0.75, 0.68, 0.60, 1.0))
				elif (texture_cover_active and scatter_roll >= 0.98) or not texture_cover_active:
					if not texture_cover_active and scatter_roll < 0.50:
						var scale_factor = rng.randf_range(0.4, 1.1)
						var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
						stone_transforms.append(tf)
						stone_colors.append(Color(0.75, 0.68, 0.60, 1.0))
					elif not texture_cover_active and scatter_roll < 0.98:
						var scale_factor = rng.randf_range(0.5, 0.9)
						var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
						grass_transforms.append(tf)
						grass_colors.append(Color(rng.randf_range(0.55, 1.18), rng.randf_range(0.64, 1.14), rng.randf_range(0.42, 0.88), 1.0))
					else: # Distinctive mushrooms remain individual models.
						var scale_factor = rng.randf_range(0.5, 1.4)
						var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
						mushroom_transforms.append(tf)
						var cap_col = _get_model_instance_color("mushrooms", rng, Color(0.44, 0.27, 0.16, 1.0))
						mushroom_colors.append(cap_col)

			TerrainManagerClass.TerrainType.SAND:
				if (not texture_cover_active and scatter_roll < 0.40) or (texture_cover_active and scatter_roll < 0.15):
					var scale_factor = rng.randf_range(0.35, 0.85)
					var tf = Transform3D(instance_basis.scaled(Vector3.ONE * scale_factor), pos)
					stone_transforms.append(tf)
					stone_colors.append(Color(0.9, 0.85, 0.75, 1.0))

	# Populate MultiMeshes
	_add_multimesh_to_chunk(chunk_root, "Grass", grass_mesh, grass_mat, grass_transforms, grass_colors)
	_add_multimesh_to_chunk(chunk_root, "Flowers", flower_mesh, flower_mat, flower_transforms, flower_colors, flower_petal_angles)
	_add_multimesh_to_chunk(chunk_root, "Stones", stone_mesh, stone_mat, stone_transforms, stone_colors)
	_add_multimesh_to_chunk(chunk_root, "Crops", crop_mesh, crop_mat, crop_transforms, crop_colors)
	_add_multimesh_to_chunk(chunk_root, "Shrubs", shrub_mesh, shrub_mat, shrub_transforms, shrub_colors)
	_add_multimesh_to_chunk(chunk_root, "Mushrooms", mushroom_mesh, mushroom_mat, mushroom_transforms, mushroom_colors)
	var placed_instances = grass_transforms.size() + flower_transforms.size() + stone_transforms.size() + crop_transforms.size() + shrub_transforms.size() + mushroom_transforms.size()
	chunk_root.set_meta("clutter_placed_instances", placed_instances)
	var build_ms = float(Time.get_ticks_usec() - build_started_usec) / 1000.0
	_telemetry_chunk_builds += 1
	_telemetry_chunk_build_ms_total += build_ms
	_telemetry_chunk_build_ms_max = maxf(_telemetry_chunk_build_ms_max, build_ms)

	return chunk_root

func _add_multimesh_to_chunk(
	parent: Node3D,
	item_name: String,
	mesh_res: Mesh,
	mat: Material,
	transforms: Array[Transform3D],
	colors: Array[Color],
	custom_data: Array[Color] = []
) -> void:
	if transforms.is_empty() or not mesh_res:
		return

	var mmi = MultiMeshInstance3D.new()
	mmi.name = item_name + "MultiMesh"
	mmi.material_override = mat

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = not custom_data.is_empty()
	mm.mesh = mesh_res
	mm.instance_count = transforms.size()
	mm.visible_instance_count = int(floor(float(transforms.size()) * adaptive_density_scale))
	var mesh_aabb = mesh_res.get_aabb()
	var bounds_min = Vector3(INF, INF, INF)
	var bounds_max = Vector3(-INF, -INF, -INF)

	for i in range(transforms.size()):
		var instance_transform = transforms[i]
		mm.set_instance_transform(i, instance_transform)
		if i < colors.size():
			mm.set_instance_color(i, colors[i])
		if i < custom_data.size():
			mm.set_instance_custom_data(i, custom_data[i])

		# MultiMesh's automatically inferred bounds can miss procedural geometry,
		# especially after per-instance scaling and shader wind displacement. Give
		# the renderer a conservative sphere bound for every placed mesh.
		var instance_scale = instance_transform.basis.get_scale()
		var max_scale = maxf(instance_scale.x, maxf(instance_scale.y, instance_scale.z))
		var bound_radius = mesh_aabb.size.length() * 0.5 * max_scale + 0.5
		var bound_center = instance_transform * mesh_aabb.get_center()
		var radius_vec = Vector3.ONE * bound_radius
		bounds_min = bounds_min.min(bound_center - radius_vec)
		bounds_max = bounds_max.max(bound_center + radius_vec)

	mm.custom_aabb = AABB(bounds_min, bounds_max - bounds_min)

	mmi.multimesh = mm
	parent.add_child(mmi)

func _effective_draw_distance() -> float:
	return clampf(view_radius * adaptive_draw_distance_scale, chunk_size, 1000.0)

## Apply temporary quality scales without changing the user's base slider values.
## Instance visibility is adjusted in place; only draw-distance changes rebuild the chunk set.
func set_adaptive_quality(draw_scale: float, density_scale: float) -> void:
	var next_draw = clampf(draw_scale, 0.5, 1.5)
	var next_density = clampf(density_scale, 0.5, 1.0)
	var draw_changed = not is_equal_approx(adaptive_draw_distance_scale, next_draw)
	var density_changed = not is_equal_approx(adaptive_density_scale, next_density)
	adaptive_draw_distance_scale = next_draw
	adaptive_density_scale = next_density
	if density_changed:
		for chunk in active_chunks.values():
			if not is_instance_valid(chunk):
				continue
			for node in chunk.find_children("*", "MultiMeshInstance3D", true, false):
				var mmi = node as MultiMeshInstance3D
				if mmi.multimesh:
					mmi.multimesh.visible_instance_count = int(floor(float(mmi.multimesh.instance_count) * adaptive_density_scale))
	if draw_changed:
		_update_material_world_parameters()
		last_update_pos = Vector3(99999.0, 99999.0, 99999.0)

func _clear_all_chunks() -> void:
	for node in active_chunks.values():
		if is_instance_valid(node):
			node.queue_free()
	active_chunks.clear()
	last_update_pos = Vector3(99999, 99999, 99999)
