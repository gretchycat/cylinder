@tool
class_name ClutterManager
extends Node3D

const Config = preload("res://scripts/map_config.gd")
const Assets = preload("res://scripts/map_asset_loader.gd")
const CLUTTER_SHADER = preload("res://assets/shaders/ground_clutter.gdshader")
@export var enabled: bool = true
@export var performance_telemetry_enabled: bool = false
@export var view_radius: float = 0
@export var fade_distance: float = 0
@export var chunk_size: float = 1
@export var density_multiplier: float = 1
var adaptive_draw_distance_scale: float = 1
var adaptive_density_scale: float = 1
var cylinder_world: CylinderGenerator
var active_chunks: Dictionary = {}
var pending_chunk_tasks: Dictionary = {}
var pending_chunk_results: Dictionary = {}
var _results_mutex: Mutex = Mutex.new()
var needed_chunks_cache: Dictionary = {}
var last_update_pos := Vector3(INF, INF, INF)
var last_cam_pos := Vector3(INF, INF, INF)
var cam_velocity: float = 0.0
var map_config: Dictionary = {}
var all_biomes_by_raster_id: Dictionary = {}
var parts: Dictionary = {}
var parts_lod1: Dictionary = {}
var update_timer: float = 0

func _ready() -> void:
	add_to_group("clutter_manager")
	reload_clutter()

func reload_clutter() -> void:
	_clear_all_chunks()
	cylinder_world = get_tree().get_first_node_in_group("cylinder_world")
	if not cylinder_world or cylinder_world.active_map_config.is_empty():
		return
	map_config = cylinder_world.active_map_config
	_build_biome_registry()
	view_radius = map_config.ground_clutter.view_radius_m
	fade_distance = map_config.ground_clutter.fade_distance_m
	chunk_size = map_config.ground_clutter.chunk_size_m
	density_multiplier = map_config.ground_clutter.density_multiplier
	parts.clear()
	parts_lod1.clear()
	for id in map_config.ground_clutter.models:
		var definition: Dictionary = map_config.ground_clutter.models[id]
		var instance = Assets.instantiate_model(Config.resolve_map_asset_path(map_config, definition.scene_path))
		if not instance:
			continue
		if instance.has_method("build_mesh"):
			instance.mesh = instance.call("build_mesh", 0)
		var model_parts: Array = []
		_collect_parts(instance, Transform3D.IDENTITY, definition, model_parts)
		parts[id] = model_parts

		var model_parts_l1: Array = []
		if instance.has_method("build_mesh"):
			instance.mesh = instance.call("build_mesh", 1)
		_collect_parts(instance, Transform3D.IDENTITY, definition, model_parts_l1)
		parts_lod1[id] = model_parts_l1
		instance.free()

func _build_biome_registry() -> void:
	# A map's biome descriptors are authoritative, including empty clutter lists.
	# Do not fill missing IDs from unrelated global biome files.
	all_biomes_by_raster_id.clear()
	if map_config.has("biomes") and map_config.biomes is Dictionary:
		for b_key in map_config.biomes:
			var b = map_config.biomes[b_key]
			if b is Dictionary and b.has("raster_id"):
				all_biomes_by_raster_id[int(b.raster_id)] = b

