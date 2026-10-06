class_name WorldEditor
extends Node

const REACH: float = 5000.0
const BASE_PAINT_DISTANCE: float = 500.0
const Storage = preload("res://scripts/world_edit_storage.gd")
const Config = preload("res://scripts/map_config.gd")

enum SubMode {
	OBJECT,
	PAINTER,
	ELEVATION
}

var sub_mode: SubMode = SubMode.OBJECT
var brush_radius_m: float = 10.0
var elevation_step_m: float = 5.0
var selected_biome_id: int = 0
var enabled := false
var player: PlayerController
var catalog: Array[Dictionary] = []
var texture_catalog: Array[Dictionary] = []
var selected_index := 0
var selected_texture_index := 0
var status := "Aim at a surface to edit"

func _ready() -> void:
	reload_catalog()
	reload_texture_catalog()

func reload_catalog() -> void:
	catalog.clear()
	selected_index = 0
	var references = get_tree().get_first_node_in_group("reference_objects")
	var config: Dictionary = references.active_map_config if references else Config.load_map_config(Config.active_map())
	if config.is_empty():
		return
	for id in config.objects.model_catalog:
		var item: Dictionary = config.objects.model_catalog[id].duplicate(true)
		item["id"] = id
		item["path"] = Config.resolve_map_asset_path(config, item.scene_path)
		item["type"] = int(item.behavior_type)
		catalog.append(item)

func reload_texture_catalog() -> void:
	texture_catalog.clear()
	selected_texture_index = 0
	var references = get_tree().get_first_node_in_group("reference_objects")
	var config: Dictionary = references.active_map_config if references else Config.load_map_config(Config.active_map())
	if config.is_empty():
		return

	var known_paths: Dictionary = {}
	var known_basenames: Dictionary = {}
	var max_id: int = -1

	for key in config.biomes:
		var biome: Dictionary = config.biomes[key].duplicate(true)
		biome["key"] = key
		var r_id := int(biome.raster_id)
		biome["id"] = r_id
		if r_id > max_id:
			max_id = r_id
		var path := Config.resolve_map_asset_path(config, biome.get("texture", ""))
		biome["path"] = path
		biome["name"] = str(biome.get("name", key.capitalize()))
		biome["rotate"] = bool(biome.get("rotate", biome.get("blended", true)))
		texture_catalog.append(biome)
		known_paths[path] = true
		known_basenames[path.get_file()] = true

	# Scan assets/textures/terrain and textures/imported for all available ground textures
	var map_dir: String = config.get("map_directory", "res://assets/maps/default")
	var search_dirs: Array[String] = ["res://assets/textures/terrain", map_dir.path_join("textures/imported")]

	for dir_path in search_dirs:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		var dir := DirAccess.open(dir_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and not file_name.ends_with(".import"):
				var ext := file_name.get_extension().to_lower()
				if ext in ["png", "jpg", "jpeg", "webp"] and not file_name.begins_with("end_cap"):
					var full_path := dir_path.path_join(file_name)
					var rel_path := full_path
					if not known_paths.has(full_path) and not known_paths.has(rel_path) and not known_basenames.has(file_name):
						max_id = mini(max_id + 1, 255)
						var b_key := file_name.get_basename().validate_node_name()
						var auto_entry: Dictionary = {
							"key": b_key,
							"id": max_id,
							"raster_id": max_id,
							"path": full_path,
							"texture": full_path,
							"name": file_name.get_basename().replace("_", " ").capitalize(),
							"texture_size_m": 20.0,
							"roughness": 0.8,
							"tint": [1.0, 1.0, 1.0, 1.0],
							"blended": true,
							"rotate": true,
							"clutter_density": 0.5,
							"clutter_object_set": []
						}
						texture_catalog.append(auto_entry)
						known_paths[full_path] = true
						known_basenames[file_name] = true
			file_name = dir.get_next()

	if not texture_catalog.is_empty():
		selected_biome_id = texture_catalog[0].id

func current_object() -> Dictionary:
	return catalog[selected_index] if selected_index >= 0 and selected_index < catalog.size() else {}

func current_texture() -> Dictionary:
	return texture_catalog[selected_texture_index] if selected_texture_index >= 0 and selected_texture_index < texture_catalog.size() else {}

func ray_hit() -> Dictionary:
	if not player or not player.camera:
		return {}
	var camera := player.camera
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * REACH)
	query.exclude = [player.get_rid()]
	query.hit_back_faces = true
	return player.get_world_3d().direct_space_state.intersect_ray(query)

