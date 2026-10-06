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
var grassland_density_multiplier: float = 1
var farmland_density_multiplier: float = 1
var adaptive_draw_distance_scale: float = 1
var adaptive_density_scale: float = 1
var cylinder_world: CylinderGenerator
var active_chunks: Dictionary = {}
var last_update_pos := Vector3(INF, INF, INF)
var map_config: Dictionary = {}
var parts: Dictionary = {}
var parts_lod1: Dictionary = {}
var update_timer: float = 0

func _ready() -> void:
	reload_clutter()

var _texture_avg_cache: Dictionary = {}

func reload_clutter() -> void:
	_clear_all_chunks()
	_texture_avg_cache.clear()
	cylinder_world = get_tree().get_first_node_in_group("cylinder_world")
	if not cylinder_world or cylinder_world.active_map_config.is_empty():
		return
	map_config = cylinder_world.active_map_config
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

func _get_biome_texture_average_color(biome: Dictionary) -> Color:
	var tex_file: String = biome.get("texture", "")
	var tex_name: String = tex_file.get_file().to_lower()
	var b_name: String = str(biome.get("name", "")).to_lower()
	if "badlands" in tex_name or "badlands" in b_name or "sand" in tex_name or "beach" in tex_name or "dune" in tex_name or "river" in b_name or "bank" in b_name or "alluvial" in b_name or "clay" in tex_name or "water_bed" in tex_name or "waterbed" in tex_name:
		tex_file = "res://assets/textures/terrain/grass_0.png"

	var path: String = Config.resolve_map_asset_path(map_config, tex_file)
	if path.is_empty():
		return Color(0.299, 0.374, 0.110, 1.0)
	if _texture_avg_cache.has(path):
		return _texture_avg_cache[path]

	var img: Image = Assets.load_image(path)
	if not img or img.is_empty():
		_texture_avg_cache[path] = Color(0.299, 0.374, 0.110, 1.0)
		return Color(0.299, 0.374, 0.110, 1.0)

	var w: int = img.get_width()
	var h: int = img.get_height()
	var r_sum: float = 0.0
	var g_sum: float = 0.0
	var b_sum: float = 0.0
	var count: int = 0
	var step_x: int = max(1, w / 32)
	var step_y: int = max(1, h / 32)

	for y in range(0, h, step_y):
		for x in range(0, w, step_x):
			var c := img.get_pixel(x, y)
			r_sum += c.r
			g_sum += c.g
			b_sum += c.b
			count += 1

	var avg := Color(r_sum / float(count), g_sum / float(count), b_sum / float(count), 1.0) if count > 0 else Color(0.299, 0.374, 0.110, 1.0)
	_texture_avg_cache[path] = avg
	return avg

func _collect_parts(node: Node, parent: Transform3D, definition: Dictionary, output: Array) -> void:
	var transform = parent
	if node is Node3D:
		transform *= node.transform
	if node is MeshInstance3D and node.mesh:
		var material: Material
		if definition.has("base_color"):
			var shader = ShaderMaterial.new()
			shader.shader = CLUTTER_SHADER
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
	for node in active_chunks.values():
		if is_instance_valid(node):
			node.queue_free()
	active_chunks.clear()
	last_update_pos = Vector3(INF, INF, INF)

func _update_material_world_parameters() -> void:
	for model in parts.values():
		for part in model:
			if part.material is ShaderMaterial:
				part.material.set_shader_parameter("max_distance", _effective_draw_distance())

func _process(delta: float) -> void:
	if not enabled or not cylinder_world or map_config.is_empty():
		return
	update_timer += delta
	if update_timer < 0.2:
		return
	update_timer = 0
	var position = _get_active_camera_position()
	if position.distance_squared_to(last_update_pos) >= 16:
		last_update_pos = position
		_update_active_chunks(position)

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
	return Vector3.ZERO

## Calculate cylinder coordinates (theta, z) from 3D world position
func _world_to_cylindrical(pos: Vector3) -> Vector2:
	var theta = atan2(pos.y, pos.x) # [-PI, PI]
	var z = pos.z                   # [-9000, 9000]
	return Vector2(theta, z)

## Update chunks around camera
func _update_active_chunks(cam_pos: Vector3) -> void:
	var cyl_r = cylinder_world.radius
	var cyl_len = cylinder_world.cylinder_length
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