func _collect_parts(node: Node, parent: Transform3D, definition: Dictionary, output: Array) -> void:
	var transform = parent
	if node is Node3D:
		transform *= node.transform
	if node is MeshInstance3D and node.mesh:
		var material: Material
		if definition.has("base_color"):
			var shader = ShaderMaterial.new()
			shader.shader = CLUTTER_SHADER
			# Procedural assets may carry an atlas on their source material.
			var source_material: Material = node.get_active_material(0)
			if source_material is BaseMaterial3D and source_material.albedo_texture:
				shader.set_shader_parameter("albedo_texture", source_material.albedo_texture)
			preload("res://scripts/map_runtime.gd").shader_parameters(shader, map_config)
			for key in ["base_color", "tip_color"]:
				if definition.has(key):
					shader.set_shader_parameter(key, Config.color(definition[key]))
			for key in ["wind_speed", "wind_strength", "roughness", "metallic"]:
				if definition.has(key):
					shader.set_shader_parameter(key, definition[key])
			if definition.has("gradient_mode"):
				var mode_map = {"none": 0, "linear": 1, "radial": 2}
				shader.set_shader_parameter("gradient_mode", mode_map.get(definition.gradient_mode, 0))
			if definition.has("gradient_extent_m"):
				shader.set_shader_parameter("gradient_extent", definition.gradient_extent_m)
			shader.set_shader_parameter("max_distance", view_radius)
			shader.set_shader_parameter("fade_distance", fade_distance)
			shader.set_shader_parameter("air_color", cylinder_world.air_color)
			shader.set_shader_parameter("air_density", cylinder_world.air_density)
			shader.set_shader_parameter("air_distance_min", cylinder_world.air_distance_min)
			shader.set_shader_parameter("air_distance_max", cylinder_world.air_distance_max)
			shader.set_shader_parameter("cylinder_radius", cylinder_world.radius)
			shader.set_shader_parameter("cylinder_length", cylinder_world.cylinder_length)
			shader.set_shader_parameter("water_level", cylinder_world.water_level)
			shader.set_shader_parameter("deep_water_color", Config.color(map_config.environment.water.deep_color))
			material = shader
		var mesh = node.mesh.duplicate() as Mesh
		# Imported models retain every surface and its material. Instance COLOR
		# multiplies those materials, including alpha.
		if material == null:
			for i in mesh.get_surface_count():
				var source = node.get_active_material(i)
				if source == null or source is BaseMaterial3D:
					var copy = source.duplicate() as BaseMaterial3D if source else StandardMaterial3D.new()
					copy.vertex_color_use_as_albedo = true
					copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
					mesh.surface_set_material(i, copy)
		output.append({"mesh": mesh, "transform": transform, "material": material})
	for child in node.get_children():
		_collect_parts(child, transform, definition, output)

func _clear_all_chunks() -> void:
	flush_pending_chunk_tasks()
	for node in active_chunks.values():
		if is_instance_valid(node):
			node.queue_free()
	active_chunks.clear()
	last_update_pos = Vector3(INF, INF, INF)
	last_cam_pos = Vector3(INF, INF, INF)

func _update_material_world_parameters() -> void:
	if not cylinder_world:
		return
	for model in parts.values():
		for part in model:
			if part.material is ShaderMaterial:
				part.material.set_shader_parameter("max_distance", _effective_draw_distance())
				part.material.set_shader_parameter("air_color", cylinder_world.air_color)
				part.material.set_shader_parameter("air_density", cylinder_world.air_density)
				part.material.set_shader_parameter("air_distance_min", cylinder_world.air_distance_min)
				part.material.set_shader_parameter("air_distance_max", cylinder_world.air_distance_max)
				part.material.set_shader_parameter("cylinder_length", cylinder_world.cylinder_length)

func update_lut(texture: Texture2D, bar_len: float) -> void:
	for model in parts.values():
		for part in model:
			if part.material is ShaderMaterial:
				part.material.set_shader_parameter("axial_light_lut", texture)
				part.material.set_shader_parameter("cylinder_length", bar_len)

func _process(delta: float) -> void:
	_poll_pending_chunk_tasks()
	if not enabled or not cylinder_world or map_config.is_empty():
		return
	update_timer += delta
	if update_timer < 0.15:
		return
	var dt = update_timer
	update_timer = 0.0
	var cam_info := _get_camera_transform_info()
	var position: Vector3 = cam_info.position

	if last_cam_pos.x != INF:
		cam_velocity = (position - last_cam_pos).length() / maxf(dt, 0.001)
	last_cam_pos = position

	var needs_recheck: bool = _has_missing_needed_chunks()
	if position.distance_squared_to(last_update_pos) >= 16.0 or needs_recheck:
		last_update_pos = position
		_update_active_chunks(cam_info)