func target_object(hit: Dictionary) -> SurfaceLightObject:
	if not player or not player.camera:
		return null
	var origin := player.camera.global_position
	var direction := -player.camera.global_basis.z
	var max_distance := REACH
	var nearest: SurfaceLightObject = null
	if not hit.is_empty():
		max_distance = origin.distance_to(hit.position) + 0.05
		var ancestor: Node = hit.collider
		while ancestor:
			if ancestor is SurfaceLightObject:
				nearest = ancestor
				break
			ancestor = ancestor.get_parent()
	for object in get_tree().get_nodes_in_group("surface_light_objects"):
		if not object is SurfaceLightObject or object.is_queued_for_deletion():
			continue
		for node in object.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if not mesh.mesh or not mesh.is_visible_in_tree():
				continue
			var inverse := mesh.global_transform.affine_inverse()
			var local_hit: Variant = mesh.get_aabb().intersects_ray(inverse * origin, inverse.basis * direction)
			if local_hit == null:
				continue
			var world_hit: Vector3 = mesh.global_transform * local_hit
			var distance := (world_hit - origin).dot(direction)
			if distance >= 0.0 and distance < max_distance:
				max_distance = distance
				nearest = object
	return nearest

func place() -> SurfaceLightObject:
	if not enabled or catalog.is_empty():
		return null
	var hit := ray_hit()
	if hit.is_empty():
		status = "Aim at a surface within %d m" % int(REACH)
		return null
	var references = get_tree().get_first_node_in_group("reference_objects")
	if not references:
		status = "No object layer available"
		return null
	var normal: Vector3 = hit.normal
	if normal.is_zero_approx():
		status = "Aim at the outside of a surface"
		return null
	if normal.dot(player.camera.global_position - hit.position) < 0.0:
		normal = -normal
	var entry := current_object()
	var position: Vector3 = hit.position + normal * 0.03
	var player_fwd: Vector3 = -player.global_basis.z if player else Vector3.ZERO
	var object := SurfaceLightObject.create_on_cylinder(
		entry.type as SurfaceLightObject.ObjectType, atan2(position.y, position.x), position.z,
		references.active_map_config.geometry.cylinder_radius_m, 0.0, Config.color(entry.light_color), float(entry.light_range_m),
		0.0, normal, position, entry.variant, entry.path, player_fwd)
	object.asset_id = entry.id
	object.instance_id = "object_%d" % Time.get_ticks_usec()
	object.tint = Config.color(entry.tint)
	object.light_color = Config.color(entry.light_color)
	object.light_energy = float(entry.light_energy)
	var color: Array = entry.get("light_color", [])
	if color.size() >= 3:
		object.light_color = Config.color(color)
	object.enable_flicker = bool(entry.get("flicker", true))
	object.name = str(entry.get("name", "Object")).replace(" ", "")
	references.add_child(object)
	object.global_transform = Transform3D(object.basis, position)
	status = "Placed %s · Unsaved" % entry.get("name", "object")
	return object

func remove() -> bool:
	if not enabled:
		return false
	var object := target_object(ray_hit())
	if not object:
		status = "Aim at an object within %d m to remove it" % int(REACH)
		return false
	status = "Removed %s · Unsaved" % object.name
	object.queue_free()
	return true