func _build_chunk(cx: int, cz: int, _num_chunks_x: int, radius_m: float, length_m: float) -> Node3D:
	var root = Node3D.new()
	root.set_process(false)
	root.set_physics_process(false)
	var rng = RandomNumberGenerator.new()
	rng.seed = int(map_config.ground_clutter.seed) ^ (cx * 73856093) ^ (cz * 19349663)
	var tm = cylinder_world.terrain_manager
	var total = 0

	var active_parts_dict: Dictionary = parts

	# Aggregated MultiMesh batching table to combine identical (mesh, material) pairs across biomes & rules in chunk
	var batch_table: Array[Dictionary] = []

	for biome in map_config.biomes.values():
		var tex_avg := _get_biome_texture_average_color(biome)
		for rule in biome.clutter:
			if not active_parts_dict.has(rule.model):
				continue
			var model_name: String = str(rule.model).to_lower()
			var is_foliage: bool = ("grass" in model_name) or ("shrub" in model_name) or ("bush" in model_name) or ("fern" in model_name) or ("reed" in model_name)
			var expected: float = rule.density_per_m2 * chunk_size * chunk_size * density_multiplier
			var count = int(expected) + int(rng.randf() < fposmod(expected, 1))
			var transforms: Array[Transform3D] = []
			var colors: Array[Color] = []
			for i in count:
				var arc = (cx + rng.randf()) * chunk_size
				if arc >= TAU * radius_m:
					continue
				var theta = arc / radius_m - PI
				var z = (cz + rng.randf()) * chunk_size - length_m * 0.5
				if z > length_m * 0.5 or tm.get_biome_id(theta, z, length_m) != int(biome.raster_id):
					continue
				var point = cylinder_world.get_surface_mesh_point_and_normal(theta, z)
				if point.is_empty():
					continue
				var up: Vector3 = point.normal
				var radial = Vector3(-cos(theta), -sin(theta), 0)
				if rad_to_deg(acos(clampf(up.dot(radial), -1, 1))) > biome.max_slope_deg:
					continue
				var forward = Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
				var right = up.cross(forward).normalized()
				var basis = Basis(right, up, right.cross(up)).orthonormalized().rotated(up, rng.randf() * TAU)
				var scale_value = rng.randf_range(rule.scale_range[0], rule.scale_range[1])
				transforms.append(Transform3D(basis.scaled(Vector3.ONE * scale_value), point.position))

				var b_tint: Color = Config.color(biome.tint)
				var final_col: Color
				if is_foliage:
					var var_brightness := rng.randf_range(0.90, 1.10)
					var var_r := rng.randf_range(0.95, 1.05) * var_brightness
					var var_g := rng.randf_range(0.95, 1.05) * var_brightness
					var var_b := rng.randf_range(0.95, 1.05) * var_brightness
					if ("shrub" in model_name) or ("bush" in model_name):
						var_g *= 1.18
						var_r *= 0.92
						var_b *= 0.92
					final_col = Color(
						clampf(tex_avg.r * b_tint.r * var_r, 0.0, 1.0),
						clampf(tex_avg.g * b_tint.g * var_g, 0.0, 1.0),
						clampf(tex_avg.b * b_tint.b * var_b, 0.0, 1.0),
						1.0
					)
				else:
					var pal_col: Color = Config.palette_color(rule.palette, rng.randf())
					if ("rock" in model_name) or ("pebble" in model_name) or ("stone" in model_name):
						if rng.randf() < 0.35:
							pal_col = Color("#FFAA66")
						else:
							pal_col = Color(0.40, 0.44, 0.50, pal_col.a)
					var var_r := rng.randf_range(0.95, 1.05)
					var var_g := rng.randf_range(0.95, 1.05)
					var var_b := rng.randf_range(0.95, 1.05)
					final_col = Color(
						clampf(pal_col.r * b_tint.r * var_r, 0.0, 1.0),
						clampf(pal_col.g * b_tint.g * var_g, 0.0, 1.0),
						clampf(pal_col.b * b_tint.b * var_b, 0.0, 1.0),
						pal_col.a
					)
				colors.append(final_col)

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

	for entry in batch_table:
		_add_multimesh_to_chunk(root, entry.item_name, entry.mesh, entry.material, entry.transforms, entry.colors, entry.colors)

	root.set_meta("clutter_placed_instances", total)
	return root

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

	# Distance culling & subpixel culling thresholds on MultiMeshInstance3D
	var max_dist := _effective_draw_distance()
	var item_lower := item_name.to_lower()
	if "grass" in item_lower or "flower" in item_lower or "mushroom" in item_lower or "pebble" in item_lower:
		max_dist = minf(max_dist, 110.0)
	elif "shrub" in item_lower or "rock" in item_lower or "crop" in item_lower:
		max_dist = minf(max_dist, 220.0)

	mmi.visibility_range_end = max_dist
	mmi.visibility_range_end_margin = 20.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

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