func _has_missing_needed_chunks() -> bool:
	# Count only coverage of the current set; stale chunks and a task/result
	# pair for the same key must not hide an unscheduled nearby chunk.
	_results_mutex.lock()
	var missing: bool = false
	for key: Vector2i in needed_chunks_cache:
		if not active_chunks.has(key) and not pending_chunk_tasks.has(key) and not pending_chunk_results.has(key):
			missing = true
			break
	_results_mutex.unlock()
	return missing

func _exit_tree() -> void:
	flush_pending_chunk_tasks()

func _async_chunk_worker(key: Vector2i, params: Dictionary) -> void:
	var res = _compute_chunk_data(params.cx, params.cz, params.num_chunks_x, params.radius_m, params.length_m)
	_results_mutex.lock()
	pending_chunk_results[key] = res
	_results_mutex.unlock()

func flush_pending_chunk_tasks() -> void:
	var keys_to_flush = pending_chunk_tasks.keys().duplicate()
	for key in keys_to_flush:
		var task_id: int = pending_chunk_tasks.get(key, -1)
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)
		pending_chunk_tasks.erase(key)

	_results_mutex.lock()
	var copy_results = pending_chunk_results.duplicate()
	pending_chunk_results.clear()
	_results_mutex.unlock()

	for key in copy_results.keys():
		var res: Dictionary = copy_results[key]
		if not res.is_empty() and needed_chunks_cache.has(key) and not active_chunks.has(key):
			var chunk_node = _assemble_chunk_from_data(res)
			if chunk_node:
				add_child(chunk_node)
				active_chunks[key] = chunk_node

func _get_camera_transform_info() -> Dictionary:
	var vp := get_viewport()
	if vp:
		var cam := vp.get_camera_3d()
		if cam:
			return {
				"position": cam.global_position,
				"forward": -cam.global_transform.basis.z.normalized()
			}
	var player := get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	if player:
		return {
			"position": player.global_position,
			"forward": -player.global_transform.basis.z.normalized()
		}
	return {"position": Vector3.ZERO, "forward": Vector3.FORWARD}

func _evaluate_chunk_priority(cx: int, cz: int, num_chunks_x: int, radius_m: float, length_m: float, cam_pos: Vector3, cam_fwd: Vector3) -> Dictionary:
	var circ := TAU * radius_m
	var u_m := (float(cx) + 0.5) * chunk_size
	var theta := (u_m / radius_m) - PI
	var z_m := (float(cz) + 0.5) * chunk_size - length_m * 0.5
	var chunk_center := Vector3((radius_m - 10.0) * cos(theta), (radius_m - 10.0) * sin(theta), z_m)
	var offset := chunk_center - cam_pos
	var dist := offset.length()
	var dir := offset / dist if dist > 0.001 else Vector3.FORWARD
	var dot_fwd := cam_fwd.dot(dir)
	var is_behind := (dot_fwd < -0.20 and dist > chunk_size * 1.5)
	# Favor nearby ground first; facing only breaks ties within a small distance.
	var score := dist - (chunk_size * 0.25 * maxf(0.0, dot_fwd))
	return {
		"distance": dist,
		"dot_fwd": dot_fwd,
		"is_behind": is_behind,
		"score": score
	}