func paint_terrain(hit: Dictionary = {}) -> bool:
	if not enabled:
		return false
	if hit.is_empty():
		hit = ray_hit()
	if hit.is_empty():
		status = "Aim at terrain within %d m to paint" % int(REACH)
		return false
	var world = get_tree().get_first_node_in_group("cylinder_world")
	if not world or not world.terrain_manager:
		status = "Terrain layer unavailable"
		return false
	var tm: TerrainManager = world.terrain_manager
	var radius_m: float = world.radius
	var length_m: float = world.cylinder_length
	var pos: Vector3 = hit.position
	var hit_theta: float = atan2(pos.y, pos.x)
	var hit_z: float = pos.z

	var grid_u: int = tm.terrain_grid_u
	var grid_v: int = tm.terrain_grid_v
	if grid_u <= 0 or grid_v <= 0 or tm.terrain_data.is_empty():
		return false

	var half_cell_w: float = (TAU / float(maxi(grid_u, 1)) * radius_m) * 0.5
	var half_cell_h: float = (length_m / float(maxi(grid_v - 1, 1))) * 0.5
	var effective_radius: float = brush_radius_m
	if player and player.camera:
		var dist: float = player.camera.global_position.distance_to(pos)
		effective_radius = brush_radius_m * (dist / BASE_PAINT_DISTANCE)
	var brush_r_sq: float = effective_radius * effective_radius
	var count_modified: int = 0
	for y in range(grid_v):
		var v_norm: float = float(y) / float(maxi(grid_v - 1, 1))
		var z: float = (v_norm - 0.5) * length_m
		var dz: float = absf(z - hit_z)
		if dz > effective_radius + half_cell_h:
			continue
		for x in range(grid_u):
			var u_norm: float = float(x) / float(grid_u)
			var theta: float = u_norm * TAU
			var d_theta: float = absf(fposmod(theta - hit_theta + PI, TAU) - PI)
			var dx_m: float = d_theta * radius_m
			var min_dx: float = maxf(0.0, dx_m - half_cell_w)
			var min_dz: float = maxf(0.0, dz - half_cell_h)
			if (min_dx * min_dx + min_dz * min_dz) <= brush_r_sq:
				var idx: int = y * grid_u + x
				if tm.terrain_data[idx] != selected_biome_id:
					tm.terrain_data[idx] = selected_biome_id
					count_modified += 1

	if count_modified > 0:
		var texture_entry := current_texture()
		if not texture_entry.is_empty():
			var b_key: String = str(texture_entry.get("key", ""))
			var references = get_tree().get_first_node_in_group("reference_objects")
			var config: Dictionary = references.active_map_config if references else Config.load_map_config(Config.active_map())
			if not config.is_empty() and not b_key.is_empty() and not config.biomes.has(b_key):
				config.biomes[b_key] = texture_entry.duplicate(true)
				Config.save_document(config, config.map_directory)
				if world and world.has_method("_update_terrain_material_textures"):
					world._update_terrain_material_textures()
		if "surface_material" in world and world.surface_material is ShaderMaterial:
			world.surface_material.set_shader_parameter("terrain_map", ImageTexture.create_from_image(tm.create_terrain_type_id_image()))
		var clutter = get_tree().get_first_node_in_group("clutter_manager")
		if clutter and clutter.has_method("reload_clutter"):
			clutter.reload_clutter()
		status = "Painted %s (%d cells) · Unsaved" % [texture_entry.get("name", "texture"), count_modified]
		return true
	return false

func modify_elevation(hit: Dictionary = {}, delta_h: float = 0.0) -> bool:
	if not enabled:
		return false
	if delta_h == 0.0:
		delta_h = elevation_step_m
	if hit.is_empty():
		hit = ray_hit()
	if hit.is_empty():
		status = "Aim at terrain within %d m to elevate" % int(REACH)
		return false
	var world = get_tree().get_first_node_in_group("cylinder_world")
	if not world or not world.terrain_manager:
		status = "Terrain layer unavailable"
		return false
	var tm: TerrainManager = world.terrain_manager
	var radius_m: float = world.radius
	var length_m: float = world.cylinder_length
	var pos: Vector3 = hit.position
	var hit_theta: float = atan2(pos.y, pos.x)
	var hit_z: float = pos.z

	var grid_u: int = tm.elevation_grid_u
	var grid_v: int = tm.elevation_grid_v
	if grid_u <= 0 or grid_v <= 0 or tm.elevation_data.is_empty():
		return false

	var max_h: float = tm.elevation_variance
	var count_modified: int = 0
	for y in range(grid_v):
		var v_norm: float = float(y) / float(maxi(grid_v - 1, 1))
		var z: float = (v_norm - 0.5) * length_m
		var dz: float = absf(z - hit_z)
		if dz > brush_radius_m:
			continue
		for x in range(grid_u):
			var u_norm: float = float(x) / float(grid_u)
			var theta: float = u_norm * TAU
			var d_theta: float = absf(fposmod(theta - hit_theta + PI, TAU) - PI)
			var dx_m: float = d_theta * radius_m
			var dist: float = sqrt(dx_m * dx_m + dz * dz)
			if dist <= brush_radius_m:
				var falloff: float = 1.0 - (dist / maxf(brush_radius_m, 1.0)) * (dist / maxf(brush_radius_m, 1.0))
				var idx: int = y * grid_u + x
				var old_val: float = tm.elevation_data[idx]
				var new_val: float = clampf(old_val + delta_h * falloff, 0.0, max_h)
				if absf(new_val - old_val) > 0.0001:
					tm.elevation_data[idx] = new_val
					count_modified += 1

	if count_modified > 0:
		world.generate_cylinder()
		var verb := "Raised" if delta_h > 0 else "Lowered"
		status = "%s terrain elevation (%d cells) · Unsaved" % [verb, count_modified]
		return true
	return false

func smooth_elevation(hit: Dictionary = {}, strength: float = 0.75, max_angle_deg: float = 85.0) -> bool:
	if not enabled:
		return false
	if hit.is_empty():
		hit = ray_hit()
	if hit.is_empty():
		status = "Aim at terrain within %d m to smooth" % int(REACH)
		return false
	var world = get_tree().get_first_node_in_group("cylinder_world")
	if not world or not world.terrain_manager:
		status = "Terrain layer unavailable"
		return false
	var tm: TerrainManager = world.terrain_manager
	var radius_m: float = world.radius
	var length_m: float = world.cylinder_length
	var pos: Vector3 = hit.position
	var hit_theta: float = atan2(pos.y, pos.x)
	var hit_z: float = pos.z

	var grid_u: int = tm.elevation_grid_u
	var grid_v: int = tm.elevation_grid_v
	if grid_u <= 0 or grid_v <= 0 or tm.elevation_data.is_empty():
		return false

	var max_h: float = tm.elevation_variance
	var cells_to_smooth: Array[int] = []
	var falloffs: Array[float] = []

	for y in range(grid_v):
		var v_norm: float = float(y) / float(maxi(grid_v - 1, 1))
		var z: float = (v_norm - 0.5) * length_m
		var dz: float = absf(z - hit_z)
		if dz > brush_radius_m:
			continue
		for x in range(grid_u):
			var u_norm: float = float(x) / float(grid_u)
			var theta: float = u_norm * TAU
			var d_theta: float = absf(fposmod(theta - hit_theta + PI, TAU) - PI)
			var dx_m: float = d_theta * radius_m
			var dist: float = sqrt(dx_m * dx_m + dz * dz)
			if dist <= brush_radius_m:
				var falloff: float = 1.0 - (dist / maxf(brush_radius_m, 1.0)) * (dist / maxf(brush_radius_m, 1.0))
				var idx: int = y * grid_u + x
				cells_to_smooth.append(idx)
				falloffs.append(falloff)

	if cells_to_smooth.is_empty():
		return false

	var max_slope_tan: float = tan(deg_to_rad(clampf(max_angle_deg, 10.0, 89.5)))
	var dx_cell: float = (TAU * radius_m) / float(grid_u)
	var dz_cell: float = length_m / float(maxi(grid_v - 1, 1))
	var cell_dist_avg: float = (dx_cell + dz_cell) * 0.5

	var count_modified: int = 0
	var old_data := tm.elevation_data.duplicate()
	for i in range(cells_to_smooth.size()):
		var idx: int = cells_to_smooth[i]
		var falloff: float = falloffs[i]
		var cy: int = idx / grid_u
		var cx: int = idx % grid_u

		var sum: float = 0.0
		var weight_sum: float = 0.0
		for ny in range(maxi(0, cy - 1), mini(grid_v, cy + 2)):
			for nx_offset in range(-1, 2):
				var nx: int = (cx + nx_offset + grid_u) % grid_u
				var n_idx: int = ny * grid_u + nx
				var dist_factor: float = 1.0 if (ny == cy and nx == cx) else (0.707 if (ny != cy and nx_offset != 0) else 1.0)
				sum += old_data[n_idx] * dist_factor
				weight_sum += dist_factor

		var avg: float = sum / maxf(weight_sum, 1.0)
		var cur: float = old_data[idx]
		var max_h_delta: float = max_slope_tan * cell_dist_avg
		var diff: float = clampf(avg - cur, -max_h_delta, max_h_delta)
		var target: float = clampf(cur + diff * strength * falloff, 0.0, max_h)
		if absf(target - cur) > 0.0001:
			tm.elevation_data[idx] = target
			count_modified += 1

	if count_modified > 0:
		world.generate_cylinder()
		status = "Smoothed terrain elevation (%d cells) · Unsaved" % count_modified
		return true
	return false