func _poll_pending_chunk_tasks() -> void:
	var completed_keys: Array[Vector2i] = []
	for key in pending_chunk_tasks.keys():
		var task_id: int = pending_chunk_tasks[key]
		if WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
			completed_keys.append(key)

	for key in completed_keys:
		pending_chunk_tasks.erase(key)

	_results_mutex.lock()
	if pending_chunk_results.is_empty():
		_results_mutex.unlock()
		return

	var is_headless: bool = (DisplayServer.get_name() == "headless")
	var ready_keys: Array[Vector2i] = []
	var keys_to_prune: Array[Vector2i] = []
	for key in pending_chunk_results.keys():
		if needed_chunks_cache.has(key) and not active_chunks.has(key):
			ready_keys.append(key)
		elif not needed_chunks_cache.has(key):
			keys_to_prune.append(key)

	for key in keys_to_prune:
		pending_chunk_results.erase(key)
	_results_mutex.unlock()

	if ready_keys.is_empty():
		return

	if not is_headless and cylinder_world:
		var cam_info := _get_camera_transform_info()
		var cyl_r := cylinder_world.radius
		var cyl_len := cylinder_world.cylinder_length
		var num_chunks_x := int(ceil((TAU * cyl_r) / chunk_size))
		var prio_scores: Dictionary = {}
		for key in ready_keys:
			prio_scores[key] = float(_evaluate_chunk_priority(key.x, key.y, num_chunks_x, cyl_r, cyl_len, cam_info.position, cam_info.forward).score)
		ready_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return float(prio_scores.get(a, 0.0)) < float(prio_scores.get(b, 0.0))
		)

	var frame_t0 := Time.get_ticks_usec()
	var time_budget_us := 999999999 if is_headless else 2500

	for key in ready_keys:
		_results_mutex.lock()
		var res: Dictionary = pending_chunk_results.get(key, {})
		pending_chunk_results.erase(key)
		_results_mutex.unlock()

		if not res.is_empty() and needed_chunks_cache.has(key) and not active_chunks.has(key):
			var chunk_node = _assemble_chunk_from_data(res)
			if chunk_node:
				add_child(chunk_node)
				active_chunks[key] = chunk_node

		if not is_headless and (Time.get_ticks_usec() - frame_t0) >= time_budget_us:
			break

func _get_active_camera_position() -> Vector3:
	return _get_camera_transform_info().position

func _world_to_cylindrical(pos: Vector3) -> Vector2:
	var theta = atan2(pos.y, pos.x)
	var z = pos.z
	return Vector2(theta, z)

func _update_active_chunks(cam_info_arg: Variant = null) -> void:
	var cam_info: Dictionary = cam_info_arg if cam_info_arg is Dictionary else _get_camera_transform_info()
	var cam_pos: Vector3 = cam_info.get("position", Vector3.ZERO)
	var cam_fwd: Vector3 = cam_info.get("forward", Vector3.FORWARD)

	var cyl_r = cylinder_world.radius
	var cyl_len = cylinder_world.cylinder_length
	var circ = TAU * cyl_r

	var cyl_coords = _world_to_cylindrical(cam_pos)
	var cam_theta = cyl_coords.x
	var cam_z = cyl_coords.y

	var cam_u_m = fposmod(cam_theta + PI, TAU) * cyl_r
	var cam_z_m = cam_z + cyl_len * 0.5

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

	var is_headless: bool = (DisplayServer.get_name() == "headless")
	var unplaced_candidates: Array[Dictionary] = []

	for dz in range(-chunk_radius, chunk_radius + 1):
		var cz = center_chunk_z + dz
		if cz < 0 or cz >= num_chunks_z:
			continue

		for dx in range(-chunk_radius, chunk_radius + 1):
			var chunk_offset_x = float(dx) * chunk_size - camera_chunk_offset_x
			var chunk_offset_z = float(dz) * chunk_size - camera_chunk_offset_z
			var nearest_x = maxf(maxf(chunk_offset_x, -(chunk_offset_x + chunk_size)), 0.0)
			var nearest_z = maxf(maxf(chunk_offset_z, -(chunk_offset_z + chunk_size)), 0.0)
			if nearest_x * nearest_x + nearest_z * nearest_z > clutter_radius_squared:
				continue
			var cx = posmod(center_chunk_x + dx, num_chunks_x)
			var key = Vector2i(cx, cz)
			needed_chunks[key] = true

			_results_mutex.lock()
			var has_res = pending_chunk_results.has(key)
			_results_mutex.unlock()

			if not active_chunks.has(key) and not pending_chunk_tasks.has(key) and not has_res:
				var prio := _evaluate_chunk_priority(cx, cz, num_chunks_x, cyl_r, cyl_len, cam_pos, cam_fwd)
				unplaced_candidates.append({"key": key, "cx": cx, "cz": cz, "prio": prio})

	needed_chunks_cache = needed_chunks

	unplaced_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.prio.score) < float(b.prio.score)
	)

	const MAX_PENDING_TASKS := 6

	var max_dispatch_per_tick: int = 999999 if is_headless else (1 if cam_velocity > 20.0 else 3)
	var dispatched: int = 0
	for item in unplaced_candidates:
		if not is_headless and (dispatched >= max_dispatch_per_tick or pending_chunk_tasks.size() >= MAX_PENDING_TASKS):
			break

		var key: Vector2i = item.key
		var task_params = {
			"cx": item.cx,
			"cz": item.cz,
			"num_chunks_x": num_chunks_x,
			"radius_m": cyl_r,
			"length_m": cyl_len
		}
		var task_id = WorkerThreadPool.add_task(Callable(self, "_async_chunk_worker").bind(key, task_params))
		pending_chunk_tasks[key] = task_id
		dispatched += 1

	if is_headless:
		flush_pending_chunk_tasks()

	var to_remove: Array[Vector2i] = []
	for key in active_chunks.keys():
		if not needed_chunks.has(key):
			to_remove.append(key)

	for key in to_remove:
		var node = active_chunks[key]
		if is_instance_valid(node):
			node.queue_free()
		active_chunks.erase(key)