func save_edits() -> Error:
	if not enabled:
		return ERR_UNAVAILABLE
	var references = get_tree().get_first_node_in_group("reference_objects")
	if not references:
		status = "No object layer available"
		return ERR_UNAVAILABLE
	var world = get_tree().get_first_node_in_group("cylinder_world")

	# Save object placements first (this handles copying res:// maps to user:// if needed and updates references.active_map_config)
	var error := Storage.save(references, "", player)
	if error != OK:
		status = "Could not save object placements (%s)" % error_string(error)
		return error

	# Save terrain elevation and biome rasters into the active user map package
	if world and world.terrain_manager:
		var cfg = references.active_map_config
		var elev_p = Config.get_elevation_map_path(cfg)
		var terr_p = Config.get_terrain_map_path(cfg)
		DirAccess.make_dir_recursive_absolute(elev_p.get_base_dir())
		DirAccess.make_dir_recursive_absolute(terr_p.get_base_dir())
		var elev_ok = world.terrain_manager.save_elevation(elev_p)
		var terr_ok = world.terrain_manager.save_terrain(terr_p)
		if not elev_ok or not terr_ok:
			status = "Could not save terrain elevation or biomes to " + cfg.map_directory
			return ERR_CANT_CREATE

	if world:
		world.load_map_package(references.active_map_config.map_directory)
	Config.activate(references.active_map_config.map_directory)
	status = "Saved — edits and terrain height/textures"
	return OK

func tint_target(appearance: Color, emission: Color) -> void:
	var object = target_object(ray_hit())
	if not object:
		status = "Aim at an object to tint it"
		return
	object.tint = appearance
	object.light_color = emission
	object.rebuild_object()
	status = "Tinted %s · Unsaved" % object.name

func import_object_model(source_path: String) -> bool:
	if not FileAccess.file_exists(source_path):
		status = "Model file not found: %s" % source_path
		return false
	var references = get_tree().get_first_node_in_group("reference_objects")
	var config: Dictionary = references.active_map_config if references else Config.load_map_config(Config.active_map())
	var map_dir: String = config.get("map_directory", "res://assets/maps/default")
	var file_name: String = source_path.get_file()
	var dest_dir: String = map_dir.path_join("models/imported")
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var dest_path: String = dest_dir.path_join(file_name)
	DirAccess.copy_absolute(source_path, dest_path)
	var rel_path: String = "models/imported/" + file_name

	var asset_id: String = file_name.get_basename().validate_node_name() + "_" + str(Time.get_ticks_msec())
	var new_entry: Dictionary = {
		"name": file_name.get_basename().capitalize(),
		"scene_path": rel_path,
		"behavior_type": 0,
		"variant": 0,
		"tint": [1.0, 1.0, 1.0, 1.0],
		"light_color": [1.0, 0.8, 0.4, 1.0],
		"light_energy": 0.0,
		"light_range_m": 0.0,
		"flicker": false
	}
	config.objects.model_catalog[asset_id] = new_entry
	Config.save_document(config, map_dir)
	reload_catalog()
	status = "Imported object %s · Saved catalog" % new_entry.name
	return true