func _build_chunk(cx: int, cz: int, num_chunks_x: int, radius_m: float, length_m: float) -> Node3D:
	var data = _compute_chunk_data(cx, cz, num_chunks_x, radius_m, length_m)
	return _assemble_chunk_from_data(data)

func _assemble_chunk_from_data(data: Dictionary) -> Node3D:
	if data.is_empty():
		return null
	var root = Node3D.new()
	root.set_process(false)
	root.set_physics_process(false)
	var batch_table: Array = data.get("batch_table", [])
	var total: int = data.get("total", 0)

	for entry in batch_table:
		if entry is Dictionary and entry.has("mesh") and entry.mesh != null:
			_add_multimesh_to_chunk(root, entry.get("item_name", "Clutter"), entry.mesh, entry.get("material", null), entry.get("transforms", []), entry.get("colors", []), entry.get("colors", []))

	root.set_meta("clutter_placed_instances", total)
	return root

func _compute_chunk_data(cx: int, cz: int, _num_chunks_x: int, radius_m: float, length_m: float) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = int(map_config.ground_clutter.seed) ^ (cx * 73856093) ^ (cz * 19349663)
	var tm = cylinder_world.terrain_manager
	var total = 0

	var active_parts_dict: Dictionary = parts
	var batch_table: Array[Dictionary] = []
	var chunk_area: float = chunk_size * chunk_size

	var present_biome_ids: Dictionary = {}
	for sample_z in range(0, 5):
		var z_m = (cz + float(sample_z) / 4.0) * chunk_size - length_m * 0.5
		for sample_x in range(0, 5):
			var u_m = (cx + float(sample_x) / 4.0) * chunk_size
			var theta_s = u_m / radius_m - PI
			var r_id = tm.get_biome_id(theta_s, z_m, length_m)
			if all_biomes_by_raster_id.has(r_id):
				present_biome_ids[r_id] = true

	if present_biome_ids.is_empty():
		var center_u = (cx + 0.5) * chunk_size
		var center_z = (cz + 0.5) * chunk_size - length_m * 0.5
		var center_r_id = tm.get_biome_id(center_u / radius_m - PI, center_z, length_m)
		if all_biomes_by_raster_id.has(center_r_id):
			present_biome_ids[center_r_id] = true

	for r_id in present_biome_ids.keys():
		var biome: Dictionary = all_biomes_by_raster_id.get(r_id, {})
		var rules: Array = biome.get("clutter", [])

		for rule_var in rules:
			var rule: Dictionary = rule_var if rule_var is Dictionary else {}
			if rule.is_empty() or not rule.has("model") or not active_parts_dict.has(rule.model):
				continue

			var base_density: float = float(rule.get("density_per_m2", 0.0))
			var expected: float = base_density * chunk_area * density_multiplier
			var count: int = int(expected) + int(rng.randf() < fposmod(expected, 1.0))

			var transforms: Array[Transform3D] = []
			var colors: Array[Color] = []

			for i in range(count):
				var arc = (cx + rng.randf()) * chunk_size
				if arc >= TAU * radius_m:
					continue
				var theta = arc / radius_m - PI
				var z = (cz + rng.randf()) * chunk_size - length_m * 0.5
				if z > length_m * 0.5 or z < -length_m * 0.5:
					continue

				var sampled_r_id = tm.get_biome_id(theta, z, length_m)
				if sampled_r_id != r_id:
					continue

				var point = cylinder_world.get_surface_mesh_point_and_normal(theta, z)
				if point.is_empty():
					continue

				if (point.get("elevation", 0.0) < cylinder_world.water_level) != bool(biome.get("submerged", false)):
					continue

				var up: Vector3 = point.normal
				var radial = Vector3(-cos(theta), -sin(theta), 0)
				var max_slope: float = float(biome.get("max_slope_deg", 45.0))
				if rad_to_deg(acos(clampf(up.dot(radial), -1, 1))) > max_slope:
					continue

				var forward = Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
				var right = up.cross(forward).normalized()
				var basis = Basis(right, up, right.cross(up)).orthonormalized().rotated(up, rng.randf() * TAU)

				var scale_range: Array = rule.get("scale_range", [0.7, 1.2])
				# The procedural woodland bush is authored at its 1x native size.
				# Keep every ground-clutter bush in the full native-to-large range,
				# even while older biome descriptors are still using the former 0.5x
				# floor.
				if str(rule.model) == "shrubs":
					scale_range = [1.0, 3.0]
				var scale_value = rng.randf_range(float(scale_range[0]), float(scale_range[1]))
				var clutter_pos = point.position - up * 0.05
				transforms.append(Transform3D(basis.scaled(Vector3.ONE * scale_value), clutter_pos))

				colors.append(Config.palette_color(rule.palette, rng.randf()))

			if not transforms.is_empty():
				var rule_parts: Array = active_parts_dict[rule.model]
				for part in rule_parts:
					var found_entry: Dictionary = {}
					for entry in batch_table:
						if entry.item_name == rule.model and entry.mesh == part.mesh and entry.material == part.material:
							found_entry = entry
							break
					if found_entry.is_empty():
						found_entry = {
							"item_name": str(rule.model),
							"mesh": part.mesh,
							"material": part.material,
							"transforms": [] as Array[Transform3D],
							"colors": [] as Array[Color]
						}
						batch_table.append(found_entry)
					for idx in transforms.size():
						found_entry.transforms.append(transforms[idx] * part.transform)
						found_entry.colors.append(colors[idx])
				total += transforms.size()

	return {
		"batch_table": batch_table,
		"total": total
	}

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
	mmi.set_process(false)
	mmi.set_physics_process(false)
	mmi.name = item_name + "MultiMesh"
	mmi.material_override = mat

	var max_dist := _effective_draw_distance()

	# Extra cull margin to prevent camera panning / rotational frustum clipping
	mmi.extra_cull_margin = float(mesh_res.get_meta("extra_cull_margin_m", 150.0))

	# Set visibility_range_end to match _effective_draw_distance() for full draw radius coverage
	mmi.visibility_range_end = max_dist
	mmi.visibility_range_end_margin = 50.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = not custom_data.is_empty()
	mm.mesh = mesh_res
	mm.instance_count = transforms.size()
	mm.visible_instance_count = int(floor(float(transforms.size()) * adaptive_density_scale))
	var custom_palette_only: bool = bool(mesh_res.get_meta("palette_in_custom_data", false)) and mat is ShaderMaterial and mat.shader == CLUTTER_SHADER and not custom_data.is_empty()
	var mesh_aabb = mesh_res.get_aabb()
	var bounds_min = Vector3(INF, INF, INF)
	var bounds_max = Vector3(-INF, -INF, -INF)

	for i in range(transforms.size()):
		var instance_transform = transforms[i]
		mm.set_instance_transform(i, instance_transform)
		if i < colors.size():
			mm.set_instance_color(i, Color.WHITE if custom_palette_only else colors[i])
		if i < custom_data.size():
			mm.set_instance_custom_data(i, custom_data[i])

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