func import_ground_texture(source_path: String, rotate_enabled: bool = true) -> bool:
	if not FileAccess.file_exists(source_path):
		status = "Texture file not found: %s" % source_path
		return false
	var references = get_tree().get_first_node_in_group("reference_objects")
	var config: Dictionary = references.active_map_config if references else Config.load_map_config(Config.active_map())
	var map_dir: String = config.get("map_directory", "res://assets/maps/default")
	var file_name: String = source_path.get_file()
	var dest_dir: String = map_dir.path_join("textures/imported")
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var dest_path: String = dest_dir.path_join(file_name)
	DirAccess.copy_absolute(source_path, dest_path)
	var rel_path: String = "textures/imported/" + file_name

	var max_id: int = -1
	for b_key in config.biomes:
		var r_id = int(config.biomes[b_key].get("raster_id", 0))
		if r_id > max_id:
			max_id = r_id
	var next_id: int = mini(max_id + 1, 255)
	var biome_key: String = file_name.get_basename().validate_node_name()
	var new_biome: Dictionary = {
		"name": file_name.get_basename().capitalize(),
		"raster_id": next_id,
		"texture": rel_path,
		"texture_size_m": 20.0,
		"roughness": 0.8,
		"tint": [1.0, 1.0, 1.0, 1.0],
		"blended": true,
		"rotate": rotate_enabled,
		"clutter_density": 0.5,
		"clutter_object_set": []
	}
	config.biomes[biome_key] = new_biome
	Config.save_document(config, map_dir)
	reload_texture_catalog()
	var world = get_tree().get_first_node_in_group("cylinder_world")
	if world:
		world._update_terrain_material_textures()
	status = "Imported ground texture %s · Saved biomes" % new_biome.name
	return true

func replace_ground_texture(texture_index: int, source_path: String, rotate_enabled: bool = true) -> bool:
	if texture_index < 0 or texture_index >= texture_catalog.size():
		status = "Invalid ground texture index: %d" % texture_index
		return false
	if not FileAccess.file_exists(source_path):
		status = "Texture file not found: %s" % source_path
		return false

	var target_biome: Dictionary = texture_catalog[texture_index]
	var biome_key: String = str(target_biome.get("key", ""))
	if biome_key.is_empty():
		status = "Target ground biome key not found"
		return false

	var references = get_tree().get_first_node_in_group("reference_objects")
	var config: Dictionary = references.active_map_config if references else Config.load_map_config(Config.active_map())
	var map_dir: String = config.get("map_directory", "res://assets/maps/default")
	var file_name: String = source_path.get_file()
	var dest_dir: String = map_dir.path_join("textures/imported")
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var dest_path: String = dest_dir.path_join(file_name)
	DirAccess.copy_absolute(source_path, dest_path)
	var rel_path: String = "textures/imported/" + file_name

	if not config.get("biomes", {}).has(biome_key):
		status = "Biome '%s' not found in active map config" % biome_key
		return false

	config.biomes[biome_key]["texture"] = rel_path
	config.biomes[biome_key]["rotate"] = rotate_enabled
	Config.save_document(config, map_dir)

	reload_texture_catalog()
	if texture_index < texture_catalog.size():
		selected_texture_index = texture_index
		selected_biome_id = int(texture_catalog[texture_index].get("id", 0))

	var world = get_tree().get_first_node_in_group("cylinder_world")
	if world and world.has_method("_update_terrain_material_textures"):
		world._update_terrain_material_textures()

	status = "Replaced ground texture for %s with %s" % [config.biomes[biome_key].get("name", biome_key), file_name]
	return true

func set_biome_rotate(texture_index: int, rotate_enabled: bool) -> bool:
	if texture_index < 0 or texture_index >= texture_catalog.size():
		status = "Invalid ground texture index: %d" % texture_index
		return false

	var target_biome: Dictionary = texture_catalog[texture_index]
	var biome_key: String = str(target_biome.get("key", ""))
	if biome_key.is_empty():
		status = "Target ground biome key not found"
		return false

	var references = get_tree().get_first_node_in_group("reference_objects")
	var config: Dictionary = references.active_map_config if references else Config.load_map_config(Config.active_map())
	var map_dir: String = config.get("map_directory", "res://assets/maps/default")

	if not config.get("biomes", {}).has(biome_key):
		status = "Biome '%s' not found in active map config" % biome_key
		return false

	config.biomes[biome_key]["rotate"] = rotate_enabled
	Config.save_document(config, map_dir)

	reload_texture_catalog()
	if texture_index < texture_catalog.size():
		selected_texture_index = texture_index
		selected_biome_id = int(texture_catalog[texture_index].get("id", 0))

	var world = get_tree().get_first_node_in_group("cylinder_world")
	if world and world.has_method("_update_terrain_material_textures"):
		world._update_terrain_material_textures()

	status = "%s texture rotation: %s" % [config.biomes[biome_key].get("name", biome_key), "ENABLED" if rotate_enabled else "DISABLED"]
	return true



